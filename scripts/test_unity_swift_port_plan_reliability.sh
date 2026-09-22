#!/usr/bin/env bash

# Network-free reliability fixtures for the AI port-plan response boundary.
# A temporary curl shim returns deterministic Responses API envelopes; no API key,
# repository source, branch, or sync baseline is changed.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port_plan_script="$repo_root/scripts/unity_swift_port_plan.sh"
patch_proposal_script="$repo_root/scripts/unity_swift_patch_proposal.sh"
apply_script="$repo_root/scripts/unity_swift_apply_validated_patch.sh"
baseline_file="$repo_root/.sync/unity-last-synced-commit"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unity-swift-port-plan-reliability.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

printf '%s\n' '## Fixture finding' '- **Status:** `MISSING_IN_SWIFT`' > "$tmp_dir/semantic.md"
baseline_before="$(shasum -a 256 "$baseline_file" | awk '{print $1}')"

valid_plan="$tmp_dir/valid-plan.json"
jq -n '
  {
    schema: "zeywin.unity-swift-port-plan", schema_version: "1.0", plan_status: "ready",
    items: [{
      id: "fixture-item", source_status: "MISSING_IN_SWIFT",
      source_unity_commits: ["0123456789012345678901234567890123456789"],
      unity_file_symbol: "Runtime/Core/Fixture.cs — Fixture",
      behavior_to_port: "Port the fixture behavior.",
      target_swift_files_symbols: [], patch_ready: false,
      implementation_steps: ["Confirm the target."],
      tests_to_add_or_update: ["Add a deterministic fixture test."],
      risk_level: "medium", dependencies: ["Product confirmation."],
      blockers: ["Swift target is not confirmed."],
      acceptance_criteria: ["The behavior is approved."], swift_port_needed: true
    }]
  }' > "$valid_plan"

mock_bin="$tmp_dir/bin"
mkdir -p "$mock_bin"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    '' \
    'output=""' \
    'while [[ $# -gt 0 ]]; do' \
    '    if [[ "$1" == "-o" ]]; then' \
    '        output="$2"' \
    '        shift 2' \
    '    else' \
    '        shift' \
    '    fi' \
    'done' \
    '[[ -n "$output" ]] || exit 2' \
    'count=0' \
    '[[ ! -f "$MOCK_CURL_COUNT_FILE" ]] || count="$(<"$MOCK_CURL_COUNT_FILE")"' \
    'count=$((count + 1))' \
    'printf "%s\n" "$count" > "$MOCK_CURL_COUNT_FILE"' \
    'cp "$MOCK_CURL_RESPONSES_DIR/response-${count}.json" "$output"' \
    > "$mock_bin/curl"
chmod +x "$mock_bin/curl"

