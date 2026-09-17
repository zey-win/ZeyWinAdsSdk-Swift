#!/usr/bin/env bash

# Report-only AI port-plan generator for Unity -> Swift parity findings.
# It never changes Swift/Unity source, branches, pull requests, or the sync baseline.

set -euo pipefail
umask 077

semantic_report=""
markdown_output="unity-swift-port-plan.md"
json_output="unity-swift-port-plan.json"
model="${OPENAI_MODEL:-gpt-5.6-terra}"
api_url="${OPENAI_RESPONSES_API_URL:-https://api.openai.com/v1/responses}"

usage() {
    cat <<'EOF'
Usage:
  scripts/unity_swift_port_plan.sh --semantic-report <report> [options]

Options:
  --markdown-output <path>  Default: unity-swift-port-plan.md.
  --json-output <path>      Default: unity-swift-port-plan.json.
  --model <model>           Default: OPENAI_MODEL or gpt-5.6-terra.
  --api-url <url>           Default: OpenAI Responses API endpoint.
  -h, --help                Show this message.

Required environment when the plan has eligible items:
  OPENAI_API_KEY             Read only at runtime. Do not put it in a file.

Only semantic findings marked MISSING_IN_SWIFT or PARTIALLY_IMPLEMENTED can enter
the plan. NEEDS_HUMAN_REVIEW is deliberately excluded.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --semantic-report)
            semantic_report="$2"
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

if [[ -z "$semantic_report" ]] || [[ ! -f "$semantic_report" ]]; then
    echo "--semantic-report must point to a generated semantic analysis report." >&2
    exit 2
fi

mkdir -p "$(dirname "$markdown_output")" "$(dirname "$json_output")"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unity-swift-port-plan.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

eligible_sections="$tmp_dir/eligible-sections.md"
status_count_file="$tmp_dir/item-status-count"
eligible_section_count_file="$tmp_dir/eligible-section-count"
prompt_file="$tmp_dir/prompt.md"
payload_file="$tmp_dir/request.json"
response_file="$tmp_dir/response.json"
plan_json_file="$tmp_dir/plan.json"

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
semantic_basename="$(basename "$semantic_report")"

