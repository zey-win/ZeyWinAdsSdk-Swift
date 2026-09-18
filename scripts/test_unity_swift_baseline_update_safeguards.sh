#!/usr/bin/env bash

# Network-free fixtures for the deterministic Unity baseline-update gate. Every
# repository is temporary; this test never modifies the caller's baseline or refs.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
baseline_script="$repo_root/scripts/unity_swift_baseline_update.sh"
workflow="$repo_root/.github/workflows/unity-swift-baseline-update.yml"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unity-swift-baseline-tests.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
expect_failure() {
    local name="$1"
    shift
    if "$@" >"$tmp_dir/${name}.out" 2>"$tmp_dir/${name}.err"; then
        fail "$name unexpectedly succeeded"
    fi
    pass "$name"
}
commit() {
    local repo="$1" message="$2"
    git -C "$repo" add .
    git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm "$message"
}

unity_repo="$tmp_dir/unity"
git init -q -b main "$unity_repo"
printf 'first\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'unity baseline'
old_sha="$(git -C "$unity_repo" rev-parse HEAD)"
printf 'second\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'unity target'
new_sha="$(git -C "$unity_repo" rev-parse HEAD)"

make_swift_source() {
    local repo="$1" baseline="$2" unity_head="$3" branch="$4" trailer="$5"
    mkdir -p "$repo/.sync"
    git init -q -b main "$repo"
    printf '%s\n' "$baseline" > "$repo/.sync/unity-last-synced-commit"
    commit "$repo" 'swift main'
    git -C "$repo" checkout -qb "$branch"
    if [[ "$trailer" == "valid" ]]; then
        git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit --allow-empty -qm 'Sync Unity fixture changes to Swift' -m "Unity-Head: ${unity_head}"
    elif [[ "$trailer" == "missing" ]]; then
        git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit --allow-empty -qm 'Sync Unity fixture changes to Swift'
    elif [[ "$trailer" == "duplicate" ]]; then
        git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit --allow-empty -qm 'Sync Unity fixture changes to Swift' -m $'Unity-Head: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\nUnity-Head: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
    else
        git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit --allow-empty -qm 'Sync Unity fixture changes to Swift' -m 'Unity-Head: not-a-sha'
    fi
}

valid_swift="$tmp_dir/valid-swift"
valid_branch="sync/unity-${new_sha:0:7}"
make_swift_source "$valid_swift" "$old_sha" "$new_sha" "$valid_branch" valid
before_validate="$(tr -d '[:space:]' < "$valid_swift/.sync/unity-last-synced-commit")"
bash "$baseline_script" --mode validate --swift-repo "$valid_swift" --unity-repo "$unity_repo" \
    --source-ref HEAD --source-branch "$valid_branch" --report-output "$tmp_dir/valid.json"
[[ "$(jq -r '.status' "$tmp_dir/valid.json")" == ready ]] || fail 'valid source was not ready'
[[ "$(tr -d '[:space:]' < "$valid_swift/.sync/unity-last-synced-commit")" == "$before_validate" ]] || fail 'validate changed baseline before merge preparation'
pass 'valid merged sync source prepares a baseline update without changing baseline in validate mode'

bash "$baseline_script" --mode prepare --swift-repo "$valid_swift" --unity-repo "$unity_repo" \
    --source-ref HEAD --source-branch "$valid_branch" --report-output "$tmp_dir/prepared.json"
[[ "$(tr -d '[:space:]' < "$valid_swift/.sync/unity-last-synced-commit")" == "$new_sha" ]] || fail 'prepare did not advance baseline'
[[ "$(git -C "$valid_swift" diff --name-only)" == '.sync/unity-last-synced-commit' ]] || fail 'prepare changed more than baseline file'
pass 'prepare changes only the baseline file'

wrong_branch_swift="$tmp_dir/wrong-branch"
make_swift_source "$wrong_branch_swift" "$old_sha" "$new_sha" sync/unity-deadbee valid
expect_failure wrong_branch_sha7 \
    bash "$baseline_script" --mode validate --swift-repo "$wrong_branch_swift" --unity-repo "$unity_repo" \
    --source-ref HEAD --source-branch sync/unity-deadbee --report-output "$tmp_dir/wrong-branch.json"

missing_trailer_swift="$tmp_dir/missing-trailer"
make_swift_source "$missing_trailer_swift" "$old_sha" "$new_sha" "$valid_branch" missing
expect_failure missing_unity_head_trailer \
    bash "$baseline_script" --mode validate --swift-repo "$missing_trailer_swift" --unity-repo "$unity_repo" \
    --source-ref HEAD --source-branch "$valid_branch" --report-output "$tmp_dir/missing.json"

