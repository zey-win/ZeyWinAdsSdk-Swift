#!/usr/bin/env bash

# Report-only Unity -> Swift change detector.
# It never edits Swift production code, creates branches, commits, or pull requests.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unity_dir=""
state_file="$repo_root/.sync/unity-last-synced-commit"
output_file="$repo_root/unity-swift-change-report.md"
from_commit=""
to_ref="origin/main"
status_output=""

usage() {
    cat <<'EOF'
Usage:
  scripts/unity_swift_change_detector.sh --unity-dir <clone> [options]

Options:
  --from <commit>       Override the manually maintained last synced commit.
                        This does not update the state file.
  --to <ref>            Unity target ref. Default: origin/main.
  --state-file <path>   Default: .sync/unity-last-synced-commit.
  --output <path>       Default: unity-swift-change-report.md.
  --status-output <path>  Write changes, no_op, bootstrap, or unavailable.
  -h, --help            Show this message.

The state file must contain one manually reviewed Unity commit. If it is UNSET,
the detector writes a bootstrap report and exits successfully without guessing
a baseline.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --unity-dir)
            unity_dir="$2"
            shift 2
            ;;
        --from)
            from_commit="$2"
            shift 2
            ;;
        --to)
            to_ref="$2"
            shift 2
            ;;
        --state-file)
            state_file="$2"
            shift 2
            ;;
        --output)
            output_file="$2"
            shift 2
            ;;
        --status-output)
            status_output="$2"
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

mkdir -p "$(dirname "$output_file")"
[[ -z "$status_output" ]] || mkdir -p "$(dirname "$status_output")"
write_status() { [[ -z "$status_output" ]] || printf '%s\n' "$1" > "$status_output"; }

if [[ -z "$from_commit" ]] && [[ -f "$state_file" ]]; then
    from_commit="$(awk '!/^[[:space:]]*(#|$)/ { print; exit }' "$state_file")"
fi

to_commit="$(git -C "$unity_dir" rev-parse --verify "${to_ref}^{commit}")"
to_short="$(git -C "$unity_dir" rev-parse --short "$to_commit")"

