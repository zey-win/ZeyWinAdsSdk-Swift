#!/usr/bin/env bash

# Local, network-free fixtures for the write/idempotency safeguards in 6.5B-2.
# It never touches the caller's repository: every Git worktree lives under mktemp.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
apply_script="$repo_root/scripts/unity_swift_apply_validated_patch.sh"
identity_script="$repo_root/scripts/unity_swift_sync_branch_identity.sh"
workflow="$repo_root/.github/workflows/unity-swift-semantic-analysis.yml"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unity-swift-sync-safeguards.XXXXXX")"
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

make_repo() {
    local dir="$1"
    mkdir -p "$dir/Sources/ZeyWinSDK/Core" "$dir/.sync"
    printf 'enum Existing {}\n' > "$dir/Sources/ZeyWinSDK/Core/Existing.swift"
    printf 'baseline\n' > "$dir/.sync/unity-last-synced-commit"
    git -C "$dir" init -q
    git -C "$dir" add .
    git -C "$dir" -c user.name=test -c user.email=test@example.invalid commit -qm initial
}

make_ready_artifacts() {
    local dir="$1"
    local patch="$dir/proposed.patch"
    local plan="$dir/port-plan.json"
    local proposal="$dir/patch-proposal.json"
    mkdir -p "$dir"
    printf '%s\n' \
        'diff --git a/Sources/ZeyWinSDK/Core/Generated.swift b/Sources/ZeyWinSDK/Core/Generated.swift' \
        'new file mode 100644' \
        'index 0000000..d1ef3de' \
        '--- /dev/null' \
        '+++ b/Sources/ZeyWinSDK/Core/Generated.swift' \
        '@@ -0,0 +1 @@' \
        '+enum Generated {}' > "$patch"
    jq -n '
      {
        schema: "zeywin.unity-swift-port-plan", schema_version: "1.0", plan_status: "ready",
        items: [{
          id: "new-swift-file", source_status: "MISSING_IN_SWIFT", swift_port_needed: true,
          patch_ready: true,
          source_unity_commits: ["0123456789012345678901234567890123456789"],
          target_swift_files_symbols: ["Sources/ZeyWinSDK/Core/Generated.swift — Generated"],
          blockers: []
        }]
      }' > "$plan"
    jq -n --rawfile patch "$patch" '
      {
        schema: "zeywin.unity-swift-patch-proposal", schema_version: "1.0", proposal_status: "ready",
        items: [{
          id: "new-swift-file", source_unity_commits: ["0123456789012345678901234567890123456789"],
          target_swift_files: ["Sources/ZeyWinSDK/Core/Generated.swift"],
          exact_proposed_changes: ["Add Generated."], unified_diff: ($patch | rtrimstr("\n"))
        }]
      }' > "$proposal"
}

valid_repo="$tmp_dir/valid"
valid_artifacts="$tmp_dir/valid-artifacts"
make_repo "$valid_repo"
make_ready_artifacts "$valid_artifacts"
bash "$apply_script" --mode apply --repo-root "$valid_repo" \
    --port-plan "$valid_artifacts/port-plan.json" --proposal "$valid_artifacts/patch-proposal.json" \
    --patch "$valid_artifacts/proposed.patch" --report-output "$valid_artifacts/report.md" \
    --applied-patch-output "$valid_artifacts/applied.patch" --changed-paths-output "$valid_artifacts/changed.txt"
grep -Fqx 'Sources/ZeyWinSDK/Core/Generated.swift' "$valid_artifacts/changed.txt" || fail 'new Swift file was not reported'
[[ -f "$valid_repo/Sources/ZeyWinSDK/Core/Generated.swift" ]] || fail 'new Swift file was not created'
git -C "$valid_repo" add -- "$(cat "$valid_artifacts/changed.txt")"
git -C "$valid_repo" -c user.name=test -c user.email=test@example.invalid commit -qm 'fixture new file'
git -C "$valid_repo" show --format='' --name-only HEAD | grep -Fqx 'Sources/ZeyWinSDK/Core/Generated.swift' || fail 'new Swift file was not committed'
pass 'new Swift file is validated and included in a commit'

dirty_repo="$tmp_dir/forbidden-untracked"
dirty_artifacts="$tmp_dir/forbidden-untracked-artifacts"
make_repo "$dirty_repo"
make_ready_artifacts "$dirty_artifacts"
mkdir -p "$dirty_repo/.github"
printf 'forbidden\n' > "$dirty_repo/.github/untracked.yml"
expect_failure forbidden_untracked_before_apply \
    bash "$apply_script" --mode apply --repo-root "$dirty_repo" \
    --port-plan "$dirty_artifacts/port-plan.json" --proposal "$dirty_artifacts/patch-proposal.json" \
    --patch "$dirty_artifacts/proposed.patch" --report-output "$dirty_artifacts/report.md" \
    --applied-patch-output "$dirty_artifacts/applied.patch"
[[ ! -f "$dirty_repo/Sources/ZeyWinSDK/Core/Generated.swift" ]] || fail 'patch applied despite forbidden untracked file'

full_head='abcdef0123456789abcdef0123456789abcdef01'
same_short_different_head='abcdef0fffffffffffffffffffffffffffffffff'
identity_repo="$tmp_dir/identity"
make_repo "$identity_repo"
git -C "$identity_repo" -c user.name=test -c user.email=test@example.invalid commit --allow-empty -qm 'Sync Unity abcdef0 changes to Swift' -m "Unity-Head: ${full_head}"
bash "$identity_script" --repo-root "$identity_repo" --ref HEAD --unity-head "$full_head"
pass 'exact full Unity SHA trailer verifies existing branch'
expect_failure same_sha7_different_full_sha \
    bash "$identity_script" --repo-root "$identity_repo" --ref HEAD --unity-head "$same_short_different_head"

pr_step="$(awk '/- name: Create or find sync pull request/{capture=1} /- name: Verify auto-created PR receives the required CI check/{capture=0} capture{print}' "$workflow")"
printf '%s\n' "$pr_step" | grep -Fq 'gh pr list --head "$sync_branch" --base main --state open' || fail 'existing PR lookup is missing'
printf '%s\n' "$pr_step" | grep -Fq 'if [[ "$existing" != "null" && -n "$existing" ]]' || fail 'existing PR no-duplicate exit is missing'
printf '%s\n' "$pr_step" | grep -Fq 'gh pr create --base main --head "$sync_branch"' || fail 'verified existing branch cannot create a missing PR'
printf '%s\n' "$pr_step" | grep -Fq 'steps.branch.outputs.state' && fail 'PR creation is still incorrectly limited to new branches'
pass 'verified branch creates only a missing PR and reuses an existing PR'

grep -Fq 'UNITY_SWIFT_SYNC_TOKEN' "$workflow" || fail 'non-recursive automation token is not configured'
grep -Fq "required_name='Required iOS Simulator XCTest'" "$workflow" || fail 'required PR CI check is not awaited'
grep -Fq 'gh pr checks "$pr_number"' "$workflow" || fail 'PR check publication is not verified'
pass 'auto-created PR is required to publish the protected CI check'

echo 'All Unity → Swift sync write/idempotency safeguard fixtures passed.'