duplicate_trailer_swift="$tmp_dir/duplicate-trailer"
make_swift_source "$duplicate_trailer_swift" "$old_sha" "$new_sha" "$valid_branch" duplicate
expect_failure duplicate_unity_head_trailer \
    bash "$baseline_script" --mode validate --swift-repo "$duplicate_trailer_swift" --unity-repo "$unity_repo" \
    --source-ref HEAD --source-branch "$valid_branch" --report-output "$tmp_dir/duplicate.json"

invalid_trailer_swift="$tmp_dir/invalid-trailer"
make_swift_source "$invalid_trailer_swift" "$old_sha" "$new_sha" "$valid_branch" invalid
expect_failure invalid_unity_head_sha \
    bash "$baseline_script" --mode validate --swift-repo "$invalid_trailer_swift" --unity-repo "$unity_repo" \
    --source-ref HEAD --source-branch "$valid_branch" --report-output "$tmp_dir/invalid.json"

git -C "$unity_repo" checkout -qb feature "$old_sha"
printf 'feature-only\n' > "$unity_repo/feature.txt"
commit "$unity_repo" 'feature-only unity commit'
feature_sha="$(git -C "$unity_repo" rev-parse HEAD)"
git -C "$unity_repo" checkout -q main
not_main_swift="$tmp_dir/not-main"
make_swift_source "$not_main_swift" "$old_sha" "$feature_sha" "sync/unity-${feature_sha:0:7}" valid
expect_failure unity_sha_not_in_main \
    bash "$baseline_script" --mode validate --swift-repo "$not_main_swift" --unity-repo "$unity_repo" \
    --source-ref HEAD --source-branch "sync/unity-${feature_sha:0:7}" --report-output "$tmp_dir/not-main.json"

git -C "$unity_repo" switch -q --orphan unrelated
git -C "$unity_repo" read-tree --empty
printf 'unrelated-root\n' > "$unity_repo/unrelated.txt"
commit "$unity_repo" 'unrelated Unity root'
unrelated_sha="$(git -C "$unity_repo" rev-parse HEAD)"
git -C "$unity_repo" checkout -q main
unrelated_swift="$tmp_dir/unrelated"
make_swift_source "$unrelated_swift" "$old_sha" "$unrelated_sha" "sync/unity-${unrelated_sha:0:7}" valid
expect_failure unrelated_unity_history \
    bash "$baseline_script" --mode validate --swift-repo "$unrelated_swift" --unity-repo "$unity_repo" \
    --source-ref HEAD --source-branch "sync/unity-${unrelated_sha:0:7}" --report-output "$tmp_dir/unrelated.json"

older_swift="$tmp_dir/older"
make_swift_source "$older_swift" "$new_sha" "$old_sha" "sync/unity-${old_sha:0:7}" valid
expect_failure new_sha_older_than_baseline \
    bash "$baseline_script" --mode validate --swift-repo "$older_swift" --unity-repo "$unity_repo" \
    --source-ref HEAD --source-branch "sync/unity-${old_sha:0:7}" --report-output "$tmp_dir/older.json"

# Stale baseline PR reproduction: A -> B is valid, then main advances A -> C;
# the old A -> B PR must fail, while a fresh C -> D PR succeeds.
printf 'third\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'unity C'
unity_c="$(git -C "$unity_repo" rev-parse HEAD)"
printf 'fourth\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'unity D'
unity_d="$(git -C "$unity_repo" rev-parse HEAD)"

baseline_pr_repo="$tmp_dir/baseline-pr"
mkdir -p "$baseline_pr_repo/.sync"
git init -q -b main "$baseline_pr_repo"
printf '%s\n' "$old_sha" > "$baseline_pr_repo/.sync/unity-last-synced-commit"
commit "$baseline_pr_repo" 'baseline A'
git -C "$baseline_pr_repo" checkout -qb "sync/baseline-${new_sha:0:7}"
printf '%s\n' "$new_sha" > "$baseline_pr_repo/.sync/unity-last-synced-commit"
commit "$baseline_pr_repo" "Advance Unity sync baseline to ${new_sha:0:7}"
bash "$repo_root/scripts/unity_swift_baseline_pr_validate.sh" \
    --swift-repo "$baseline_pr_repo" --unity-repo "$unity_repo" \
    --main-ref main --branch-ref "sync/baseline-${new_sha:0:7}" \
    --branch-name "sync/baseline-${new_sha:0:7}" --report-output "$tmp_dir/a-to-b.json"
