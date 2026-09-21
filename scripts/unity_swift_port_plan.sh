#!/usr/bin/env bash

# Report-only AI port-plan generator for Unity -> Swift parity findings.
# It never changes Swift/Unity source, branches, pull requests, or the sync baseline.

set -euo pipefail
umask 077

semantic_report=""
markdown_output="unity-swift-port-plan.md"
json_output="unity-swift-port-plan.json"
diagnostics_output=""
model="${OPENAI_MODEL:-gpt-5.6-terra}"
api_url="${OPENAI_RESPONSES_API_URL:-https://api.openai.com/v1/responses}"

usage() {
    cat <<'EOF'
Usage:
  scripts/unity_swift_port_plan.sh --semantic-report <report> [options]

Options:
  --markdown-output <path>  Default: unity-swift-port-plan.md.
  --json-output <path>      Default: unity-swift-port-plan.json.
  --diagnostics-output <path>
                           Default: <json-output>.diagnostics.json. Stores raw
                           AI responses and validation results; never secrets.
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
        --diagnostics-output)
            diagnostics_output="$2"
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

if [[ -z "$diagnostics_output" ]]; then
    diagnostics_output="${json_output}.diagnostics.json"
fi

mkdir -p "$(dirname "$markdown_output")" "$(dirname "$json_output")" "$(dirname "$diagnostics_output")"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unity-swift-port-plan.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

eligible_sections="$tmp_dir/eligible-sections.md"
status_count_file="$tmp_dir/item-status-count"
eligible_section_count_file="$tmp_dir/eligible-section-count"
prompt_file="$tmp_dir/prompt.md"
payload_file="$tmp_dir/request.json"
response_file="$tmp_dir/response.json"
plan_json_file="$tmp_dir/plan.json"
diagnostic_attempts_file="$tmp_dir/diagnostic-attempts.json"
printf '[]\n' > "$diagnostic_attempts_file"

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

write_diagnostics() {
    local final_status="$1" repair_retry_used="$2" final_error="${3:-}"

    jq -n \
        --arg generated_at "$generated_at" \
        --arg source_report "$semantic_basename" \
        --arg model "$model" \
        --arg final_status "$final_status" \
        --arg final_error "$final_error" \
        --argjson repair_retry_used "$repair_retry_used" \
        --slurpfile attempts "$diagnostic_attempts_file" \
        '{
            schema: "zeywin.unity-swift-port-plan-diagnostics",
            schema_version: "1.0",
            generated_at_utc: $generated_at,
            source_semantic_report: $source_report,
            model: $model,
            repair_retry_used: $repair_retry_used,
            final_status: $final_status,
            validation_error: (if $final_error == "" then null else $final_error end),
            attempts: $attempts[0]
        }' > "$diagnostics_output"
}

record_attempt() {
    local attempt="$1" response_status="$2" validation_error="$3" raw_response_file="$4" raw_text_file="$5"
    local attempt_file="$tmp_dir/attempt-${attempt}.json"

    jq -n \
        --argjson attempt "$attempt" \
        --arg response_status "$response_status" \
        --arg validation_error "$validation_error" \
        --rawfile raw_api_response "$raw_response_file" \
        --rawfile raw_ai_response "$raw_text_file" \
        '{
            attempt: $attempt,
            response_status: $response_status,
            validation_error: (if $validation_error == "" then null else $validation_error end),
            raw_api_response: $raw_api_response,
            raw_ai_response: $raw_ai_response
        }' > "$attempt_file"
    jq --slurpfile attempt "$attempt_file" '. + $attempt' "$diagnostic_attempts_file" > "$tmp_dir/diagnostic-attempts-next.json"
    mv "$tmp_dir/diagnostic-attempts-next.json" "$diagnostic_attempts_file"
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

    write_diagnostics unavailable "${repair_retry_used:-false}" "$reason"
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

    write_diagnostics no_op false
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

Return only one JSON object matching the requested schema exactly. Do not use
Markdown fences. Do not add prose, explanations, headings, or any text before or
after the JSON object.

## Eligible semantic findings

$(cat "$eligible_sections")
EOF

jq -n \
    --arg model "$model" \
    --rawfile input "$prompt_file" \
    '{
        model: $model,
        store: false,
        instructions: "You are a senior SDK parity planner. Produce a read-only implementation plan only; never output code or repository-changing commands. Return only the requested JSON object: no Markdown fences and no prose around it.",
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

request_plan() {
    local request_file="$1" output_file="$2"
    curl --fail-with-body --silent --show-error \
        --retry 2 --retry-all-errors --connect-timeout 15 --max-time 180 \
        -X POST "$api_url" \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -H 'Content-Type: application/json' \
        --data-binary "@$request_file" \
        -o "$output_file"
}

extract_plan_text() {
    local api_response="$1" text_output="$2"
    response_status="unknown"
    extraction_error=""

    if ! jq -e . "$api_response" > /dev/null 2>&1; then
        extraction_error="The OpenAI Responses API envelope was malformed JSON."
        : > "$text_output"
        return 1
    fi
    response_status="$(jq -r '.status // "unknown"' "$api_response")"
    if ! jq -r '[.output[]? | select(.type == "message") | .content[]? | select(.type == "output_text") | .text] | join("\n")' "$api_response" > "$text_output"; then
        extraction_error="The OpenAI Responses API envelope did not contain a readable output payload."
        return 1
    fi
    if [[ "$response_status" != "completed" ]]; then
        extraction_error="The OpenAI Responses API returned status \`${response_status}\` without a usable port plan."
        return 1
    fi
}

