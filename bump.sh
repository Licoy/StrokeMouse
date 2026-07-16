#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: bump.sh -v x.y.z [-p] [--force|-f]

  -v x.y.z     Target marketing version (required)
  -p           Push branch + tag to origin after tagging
  -f, --force  Allow re-tagging the same version when files are already
               aligned (build need not increase). Deletes an existing
               local/remote tag for that version, retags HEAD, and pushes
               (implies -p). Use when re-releasing or recovering a tag.

Examples:
  ./bump.sh -v 0.0.2              # local commit + tag only
  ./bump.sh -v 0.0.2 -p           # commit, tag, push
  ./bump.sh -v 0.0.1 --force      # force retag current version + push
EOF
  exit 2
}

VERSION=""
PUSH=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v)
      [[ $# -ge 2 ]] || usage
      VERSION="$2"
      shift 2
      ;;
    -p)
      PUSH=1
      shift
      ;;
    -f | --force)
      FORCE=1
      PUSH=1
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$VERSION" ]] || usage
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
TAG="v$VERSION"

if (( BUILD > CURRENT_BUILD )); then
  :
elif (( FORCE )); then
  echo "Force: allowing non-increasing build (current=$CURRENT_BUILD requested=$BUILD)."
else
  echo "Build number must increase: current=$CURRENT_BUILD requested=$BUILD" >&2
  echo "Hint: use --force to re-tag / re-push the same or lower formula build." >&2
  exit 1
fi

HAS_REMOTE=0
if git remote get-url origin >/dev/null 2>&1; then
  HAS_REMOTE=1
fi

LOCAL_TAG_EXISTS=0
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  LOCAL_TAG_EXISTS=1
fi

REMOTE_TAG_EXISTS=0
if (( HAS_REMOTE )); then
  REMOTE_TAG="$(git ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null || true)"
  [[ -z "$REMOTE_TAG" ]] || REMOTE_TAG_EXISTS=1
fi

if (( !FORCE )); then
  if (( LOCAL_TAG_EXISTS )); then
    echo "Local tag already exists: $TAG" >&2
    echo "Hint: use --force to delete and recreate it on HEAD." >&2
    exit 1
  fi
  if (( REMOTE_TAG_EXISTS )); then
    echo "Remote tag already exists: $TAG" >&2
    echo "Hint: use --force to move the remote tag to the new release commit." >&2
    exit 1
  fi
fi

BRANCH="$(git branch --show-current)"
if [[ "$PUSH" -eq 1 && -z "$BRANCH" ]]; then
  echo "Cannot push from a detached HEAD." >&2
  exit 1
fi

if (( FORCE && (LOCAL_TAG_EXISTS || REMOTE_TAG_EXISTS) )); then
  echo "Force: existing tag $TAG will be removed and recreated on HEAD."
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

CREATED_COMMIT=0
if ! git diff --cached --quiet; then
  git commit -m "chore(release): bump version to $VERSION"
  CREATED_COMMIT=1
elif (( FORCE )); then
  echo "Force: version sources already at $VERSION ($BUILD); no new commit."
else
  echo "Nothing to commit after version bump (unexpected)." >&2
  exit 1
fi

# Drop existing local tag so we can retag HEAD (annotated).
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  OLD_TARGET="$(git rev-list -n 1 "$TAG")"
  echo "Force: deleting local tag $TAG (was $OLD_TARGET)."
  git tag -d "$TAG" >/dev/null
fi

git tag -a "$TAG" -m "Release $TAG"
echo "Tagged $TAG -> $(git rev-parse --short HEAD)"

if [[ "$PUSH" -eq 1 ]]; then
  if (( !HAS_REMOTE )); then
    echo "No origin remote; skip push." >&2
    exit 1
  fi

  # Move remote tag to the new commit: delete first if present, then push.
  if (( REMOTE_TAG_EXISTS )) || (( FORCE )); then
    if git ls-remote --tags origin "refs/tags/$TAG" | grep -q .; then
      echo "Force: deleting remote tag $TAG."
      git push origin ":refs/tags/$TAG"
    fi
  fi

  git push --atomic origin "$BRANCH" "$TAG"
  echo "Pushed $BRANCH and $TAG to origin."
fi

if (( CREATED_COMMIT )); then
  echo "Bumped $CURRENT_VERSION ($CURRENT_BUILD) -> $VERSION ($BUILD), committed and tagged $TAG."
else
  echo "Retagged $TAG at $VERSION ($BUILD) on HEAD without a new version commit."
fi

if [[ "$PUSH" -eq 0 ]]; then
  echo "Push atomically with: git push --atomic origin HEAD $TAG"
fi
