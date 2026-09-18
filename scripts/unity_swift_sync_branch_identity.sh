#!/usr/bin/env bash

# Verifies that an existing sync branch belongs to one exact Unity head. This is
# intentionally read-only: it does not fetch, create branches, alter refs, or
# change Git configuration.

set -euo pipefail

repo_root="$(pwd)"
ref=""
unity_head=""

usage() {
    cat <<'EOF'
Usage:
  scripts/unity_swift_sync_branch_identity.sh --ref <git-ref> --unity-head <40-sha> [--repo-root <path>]

The ref is accepted only when its tip commit has exactly one Git trailer:
  Unity-Head: <the exact supplied 40-character SHA>
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root) repo_root="$2"; shift 2 ;;
        --ref) ref="$2"; shift 2 ;;
        --unity-head) unity_head="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -d "$repo_root" && -n "$ref" && "$unity_head" =~ ^[0-9a-f]{40}$ ]] || {
    usage >&2
    exit 2
}

git -C "$repo_root" rev-parse --verify --quiet "${ref}^{commit}" > /dev/null || {
    echo "Git ref is not a commit: ${ref}" >&2
    exit 3
}

trailers="$(git -C "$repo_root" log -1 --format=%B "$ref" | git interpret-trailers --parse | awk -F': ' '$1 == "Unity-Head" { print $2 }')"
trailer_count="$(printf '%s\n' "$trailers" | sed '/^$/d' | wc -l | tr -d ' ')"

if [[ "$trailer_count" != "1" || "$trailers" != "$unity_head" ]]; then
    echo "${ref} is not verified for Unity head ${unity_head}." >&2
    exit 4
fi

echo "Verified ${ref} for Unity head ${unity_head}."
