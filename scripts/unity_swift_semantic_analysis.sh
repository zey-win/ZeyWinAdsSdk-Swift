#!/usr/bin/env bash

# Report-only AI semantic analysis for Unity -> Swift parity review.
# It never edits source code, branches, pull requests, or the sync baseline.

set -euo pipefail
shopt -s nullglob
umask 077

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unity_dir=""
detector_report=""
output_file="$repo_root/unity-swift-semantic-analysis.md"
model="${OPENAI_MODEL:-gpt-5.2}"
api_url="${OPENAI_RESPONSES_API_URL:-https://api.openai.com/v1/responses}"
max_diff_bytes="${UNITY_SWIFT_MAX_DIFF_BYTES:-350000}"
max_file_bytes="${UNITY_SWIFT_MAX_FILE_BYTES:-45000}"

usage() {
    cat <<'EOF'
Usage:
  scripts/unity_swift_semantic_analysis.sh \
    --unity-dir <clone> --detector-report <report> [options]

Options:
  --output <path>        Default: unity-swift-semantic-analysis.md.
  --model <model>        Default: OPENAI_MODEL or gpt-5.2.
  --api-url <url>        Default: OpenAI Responses API endpoint.
  -h, --help             Show this message.

Required environment:
  OPENAI_API_KEY          Read only at runtime. Do not put it in a file.

The script sends only the detector report, the Unity diff for COMMON/IOS/
REVIEW_REQUIRED files, and mapped Swift source/test files. It does not edit either
repository and does not update .sync/unity-last-synced-commit.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --unity-dir)
            unity_dir="$2"
            shift 2
            ;;
        --detector-report)
            detector_report="$2"
            shift 2
            ;;
        --output)
            output_file="$2"
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

if [[ -z "$unity_dir" ]] || [[ ! -d "$unity_dir/.git" ]]; then
    echo "--unity-dir must point to a Unity SDK git clone." >&2
    exit 2
fi

if [[ -z "$detector_report" ]] || [[ ! -f "$detector_report" ]]; then
    echo "--detector-report must point to a generated detector report." >&2
    exit 2
fi

mkdir -p "$(dirname "$output_file")"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unity-swift-semantic.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

analysis_input="$tmp_dir/analysis-input.md"
api_payload="$tmp_dir/request.json"
api_response="$tmp_dir/response.json"
relevant_paths="$tmp_dir/relevant-unity-paths.txt"
swift_paths="$tmp_dir/relevant-swift-paths.txt"
unity_range=""

