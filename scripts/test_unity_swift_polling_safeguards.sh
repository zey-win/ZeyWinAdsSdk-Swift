#!/usr/bin/env bash

# Network-free fixtures for Swift-only Unity polling. They exercise detector range
# behavior without invoking OpenAI, creating branches, or changing this checkout.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
detector="$repo_root/scripts/unity_swift_change_detector.sh"
workflow="$repo_root/.github/workflows/unity-swift-semantic-analysis.yml"
apply_script="$repo_root/scripts/unity_swift_apply_validated_patch.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unity-swift-polling-tests.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
commit() {
    local repo="$1" message="$2"
    git -C "$repo" add .
    git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm "$message"
}
run_detector() {
    local name="$1" state="$2"
    printf '%s\n' "$state" > "$tmp_dir/baseline"
    bash "$detector" --unity-dir "$unity_repo" --to main --state-file "$tmp_dir/baseline" \
        --output "$tmp_dir/${name}.md" --status-output "$tmp_dir/${name}.status"
}

unity_repo="$tmp_dir/unity"
git init -q -b main "$unity_repo"
printf 'A\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'A'
sha_a="$(git -C "$unity_repo" rev-parse HEAD)"
printf 'B\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'B'
sha_b="$(git -C "$unity_repo" rev-parse HEAD)"
printf 'C\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'C'
sha_c="$(git -C "$unity_repo" rev-parse HEAD)"
printf 'D\n' > "$unity_repo/state.txt"
commit "$unity_repo" 'D'
sha_d="$(git -C "$unity_repo" rev-parse HEAD)"

run_detector baseline_equals_head "$sha_d"
[[ "$(tr -d '[:space:]' < "$tmp_dir/baseline_equals_head.status")" == no_op ]] || fail 'baseline == Unity main was not no_op'
grep -Fq 'No Unity files changed in this range.' "$tmp_dir/baseline_equals_head.md" || fail 'no-op report is missing'
[[ "$(tr -d '[:space:]' < "$tmp_dir/baseline")" == "$sha_d" ]] || fail 'detector changed baseline'
pass 'baseline == Unity main is a clean no_op without state mutation'

run_detector one_commit_range "$sha_c"
[[ "$(tr -d '[:space:]' < "$tmp_dir/one_commit_range.status")" == changes ]] || fail 'one commit range was not changes'
grep -Fq "${sha_c}..${sha_d}" "$tmp_dir/one_commit_range.md" || fail 'one commit range is incorrect'
pass 'baseline behind by one commit produces the complete range'

run_detector multiple_commit_range "$sha_a"
[[ "$(tr -d '[:space:]' < "$tmp_dir/multiple_commit_range.status")" == changes ]] || fail 'multiple commit range was not changes'
grep -Fq "${sha_a}..${sha_d}" "$tmp_dir/multiple_commit_range.md" || fail 'multiple commit range is incorrect'
grep -Fq 'state.txt' "$tmp_dir/multiple_commit_range.md" || fail 'multiple commit diff did not include changed file'
pass 'baseline behind by multiple commits produces one full A..D range'

grep -Fq 'workflow_dispatch:' "$workflow" || fail 'manual trigger is missing'
grep -Fq -- "- cron: '17 * * * *'" "$workflow" || fail 'hourly polling schedule is missing'
grep -Fq 'group: unity-swift-sync-pipeline' "$workflow" || fail 'shared polling concurrency group is missing'
grep -Fq 'cancel-in-progress: false' "$workflow" || fail 'polling runs could cancel a write stage'
grep -Fq 'steps.detector-status.outputs.status == '\''changes'\''' "$workflow" || fail 'semantic AI is not gated on detector changes'
grep -Fq 'state=pending_sync_pr' "$workflow" || fail 'open sync PR reuse is missing'
grep -Fq 'state=pending_baseline_pr' "$workflow" || fail 'merged sync/pending baseline handling is missing'
grep -Fq 'headRefOid' "$workflow" || fail 'pending PR identity is not checked when source branch is absent'
grep -Fq 'FROM_COMMIT: ${{ inputs.from_commit }}' "$workflow" || fail 'manual from_commit override is missing'
if grep -Eq 'repository_dispatch|UNITY_TO_SWIFT_DISPATCH_TOKEN|unity-main-updated' "$workflow"; then
    fail 'Swift-only polling workflow contains a dispatch dependency'
fi
grep -Fq 'apply --check --whitespace=error' "$apply_script" || fail 'patch conflict must fail before push'
pass 'manual/scheduled triggers, serialized concurrency, pending PR reuse, and AI skip gates are configured'

echo 'All Swift-only Unity polling safeguards passed.'