write_header() {
    cat <<EOF
# Unity → Swift change detector report

- Generated (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')
- Unity repository: \`https://github.com/zey-win/ZeyWinAdsSDK-Unity.git\`
- Target: \`${to_ref}\` (\`${to_commit}\`)
- Mode: report-only — no Swift code, state, branch, PR, or merge was changed.

EOF
}

if [[ -z "$from_commit" ]] || [[ "$from_commit" == "UNSET" ]]; then
    {
        write_header
        cat <<EOF
## Bootstrap required

No trusted \`last_synced_commit\` is configured. Set one manually in
\`${state_file#$repo_root/}\` after reviewing the corresponding Unity → Swift
parity point, or rerun with \`--from <commit>\` for a one-off report.

The detector deliberately does not infer or update this value.
EOF
    } > "$output_file"

    echo "Wrote bootstrap report: $output_file"
    write_status bootstrap
    exit 0
fi

if ! from_commit="$(git -C "$unity_dir" rev-parse --verify "${from_commit}^{commit}" 2>/dev/null)"; then
    {
        write_header
        cat <<EOF
## Baseline unavailable

The configured baseline could not be resolved in the Unity clone:

\`\`\`
${from_commit}
\`\`\`

Fetch the commit into the clone or provide a reachable \`--from <commit>\`.
EOF
    } > "$output_file"
    echo "Unity baseline is unavailable: $from_commit" >&2
    write_status unavailable
    exit 2
fi

from_short="$(git -C "$unity_dir" rev-parse --short "$from_commit")"

classify() {
    local path="$1"

    case "$path" in
        Runtime/Plugins/iOS/*|Runtime/Core/AppTrackingTransparency.cs)
            echo "IOS"
            ;;
        Runtime/Plugins/Android/*|AndroidInstrumentedTests~/*|Runtime/Core/Android*.cs|Runtime/Core/GoogleAdsAttribution.cs)
            echo "ANDROID"
            ;;
        Editor/*|Tests/*|Samples~/*|*.meta|README.md|CHANGELOG.md|LICENSE.md|SECURITY.md|package.json|*.asmdef)
            echo "UNITY_ONLY"
            ;;
        Runtime/Ads/*|Runtime/ZeyWinAds.cs|Runtime/ZeyWinAdsAutoInitializer.cs|Runtime/Core/AdClient.cs|Runtime/Core/AdLoader.cs|Runtime/Core/AdCache.cs|Runtime/Core/Models.cs|Runtime/Core/DeviceInfo.cs|Runtime/Core/DeviceIdentity.cs|Runtime/Core/DeviceReport.cs|Runtime/Core/GeoCheck.cs|Runtime/Core/ReferralManager.cs|Runtime/Core/OfferAssignmentStore.cs|Runtime/Core/UrlHelper.cs)
            echo "COMMON"
            ;;
        *)
            echo "REVIEW_REQUIRED"
            ;;
    esac
}

swift_counterparts() {
    local path="$1"

    case "$path" in
        *ReferralManager.cs|*OfferAssignmentStore.cs)
            echo "Sources/ZeyWinSDK/ZeyWinSDK.swift; Sources/ZeyWinSDK/Storage/PromotionURLStore.swift; Sources/ZeyWinSDK/Decision/ContentResolver.swift"
            ;;
        *AdClient.cs|*AdLoader.cs|*Models.cs|Runtime/Ads/*)
            echo "Sources/ZeyWinSDK/Network/RealAPIClient.swift; Sources/ZeyWinSDK/Network/Models/*; Sources/ZeyWinSDK/Decision/ContentResolver.swift; Sources/ZeyWinSDK/ZeyWinSDK.swift"
            ;;
        *DeviceInfo.cs|*DeviceIdentity.cs|*DeviceReport.cs|*GeoCheck.cs|*SecurityCheck.cs)
            echo "Sources/ZeyWinSDK/Device/*; Sources/ZeyWinSDK/Network/Models/SDKDeviceReport*; Sources/ZeyWinSDK/ZeyWinSDK.swift"
            ;;
        *WebView*|*HtmlView*)
            echo "Sources/ZeyWinSDK/Presentation/SDKWebViewController.swift; Sources/ZeyWinSDK/Presentation/ContentPresenter.swift; Tests/ZeyWinSDKTests/SDKWebViewIntegrationTests.swift"
            ;;
        *Loading*|*StartupOverlay*|*ZeyWinAds.cs|*AutoInitializer*)
            echo "Sources/ZeyWinSDK/ZeyWinSDK.swift; Sources/ZeyWinSDK/Presentation/ContentPresenter.swift; Sources/ZeyWinSDK/Presentation/SDKLoadingViewController.swift"
            ;;
        *BannerAd.cs|*NativeAd.cs)
            echo "Sources/ZeyWinSDK/Presentation/SDKBannerView.swift; Sources/ZeyWinSDK/Presentation/SDKPromoModalView.swift; Sources/ZeyWinSDK/Presentation/ContentPresenter.swift"
            ;;
        *)
            echo "No reliable one-to-one mapping; manual Swift architecture review required."
            ;;
    esac
}

potential_behavior() {
    local category="$1"
    local path="$2"

    case "$category" in
        COMMON)
            echo "Shared SDK behavior may have changed. Compare the Unity diff with the mapped Swift request, resolver, device, referral, or presentation flow."
            ;;
        IOS)
            echo "Native iOS behavior may have changed. Compare lifecycle, WebView, overlay, ATT, or platform bridge behavior with the mapped Swift implementation."
            ;;
        ANDROID)
            echo "Android-only implementation or instrumentation changed; no Swift port is implied."
            ;;
        UNITY_ONLY)
            echo "Unity editor, test, sample, metadata, or package-only change; no Swift port is implied."
            ;;
        *)
            echo "The path alone is insufficient to determine platform parity. Review the Unity diff before deciding whether Swift changes are needed."
            ;;
    esac
}

risk_and_action() {
    local category="$1"

    case "$category" in
        COMMON)
            echo "Medium to high — port only after semantic review; add or update Swift unit/API/E2E coverage for the affected flow.|Potentially yes"
            ;;
        IOS)
            echo "Medium to high — validate on iOS Simulator and, when relevant, real device; add WebView/presentation/device coverage.|Potentially yes"
            ;;
        ANDROID)
            echo "Low for Swift — confirm it does not alter a shared backend contract.|No, unless the diff reveals a shared API contract"
            ;;
        UNITY_ONLY)
            echo "Low for Swift — Unity-specific artifact.|No"
            ;;
        *)
            echo "Unknown — manual comparison required before any port decision.|REVIEW_REQUIRED"
            ;;
    esac
}

changed_symbols() {
    local path="$1"

    git -C "$unity_dir" diff --unified=0 "$from_commit" "$to_commit" -- "$path" \
        | awk '
            /^[+-]/ && !/^(\+\+\+|---)/ {
                line = substr($0, 2)
                if (line !~ /^[[:space:]]*\/\// && line ~ /(class |struct |enum |interface |[[:space:]](public|private|protected|internal)[[:space:]].*\()/) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                    print line
                }
            }
        ' \
        | sort -u \
        | head -8 \
        | sed 's/^/- `/' \
        | sed 's/$/`/' || true
}

related_commits() {
    local path="$1"

    git -C "$unity_dir" log --format='- `%h` %s' "$from_commit..$to_commit" -- "$path" \
        | head -5 || true
}

changed_files_file="$(mktemp "${TMPDIR:-/tmp}/unity-swift-changed.XXXXXX")"
trap 'rm -f "$changed_files_file"' EXIT
git -C "$unity_dir" diff --name-only --diff-filter=ACDMRT "$from_commit" "$to_commit" | sort > "$changed_files_file"

{
    write_header
    cat <<EOF
## Commit range

\`${from_commit}..${to_commit}\`

## Changed Unity files

EOF

    if [[ ! -s "$changed_files_file" ]]; then
        echo "No Unity files changed in this range."
    else
        while IFS= read -r path; do
            echo "- \`${path}\`"
        done < "$changed_files_file"
    fi

    cat <<'EOF'

## Classification report

EOF

    if [[ ! -s "$changed_files_file" ]]; then
        echo "No porting review is required."
    fi

    while IFS= read -r path; do
        category="$(classify "$path")"
        counterparts="$(swift_counterparts "$path")"
        behavior="$(potential_behavior "$category" "$path")"
        IFS='|' read -r risk port_action <<< "$(risk_and_action "$category")"
        symbols="$(changed_symbols "$path")"
        commits="$(related_commits "$path")"

        cat <<EOF
### \`${path}\`

- Classification: **${category}**
- Related Unity commits:
${commits:-  - No path-specific commit subject available.}
- Changed Unity symbols:
${symbols:-  - No declaration-level symbol detected; inspect the file diff.}
- Swift counterparts: ${counterparts}
- Potential behavior change: ${behavior}
- Risk: ${risk}
- Test focus: ${category} changes require the mapped Swift tests to be reviewed; add coverage only after a human confirms parity work.
- Port to Swift: **${port_action}**

EOF
    done < "$changed_files_file"

    cat <<EOF
## Manual review rules

- \`COMMON\` and \`IOS\` entries are candidates only, not automatic port instructions.
- \`REVIEW_REQUIRED\` entries must be classified by a maintainer before changing Swift.
- \`ANDROID\` and \`UNITY_ONLY\` entries are retained for auditability and do not trigger Swift edits.
- Update \`${state_file#$repo_root/}\` manually only after the report has been reviewed and all required Swift parity work is complete.
EOF
} > "$output_file"

if [[ -s "$changed_files_file" ]]; then
    write_status changes
else
    write_status no_op
fi

echo "Wrote report: $output_file"