write_markdown_header() {
    cat <<EOF
# Unity → Swift port plan

- Generated (UTC): ${generated_at}
- Source semantic report: \`${semantic_basename}\`
- Mode: plan-only — no Swift/Unity source, branch, PR, merge, or baseline was changed.

EOF
}

write_unavailable_outputs() {
    local reason="$1"

    jq -n \
        --arg generated_at "$generated_at" \
        --arg source_report "$semantic_basename" \
        --arg reason "$reason" \
        '{
            schema: "zeywin.unity-swift-port-plan",
            schema_version: "1.0",
            generated_at_utc: $generated_at,
            source_semantic_report: $source_report,
            plan_status: "unavailable",
            items: [],
            error: $reason
        }' > "$json_output"

    {
        write_markdown_header
        echo '## Plan unavailable'
        echo
        echo "$reason"
    } > "$markdown_output"
}

write_no_op_outputs() {
    jq -n \
        --arg generated_at "$generated_at" \
        --arg source_report "$semantic_basename" \
        '{
            schema: "zeywin.unity-swift-port-plan",
            schema_version: "1.0",
            generated_at_utc: $generated_at,
            source_semantic_report: $source_report,
            plan_status: "no_op",
            items: []
        }' > "$json_output"

    {
        write_markdown_header
        cat <<'EOF'
## No port items

The semantic report contains no findings with status `MISSING_IN_SWIFT` or
`PARTIALLY_IMPLEMENTED`. `ALREADY_IMPLEMENTED`, `NOT_APPLICABLE_TO_SWIFT`, and
`NEEDS_HUMAN_REVIEW` findings are intentionally excluded from an automatic plan.
EOF
    } > "$markdown_output"
}

# Preserve only whole Markdown sections whose explicit Status field is eligible.
# The semantic-analysis prompt emits the field as a label followed by a value, e.g.:
#
#   6. **Status**
#      **MISSING_IN_SWIFT**
#
# It may also be rendered on one line (`**Status:** MISSING_IN_SWIFT`).  Do not
# infer eligibility from the summary table; every selected section needs its own
# explicit status field.
awk -v status_count_file="$status_count_file" -v eligible_section_count_file="$eligible_section_count_file" '
    function normalized(line) {
        line = tolower(line)
        gsub(/[\*`]/, "", line)
        return line
    }
    function status_kind(line) {
        line = normalized(line)
        if (line ~ /(^|[^a-z_])missing_in_swift([^a-z_]|$)/) {
            return "MISSING_IN_SWIFT"
        }
        if (line ~ /(^|[^a-z_])partially_implemented([^a-z_]|$)/) {
            return "PARTIALLY_IMPLEMENTED"
        }
        if (line ~ /(^|[^a-z_])already_implemented([^a-z_]|$)/) {
            return "ALREADY_IMPLEMENTED"
        }
        if (line ~ /(^|[^a-z_])not_applicable_to_swift([^a-z_]|$)/) {
            return "NOT_APPLICABLE_TO_SWIFT"
        }
        if (line ~ /(^|[^a-z_])needs_human_review([^a-z_]|$)/) {
            return "NEEDS_HUMAN_REVIEW"
        }
        return ""
    }
    function is_status_label(line, value) {
        value = normalized(line)
        sub(/^[[:space:]]*[-+][[:space:]]+/, "", value)
        sub(/^[[:space:]]*[0-9]+[.)][[:space:]]+/, "", value)
        if (value !~ /^(semantic[[:space:]]+|parity[[:space:]]+)?status/) {
            return 0
        }
        sub(/^(semantic[[:space:]]+|parity[[:space:]]+)?status/, "", value)
        return value ~ /^[[:space:]]*:?[[:space:]]*(already_implemented|partially_implemented|missing_in_swift|not_applicable_to_swift|needs_human_review)?[[:space:]]*$/
    }
    function record_status(kind) {
        if (kind == "") {
            return
        }
        item_status_count++
        if (kind == "MISSING_IN_SWIFT" || kind == "PARTIALLY_IMPLEMENTED") {
            eligible = 1
        }
    }
    function flush_section() {
        if (section != "" && eligible) {
            printf "%s\n", section
            eligible_section_count++
        }
    }
    /^##( |# )/ {
        flush_section()
        section = $0 ORS
        eligible = 0
        awaiting_status = 0
        next
    }
    {
        section = section $0 ORS
        if (awaiting_status) {
            if ($0 ~ /^[[:space:]]*$/) {
                next
            }
            record_status(status_kind($0))
            awaiting_status = 0
            next
        }
        if (is_status_label($0)) {
            kind = status_kind($0)
            if (kind != "") {
                record_status(kind)
            } else {
                awaiting_status = 1
            }
        }
    }
    END {
        flush_section()
        print item_status_count > status_count_file
        print eligible_section_count > eligible_section_count_file
    }
' "$semantic_report" > "$eligible_sections"

item_status_count="$(tr -d '[:space:]' < "$status_count_file")"
eligible_sections_count="$(tr -d '[:space:]' < "$eligible_section_count_file")"

if [[ -z "$item_status_count" || "$item_status_count" == "0" ]]; then
    if grep -qi 'No semantic review required' "$semantic_report"; then
        write_no_op_outputs
        echo "Wrote no-op port plan."
        exit 0
    fi

    write_unavailable_outputs "The semantic report is malformed: no explicit item Status field was found."
    echo "Malformed semantic report: no explicit item Status field was found." >&2
    exit 3
fi

if [[ ! -s "$eligible_sections" ]]; then
    write_no_op_outputs
    echo "Wrote no-op port plan."
    exit 0
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    write_unavailable_outputs "The required GitHub Actions secret \`OPENAI_API_KEY\` was not available."
    echo "OPENAI_API_KEY is required when the semantic report has port items." >&2
    exit 4
fi

