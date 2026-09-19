#!/usr/bin/env bash

# Final network-free idempotency/conflict fixtures for the Unity -> Swift sync
# pipeline. Every Git repository below is temporary. This script does not call
# OpenAI, create remote branches/PRs, or modify the caller's checkout/baseline.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
detector="$repo_root/scripts/unity_swift_change_detector.sh"
apply_script="$repo_root/scripts/unity_swift_apply_validated_patch.sh"
identity_script="$repo_root/scripts/unity_swift_sync_branch_identity.sh"
baseline_pr_script="$repo_root/scripts/unity_swift_baseline_pr_validate.sh"
workflow="$repo_root/.github/workflows/unity-swift-semantic-analysis.yml"
baseline_workflow="$repo_root/.github/workflows/unity-swift-baseline-pr-validation.yml"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unity-swift-final-idempotency.XXXXXX")"
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
assert_baseline() {
    local repo="$1" expected="$2" description="$3"
    local actual
    actual="$(tr -d '[:space:]' < "$repo/.sync/unity-last-synced-commit")"
    [[ "$actual" == "$expected" ]] || fail "$description changed the baseline"
}
assert_clean() {
    local repo="$1" description="$2"
    [[ -z "$(git -C "$repo" status --porcelain=v1 --untracked-files=all)" ]] || fail "$description changed the fixture worktree"
}

make_swift_repo() {
    local repo="$1" baseline="$2"
    mkdir -p "$repo/.sync" "$repo/Sources/ZeyWinSDK/Core"
    printf '%s\n' "$baseline" > "$repo/.sync/unity-last-synced-commit"
    printf 'enum Existing {}\n' > "$repo/Sources/ZeyWinSDK/Core/Existing.swift"
    git init -q -b main "$repo"
    commit "$repo" 'Swift fixture main'
}
run_detector() {
    local name="$1" state="$2"
    printf '%s\n' "$state" > "$tmp_dir/${name}.baseline"
    bash "$detector" --unity-dir "$unity_repo" --to main \
        --state-file "$tmp_dir/${name}.baseline" \
        --output "$tmp_dir/${name}.md" --status-output "$tmp_dir/${name}.status"
}
make_conflict_artifacts() {
    local dir="$1" source_sha="$2"
    mkdir -p "$dir"
    printf '%s\n' \
        'diff --git a/Sources/ZeyWinSDK/Core/Existing.swift b/Sources/ZeyWinSDK/Core/Existing.swift' \
        'index 2b5f89b..c9e74c4 100644' \
        '--- a/Sources/ZeyWinSDK/Core/Existing.swift' \
        '+++ b/Sources/ZeyWinSDK/Core/Existing.swift' \
        '@@ -1 +1 @@' \
        '-enum Existing {}' \
        '+enum Updated {}' > "$dir/proposed.patch"
    jq -n --arg sha "$source_sha" '
      {
        schema: "zeywin.unity-swift-port-plan", schema_version: "1.0", plan_status: "ready",
        items: [{
          id: "fixture-existing-swift-file", source_status: "MISSING_IN_SWIFT",
          swift_port_needed: true, patch_ready: true, source_unity_commits: [$sha],
          target_swift_files_symbols: ["Sources/ZeyWinSDK/Core/Existing.swift — Existing"], blockers: []
        }]
      }' > "$dir/port-plan.json"
    jq -n --arg sha "$source_sha" --rawfile patch "$dir/proposed.patch" '
      {
        schema: "zeywin.unity-swift-patch-proposal", schema_version: "1.0", proposal_status: "ready",
        items: [{
          id: "fixture-existing-swift-file", source_unity_commits: [$sha],
          target_swift_files: ["Sources/ZeyWinSDK/Core/Existing.swift"],
          exact_proposed_changes: ["Update the fixture declaration."],
          unified_diff: ($patch | rtrimstr("\n"))
        }]
      }' > "$dir/patch-proposal.json"
}
make_forbidden_artifacts() {
    local dir="$1" source_sha="$2" path="$3"
    mkdir -p "$dir"
    printf '%s\n' \
        "diff --git a/${path} b/${path}" \
        'new file mode 100644' \
        'index 0000000..15b349a' \
        '--- /dev/null' \
        "+++ b/${path}" \
        '@@ -0,0 +1 @@' \
        '+forbidden' > "$dir/proposed.patch"
    jq -n --arg sha "$source_sha" --arg path "$path" '
      {
        schema: "zeywin.unity-swift-port-plan", schema_version: "1.0", plan_status: "ready",
        items: [{
          id: "forbidden-path", source_status: "MISSING_IN_SWIFT", swift_port_needed: true,
          patch_ready: true, source_unity_commits: [$sha],
          target_swift_files_symbols: [($path + " — fixture")], blockers: []
        }]
      }' > "$dir/port-plan.json"
    jq -n --arg sha "$source_sha" --arg path "$path" --rawfile patch "$dir/proposed.patch" '
      {
        schema: "zeywin.unity-swift-patch-proposal", schema_version: "1.0", proposal_status: "ready",
        items: [{
          id: "forbidden-path", source_unity_commits: [$sha], target_swift_files: [$path],
          exact_proposed_changes: ["Attempt a forbidden file."], unified_diff: ($patch | rtrimstr("\n"))
        }]
      }' > "$dir/patch-proposal.json"
}

