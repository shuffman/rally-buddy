#!/usr/bin/env bash
# Bump the app's semantic version (MARKETING_VERSION in project.yml),
# commit, and tag. Build numbers are not touched — App Store Connect
# assigns them at upload (manageAppVersionAndBuildNumber).
#
# usage: scripts/bump-version.sh major|minor|patch
set -euo pipefail
cd "$(dirname "$0")/.."

PART=${1:-}
if [[ ! "$PART" =~ ^(major|minor|patch)$ ]]; then
  echo "usage: $0 major|minor|patch" >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: working tree not clean — commit or stash first" >&2
  exit 1
fi

CURRENT=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
if [[ -z "$CURRENT" ]]; then
  echo "error: MARKETING_VERSION not found in project.yml" >&2
  exit 1
fi

IFS=. read -r MAJOR MINOR PATCH <<<"$CURRENT"
case $PART in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
NEW="$MAJOR.$MINOR.$PATCH"

sed -i '' "s/MARKETING_VERSION: \"$CURRENT\"/MARKETING_VERSION: \"$NEW\"/" project.yml
xcodegen generate >/dev/null

git add project.yml
git commit -m "Release v$NEW"
git tag -a "v$NEW" -m "Rally Buddy v$NEW"

echo "bumped $CURRENT -> $NEW, committed, and tagged v$NEW"
echo "next: git push && git push --tags, then archive + upload (see CLAUDE.md)"