[[ "$(jq -r '.status' "$tmp_dir/a-to-b.json")" == ready ]] || fail 'A -> B baseline PR was not ready'
pass 'baseline PR B is valid against current baseline A'

git -C "$baseline_pr_repo" checkout -q main
printf '%s\n' "$unity_c" > "$baseline_pr_repo/.sync/unity-last-synced-commit"
commit "$baseline_pr_repo" "Advance Unity sync baseline to ${unity_c:0:7}"
expect_failure stale_a_to_b_after_main_advances_to_c \
    bash "$repo_root/scripts/unity_swift_baseline_pr_validate.sh" \
    --swift-repo "$baseline_pr_repo" --unity-repo "$unity_repo" \
    --main-ref main --branch-ref "sync/baseline-${new_sha:0:7}" \
    --branch-name "sync/baseline-${new_sha:0:7}" --report-output "$tmp_dir/stale-a-to-b.json"

baseline_a_commit="$(git -C "$baseline_pr_repo" rev-parse main~1)"
git -C "$baseline_pr_repo" checkout -qb "sync/baseline-${unity_c:0:7}" "$baseline_a_commit"
printf '%s\n' "$unity_c" > "$baseline_pr_repo/.sync/unity-last-synced-commit"
commit "$baseline_pr_repo" "Advance Unity sync baseline to ${unity_c:0:7}"
bash "$repo_root/scripts/unity_swift_baseline_pr_validate.sh" \
    --swift-repo "$baseline_pr_repo" --unity-repo "$unity_repo" \
    --main-ref main --branch-ref "sync/baseline-${unity_c:0:7}" \
    --branch-name "sync/baseline-${unity_c:0:7}" --report-output "$tmp_dir/duplicate-c.json"
[[ "$(jq -r '.status' "$tmp_dir/duplicate-c.json")" == no_op ]] || fail 'duplicate C baseline PR was not classified no_op'
pass 'already-applied baseline PR is classified no_op for merge blocking'

git -C "$baseline_pr_repo" checkout -qb "sync/baseline-${unity_d:0:7}" main
printf '%s\n' "$unity_d" > "$baseline_pr_repo/.sync/unity-last-synced-commit"
commit "$baseline_pr_repo" "Advance Unity sync baseline to ${unity_d:0:7}"
bash "$repo_root/scripts/unity_swift_baseline_pr_validate.sh" \
    --swift-repo "$baseline_pr_repo" --unity-repo "$unity_repo" \
    --main-ref main --branch-ref "sync/baseline-${unity_d:0:7}" \
    --branch-name "sync/baseline-${unity_d:0:7}" --report-output "$tmp_dir/c-to-d.json"
[[ "$(jq -r '.status' "$tmp_dir/c-to-d.json")" == ready ]] || fail 'C -> D baseline PR was not ready'
pass 'fresh baseline PR D is valid against current baseline C'

workflow_gate="$(sed -n '/jobs:/,/^$/p' "$workflow")"
printf '%s\n' "$workflow_gate" | grep -Fq 'github.event.pull_request.merged == true' || fail 'closed-but-unmerged PR is not gated'
printf '%s\n' "$workflow_gate" | grep -Fq "github.event.pull_request.base.ref == 'main'" || fail 'non-main PR is not gated'
printf '%s\n' "$workflow_gate" | grep -Fq "startsWith(github.event.pull_request.head.ref, 'sync/unity-')" || fail 'normal feature PR is not gated'
grep -Fq 'state=verified_existing' "$workflow" || fail 'existing verified baseline branch is not reusable'
grep -Fq 'gh pr list --head "$baseline_branch" --base main --state open' "$workflow" || fail 'existing baseline PR reuse is missing'
grep -Fq 'Existing baseline branch has an unexpected tip commit subject' "$workflow" || fail 'conflicting baseline branch does not fail safely'
pass 'closed/unmerged and normal PRs are no-op; baseline branch and PR idempotency gates exist'

pr_validation_workflow="$repo_root/.github/workflows/unity-swift-baseline-pr-validation.yml"
grep -Fq 'types: [opened, synchronize, reopened]' "$pr_validation_workflow" || fail 'baseline PR validation trigger is incomplete'
grep -Fq "startsWith(github.event.pull_request.head.ref, 'sync/baseline-')" "$pr_validation_workflow" || fail 'baseline PR branch gate is missing'
grep -Fq 'Block an obsolete no-op baseline PR' "$pr_validation_workflow" || fail 'obsolete baseline PRs are not blocked'
pass 'baseline PR required validation workflow gates stale and duplicate updates'

echo 'All Unity → Swift baseline-update safeguard fixtures passed.'