validate_plan_text() {
    local text_file="$1"
    validation_error=""

    if ! jq -e . "$text_file" > /dev/null 2>&1; then
        validation_error="The AI response was not valid JSON."
        return 1
    fi
    if ! jq -e -s '
        length == 1 and
        (.[0] |
            .schema == "zeywin.unity-swift-port-plan"
            and .schema_version == "1.0"
            and .plan_status == "ready"
            and (.items | type == "array")
            and (.items | length > 0)
            and all(.items[];
                (.id | type == "string" and length > 0)
                and (.source_status == "MISSING_IN_SWIFT" or .source_status == "PARTIALLY_IMPLEMENTED")
                and (.source_unity_commits | type == "array" and all(.[]; type == "string"))
                and (.unity_file_symbol | type == "string")
                and (.behavior_to_port | type == "string")
                and (.target_swift_files_symbols | type == "array" and all(.[]; type == "string"))
                and (.patch_ready | type == "boolean")
                and (.implementation_steps | type == "array" and all(.[]; type == "string"))
                and (.tests_to_add_or_update | type == "array" and all(.[]; type == "string"))
                and (.risk_level == "low" or .risk_level == "medium" or .risk_level == "high")
                and (.dependencies | type == "array" and all(.[]; type == "string"))
                and (.blockers | type == "array" and all(.[]; type == "string"))
                and (.acceptance_criteria | type == "array" and all(.[]; type == "string"))
                and .swift_port_needed == true
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
        )
    ' "$text_file" > /dev/null; then
        validation_error="The AI response did not conform to the required port-plan schema."
        return 1
    fi

    plan_items_count="$(jq -s '.[0].items | length' "$text_file")"
    if [[ "$plan_items_count" != "$eligible_sections_count" ]]; then
        validation_error="The AI response returned ${plan_items_count} plan items for ${eligible_sections_count} eligible semantic findings."
        return 1
    fi
}

repair_retry_used=false
first_plan_text_file="$tmp_dir/plan-attempt-1.txt"
if ! request_plan "$payload_file" "$response_file"; then
    write_unavailable_outputs "The OpenAI Responses API request for the port plan failed."
    exit 5
fi
if ! extract_plan_text "$response_file" "$first_plan_text_file"; then
    record_attempt 1 "$response_status" "$extraction_error" "$response_file" "$first_plan_text_file"
    write_unavailable_outputs "$extraction_error"
    exit 6
fi

if validate_plan_text "$first_plan_text_file"; then
    record_attempt 1 "$response_status" "" "$response_file" "$first_plan_text_file"
    final_plan_text_file="$first_plan_text_file"
else
    record_attempt 1 "$response_status" "$validation_error" "$response_file" "$first_plan_text_file"
    repair_retry_used=true
    repair_prompt_file="$tmp_dir/repair-prompt.md"
    repair_payload_file="$tmp_dir/repair-request.json"
    repair_response_file="$tmp_dir/repair-response.json"
    repair_plan_text_file="$tmp_dir/plan-attempt-2.txt"

    cat > "$repair_prompt_file" <<EOF
Return only one corrected JSON object matching the existing
\`zeywin.unity-swift-port-plan\` schema version \`1.0\`. Do not use Markdown
fences or prose. Do not omit fields, relax schema requirements, invent missing
facts, or create a no-op plan. Preserve exactly ${eligible_sections_count} eligible
items from the semantic report.

The first response failed validation for this exact reason:

\`${validation_error}\`

## Original semantic report

$(cat "$semantic_report")

## First raw AI response

$(cat "$first_plan_text_file")
EOF
    jq \
        --arg instructions "You are repairing a failed JSON-only SDK port plan response. Return only one corrected JSON object matching the supplied strict schema; no Markdown fences or prose." \
        --rawfile input "$repair_prompt_file" \
        '.instructions = $instructions | .input[0].content[0].text = $input' \
        "$payload_file" > "$repair_payload_file"

    if ! request_plan "$repair_payload_file" "$repair_response_file"; then
        write_unavailable_outputs "The OpenAI Responses API repair request for the port plan failed."
        exit 5
    fi
    if ! extract_plan_text "$repair_response_file" "$repair_plan_text_file"; then
        record_attempt 2 "$response_status" "$extraction_error" "$repair_response_file" "$repair_plan_text_file"
        write_unavailable_outputs "$extraction_error"
        exit 6
    fi
    if ! validate_plan_text "$repair_plan_text_file"; then
        record_attempt 2 "$response_status" "$validation_error" "$repair_response_file" "$repair_plan_text_file"
        write_unavailable_outputs "The repair retry did not conform to the required port-plan schema: ${validation_error}"
        exit 7
    fi
    record_attempt 2 "$response_status" "" "$repair_response_file" "$repair_plan_text_file"
    final_plan_text_file="$repair_plan_text_file"
fi

jq -s '.[0]' "$final_plan_text_file" > "$plan_json_file"

jq \
    --arg generated_at "$generated_at" \
    --arg source_report "$semantic_basename" \
    '. + {
        generated_at_utc: $generated_at,
        source_semantic_report: $source_report
    }' "$plan_json_file" > "$json_output"

write_diagnostics ready "$repair_retry_used"

{
    write_markdown_header
    echo '## Summary'
    echo
    echo "- Plan status: \`ready\`"
    echo "- Eligible items: $(jq '.items | length' "$json_output")"
    echo "- Repair retry used: \`${repair_retry_used}\`"
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
