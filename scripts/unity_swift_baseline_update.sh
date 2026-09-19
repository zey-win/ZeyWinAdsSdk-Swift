#!/usr/bin/env bash

# Deterministically verifies a merged Unity sync commit and, only in prepare mode,
# advances the local baseline file for a separate baseline-only PR. It never creates
# branches, commits, pushes, PRs, merges, alters Git config, or changes Swift source.

set -euo pipefail
umask 077

mode="validate"
swift_repo="$(pwd)"
unity_repo=""
source_ref=""
source_branch=""
report_output="unity-swift-baseline-validation.json"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
identity_script="$script_dir/unity_swift_sync_branch_identity.sh"
baseline_relative_path=".sync/unity-last-synced-commit"

usage() {
    cat <<'EOF'
Usage:
  scripts/unity_swift_baseline_update.sh \
    --mode validate|prepare \
    --swift-repo <repo> \
    --unity-repo <repo> \
    --source-ref <git-ref> \
    --source-branch <sync/unity-sha7> \
    --report-output <json>

validate is read-only. prepare changes only .sync/unity-last-synced-commit after
all trailer, branch, Unity-main, and ancestry checks pass.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) mode="$2"; shift 2 ;;
        --swift-repo) swift_repo="$2"; shift 2 ;;
        --unity-repo) unity_repo="$2"; shift 2 ;;
        --source-ref) source_ref="$2"; shift 2 ;;
        --source-branch) source_branch="$2"; shift 2 ;;
        --report-output) report_output="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ "$mode" == "validate" || "$mode" == "prepare" ]] \
    && [[ -d "$swift_repo" && -d "$unity_repo" ]] \
    && [[ -n "$source_ref" && "$source_branch" =~ ^sync/unity-[0-9a-f]{7}$ ]] \
    && [[ -x "$identity_script" || -f "$identity_script" ]] || {
    usage >&2
    exit 2
}

mkdir -p "$(dirname "$report_output")"
baseline_file="$swift_repo/$baseline_relative_path"

write_report() {
    local status="$1" reason="$2" old_baseline="${3:-}" new_baseline="${4:-}"
    jq -n \
        --arg status "$status" \
        --arg reason "$reason" \
        --arg source_ref "$source_ref" \
        --arg source_branch "$source_branch" \
        --arg old_baseline "$old_baseline" \
        --arg new_baseline "$new_baseline" \
        '{
            schema: "zeywin.unity-swift-baseline-update",
            schema_version: "1.0",
            status: $status,
            reason: $reason,
            source_ref: $source_ref,
            source_branch: $source_branch,
            old_baseline: $old_baseline,
            new_baseline: $new_baseline
        }' > "$report_output"
}
fail() {
    write_report unavailable "$1" "${old_baseline:-}" "${unity_head:-}"
    echo "$1" >&2
    exit 1
}

git -C "$swift_repo" rev-parse --verify --quiet "${source_ref}^{commit}" > /dev/null \
    || fail "Source sync ref is not an available commit: ${source_ref}."
[[ -f "$baseline_file" ]] || fail "Baseline file is missing: ${baseline_relative_path}."

old_baseline="$(tr -d '[:space:]' < "$baseline_file")"
[[ "$old_baseline" =~ ^[0-9a-f]{40}$ ]] \
    || fail "Current baseline is not a lowercase 40-character SHA."

message="$(git -C "$swift_repo" log -1 --format=%B "$source_ref")"
# `interpret-trailers --parse` de-duplicates equal trailers. The raw count keeps
# this baseline gate strict when a commit contains duplicate Unity-Head lines.
raw_trailers="$(printf '%s\n' "$message" | awk '/^Unity-Head:[[:space:]]*/ { sub(/^Unity-Head:[[:space:]]*/, ""); print }')"
raw_trailer_count="$(printf '%s\n' "$raw_trailers" | sed '/^$/d' | wc -l | tr -d ' ')"
parsed_trailers="$(printf '%s\n' "$message" | git interpret-trailers --parse | awk -F': ' '$1 == "Unity-Head" { print $2 }')"
parsed_trailer_count="$(printf '%s\n' "$parsed_trailers" | sed '/^$/d' | wc -l | tr -d ' ')"
[[ "$raw_trailer_count" == "1" && "$raw_trailers" =~ ^[0-9a-f]{40}$ \
    && "$parsed_trailer_count" == "1" && "$parsed_trailers" == "$raw_trailers" ]] \
    || fail "Source sync commit must contain exactly one lowercase 40-character Unity-Head trailer."
unity_head="$raw_trailers"

expected_short_sha="${unity_head:0:7}"
[[ "$source_branch" == "sync/unity-${expected_short_sha}" ]] \
    || fail "Source branch SHA7 does not match Unity-Head trailer."

# Reuse the existing exact-trailer verifier so this gate cannot drift from sync-apply.
bash "$identity_script" --repo-root "$swift_repo" --ref "$source_ref" --unity-head "$unity_head" \
    || fail "Source sync commit did not pass exact Unity-Head identity verification."

git -C "$unity_repo" rev-parse --verify --quiet "main^{commit}" > /dev/null \
    || fail "Unity repository does not have a main commit."
git -C "$unity_repo" cat-file -e "${unity_head}^{commit}" 2> /dev/null \
    || fail "Unity-Head is not a commit available in the Unity repository."
git -C "$unity_repo" merge-base --is-ancestor "$unity_head" main \
    || fail "Unity-Head is not in Unity main history."
git -C "$unity_repo" cat-file -e "${old_baseline}^{commit}" 2> /dev/null \
    || fail "Current baseline is not a commit available in the Unity repository."
git -C "$unity_repo" merge-base --is-ancestor "$old_baseline" "$unity_head" \
    || fail "Unity-Head is older than, or unrelated to, the current baseline."

if [[ "$old_baseline" == "$unity_head" ]]; then
    write_report no_op "Baseline already equals the verified Unity-Head." "$old_baseline" "$unity_head"
    echo "Baseline already equals ${unity_head}."
    exit 0
fi

if [[ "$mode" == "validate" ]]; then
    write_report ready "Source trailer, branch identity, Unity main membership, and ancestry were verified." "$old_baseline" "$unity_head"
    echo "Baseline update is ready: ${old_baseline} -> ${unity_head}."
    exit 0
fi

[[ -z "$(git -C "$swift_repo" status --porcelain=v1 --untracked-files=all)" ]] \
    || fail "Swift checkout is not clean before baseline preparation."
printf '%s\n' "$unity_head" > "$baseline_file"
changed_paths="$(git -C "$swift_repo" diff --name-only)"
[[ "$changed_paths" == "$baseline_relative_path" ]] \
    || fail "Baseline preparation changed paths other than ${baseline_relative_path}."

write_report prepared "Only the baseline file was changed after all verification checks." "$old_baseline" "$unity_head"
echo "Prepared baseline update: ${old_baseline} -> ${unity_head}."