write_header() {
    cat <<EOF
# Unity → Swift AI semantic analysis

- Generated (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')
- Provider: OpenAI Responses API
- Model: \`${model}\`
- Mode: report-only — no Swift/Unity code, branch, PR, merge, or baseline was changed.

EOF
}

write_unavailable_report() {
    local reason="$1"

    {
        write_header
        cat <<EOF
## Analysis unavailable

${reason}

The detector report is still available as a separate artifact. No source code or
\`.sync/unity-last-synced-commit\` was changed.
EOF
    } > "$output_file"
}

# The detector is the source of truth for which Unity paths merit semantic review.
# Android and Unity-only changes remain in its report but are intentionally excluded
# from the API context unless their classification is later changed to REVIEW_REQUIRED.
awk '
    /^### `/{
        path = $0
        sub(/^### `/, "", path)
        sub(/`$/, "", path)
    }
    /^- Classification: \*\*(COMMON|IOS|REVIEW_REQUIRED)\*\*/ && path != "" {
        print path
    }
' "$detector_report" | sort -u > "$relevant_paths"

unity_range="$(awk '/^`[0-9a-f]+\.\.[0-9a-f]+`$/{gsub(/`/, ""); print; exit}' "$detector_report")"
if [[ -z "$unity_range" ]]; then
    write_unavailable_report "The detector report did not contain a resolvable Unity commit range."
    exit 2
fi

if [[ ! -s "$relevant_paths" ]]; then
    {
        write_header
        cat <<'EOF'
## No semantic review required

The detector found no `COMMON`, `IOS`, or `REVIEW_REQUIRED` changes. `ANDROID` and
`UNITY_ONLY` entries remain available in the detector report for auditability and do
not imply a Swift port.
EOF
    } > "$output_file"
    echo "Wrote no-change semantic report: $output_file"
    exit 0
fi

map_swift_patterns() {
    local unity_path="$1"

    case "$unity_path" in
        *ReferralManager.cs|*OfferAssignmentStore.cs)
            cat <<'EOF'
Sources/ZeyWinSDK/ZeyWinSDK.swift
Sources/ZeyWinSDK/Storage/PromotionURLStore.swift
Sources/ZeyWinSDK/Decision/ContentResolver.swift
Tests/ZeyWinSDKTests/PromotionURLPersistenceTests.swift
Tests/ZeyWinSDKTests/SDKDeviceE2ETests.swift
Tests/ZeyWinSDKTests/RealAPIClientTests.swift
EOF
            ;;
        *AdClient.cs|*AdLoader.cs|*AdCache.cs|*Models.cs|Runtime/Ads/*)
            cat <<'EOF'
Sources/ZeyWinSDK/Network/RealAPIClient.swift
Sources/ZeyWinSDK/Network/Models/*.swift
Sources/ZeyWinSDK/Decision/ContentResolver.swift
Sources/ZeyWinSDK/ZeyWinSDK.swift
Tests/ZeyWinSDKTests/RealAPIClientTests.swift
Tests/ZeyWinSDKTests/ContentResolverTests.swift
Tests/ZeyWinSDKTests/SDKDeviceE2ETests.swift
EOF
            ;;
        *DeviceInfo.cs|*DeviceIdentity.cs|*DeviceReport.cs|*GeoCheck.cs|*SecurityCheck.cs)
            cat <<'EOF'
Sources/ZeyWinSDK/Device/*.swift
Sources/ZeyWinSDK/Network/Models/SDKDeviceReport*.swift
Sources/ZeyWinSDK/ZeyWinSDK.swift
Tests/ZeyWinSDKTests/RealAPIClientTests.swift
Tests/ZeyWinSDKTests/SDKDeviceE2ETests.swift
EOF
            ;;
        *WebView*|*HtmlView*)
            cat <<'EOF'
Sources/ZeyWinSDK/Presentation/SDKWebViewController.swift
Sources/ZeyWinSDK/Presentation/ContentPresenter.swift
Tests/ZeyWinSDKTests/SDKWebViewIntegrationTests.swift
Tests/ZeyWinSDKTests/SDKDeviceE2ETests.swift
TestHost/ZeyWinSDKHostedIntegrationTests/HostedOfferPresentationTests.swift
EOF
            ;;
        *Loading*|*StartupOverlay*|*ZeyWinAds.cs|*AutoInitializer*)
            cat <<'EOF'
Sources/ZeyWinSDK/ZeyWinSDK.swift
Sources/ZeyWinSDK/Presentation/ContentPresenter.swift
Sources/ZeyWinSDK/Presentation/SDKLoadingViewController.swift
Tests/ZeyWinSDKTests/SDKDeviceE2ETests.swift
TestHost/ZeyWinSDKHostedIntegrationTests/HostedOfferPresentationTests.swift
EOF
            ;;
        *BannerAd.cs|*NativeAd.cs)
            cat <<'EOF'
Sources/ZeyWinSDK/Presentation/SDKBannerView.swift
Sources/ZeyWinSDK/Presentation/SDKPromoModalView.swift
Sources/ZeyWinSDK/Presentation/ContentPresenter.swift
Tests/ZeyWinSDKTests/ContentResolverTests.swift
Tests/ZeyWinSDKTests/SDKDeviceE2ETests.swift
EOF
            ;;
        *)
            # REVIEW_REQUIRED needs a small, explicitly labelled baseline context;
            # it must not cause a whole-repository upload.
            cat <<'EOF'
Sources/ZeyWinSDK/ZeyWinSDK.swift
Sources/ZeyWinSDK/Decision/ContentResolver.swift
Tests/ZeyWinSDKTests/ContentResolverTests.swift
Tests/ZeyWinSDKTests/SDKDeviceE2ETests.swift
EOF
            ;;
    esac
}

while IFS= read -r unity_path; do
    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue

        for candidate in "$repo_root"/$pattern; do
            [[ -f "$candidate" ]] || continue
            relative_path="${candidate#"$repo_root"/}"
            printf '%s\n' "$relative_path"
        done
    done < <(map_swift_patterns "$unity_path")
done < "$relevant_paths" | sort -u > "$swift_paths"

{
    cat <<'EOF'
# AI semantic parity review request

You are reviewing Unity → native Swift SDK parity. This is a report-only audit.
Do not propose writing code, branches, PRs, merges, or baseline updates. Compare
behavior, not line-for-line source. Treat Android/JNI-only implementation details as
NOT_APPLICABLE_TO_SWIFT unless the shown diff changes a shared API contract.

For every relevant Unity change, use exactly one status:

- ALREADY_IMPLEMENTED
- PARTIALLY_IMPLEMENTED
- MISSING_IN_SWIFT
- NOT_APPLICABLE_TO_SWIFT
- NEEDS_HUMAN_REVIEW

Return Markdown only. Begin with `# Unity → Swift semantic analysis` and a compact
status summary table. Then make one `##` section per relevant Unity change. Every
section must include all of these labelled fields:

1. Unity commit
2. Unity file / symbol
3. Actual behavior change
4. Mapped Swift files / symbols
5. Current Swift behavior
6. Status
7. Parity gap
8. Risk
9. Existing test coverage
10. Recommended tests
11. Swift port needed

Do not infer facts missing from the evidence. Mark ambiguous items
NEEDS_HUMAN_REVIEW. Explicitly say `No` when no port is needed.

## Detector report

EOF
    cat "$detector_report"

    cat <<'EOF'

## Relevant Unity commit range and diff

EOF

    relevant_count="$(wc -l < "$relevant_paths" | tr -d ' ')"
    per_file_diff_bytes=$((max_diff_bytes / relevant_count))
    if [[ "$per_file_diff_bytes" -lt 20000 ]]; then
        per_file_diff_bytes=20000
    fi

    diff_index=0
    while IFS= read -r unity_path; do
        diff_index=$((diff_index + 1))
        diff_file="$tmp_dir/unity-diff-${diff_index}.patch"

        echo "### Unity diff: \`${unity_path}\`"
        git -C "$unity_dir" diff --no-ext-diff --unified=30 \
            "$unity_range" -- "$unity_path" > "$diff_file"
        head -c "$per_file_diff_bytes" "$diff_file"
        printf '\n\n'
    done < "$relevant_paths"

    cat <<'EOF'
## Relevant current Swift source and tests

EOF

    while IFS= read -r swift_path; do
        echo "### Swift file: \`${swift_path}\`"
        head -c "$max_file_bytes" "$repo_root/$swift_path"
        if [[ "$(wc -c < "$repo_root/$swift_path")" -gt "$max_file_bytes" ]]; then
            printf '\n\n[Truncated after %s bytes]\n' "$max_file_bytes"
        fi
        printf '\n\n'
    done < "$swift_paths"
} > "$analysis_input"

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    write_unavailable_report "The required GitHub Actions secret \`OPENAI_API_KEY\` was not available."
    echo "OPENAI_API_KEY is required for semantic analysis." >&2
    exit 3
fi

jq -n \
    --arg model "$model" \
    --rawfile input "$analysis_input" \
    '{
        model: $model,
        store: false,
        instructions: "You are a senior SDK parity reviewer. Follow the requested Markdown schema exactly. Do not include credentials or change instructions.",
        input: [{role: "user", content: [{type: "input_text", text: $input}]}]
    }' > "$api_payload"

if ! curl --fail-with-body --silent --show-error \
    --retry 2 --retry-all-errors --connect-timeout 15 --max-time 180 \
    -X POST "$api_url" \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -H 'Content-Type: application/json' \
    --data-binary "@$api_payload" \
    -o "$api_response"; then
    write_unavailable_report "The OpenAI Responses API request failed. Inspect the workflow log and detector artifact; this job intentionally fails rather than publishing an incomplete AI assessment."
    exit 4
fi

response_status="$(jq -r '.status // "unknown"' "$api_response")"
analysis_text="$(jq -r '[.output[]? | select(.type == "message") | .content[]? | select(.type == "output_text") | .text] | join("\n")' "$api_response")"

if [[ "$response_status" != "completed" ]] || [[ -z "$analysis_text" ]] || [[ "$analysis_text" == "null" ]]; then
    write_unavailable_report "The OpenAI Responses API returned status \`${response_status}\` without a usable text assessment."
    exit 5
fi

{
    write_header
    echo "## AI assessment"
    echo
    printf '%s\n' "$analysis_text"
    cat <<EOF

## Evidence included

- Detector report: \`$(basename "$detector_report")\`
- Unity diff scope: \`COMMON\`, \`IOS\`, and \`REVIEW_REQUIRED\` paths only
- Swift context: $(wc -l < "$swift_paths" | tr -d ' ') mapped source/test files
- API request retention: \`store: false\`

EOF
} > "$output_file"

echo "Wrote AI semantic report: $output_file"