# A -> B -> C -> D represents the Unity main history seen by one polling run.
unity_repo="$tmp_dir/unity"
git init -q -b main "$unity_repo"
printf 'A\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'Unity A'
sha_a="$(git -C "$unity_repo" rev-parse HEAD)"
printf 'B\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'Unity B'
sha_b="$(git -C "$unity_repo" rev-parse HEAD)"
printf 'C\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'Unity C'
sha_c="$(git -C "$unity_repo" rev-parse HEAD)"
printf 'D\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'Unity D'
sha_d="$(git -C "$unity_repo" rev-parse HEAD)"

# A/E/D: detector computes exactly one full range and becomes no_op only after
# the committed baseline reaches current Unity main. The detector is report-only.
run_detector full_a_to_d "$sha_a"
[[ "$(tr -d '[:space:]' < "$tmp_dir/full_a_to_d.status")" == changes ]] || fail 'A..D detector status was not changes'
grep -Fq "\`${sha_a}..${sha_d}\`" "$tmp_dir/full_a_to_d.md" || fail 'A..D detector range is incorrect'
[[ "$(tr -d '[:space:]' < "$tmp_dir/full_a_to_d.baseline")" == "$sha_a" ]] || fail 'detector advanced baseline A during full range'
pass 'A..D is processed as one full report-only range without baseline mutation'

run_detector baseline_at_d "$sha_d"
[[ "$(tr -d '[:space:]' < "$tmp_dir/baseline_at_d.status")" == no_op ]] || fail 'baseline D/current Unity D was not no_op'
[[ "$(tr -d '[:space:]' < "$tmp_dir/baseline_at_d.baseline")" == "$sha_d" ]] || fail 'no_op detector changed baseline D'
pass 'advanced baseline D with Unity D produces clean no_op'

# A/B/C/N: branch name is only a convenience. Exact tip trailer is the identity
# source for re-runs, open PR suppression, and merged-PR/baseline-pending state.
identity_repo="$tmp_dir/identity"
make_swift_repo "$identity_repo" "$sha_a"
sync_branch="sync/unity-${sha_d:0:7}"
git -C "$identity_repo" checkout -qb "$sync_branch"
git -C "$identity_repo" -c user.name=test -c user.email=test@example.invalid \
    commit --allow-empty -qm "Sync Unity ${sha_d:0:7} changes to Swift" -m "Unity-Head: ${sha_d}"
first_sync_tip="$(git -C "$identity_repo" rev-parse HEAD)"
bash "$identity_script" --repo-root "$identity_repo" --ref HEAD --unity-head "$sha_d"
bash "$identity_script" --repo-root "$identity_repo" --ref HEAD --unity-head "$sha_d"
[[ "$(git -C "$identity_repo" rev-parse HEAD)" == "$first_sync_tip" ]] || fail 'same target rerun changed the verified sync branch'
assert_baseline "$identity_repo" "$sha_a" 'identity verification'
pass 'same Unity target rerun is identified by exact full Unity-Head without a second branch'

collision_a='abcdef0123456789abcdef0123456789abcdef01'
collision_b='abcdef0fffffffffffffffffffffffffffffffff'
collision_repo="$tmp_dir/sha7-collision"
make_swift_repo "$collision_repo" "$sha_a"
git -C "$collision_repo" checkout -qb sync/unity-abcdef0
git -C "$collision_repo" -c user.name=test -c user.email=test@example.invalid \
    commit --allow-empty -qm 'Sync collision fixture' -m "Unity-Head: ${collision_a}"
bash "$identity_script" --repo-root "$collision_repo" --ref HEAD --unity-head "$collision_a"
expect_failure same_sha7_different_full_sha \
    bash "$identity_script" --repo-root "$collision_repo" --ref HEAD --unity-head "$collision_b"
git -C "$collision_repo" -c user.name=test -c user.email=test@example.invalid \
    commit --allow-empty -qm 'Missing trailer'
