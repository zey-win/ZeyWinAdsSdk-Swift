#!/usr/bin/env bash

# Validates and, only when explicitly requested, applies a previously validated
# Unity -> Swift patch proposal. This script never creates branches, commits, pushes,
# creates PRs, merges, changes git config, or updates the Unity sync baseline.

set -euo pipefail
umask 077

mode=""
port_plan=""
proposal=""
patch_file=""
repo_root="$(pwd)"
report_output="sync-validation-report.md"
applied_patch_output="applied-patch.diff"
status_output=""
changed_paths_output=""

usage() {
    cat <<'EOF'
Usage:
  scripts/unity_swift_apply_validated_patch.sh --mode validate|apply \
    --port-plan <json> --proposal <json> --patch <diff> [options]

Options:
  --repo-root <path>             Default: current directory.
  --report-output <path>         Default: sync-validation-report.md.
  --applied-patch-output <path>  Default: applied-patch.diff.
  --status-output <path>         Write ready, no_op, or unavailable for workflows.
  --changed-paths-output <path>  Write every changed path after a successful apply.

The validate mode is read-only. The apply mode runs git apply only after all contract,
per-item path, and clean-apply checks pass. Neither mode performs git writes beyond
the working-tree patch in apply mode.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) mode="$2"; shift 2 ;;
        --port-plan) port_plan="$2"; shift 2 ;;
        --proposal) proposal="$2"; shift 2 ;;
        --patch) patch_file="$2"; shift 2 ;;
        --repo-root) repo_root="$2"; shift 2 ;;
        --report-output) report_output="$2"; shift 2 ;;
        --applied-patch-output) applied_patch_output="$2"; shift 2 ;;
        --status-output) status_output="$2"; shift 2 ;;
        --changed-paths-output) changed_paths_output="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ "$mode" != "validate" && "$mode" != "apply" ]] || [[ ! -f "$port_plan" ]] || [[ ! -f "$proposal" ]] || [[ ! -f "$patch_file" ]] || [[ ! -d "$repo_root" ]]; then
    usage >&2
    exit 2
fi

mkdir -p "$(dirname "$report_output")" "$(dirname "$applied_patch_output")"
[[ -z "$changed_paths_output" ]] || mkdir -p "$(dirname "$changed_paths_output")"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unity-swift-apply.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

