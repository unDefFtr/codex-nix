#!/usr/bin/env bash
#
# Update codex to a new version.
#
# Usage:
#   ./scripts/update.sh              # update to latest
#   ./scripts/update.sh --check      # check for new version, don't update
#   ./scripts/update.sh 0.105.0      # update to specific version

set -euo pipefail

REPO="openai/codex"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_NIX="${SCRIPT_DIR}/../package.nix"

PLATFORMS=(
  "aarch64-apple-darwin"
  "x86_64-apple-darwin"
  "x86_64-unknown-linux-musl"
  "aarch64-unknown-linux-musl"
)

current_version() {
  grep 'version = "' "$PACKAGE_NIX" | head -1 | sed 's/.*"\(.*\)".*/\1/'
}

latest_version() {
  if command -v gh >/dev/null 2>&1; then
    gh release view --repo "$REPO" --json tagName -q '.tagName' | sed 's/^rust-v//'
  else
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
      | grep '"tag_name"' \
      | sed 's/.*"rust-v\(.*\)".*/\1/'
  fi
}

# --- main ---

CURRENT=$(current_version)
echo "Current version: ${CURRENT}"

if [[ "${1:-}" == "--check" ]] || [[ $# -eq 0 ]]; then
  LATEST=$(latest_version)
  echo "Latest version:  ${LATEST}"
  if [[ "$CURRENT" == "$LATEST" ]]; then
    echo "Already up to date."
    exit 0
  fi
  echo ""
  echo "Update available! Run:"
  echo "  ./scripts/update.sh ${LATEST}"
  [[ "${1:-}" == "--check" ]] && exit 0
  # If called with no args, fall through to update
  NEW_VERSION="$LATEST"
else
  NEW_VERSION="$1"
fi

echo "Updating to:     ${NEW_VERSION}"
echo ""

echo "Fetching SHA256 hashes..."
hashes_file=""
updated_package=""
cleanup() {
  [[ -z "$hashes_file" ]] || rm -f -- "$hashes_file"
  [[ -z "$updated_package" ]] || rm -f -- "$updated_package"
}
trap cleanup EXIT

hashes_file=$(mktemp)
updated_package=$(mktemp "${PACKAGE_NIX}.tmp.XXXXXX")

for platform in "${PLATFORMS[@]}"; do
  url="https://github.com/${REPO}/releases/download/rust-v${NEW_VERSION}/codex-${platform}.tar.gz"
  if ! hash=$(nix-prefetch-url "$url" | tail -1); then
    echo "Failed to fetch ${platform} from ${url}" >&2
    exit 1
  fi

  if [[ -z "$hash" || "$hash" == *[[:space:]]* ]]; then
    echo "Invalid hash returned for ${platform}: ${hash}" >&2
    exit 1
  fi

  echo "  ${platform}: ${hash}"
  printf '%s\t%s\n' "$platform" "$hash" >> "$hashes_file"
done

awk -F '\t' -v new_version="$NEW_VERSION" '
  NR == FNR {
    hashes[$1] = $2
    next
  }
  /^[[:space:]]*version = "/ && !version_updated {
    sub(/version = "[^"]*"/, "version = \"" new_version "\"")
    version_updated = 1
  }
  /hashes = \{/ { in_block=1 }
  in_block {
    for (platform in hashes) {
      if ($0 ~ "\"" platform "\"") {
        sub(/= "[^"]*"/, "= \"" hashes[platform] "\"")
        updated[platform] = 1
        break
      }
    }
  }
  in_block && /\};/ { in_block=0 }
  { print }
  END {
    if (!version_updated) {
      print "Could not find version in package.nix" > "/dev/stderr"
      failed = 1
    }
    for (platform in hashes) {
      if (!updated[platform]) {
        print "Could not find hash entry for " platform " in package.nix" > "/dev/stderr"
        failed = 1
      }
    }
    exit failed
  }
' "$hashes_file" "$PACKAGE_NIX" > "$updated_package"

mv "$updated_package" "$PACKAGE_NIX"
updated_package=""

echo ""
echo "Updated package.nix to v${NEW_VERSION}"
echo ""
echo "Next steps:"
echo "  1. nix build              # verify it builds"
echo "  2. ./result/bin/codex --version"
echo "  3. git add package.nix && git commit -m \"update codex to ${NEW_VERSION}\""