expect_failure missing_unity_head_does_not_verify \
    bash "$identity_script" --repo-root "$collision_repo" --ref HEAD --unity-head "$collision_a"
git -C "$collision_repo" -c user.name=test -c user.email=test@example.invalid \
    commit --allow-empty -qm 'Duplicate trailer' \
    -m "Unity-Head: ${collision_a}" -m "Unity-Head: ${collision_a}"
expect_failure duplicate_unity_head_does_not_verify \
    bash "$identity_script" --repo-root "$collision_repo" --ref HEAD --unity-head "$collision_a"
pass 'wrong, missing, duplicate, and SHA7-colliding trailers cannot claim current target identity'

# Static job gates exercise the GitHub-only open/merged PR lookup without a
# network call. The conditional chain blocks every downstream write stage when a
# verified PR exists, while invalid identity falls through to the strict apply gate.
grep -Fq 'state=pending_sync_pr' "$workflow" || fail 'open verified sync PR state is absent'
grep -Fq 'state=pending_baseline_pr' "$workflow" || fail 'merged verified sync PR state is absent'
grep -Fq 'headRefOid' "$workflow" || fail 'PR identity is not checked against its exact head commit'
grep -Fq 'raw_trailer_count" == 1 && "$raw_trailers" == "$unity_head"' "$workflow" || fail 'pending PR suppression does not require an exact raw trailer'
grep -Fq 'parsed_trailer_count" == 1 && "$parsed_trailers" == "$unity_head"' "$workflow" || fail 'pending PR suppression does not require a parsed trailer'
grep -Fq "needs.semantic-report.outputs.pipeline_state == 'ready'" "$workflow" || fail 'port plan is not stopped by pending PR state'
grep -Fq "steps.pending-sync.outputs.state == 'ready'" "$workflow" || fail 'semantic analysis is not stopped by pending PR state'
pass 'verified open PR maps to pending_sync_pr and verified merged PR maps to pending_baseline_pr; both stop downstream work'

# F/G/H/M: a patch that was valid on an older main must fail cleanly after a
# conflict. Invalid inputs and paths outside the per-item/global allowlist fail
# before apply. No fixture commits, branch pushes, or baseline writes occur here.
conflict_repo="$tmp_dir/patch-conflict"
conflict_artifacts="$tmp_dir/patch-conflict-artifacts"
make_swift_repo "$conflict_repo" "$sha_a"
make_conflict_artifacts "$conflict_artifacts" "$sha_d"
git -C "$conflict_repo" apply --check --whitespace=error "$conflict_artifacts/proposed.patch" || fail 'fixture patch was not valid on old Swift state'
printf 'enum ConflictingMain {}\n' > "$conflict_repo/Sources/ZeyWinSDK/Core/Existing.swift"
commit "$conflict_repo" 'Concurrent Swift main change'
conflict_before_log="$(git -C "$conflict_repo" rev-parse HEAD)"
expect_failure patch_conflict_fails_before_apply \
    bash "$apply_script" --mode apply --repo-root "$conflict_repo" \
    --port-plan "$conflict_artifacts/port-plan.json" --proposal "$conflict_artifacts/patch-proposal.json" \
    --patch "$conflict_artifacts/proposed.patch" --report-output "$tmp_dir/conflict-report.md" \
    --applied-patch-output "$tmp_dir/conflict-applied.patch"
[[ "$(git -C "$conflict_repo" rev-parse HEAD)" == "$conflict_before_log" ]] || fail 'conflicting patch created a commit'
grep -Fqx 'enum ConflictingMain {}' "$conflict_repo/Sources/ZeyWinSDK/Core/Existing.swift" || fail 'conflicting patch changed Swift fixture'
assert_baseline "$conflict_repo" "$sha_a" 'conflicting patch'
assert_clean "$conflict_repo" 'conflicting patch failure'
pass 'patch conflict fails git apply --check with no apply, commit, push, PR, or baseline mutation'

for forbidden_path in .github/escaped.yml .sync/escaped README.md; do
    forbidden_repo="$tmp_dir/forbidden-${forbidden_path//\//_}"
    forbidden_artifacts="$tmp_dir/forbidden-artifacts-${forbidden_path//\//_}"
    make_swift_repo "$forbidden_repo" "$sha_a"
    make_forbidden_artifacts "$forbidden_artifacts" "$sha_d" "$forbidden_path"
    expect_failure "forbidden_${forbidden_path//\//_}" \
        bash "$apply_script" --mode apply --repo-root "$forbidden_repo" \
        --port-plan "$forbidden_artifacts/port-plan.json" --proposal "$forbidden_artifacts/patch-proposal.json" \
        --patch "$forbidden_artifacts/proposed.patch" --report-output "$tmp_dir/forbidden-report.md" \
        --applied-patch-output "$tmp_dir/forbidden-applied.patch"
    [[ ! -e "$forbidden_repo/$forbidden_path" ]] || fail "forbidden patch created ${forbidden_path}"
    assert_baseline "$forbidden_repo" "$sha_a" "forbidden path ${forbidden_path}"
    assert_clean "$forbidden_repo" "forbidden path ${forbidden_path}"
