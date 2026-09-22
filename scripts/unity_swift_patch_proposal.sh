#!/usr/bin/env bash

# Read-only Swift patch proposal generator for a completed Unity -> Swift port plan.
# It only writes proposal artifacts. It never applies a patch or changes repository state.

set -euo pipefail
umask 077

port_plan=""
patch_ready_port_plan=""
markdown_output="patch-proposal.md"
json_output="patch-proposal.json"
patch_output="proposed.patch"
repo_root="$(pwd)"
model="${OPENAI_MODEL:-gpt-5.6-terra}"
api_url="${OPENAI_RESPONSES_API_URL:-https://api.openai.com/v1/responses}"

usage() {
    cat <<'EOF'
Usage:
  scripts/unity_swift_patch_proposal.sh --port-plan <plan.json> [options]

Options:
  --markdown-output <path>  Default: patch-proposal.md.
  --json-output <path>      Default: patch-proposal.json.
  --patch-output <path>     Default: proposed.patch.
  --repo-root <path>        Default: current directory.
  --model <model>           Default: OPENAI_MODEL or gpt-5.6-terra.
  --api-url <url>           Default: OpenAI Responses API endpoint.
  -h, --help                Show this message.

Required environment for a ready port plan:
  OPENAI_API_KEY             Read only at runtime. Do not put it in a file.

The generated proposed.patch is an artifact only. This script never invokes patch,
git write commands, commits, pushes, creates PRs, or updates the sync baseline.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port-plan)
            port_plan="$2"
            shift 2
            ;;
        --markdown-output)
            markdown_output="$2"
            shift 2
            ;;
        --json-output)
            json_output="$2"
            shift 2
            ;;
        --patch-output)
            patch_output="$2"
            shift 2
            ;;
        --repo-root)
            repo_root="$2"
            shift 2
            ;;
        --model)
            model="$2"
            shift 2
            ;;
        --api-url)
            api_url="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$port_plan" ]] || [[ ! -f "$port_plan" ]]; then
    echo "--port-plan must point to a generated Unity -> Swift port-plan JSON file." >&2
    exit 2
fi

if [[ ! -d "$repo_root" ]]; then
    echo "--repo-root must point to the checked-out Swift repository." >&2
    exit 2
fi

mkdir -p "$(dirname "$markdown_output")" "$(dirname "$json_output")" "$(dirname "$patch_output")"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unity-swift-patch-proposal.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

target_paths_file="$tmp_dir/target-paths.txt"
port_item_targets_file="$tmp_dir/port-item-targets.json"
context_file="$tmp_dir/context.md"
payload_file="$tmp_dir/request.json"
response_file="$tmp_dir/response.json"
proposal_json_file="$tmp_dir/proposal.json"

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
port_plan_basename="$(basename "$port_plan")"

