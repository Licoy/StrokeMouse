#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") -v x.y.z [-p]" >&2
  exit 2
}

VERSION=""
PUSH=0
while getopts ":v:p" option; do
  case "$option" in
    v) VERSION="$OPTARG" ;;
    p) PUSH=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

[[ $# -eq 0 && -n "$VERSION" ]] || usage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Version must use x.y.z format, got: $VERSION" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
[[ "$ROOT" == "$SCRIPT_DIR" ]] || {
  echo "bump.sh must live at the repository root: $ROOT" >&2
  exit 1
}
cd "$ROOT"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "Tracked working tree is not clean. Commit or stash changes first." >&2
  git status --short --untracked-files=no >&2
  exit 1
fi

command -v xcodegen >/dev/null 2>&1 || {
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
}

PROJECT_SPEC="project.yml"
WEBSITE_VERSION="website/docs/.vitepress/theme/constants.ts"
[[ -f "$PROJECT_SPEC" && -f "$WEBSITE_VERSION" ]] || {
  echo "Version source is missing: $PROJECT_SPEC or $WEBSITE_VERSION" >&2
  exit 1
}

CURRENT_VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$PROJECT_SPEC")"
CURRENT_BUILD="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$PROJECT_SPEC")"
[[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || {
  echo "Current build number is not numeric: $CURRENT_BUILD" >&2
  exit 1
}

IFS=. read -r MAJOR MINOR PATCH <<<"$VERSION"
BUILD=$((10#$MAJOR * 1000000 + 10#$MINOR * 1000 + 10#$PATCH))
(( BUILD > CURRENT_BUILD )) || {
  echo "Build number must increase: current=$CURRENT_BUILD requested=$BUILD" >&2
  exit 1
}

TAG="v$VERSION"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Local tag already exists: $TAG" >&2
  exit 1
fi

if git remote get-url origin >/dev/null 2>&1; then
  REMOTE_TAG="$(git ls-remote --tags origin "refs/tags/$TAG")" || {
    echo "Unable to check remote tag $TAG." >&2
    exit 1
  }
  [[ -z "$REMOTE_TAG" ]] || {
    echo "Remote tag already exists: $TAG" >&2
    exit 1
  }
fi

if [[ "$PUSH" -eq 1 && -z "$(git branch --show-current)" ]]; then
  echo "Cannot push from a detached HEAD." >&2
  exit 1
fi

VERSION="$VERSION" BUILD="$BUILD" perl -0pi -e '
  $marketing = s{(MARKETING_VERSION:\s*")[^"]+("\s*)}{$1$ENV{VERSION}$2};
  $build = s{(CURRENT_PROJECT_VERSION:\s*")[^"]+("\s*)}{$1$ENV{BUILD}$2};
  die "Missing project version settings\n" unless $marketing && $build;
' "$PROJECT_SPEC"

VERSION="$VERSION" perl -0pi -e '
  $count = s{(export const APP_VERSION = \x27)[^\x27]+(\x27)}{$1$ENV{VERSION}$2};
  die "Missing website APP_VERSION\n" unless $count;
' "$WEBSITE_VERSION"

./scripts/generate_project.sh

grep -q "MARKETING_VERSION: \"$VERSION\"" "$PROJECT_SPEC"
grep -q "CURRENT_PROJECT_VERSION: \"$BUILD\"" "$PROJECT_SPEC"
grep -q "APP_VERSION = '$VERSION'" "$WEBSITE_VERSION"

git add "$PROJECT_SPEC" StrokeMouse.xcodeproj "$WEBSITE_VERSION"
git commit -m "chore(release): bump version to $VERSION"
git tag -a "$TAG" -m "Release $TAG"

if [[ "$PUSH" -eq 1 ]]; then
  BRANCH="$(git branch --show-current)"
  git push --atomic origin "$BRANCH" "$TAG"
fi

echo "Bumped $CURRENT_VERSION ($CURRENT_BUILD) -> $VERSION ($BUILD), committed and tagged $TAG."
if [[ "$PUSH" -eq 0 ]]; then
  echo "Push atomically with: git push --atomic origin HEAD $TAG"
fi