write_status() { [[ -z "$status_output" ]] || printf '%s\n' "$1" > "$status_output"; }
write_changed_paths() {
    local source="$1"
    [[ -z "$changed_paths_output" ]] || cp "$source" "$changed_paths_output"
}
write_report() {
    local status="$1" message="$2"
    {
        echo '# Unity → Swift validated patch sync'
        echo
        echo "- Mode: \`${mode}\`"
        echo "- Status: \`${status}\`"
        echo "- ${message}"
    } > "$report_output"
}
fail() {
    local message="$1"
    write_report unavailable "$message"
    printf '# Patch was not applied: %s\n' "$message" > "$applied_patch_output"
    write_status unavailable
    echo "$message" >&2
    exit 1
}
no_op() {
    write_report no_op "No patch-ready proposal item exists; no branch, patch, commit, push, or PR is needed."
    printf '# No patch was applied.\n' > "$applied_patch_output"
    write_status no_op
    echo "Validated patch sync is no-op."
    exit 0
}
is_safe_path() {
    local path="$1"
    [[ -n "$path" && "$path" != /* && "$path" != *'//'* && "$path" != ../* && "$path" != *'/../'* && "$path" != *'/..' ]]
}
package_explicit=false
is_allowed_path() {
    local path="$1"
    is_safe_path "$path" || return 1
    case "$path" in
        Sources/ZeyWinSDK/*|Tests/ZeyWinSDKTests/*) return 0 ;;
        Package.swift) [[ "$package_explicit" == true ]] ;;
        *) return 1 ;;
    esac
}
extract_patch_paths() {
    awk '
        function emit(path) { if (path != "/dev/null") { sub(/^a\//, "", path); sub(/^b\//, "", path); print path } }
        /^diff --git / { emit($3); emit($4); next }
        /^--- / { emit($2); next }
        /^\+\+\+ / { emit($2) }
    ' "$1" | sort -u
}
collect_worktree_paths() {
    {
        git -C "$repo_root" diff --name-only
        git -C "$repo_root" ls-files --others --exclude-standard
    } | LC_ALL=C sort -u
}

if ! jq -e '
    .schema == "zeywin.unity-swift-port-plan" and .schema_version == "1.0"
    and (.plan_status == "ready" or .plan_status == "no_op") and (.items | type == "array")
' "$port_plan" > /dev/null; then
    fail "Port plan schema is invalid."
fi
if [[ "$(jq -r '.plan_status' "$port_plan")" == "no_op" ]]; then no_op; fi

if ! jq -e '
    (.items | length > 0)
    and all(.items[];
        (.id | type == "string" and length > 0)
        and (.source_status == "MISSING_IN_SWIFT" or .source_status == "PARTIALLY_IMPLEMENTED")
        and .swift_port_needed == true and (.patch_ready | type == "boolean")
        and (.target_swift_files_symbols | type == "array" and all(.[]; type == "string" and length > 0))
        and (.blockers | type == "array" and all(.[]; type == "string" and length > 0))
        and ((.patch_ready == true and (.target_swift_files_symbols | length > 0) and (.blockers | length == 0))
             or (.patch_ready == false and (.target_swift_files_symbols | length == 0) and (.blockers | length > 0)))
    )
    and (([.items[].id] | length) == ([.items[].id] | unique | length))
' "$port_plan" > /dev/null; then
    fail "Ready port plan does not satisfy the patch-ready contract."
fi

patch_ready_plan="$tmp_dir/patch-ready-port-plan.json"
jq '.items |= map(select(.patch_ready == true))' "$port_plan" > "$patch_ready_plan"
ready_count="$(jq '.items | length' "$patch_ready_plan")"
if [[ "$ready_count" == "0" ]]; then
    if [[ "$(jq -r '.proposal_status // "invalid"' "$proposal")" != "no_op" ]]; then
        fail "A zero-patch-ready port plan must have a no_op patch proposal."
    fi
    no_op
fi

if ! jq -e '
    .schema == "zeywin.unity-swift-patch-proposal" and .schema_version == "1.0"
    and .proposal_status == "ready" and (.items | type == "array" and length > 0)
    and all(.items[];
        (.id | type == "string" and length > 0)
        and (.source_unity_commits | type == "array")
        and (.target_swift_files | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
        and (.unified_diff | type == "string" and test("(?m)^diff --git ") and test("(?m)^@@ "))
    )
' "$proposal" > /dev/null; then
    fail "Patch proposal schema is invalid."
fi

expected_ids="$(jq -c '[.items[].id] | sort' "$patch_ready_plan")"
proposal_ids="$(jq -c '[.items[].id] | sort' "$proposal")"
[[ "$expected_ids" == "$proposal_ids" && "$(jq '.items | length' "$proposal")" == "$ready_count" ]] || fail "Patch proposal item IDs do not match patch-ready port-plan items."

expected_patch="$tmp_dir/expected.patch"
jq -r '.items[].unified_diff' "$proposal" > "$expected_patch"
cmp -s "$expected_patch" "$patch_file" || fail "proposed.patch does not exactly match patch-proposal JSON."
[[ -s "$patch_file" ]] && grep -q '^diff --git ' "$patch_file" || fail "Patch is empty or not unified diff format."

port_targets="$tmp_dir/port-targets.json"
jq '[.items[] | {id, commits: (.source_unity_commits | sort), targets: [.target_swift_files_symbols[] | split(" — ")[0]]}]' "$patch_ready_plan" > "$port_targets"
if jq -e '.[] | .targets[] | select(. == "Package.swift")' "$port_targets" > /dev/null; then package_explicit=true; fi

item_index=0
while IFS= read -r item; do
    item_index=$((item_index + 1))
    id="$(printf '%s' "$item" | jq -r '.id')"
    targets="$tmp_dir/targets-${item_index}.txt"
    declared="$tmp_dir/declared-${item_index}.txt"
    item_patch="$tmp_dir/item-${item_index}.patch"
    paths="$tmp_dir/paths-${item_index}.txt"
    jq -r --arg id "$id" '.[] | select(.id == $id) | .targets[]' "$port_targets" > "$targets"
    [[ -s "$targets" ]] || fail "Patch proposal item ${id} has no matching port-plan target mapping."
    expected_commits="$(jq -c --arg id "$id" '.[] | select(.id == $id) | .commits' "$port_targets")"
    actual_commits="$(printf '%s' "$item" | jq -c '.source_unity_commits | sort')"
    [[ "$expected_commits" == "$actual_commits" ]] || fail "Patch proposal source commits do not match port-plan item ${id}."
    printf '%s' "$item" | jq -r '.target_swift_files[]' | sort -u > "$declared"
    while IFS= read -r path; do is_allowed_path "$path" && grep -Fqx "$path" "$targets" || fail "Proposal target ${path} is outside port-plan item ${id} allowlist."; done < "$declared"
    printf '%s' "$item" | jq -r '.unified_diff' > "$item_patch"
    extract_patch_paths "$item_patch" > "$paths"
    [[ -s "$paths" ]] || fail "Patch proposal item ${id} has no changed paths."
    while IFS= read -r path; do
        is_allowed_path "$path" || fail "Patch changes forbidden path ${path}."
        grep -Fqx "$path" "$declared" || fail "Patch path ${path} is not declared by proposal item ${id}."
        grep -Fqx "$path" "$targets" || fail "Patch path ${path} is outside port-plan item ${id} allowlist."
    done < "$paths"
done < <(jq -c '.items[]' "$proposal")

if [[ "$mode" == "validate" ]]; then
    write_report ready "Proposal, patch bytes, item IDs, source commits, and per-item target paths were validated without applying a patch."
    printf '# Patch validated but not applied in validate mode.\n' > "$applied_patch_output"
    write_status ready
    echo "Validated patch sync is ready."
    exit 0
fi

# `git diff --quiet` alone misses untracked files.  Refuse every pre-existing
# worktree change so that a post-apply untracked file is attributable to this patch.
[[ -z "$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)" ]] || fail "Working tree is not clean before patch apply."
git -C "$repo_root" apply --check --whitespace=error "$patch_file" || fail "Patch does not apply cleanly to current Swift main."
git -C "$repo_root" apply --whitespace=error "$patch_file" || fail "Patch application failed."

changed="$tmp_dir/changed.txt"
collect_worktree_paths > "$changed"
[[ -s "$changed" ]] || fail "Patch applied without a working-tree diff."
while IFS= read -r path; do
    is_allowed_path "$path" || fail "Post-apply diff contains forbidden path ${path}."
    if ! jq -r '.[].targets[]' "$port_targets" | grep -Fqx "$path"; then fail "Post-apply diff contains unexpected path ${path}."; fi
done < "$changed"
git -C "$repo_root" diff --quiet -- .sync/unity-last-synced-commit || fail "Sync baseline was modified."
# The validated input is the complete binary-safe diff, including newly-created
# files that `git diff` would not list until staged.
cp "$patch_file" "$applied_patch_output"
write_changed_paths "$changed"
{
    write_report ready "Patch applied after dry-run validation."
    echo
    echo '## Changed Swift files'
    sed 's/^/- `&`/' "$changed"
} > "$report_output"
write_status ready
echo "Validated patch was applied locally."