write_envelope() {
    local text_file="$1" output_file="$2"
    jq -n --rawfile text "$text_file" \
        '{status: "completed", output: [{type: "message", content: [{type: "output_text", text: $text}]}]}' \
        > "$output_file"
}
run_case() {
    local name="$1" first_text="$2" second_text="$3" expected_status="$4" expected_calls="$5" expected_retry="$6"
    local case_dir="$tmp_dir/$name"
    mkdir -p "$case_dir/responses"
    printf '%s' "$first_text" > "$case_dir/first.txt"
    write_envelope "$case_dir/first.txt" "$case_dir/responses/response-1.json"
    if [[ -n "$second_text" ]]; then
        printf '%s' "$second_text" > "$case_dir/second.txt"
        write_envelope "$case_dir/second.txt" "$case_dir/responses/response-2.json"
    fi

    set +e
    PATH="$mock_bin:$PATH" \
    OPENAI_API_KEY='fixture-key' \
    MOCK_CURL_COUNT_FILE="$case_dir/count" \
    MOCK_CURL_RESPONSES_DIR="$case_dir/responses" \
    bash "$port_plan_script" --semantic-report "$tmp_dir/semantic.md" \
        --markdown-output "$case_dir/plan.md" --json-output "$case_dir/plan.json" \
        --diagnostics-output "$case_dir/diagnostics.json" --api-url 'https://fixture.invalid/v1/responses' \
        >"$case_dir/stdout" 2>"$case_dir/stderr"
    local result=$?
    set -e

    if [[ "$expected_status" == ready ]]; then
        [[ "$result" == 0 ]] || fail "$name should have succeeded"
    else
        [[ "$result" != 0 ]] || fail "$name should have failed safely"
    fi
    [[ "$(tr -d '[:space:]' < "$case_dir/count")" == "$expected_calls" ]] || fail "$name used an unexpected API attempt count"
    [[ "$(jq -r '.plan_status' "$case_dir/plan.json")" == "$expected_status" ]] || fail "$name wrote an unexpected plan status"
    jq -e --arg expected "$expected_retry" '.repair_retry_used == ($expected == "true")' "$case_dir/diagnostics.json" > /dev/null \
        || fail "$name wrote an unexpected repair retry diagnostic"
    [[ "$(jq -r '.final_status' "$case_dir/diagnostics.json")" == "$expected_status" ]] || fail "$name wrote an unexpected final diagnostic status"
    [[ "$(jq '.attempts | length' "$case_dir/diagnostics.json")" == "$expected_calls" ]] || fail "$name did not preserve diagnostics for every attempt"
    jq -e '.attempts[0].attempt == 1 and (.attempts[0].raw_api_response | type == "string") and (.attempts[0].raw_ai_response | type == "string")' "$case_dir/diagnostics.json" > /dev/null \
        || fail "$name did not preserve the first raw response diagnostics"
    if [[ "$expected_calls" == 2 ]]; then
        jq -e '.attempts[1].attempt == 2 and (.attempts[1].raw_api_response | type == "string") and (.attempts[1].raw_ai_response | type == "string")' "$case_dir/diagnostics.json" > /dev/null \
            || fail "$name did not preserve the repair response diagnostics"
    fi
    pass "$name"
}

