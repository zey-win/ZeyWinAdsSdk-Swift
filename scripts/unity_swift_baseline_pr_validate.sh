#!/usr/bin/env bash

# Read-only validation for an open sync/baseline-<sha7> PR. It compares the
# proposed baseline with the current origin/main baseline so stale PRs cannot move
# the sync checkpoint backward after another baseline PR has merged.

set -euo pipefail
umask 077

swift_repo="$(pwd)"
unity_repo=""
main_ref="origin/main"
branch_ref="HEAD"
branch_name=""
report_output="unity-swift-baseline-pr-validation.json"
baseline_relative_path=".sync/unity-last-synced-commit"

usage() {
    cat <<'EOF'
Usage:
  scripts/unity_swift_baseline_pr_validate.sh \
    --swift-repo <repo> --unity-repo <repo> \
    --main-ref <origin/main> --branch-ref <PR-head-ref> \
    --branch-name <sync/baseline-sha7> --report-output <json>

This command is read-only. It reports ready, no_op (already advanced), or exits
non-zero as unavailable when a baseline PR is stale, malformed, or unsafe.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --swift-repo) swift_repo="$2"; shift 2 ;;
        --unity-repo) unity_repo="$2"; shift 2 ;;
        --main-ref) main_ref="$2"; shift 2 ;;
        --branch-ref) branch_ref="$2"; shift 2 ;;
        --branch-name) branch_name="$2"; shift 2 ;;
        --report-output) report_output="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -d "$swift_repo" && -d "$unity_repo" && "$branch_name" =~ ^sync/baseline-[0-9a-f]{7}$ ]] || {
    usage >&2
    exit 2
}
mkdir -p "$(dirname "$report_output")"

write_report() {
    local status="$1" reason="$2" current="${3:-}" proposed="${4:-}"
    jq -n \
        --arg status "$status" \
        --arg reason "$reason" \
        --arg main_ref "$main_ref" \
        --arg branch_ref "$branch_ref" \
        --arg branch_name "$branch_name" \
        --arg current_baseline "$current" \
        --arg proposed_baseline "$proposed" \
        '{
            schema: "zeywin.unity-swift-baseline-pr-validation",
            schema_version: "1.0",
            status: $status,
            reason: $reason,
            main_ref: $main_ref,
            branch_ref: $branch_ref,
            branch_name: $branch_name,
            current_baseline: $current_baseline,
            proposed_baseline: $proposed_baseline
        }' > "$report_output"
}
fail() {
    write_report unavailable "$1" "${current_baseline:-}" "${proposed_baseline:-}"
    echo "$1" >&2
    exit 1
}
read_baseline() {
    local ref="$1"
    git -C "$swift_repo" show "${ref}:${baseline_relative_path}" 2> /dev/null | tr -d '[:space:]'
}

git -C "$swift_repo" rev-parse --verify --quiet "${main_ref}^{commit}" > /dev/null \
    || fail "Current main ref is not an available commit: ${main_ref}."
git -C "$swift_repo" rev-parse --verify --quiet "${branch_ref}^{commit}" > /dev/null \
    || fail "Baseline PR branch ref is not an available commit: ${branch_ref}."

current_baseline="$(read_baseline "$main_ref")"
proposed_baseline="$(read_baseline "$branch_ref")"
[[ "$current_baseline" =~ ^[0-9a-f]{40}$ ]] \
    || fail "Current origin/main baseline is not a lowercase 40-character SHA."
[[ "$proposed_baseline" =~ ^[0-9a-f]{40}$ ]] \
    || fail "Proposed baseline is not a lowercase 40-character SHA."
[[ "$branch_name" == "sync/baseline-${proposed_baseline:0:7}" ]] \
    || fail "Baseline PR branch SHA7 does not match the proposed baseline SHA."

git -C "$unity_repo" rev-parse --verify --quiet 'main^{commit}' > /dev/null \
    || fail "Unity repository does not have a main commit."
git -C "$unity_repo" cat-file -e "${proposed_baseline}^{commit}" 2> /dev/null \
    || fail "Proposed baseline SHA is not a commit available in the Unity repository."
git -C "$unity_repo" merge-base --is-ancestor "$proposed_baseline" main \
    || fail "Proposed baseline SHA is not in Unity main history."
git -C "$unity_repo" cat-file -e "${current_baseline}^{commit}" 2> /dev/null \
    || fail "Current baseline SHA is not a commit available in the Unity repository."

if [[ "$current_baseline" == "$proposed_baseline" ]]; then
    write_report no_op "Current main already equals the proposed baseline; close this obsolete PR without merging." "$current_baseline" "$proposed_baseline"
    echo "Baseline PR is obsolete: current main already equals ${proposed_baseline}."
    exit 0
fi

changed_paths="$(git -C "$swift_repo" diff --name-only "${main_ref}...${branch_ref}")"
[[ "$changed_paths" == "$baseline_relative_path" ]] \
    || fail "Baseline PR changes files other than ${baseline_relative_path}: ${changed_paths:-<none>}."
[[ "$(git -C "$swift_repo" rev-list --count "${main_ref}..${branch_ref}")" == "1" ]] \
    || fail "Baseline PR branch does not contain exactly one baseline-only commit beyond current main."

git -C "$unity_repo" merge-base --is-ancestor "$current_baseline" "$proposed_baseline" \
    || fail "Current main baseline is newer than, or unrelated to, the proposed baseline; this PR is stale."

write_report ready "Current main baseline is an ancestor of the proposed Unity main baseline and the PR is baseline-only." "$current_baseline" "$proposed_baseline"
echo "Baseline PR is ready: ${current_baseline} -> ${proposed_baseline}."