done
pass 'tracked and newly-created paths outside the allowlist fail before apply'

invalid_repo="$tmp_dir/invalid-proposal"
make_swift_repo "$invalid_repo" "$sha_a"
printf '{malformed\n' > "$tmp_dir/malformed-proposal.json"
expect_failure malformed_patch_proposal \
    bash "$apply_script" --mode validate --repo-root "$invalid_repo" \
    --port-plan "$conflict_artifacts/port-plan.json" --proposal "$tmp_dir/malformed-proposal.json" \
    --patch "$conflict_artifacts/proposed.patch" --report-output "$tmp_dir/malformed-report.md" \
    --applied-patch-output "$tmp_dir/malformed-applied.patch"
assert_baseline "$invalid_repo" "$sha_a" 'malformed proposal'
assert_clean "$invalid_repo" 'malformed proposal failure'
pass 'malformed proposal is unavailable without any repository state mutation'

unavailable_baseline="$tmp_dir/unavailable-baseline"
printf 'not-a-unity-commit\n' > "$unavailable_baseline"
expect_failure unavailable_unity_baseline \
    bash "$detector" --unity-dir "$unity_repo" --to main --state-file "$unavailable_baseline" \
    --output "$tmp_dir/unavailable.md" --status-output "$tmp_dir/unavailable.status"
[[ "$(tr -d '[:space:]' < "$unavailable_baseline")" == not-a-unity-commit ]] || fail 'unavailable detector changed baseline'
expect_failure unavailable_unity_clone \
    bash "$detector" --unity-dir "$tmp_dir/no-such-unity-clone" --state-file "$unavailable_baseline" \
    --output "$tmp_dir/no-clone.md" --status-output "$tmp_dir/no-clone.status"
[[ "$(tr -d '[:space:]' < "$unavailable_baseline")" == not-a-unity-commit ]] || fail 'failed Unity clone changed baseline'
grep -Fq 'merge-base --is-ancestor "$baseline" "$unity_head"' "$workflow" || fail 'scheduled workflow does not reject a non-ancestor baseline'
grep -Fq '*) status=unavailable ;;' "$workflow" || fail 'malformed detector status is not downgraded to unavailable'
pass 'clone/baseline/status failure paths are non-writing and scheduled polling rejects non-ancestor baselines'

# I/J/K: the workflow only reads the baseline in polling/sync jobs. Baseline
# progression is owned by the separate baseline-only PR validator, which guards
# stale backward proposals and blocks a duplicate target as no_op.
if grep -Eq '(printf|echo|cat)[^\n]*>[[:space:]]*\.sync/unity-last-synced-commit' "$workflow"; then
    fail 'semantic/sync workflow writes the baseline directly'
fi
grep -Fq 'unity_swift_baseline_pr_validate.sh' "$baseline_workflow" || fail 'baseline-only validation workflow is missing'
grep -Fq 'Current main baseline is newer than, or unrelated to, the proposed baseline; this PR is stale.' "$baseline_pr_script" || fail 'stale baseline protection is missing'
grep -Fq 'Current main already equals the proposed baseline; close this obsolete PR without merging.' "$baseline_pr_script" || fail 'duplicate baseline target no_op is missing'
pass 'baseline remains immutable in polling/sync flow; stale and duplicate baseline PR guards are present'

# L: GitHub Actions serializes one concurrency group. It does not promise an
# unlimited queued backlog; a later queued run may replace an earlier pending run,
# which is safe because each run recomputes baseline..current Unity main.
grep -Fq 'group: unity-swift-sync-pipeline' "$workflow" || fail 'shared sync concurrency group is missing'
grep -Fq 'cancel-in-progress: false' "$workflow" || fail 'in-progress write pipeline may be cancelled'
grep -Fq 'current Unity main' "$workflow" || fail 'workflow does not document current-main polling semantics'
if grep -Eqi 'unlimited[[:space:]]+(queued|queue)' "$workflow"; then
    fail 'workflow incorrectly claims unlimited concurrency queueing'
fi
pass 'manual/scheduled runs share non-cancelling concurrency; no unlimited-queue claim is made'

echo 'All final Unity -> Swift idempotency/conflict safeguard fixtures passed.'
