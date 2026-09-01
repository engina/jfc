#!/bin/sh

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_REQUESTED_VERSION="${1:-}"

validate_version() {
  if ! printf '%s\n' "$1" \
    | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Invalid release version: $1" >&2
    echo "Expected MAJOR.MINOR.PATCH, for example 0.1.2." >&2
    exit 2
  fi
}

if [ -n "$JFC_REQUESTED_VERSION" ]; then
  validate_version "$JFC_REQUESTED_VERSION"
  printf '%s\n' "$JFC_REQUESTED_VERSION"
  exit 0
fi

cd "$JFC_REPOSITORY_ROOT"

JFC_EXACT_VERSION_TAGS=$(
  git tag --points-at HEAD \
    | /usr/bin/grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    || true
)
if [ -n "$JFC_EXACT_VERSION_TAGS" ]; then
  JFC_EXACT_VERSION_TAG_COUNT=$(
    printf '%s\n' "$JFC_EXACT_VERSION_TAGS" | /usr/bin/wc -l | /usr/bin/tr -d ' '
  )
  if [ "$JFC_EXACT_VERSION_TAG_COUNT" != "1" ]; then
    echo "HEAD has multiple semantic-version tags:" >&2
    printf '%s\n' "$JFC_EXACT_VERSION_TAGS" >&2
    exit 1
  fi

  JFC_VERSION=${JFC_EXACT_VERSION_TAGS#v}
  validate_version "$JFC_VERSION"
  printf '%s\n' "$JFC_VERSION"
  exit 0
fi

if ! command -v git-cliff >/dev/null 2>&1; then
  echo "git-cliff is required to calculate the next release version." >&2
  echo "Install it with: brew install git-cliff" >&2
  exit 1
fi

JFC_VERSION=$(git-cliff --config "$JFC_REPOSITORY_ROOT/cliff.toml" --bumped-version)
JFC_VERSION=${JFC_VERSION#v}
validate_version "$JFC_VERSION"
printf '%s\n' "$JFC_VERSION"