write_markdown_header() {
    cat <<EOF
# Unity → Swift patch proposal

- Generated (UTC): ${generated_at}
- Source port plan: \`${port_plan_basename}\`
- Mode: proposal-only — no Swift source, branch, PR, merge, patch application, or sync baseline was changed.

EOF
}

write_patch_comment() {
    local message="$1"
    printf '# %s\n' "$message" > "$patch_output"
}

write_unavailable_outputs() {
    local reason="$1"

    jq -n \
        --arg generated_at "$generated_at" \
        --arg source_port_plan "$port_plan_basename" \
        --arg reason "$reason" \
        '{
            schema: "zeywin.unity-swift-patch-proposal",
            schema_version: "1.0",
            generated_at_utc: $generated_at,
            source_port_plan: $source_port_plan,
            proposal_status: "unavailable",
            items: [],
            error: $reason
        }' > "$json_output"

    {
        write_markdown_header
        echo '## Proposal unavailable'
        echo
        echo "$reason"
    } > "$markdown_output"
    write_patch_comment "No patch was proposed: ${reason}"
}

write_no_op_outputs() {
    jq -n \
        --arg generated_at "$generated_at" \
        --arg source_port_plan "$port_plan_basename" \
        '{
            schema: "zeywin.unity-swift-patch-proposal",
            schema_version: "1.0",
            generated_at_utc: $generated_at,
            source_port_plan: $source_port_plan,
            proposal_status: "no_op",
            items: []
        }' > "$json_output"

    {
        write_markdown_header
        cat <<'EOF'
## No patch proposal

The source port plan has no patch-ready items. No OpenAI request was made and no patch
was generated.
EOF
    } > "$markdown_output"
    write_patch_comment "No patch was proposed because the port plan is no-op."
}

is_safe_relative_path() {
    local path="$1"
    [[ -n "$path" ]] || return 1
    [[ "$path" != /* ]] || return 1
    [[ "$path" != *'//'* ]] || return 1
    [[ "$path" != ../* && "$path" != *'/../'* && "$path" != *'/..' ]] || return 1
    return 0
}

package_explicit=false
is_allowed_path() {
    local path="$1"
    is_safe_relative_path "$path" || return 1

    case "$path" in
        Sources/ZeyWinSDK/*|Tests/ZeyWinSDKTests/*)
            return 0
            ;;
        Package.swift)
            [[ "$package_explicit" == true ]]
            return
            ;;
        *)
            return 1
            ;;
    esac
}

if ! jq -e '
    .schema == "zeywin.unity-swift-port-plan"
    and .schema_version == "1.0"
    and (.plan_status == "ready" or .plan_status == "no_op")
    and (.items | type == "array")
' "$port_plan" > /dev/null; then
    write_unavailable_outputs "The input port plan is malformed or has an unsupported schema."
    echo "Malformed port plan." >&2
    exit 3
fi

port_plan_status="$(jq -r '.plan_status' "$port_plan")"
if [[ "$port_plan_status" == "no_op" ]]; then
    write_no_op_outputs
    echo "Wrote no-op patch proposal."
    exit 0
fi

if ! jq -e '
    def allowed_target:
        test("^Sources/ZeyWinSDK/[^\\n:]+\\.swift( — [^\\n:]+)?$")
        or test("^Tests/ZeyWinSDKTests/[^\\n:]+\\.swift( — [^\\n:]+)?$")
        or test("^Package\\.swift( — [^\\n:]+)?$");
    (.items | length > 0)
    and all(.items[];
        (.id | type == "string" and length > 0)
        and (.source_status == "MISSING_IN_SWIFT" or .source_status == "PARTIALLY_IMPLEMENTED")
        and .swift_port_needed == true
        and (.patch_ready | type == "boolean")
        and (.target_swift_files_symbols | type == "array" and all(.[]; type == "string" and length > 0))
        and (.blockers | type == "array" and all(.[]; type == "string" and length > 0))
        and (
            (.patch_ready == true
                and (.target_swift_files_symbols | length > 0)
                and (.blockers | length == 0)
                and all(.target_swift_files_symbols[];
                    allowed_target
                )
            )
            or (.patch_ready == false
                and (.blockers | length > 0)
                and all(.target_swift_files_symbols[]; allowed_target)
            )
        )
    )
    and (([.items[].id] | length) == ([.items[].id] | unique | length))
' "$port_plan" > /dev/null; then
    write_unavailable_outputs "The ready port plan has no valid eligible items."
    echo "Ready port plan has invalid items." >&2
    exit 4
fi

jq '.items |= map(select(.patch_ready == true))' "$port_plan" > "$tmp_dir/patch-ready-port-plan.json"
patch_ready_port_plan="$tmp_dir/patch-ready-port-plan.json"
patch_ready_item_count="$(jq '.items | length' "$patch_ready_port_plan")"

if [[ "$patch_ready_item_count" == "0" ]]; then
    write_no_op_outputs
    echo "Wrote no-op patch proposal."
    exit 0
fi

jq -r '[.items[].target_swift_files_symbols[] | split(" — ")[0] | gsub("^[[:space:]]+|[[:space:]]+$"; "")] | unique[]' "$patch_ready_port_plan" > "$target_paths_file"
jq '[.items[] | {
    id: .id,
    target_paths: [.target_swift_files_symbols[] | split(" — ")[0] | gsub("^[[:space:]]+|[[:space:]]+$"; "")] | unique
}]' "$patch_ready_port_plan" > "$port_item_targets_file"

while IFS= read -r path; do
    if [[ "$path" == "Package.swift" ]]; then
        package_explicit=true
    fi
done < "$target_paths_file"

while IFS= read -r path; do
    if ! is_allowed_path "$path"; then
        write_unavailable_outputs "The port plan requested a target outside the patch-proposal allowlist: ${path}"
        echo "Forbidden port-plan target: ${path}" >&2
        exit 5
    fi
done < "$target_paths_file"

{
    echo '# Read-only patch-proposal input'
    echo
    echo '## Port plan'
    echo
    jq '.' "$patch_ready_port_plan"
    echo
    echo '## Patch allowlist'
    echo
    echo '- `Sources/ZeyWinSDK/**`'
    echo '- `Tests/ZeyWinSDKTests/**`'
    if [[ "$package_explicit" == true ]]; then
        echo '- `Package.swift` (explicitly named by the port plan)'
    fi
    echo
    echo '## Relevant Swift source/test context'

    while IFS= read -r path; do
        echo
        echo "### ${path}"
        if [[ -f "$repo_root/$path" ]]; then
            echo '```swift'
            sed -n '1,1600p' "$repo_root/$path"
            echo '```'
        else
            echo '_The port plan explicitly names this allowed target, but it does not exist yet._'
        fi
    done < "$target_paths_file"
} > "$context_file"

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    write_unavailable_outputs "The required GitHub Actions secret \`OPENAI_API_KEY\` was not available."
    echo "OPENAI_API_KEY is required for a ready patch proposal." >&2
    exit 6
fi

port_item_count="$patch_ready_item_count"

jq -n \
    --arg model "$model" \
    --rawfile input "$context_file" \
    --argjson expected_item_count "$port_item_count" \
    '{
        model: $model,
        store: false,
        instructions: "You are a senior Swift SDK engineer producing a proposal artifact only. Do not execute, apply, or describe commands that change repositories. Return exactly the requested JSON and standard unified diffs. Patch paths may only be Sources/ZeyWinSDK/**, Tests/ZeyWinSDKTests/**, or Package.swift when the port plan explicitly names it. Never propose .github, .sync, secrets, git configuration, CI, or unrelated files.",
        input: [{role: "user", content: [{type: "input_text", text: $input}]}],
        text: {
            format: {
                type: "json_schema",
                name: "unity_swift_patch_proposal",
                strict: true,
                schema: {
                    type: "object",
                    additionalProperties: false,
                    required: ["schema", "schema_version", "proposal_status", "items"],
                    properties: {
                        schema: {type: "string", enum: ["zeywin.unity-swift-patch-proposal"]},
                        schema_version: {type: "string", enum: ["1.0"]},
                        proposal_status: {type: "string", enum: ["ready"]},
                        items: {
                            type: "array",
                            minItems: $expected_item_count,
                            maxItems: $expected_item_count,
                            items: {
                                type: "object",
                                additionalProperties: false,
                                required: [
                                    "id",
                                    "source_unity_commits",
                                    "target_swift_files",
                                    "exact_proposed_changes",
                                    "unified_diff",
                                    "tests_to_add_or_update",
                                    "assumptions",
                                    "blockers",
                                    "risk_level"
                                ],
                                properties: {
                                    id: {type: "string"},
                                    source_unity_commits: {type: "array", items: {type: "string"}},
                                    target_swift_files: {type: "array", minItems: 1, items: {type: "string"}},
                                    exact_proposed_changes: {type: "array", minItems: 1, items: {type: "string"}},
                                    unified_diff: {type: "string", minLength: 1},
                                    tests_to_add_or_update: {type: "array", items: {type: "string"}},
                                    assumptions: {type: "array", items: {type: "string"}},
                                    blockers: {type: "array", items: {type: "string"}},
                                    risk_level: {type: "string", enum: ["low", "medium", "high"]}
                                }
                            }
                        }
                    }
                }
            }
        }
    }' > "$payload_file"

if ! curl --fail-with-body --silent --show-error \
    --retry 2 --retry-all-errors --connect-timeout 15 --max-time 180 \
    -X POST "$api_url" \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -H 'Content-Type: application/json' \
    --data-binary "@$payload_file" \
    -o "$response_file"; then
    write_unavailable_outputs "The OpenAI Responses API request for the patch proposal failed."
    exit 7
fi

response_status="$(jq -r '.status // "unknown"' "$response_file")"
proposal_text="$(jq -r '[.output[]? | select(.type == "message") | .content[]? | select(.type == "output_text") | .text] | join("\n")' "$response_file")"

if [[ "$response_status" != "completed" ]] || [[ -z "$proposal_text" ]] || [[ "$proposal_text" == "null" ]]; then
    write_unavailable_outputs "The OpenAI Responses API returned status \`${response_status}\` without a usable patch proposal."
    exit 8
fi

if ! printf '%s' "$proposal_text" | jq -e '
    .schema == "zeywin.unity-swift-patch-proposal"
    and .schema_version == "1.0"
    and .proposal_status == "ready"
    and (.items | type == "array" and length > 0)
    and all(.items[];
        (.id | type == "string" and length > 0)
        and (.source_unity_commits | type == "array")
        and (.target_swift_files | type == "array" and length > 0)
        and (.exact_proposed_changes | type == "array" and length > 0)
        and (.unified_diff | type == "string" and length > 0 and test("(?m)^diff --git ") and test("(?m)^@@ "))
        and (.tests_to_add_or_update | type == "array")
        and (.assumptions | type == "array")
        and (.blockers | type == "array")
        and (.risk_level == "low" or .risk_level == "medium" or .risk_level == "high")
    )
' > /dev/null; then
    write_unavailable_outputs "The AI response did not conform to the required patch-proposal schema."
    exit 9
fi

expected_ids="$(jq -c '[.items[].id] | sort' "$patch_ready_port_plan")"
proposal_ids="$(printf '%s' "$proposal_text" | jq -c '[.items[].id] | sort')"
proposal_item_count="$(printf '%s' "$proposal_text" | jq '.items | length')"
if [[ "$proposal_item_count" != "$port_item_count" ]] || [[ "$proposal_ids" != "$expected_ids" ]]; then
    write_unavailable_outputs "The AI response items do not exactly match the ready port-plan item IDs."
    echo "Patch-proposal item IDs do not match port-plan IDs." >&2
    exit 10
fi

printf '%s' "$proposal_text" | jq -r '.items[].unified_diff' > "$patch_output"

if ! grep -q '^diff --git ' "$patch_output"; then
    write_unavailable_outputs "The AI response contained an empty unified patch."
    echo "Patch proposal did not contain a unified diff." >&2
    exit 12
fi

proposal_item_index=0
while IFS= read -r proposal_item; do
    proposal_item_index=$((proposal_item_index + 1))
    item_id="$(printf '%s' "$proposal_item" | jq -r '.id')"
    item_targets_file="$tmp_dir/item-${proposal_item_index}-port-plan-targets.txt"
    item_declared_targets_file="$tmp_dir/item-${proposal_item_index}-declared-targets.txt"
    item_patch_file="$tmp_dir/item-${proposal_item_index}.patch"
    item_patch_paths_file="$tmp_dir/item-${proposal_item_index}-patch-paths.txt"

    if ! jq -e --arg id "$item_id" 'any(.[]; .id == $id)' "$port_item_targets_file" > /dev/null; then
        write_unavailable_outputs "The AI response item ${item_id} does not map to a source port-plan item."
        echo "Unknown patch-proposal item ID: ${item_id}" >&2
        exit 10
    fi

    jq -r --arg id "$item_id" '.[] | select(.id == $id) | .target_paths[]' "$port_item_targets_file" > "$item_targets_file"
    printf '%s' "$proposal_item" | jq -r '.target_swift_files[]' | sort -u > "$item_declared_targets_file"

    while IFS= read -r path; do
        if ! is_allowed_path "$path"; then
            write_unavailable_outputs "The AI response declared a target outside the patch-proposal allowlist: ${path}"
            echo "Forbidden declared patch target: ${path}" >&2
            exit 11
        fi
        if ! grep -Fqx "$path" "$item_targets_file"; then
            write_unavailable_outputs "The AI response item ${item_id} declared ${path}, which is not a target path for that port-plan item."
            echo "Cross-item or unplanned declared patch target: ${path}" >&2
            exit 11
        fi
    done < "$item_declared_targets_file"

    printf '%s' "$proposal_item" | jq -r '.unified_diff' > "$item_patch_file"
    awk '
        function emit(path) {
            if (path == "/dev/null") {
                return
            }
            sub(/^a\//, "", path)
            sub(/^b\//, "", path)
            print path
        }
        /^diff --git / {
            emit($3)
            emit($4)
            next
        }
        /^--- / {
            emit($2)
            next
        }
        /^\+\+\+ / {
            emit($2)
        }
    ' "$item_patch_file" | sort -u > "$item_patch_paths_file"

    while IFS= read -r path; do
        if ! is_allowed_path "$path"; then
            write_unavailable_outputs "The unified patch changes a forbidden path: ${path}"
            echo "Forbidden unified patch path: ${path}" >&2
            exit 11
        fi
        if ! grep -Fqx "$path" "$item_declared_targets_file"; then
            write_unavailable_outputs "The unified patch for ${item_id} changes ${path}, which the AI did not declare for that item."
            echo "Undeclared item unified patch path: ${path}" >&2
            exit 11
        fi
        if ! grep -Fqx "$path" "$item_targets_file"; then
            write_unavailable_outputs "The unified patch for ${item_id} changes ${path}, which is not a target path for that port-plan item."
            echo "Cross-item or unplanned unified patch path: ${path}" >&2
            exit 11
        fi
    done < "$item_patch_paths_file"
done < <(printf '%s' "$proposal_text" | jq -c '.items[]')

printf '%s' "$proposal_text" | jq '.' > "$proposal_json_file"
jq \
    --arg generated_at "$generated_at" \
    --arg source_port_plan "$port_plan_basename" \
    '. + {
        generated_at_utc: $generated_at,
        source_port_plan: $source_port_plan
    }' "$proposal_json_file" > "$json_output"

{
    write_markdown_header
    echo '## Summary'
    echo
    echo '- Proposal status: `ready`'
    echo "- Port-plan items: ${port_item_count}"
    echo
    echo '## Proposed changes'
    echo
    jq -r '
        .items[] |
        "### \(.id)\n\n" +
        "- Source Unity commits: " + (if (.source_unity_commits | length) == 0 then "Not supplied" else (.source_unity_commits | map("`" + . + "`") | join(", ")) end) + "\n" +
        "- Target Swift files: " + (.target_swift_files | map("`" + . + "`") | join(", ")) + "\n" +
        "- Risk: `\(.risk_level)`\n\n" +
        "#### Exact proposed changes\n\n" + ([.exact_proposed_changes[] | "- " + .] | join("\n")) + "\n\n" +
        "#### Tests to add or update\n\n" + ([.tests_to_add_or_update[] | "- " + .] | join("\n")) + "\n\n" +
        "#### Assumptions\n\n" + ([.assumptions[] | "- " + .] | join("\n")) + "\n\n" +
        "#### Blockers\n\n" + ([.blockers[] | "- " + .] | join("\n")) + "\n"
    ' "$json_output"
    echo
    echo '## Unified patch (not applied)'
    echo
    echo '```diff'
    sed -n '1,12000p' "$patch_output"
    echo '```'
} > "$markdown_output"

echo "Wrote read-only patch proposal: $markdown_output, $json_output, and $patch_output"
