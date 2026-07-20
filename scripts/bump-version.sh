#!/usr/bin/env bash
# Bump the app's semantic version (MARKETING_VERSION) and the build number
# (CURRENT_PROJECT_VERSION) in project.yml, commit, and tag.
#
# We manage the build number ourselves — ExportOptions.plist sets
# manageAppVersionAndBuildNumber=false, so Apple no longer rewrites the
# marketing version to "1.0" at upload. The build number must be unique and
# increasing, so every release bumps it by one alongside the semver.
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

BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' project.yml)
if [[ -z "$BUILD" ]]; then
  echo "error: CURRENT_PROJECT_VERSION not found in project.yml" >&2
  exit 1
fi

IFS=. read -r MAJOR MINOR PATCH <<<"$CURRENT"
case $PART in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
NEW="$MAJOR.$MINOR.$PATCH"
NEWBUILD=$((BUILD + 1))

sed -i '' "s/MARKETING_VERSION: \"$CURRENT\"/MARKETING_VERSION: \"$NEW\"/" project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$BUILD\"/CURRENT_PROJECT_VERSION: \"$NEWBUILD\"/" project.yml
xcodegen generate >/dev/null

git add project.yml
git commit -m "Release v$NEW (build $NEWBUILD)"
git tag -a "v$NEW" -m "Rally Buddy v$NEW (build $NEWBUILD)"

echo "bumped $CURRENT ($BUILD) -> $NEW ($NEWBUILD), committed, and tagged v$NEW"
echo "next: git push && git push --tags, then archive + upload (see CLAUDE.md)"