cat > "$prompt_file" <<EOF
You are producing a plan-only Unity → Swift port proposal from a completed semantic
analysis. Do not modify code, create branches, create PRs, commit, push, merge, or
update a sync baseline. Include only findings explicitly marked MISSING_IN_SWIFT or
PARTIALLY_IMPLEMENTED. Never include NEEDS_HUMAN_REVIEW, ALREADY_IMPLEMENTED, or
NOT_APPLICABLE_TO_SWIFT.

For every input finding, return one concrete plan item. Return exactly
${eligible_sections_count} items. Preserve evidence rather than
inventing APIs or behavior. Implementation steps must be ordered and target internal
Swift files/symbols named by the semantic report. Tests must name existing or proposed
XCTest/XCUITest files and state what they verify. Dependencies must list any backend,
privacy, product, real-device, or human decision needed before implementation.

Every item must include patch_ready and blockers. Set patch_ready to true only
when every target_swift_files_symbols entry is a concrete repo-relative path under
Sources/ZeyWinSDK/ or Tests/ZeyWinSDKTests/ (or Package.swift when explicitly
required), and no target-mapping blocker remains. Do not put prose, explanations,
"Human mapping required", assumptions, or blockers in target_swift_files_symbols.
When a concrete Swift target cannot be confirmed, return
target_swift_files_symbols: [], patch_ready: false, and a non-empty blockers
array that states the unresolved contract or integration decision.

Return JSON matching the requested schema exactly.

## Eligible semantic findings

$(cat "$eligible_sections")
EOF