valid_text="$(<"$valid_plan")"
candidate_plan="$tmp_dir/candidate-plan.json"
actionable_plan="$tmp_dir/actionable-plan.json"
actionable_with_blockers_plan="$tmp_dir/actionable-with-blockers-plan.json"
actionable_without_targets_plan="$tmp_dir/actionable-without-targets-plan.json"
forbidden_target_plan="$tmp_dir/forbidden-target-plan.json"
legacy_separator_plan="$tmp_dir/legacy-separator-plan.json"
jq '.items[0].target_swift_files_symbols = ["Sources/ZeyWinSDK/Network/Models/SDKInitRequest.swift — SDKInitRequest.sdkVersion"]' "$valid_plan" > "$candidate_plan"
jq '.items[0].patch_ready = true | .items[0].blockers = [] | .items[0].target_swift_files_symbols = ["Sources/ZeyWinSDK/Network/Models/SDKInitRequest.swift — SDKInitRequest.sdkVersion"]' "$valid_plan" > "$actionable_plan"
jq '.items[0].patch_ready = true | .items[0].target_swift_files_symbols = ["Sources/ZeyWinSDK/Network/Models/SDKInitRequest.swift — SDKInitRequest.sdkVersion"]' "$valid_plan" > "$actionable_with_blockers_plan"
jq '.items[0].patch_ready = true | .items[0].blockers = []' "$valid_plan" > "$actionable_without_targets_plan"
jq '.items[0].target_swift_files_symbols = ["README.md — forbidden"]' "$valid_plan" > "$forbidden_target_plan"
jq '.items[0].target_swift_files_symbols = ["Sources/ZeyWinSDK/Network/Models/SDKInitRequest.swift::SDKInitRequest.sdkVersion"]' "$valid_plan" > "$legacy_separator_plan"
candidate_text="$(<"$candidate_plan")"
actionable_text="$(<"$actionable_plan")"
actionable_with_blockers_text="$(<"$actionable_with_blockers_plan")"
actionable_without_targets_text="$(<"$actionable_without_targets_plan")"
forbidden_target_text="$(<"$forbidden_target_plan")"
legacy_separator_text="$(<"$legacy_separator_plan")"
invalid_schema='{"schema":"wrong","schema_version":"1.0","plan_status":"ready","items":[]}'
malformed_text='{not-json'
fenced_text="\`\`\`json
${valid_text}
\`\`\`"

run_case valid_first_response "$valid_text" '' ready 1 false
run_case blocked_empty_targets "$valid_text" '' ready 1 false
run_case blocked_known_candidate_targets "$candidate_text" '' ready 1 false
run_case patch_ready_valid_targets "$actionable_text" '' ready 1 false
run_case patch_ready_with_blockers "$actionable_with_blockers_text" "$actionable_with_blockers_text" unavailable 2 true
run_case patch_ready_without_targets "$actionable_without_targets_text" "$actionable_without_targets_text" unavailable 2 true
run_case forbidden_candidate_target "$forbidden_target_text" "$forbidden_target_text" unavailable 2 true
run_case legacy_double_colon_target "$legacy_separator_text" '' ready 1 false
run_case malformed_then_valid "$malformed_text" "$valid_text" ready 2 true
run_case invalid_schema_then_valid "$invalid_schema" "$valid_text" ready 2 true
run_case null_json_then_valid 'null' "$valid_text" ready 2 true
run_case malformed_then_malformed "$malformed_text" "$malformed_text" unavailable 2 true
run_case invalid_schema_then_invalid_schema "$invalid_schema" "$invalid_schema" unavailable 2 true
run_case fenced_json_then_valid "$fenced_text" "$valid_text" ready 2 true

[[ "$(jq -r '.items[0].patch_ready' "$tmp_dir/patch_ready_valid_targets/plan.json")" == true ]] \
    || fail 'valid patch-ready plan was not actionable'
[[ "$(jq -r '.items[0].target_swift_files_symbols[0]' "$tmp_dir/legacy_double_colon_target/plan.json")" == 'Sources/ZeyWinSDK/Network/Models/SDKInitRequest.swift — SDKInitRequest.sdkVersion' ]] \
    || fail 'legacy :: target was not safely normalized to canonical format'

bash "$patch_proposal_script" \
    --port-plan "$tmp_dir/blocked_known_candidate_targets/plan.json" \
    --markdown-output "$tmp_dir/blocked-candidate-proposal.md" \
    --json-output "$tmp_dir/blocked-candidate-proposal.json" \
    --patch-output "$tmp_dir/blocked-candidate.patch"
[[ "$(jq -r '.proposal_status' "$tmp_dir/blocked-candidate-proposal.json")" == no_op ]] \
    || fail 'patch_ready=false candidate targets reached patch proposal generation'
bash "$apply_script" --mode validate --repo-root "$tmp_dir" \
    --port-plan "$tmp_dir/blocked_known_candidate_targets/plan.json" \
    --proposal "$tmp_dir/blocked-candidate-proposal.json" \
    --patch "$tmp_dir/blocked-candidate.patch" \
    --report-output "$tmp_dir/blocked-candidate-apply.md" \
    --applied-patch-output "$tmp_dir/blocked-candidate-applied.patch"
pass 'blocked candidate targets remain informational for patch proposal and validated apply'

baseline_after="$(shasum -a 256 "$baseline_file" | awk '{print $1}')"
[[ "$baseline_before" == "$baseline_after" ]] || fail 'port-plan reliability fixtures changed the sync baseline'
pass 'all response failures and repair retries leave the production baseline unchanged'

echo 'All Unity -> Swift port-plan reliability fixtures passed.'