jq -n \
    --arg model "$model" \
    --rawfile input "$prompt_file" \
    '{
        model: $model,
        store: false,
        instructions: "You are a senior SDK parity planner. Produce a read-only implementation plan only; never output code or repository-changing commands.",
        input: [{role: "user", content: [{type: "input_text", text: $input}]}],
        text: {
            format: {
                type: "json_schema",
                name: "unity_swift_port_plan",
                strict: true,
                schema: {
                    type: "object",
                    additionalProperties: false,
                    required: ["schema", "schema_version", "plan_status", "items"],
                    properties: {
                        schema: {type: "string", enum: ["zeywin.unity-swift-port-plan"]},
                        schema_version: {type: "string", enum: ["1.0"]},
                        plan_status: {type: "string", enum: ["ready"]},
                        items: {
                            type: "array",
                            minItems: 1,
                            items: {
                                type: "object",
                                additionalProperties: false,
                                required: [
                                    "id",
                                    "source_status",
                                    "source_unity_commits",
                                    "unity_file_symbol",
                                    "behavior_to_port",
                                    "target_swift_files_symbols",
                                    "patch_ready",
                                    "implementation_steps",
                                    "tests_to_add_or_update",
                                    "risk_level",
                                    "dependencies",
                                    "blockers",
                                    "acceptance_criteria",
                                    "swift_port_needed"
                                ],
                                properties: {
                                    id: {type: "string"},
                                    source_status: {type: "string", enum: ["MISSING_IN_SWIFT", "PARTIALLY_IMPLEMENTED"]},
                                    source_unity_commits: {type: "array", items: {type: "string"}},
                                    unity_file_symbol: {type: "string"},
                                    behavior_to_port: {type: "string"},
                                    target_swift_files_symbols: {type: "array", items: {type: "string"}},
                                    patch_ready: {type: "boolean"},
                                    implementation_steps: {type: "array", items: {type: "string"}},
                                    tests_to_add_or_update: {type: "array", items: {type: "string"}},
                                    risk_level: {type: "string", enum: ["low", "medium", "high"]},
                                    dependencies: {type: "array", items: {type: "string"}},
                                    blockers: {type: "array", items: {type: "string"}},
                                    acceptance_criteria: {type: "array", items: {type: "string"}},
                                    swift_port_needed: {type: "boolean"}
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
    write_unavailable_outputs "The OpenAI Responses API request for the port plan failed."
    exit 5
fi

response_status="$(jq -r '.status // "unknown"' "$response_file")"
plan_text="$(jq -r '[.output[]? | select(.type == "message") | .content[]? | select(.type == "output_text") | .text] | join("\n")' "$response_file")"

if [[ "$response_status" != "completed" ]] || [[ -z "$plan_text" ]] || [[ "$plan_text" == "null" ]]; then
    write_unavailable_outputs "The OpenAI Responses API returned status \`${response_status}\` without a usable port plan."
    exit 6
fi

if ! printf '%s' "$plan_text" | jq -e '
    .schema == "zeywin.unity-swift-port-plan"
    and .schema_version == "1.0"
    and .plan_status == "ready"
    and (.items | type == "array")
    and (.items | length > 0)
    and all(.items[];
        (.source_status == "MISSING_IN_SWIFT" or .source_status == "PARTIALLY_IMPLEMENTED")
        and .swift_port_needed == true
        and (.target_swift_files_symbols | type == "array" and all(.[]; type == "string"))
        and (.blockers | type == "array" and all(.[]; type == "string"))
        and (
            (.patch_ready == true
                and (.target_swift_files_symbols | length > 0)
                and (.blockers | length == 0)
                and all(.target_swift_files_symbols[];
                    test("^Sources/ZeyWinSDK/[^\\n]+\\.swift( — [^\\n]+)?$")
                    or test("^Tests/ZeyWinSDKTests/[^\\n]+\\.swift( — [^\\n]+)?$")
                    or test("^Package\\.swift( — [^\\n]+)?$")
                )
            )
            or (.patch_ready == false
                and (.target_swift_files_symbols | length == 0)
                and (.blockers | length > 0)
            )
        )
    )
' > /dev/null; then
    write_unavailable_outputs "The AI response did not conform to the required port-plan schema."
    exit 7
fi

plan_items_count="$(printf '%s' "$plan_text" | jq '.items | length')"
if [[ "$plan_items_count" != "$eligible_sections_count" ]]; then
    write_unavailable_outputs "The AI response returned ${plan_items_count} plan items for ${eligible_sections_count} eligible semantic findings."
    echo "Port-plan item count does not match eligible semantic findings." >&2
    exit 8
fi

printf '%s' "$plan_text" | jq '.' > "$plan_json_file"

jq \
    --arg generated_at "$generated_at" \
    --arg source_report "$semantic_basename" \
    '. + {
        generated_at_utc: $generated_at,
        source_semantic_report: $source_report
    }' "$plan_json_file" > "$json_output"

{
    write_markdown_header
    echo '## Summary'
    echo
    echo "- Plan status: \`ready\`"
    echo "- Eligible items: $(jq '.items | length' "$json_output")"
    echo
    echo '## Port items'
    echo

    jq -r '
        .items[] |
        "### \(.id)\n\n" +
        "- Source status: `\(.source_status)`\n" +
        "- Source Unity commits: " + (if (.source_unity_commits | length) == 0 then "Not identified in semantic report" else (.source_unity_commits | map("`" + . + "`") | join(", ")) end) + "\n" +
        "- Unity file / symbol: \(.unity_file_symbol)\n" +
        "- Behavior to port: \(.behavior_to_port)\n" +
        "- Target Swift files / symbols: " + (if (.target_swift_files_symbols | length) == 0 then "No concrete target confirmed" else (.target_swift_files_symbols | map("`" + . + "`") | join(", ")) end) + "\n" +
        "- Patch ready: `\(.patch_ready)`\n" +
        "- Risk: `\(.risk_level)`\n" +
        "- Swift port needed: \(.swift_port_needed)\n\n" +
        "#### Implementation steps\n\n" + ([.implementation_steps[] | "- " + .] | join("\n")) + "\n\n" +
        "#### Tests\n\n" + ([.tests_to_add_or_update[] | "- " + .] | join("\n")) + "\n\n" +
        "#### Dependencies\n\n" + ([.dependencies[] | "- " + .] | join("\n")) + "\n\n" +
        "#### Blockers\n\n" + (if (.blockers | length) == 0 then "- None" else ([.blockers[] | "- " + .] | join("\n")) end) + "\n\n" +
        "#### Acceptance criteria\n\n" + ([.acceptance_criteria[] | "- " + .] | join("\n")) + "\n"
    ' "$json_output"
} > "$markdown_output"

echo "Wrote port plan: $markdown_output and $json_output"
