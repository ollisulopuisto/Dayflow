#!/usr/bin/env bash
set -euo pipefail

# Build the Dayflow app locally without changing the current checkout.
# With no ref, build the current working tree (including local edits).
# With a ref, build that commit in a temporary detached worktree.

usage() {
  cat <<'USAGE'
Usage: scripts/build_local.sh [--open] [--unsigned] [--team <team-id>]
                              [--bundle-id <identifier>] [<git-ref>]

Builds Dayflow in the Release configuration with Xcode automatic signing.
Without a git ref, builds the current working tree. With a ref such as
v2.7.21, builds that exact commit in a temporary worktree and leaves the
current checkout untouched.

Options:
  --open   Open the built Dayflow.app after a successful build
  --unsigned  Build without signing (compile-only use; screen-capture permission
              may not persist between builds)
  --team <id>  Sign with this Apple Development team instead of the project team
  --bundle-id  Use this bundle identifier (required with a different team)
  -h       Show this help

Examples:
  ./scripts/build_local.sh
  git fetch origin --tags
  ./scripts/build_local.sh --open v2.7.21
  ./scripts/build_local.sh --team ABCDE12345 --bundle-id com.example.DayflowLocal --open v2.7.21
  ./scripts/build_local.sh --unsigned v2.7.21

The app is written to:
  ~/Library/Developer/Xcode/DerivedData/Dayflow-local-<commit>/Build/Products/Release/Dayflow.app
USAGE
}

OPEN_APP=0
UNSIGNED=0
TEAM_OVERRIDE=
BUNDLE_ID_OVERRIDE=
REF=HEAD
REF_SET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open)
      OPEN_APP=1
      shift
      ;;
    --unsigned)
      UNSIGNED=1
      shift
      ;;
    --team)
      if [[ $# -lt 2 ]]; then
        printf 'ERROR: --team requires a team ID.\n' >&2
        exit 2
      fi
      TEAM_OVERRIDE=$2
      shift 2
      ;;
    --bundle-id)
      if [[ $# -lt 2 ]]; then
        printf 'ERROR: --bundle-id requires an identifier.\n' >&2
        exit 2
      fi
      BUNDLE_ID_OVERRIDE=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      if [[ $# -gt 1 || ( $# -eq 1 && "$REF_SET" -eq 1 ) ]]; then
        printf 'ERROR: Expected at most one git ref.\n' >&2
        usage >&2
        exit 2
      fi
      if [[ $# -eq 1 ]]; then
        REF=$1
        REF_SET=1
      fi
      break
      ;;
    -* )
      printf 'ERROR: Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$REF_SET" -eq 1 ]]; then
        printf 'ERROR: Expected at most one git ref.\n' >&2
        usage >&2
        exit 2
      fi
      REF=$1
      REF_SET=1
      shift
      ;;
  esac
done

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

if ! command -v xcodebuild >/dev/null 2>&1; then
  printf 'ERROR: xcodebuild not found. Install Xcode and select it with xcode-select.\n' >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  printf 'ERROR: git not found.\n' >&2
  exit 1
fi
if [[ ! -d "${REPO_ROOT}/Dayflow/Dayflow.xcodeproj" ]]; then
  printf 'ERROR: Xcode project not found under %s\n' "$REPO_ROOT" >&2
  exit 1
fi
if [[ "$REF" == -* ]]; then
  printf 'ERROR: Git refs beginning with a dash are not supported.\n' >&2
  exit 2
fi

SOURCE_ROOT=$REPO_ROOT
WORKTREE_ROOT=
if [[ "$REF" != "HEAD" ]]; then
  if ! COMMIT=$(git -C "$REPO_ROOT" rev-parse --verify "${REF}^{commit}" 2>/dev/null); then
    printf 'ERROR: Git ref not found: %s (fetch it first if it is a remote tag).\n' "$REF" >&2
    exit 1
  fi
  WORKTREE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dayflow-build.XXXXXX")
  SOURCE_ROOT="${WORKTREE_ROOT}/source"
  cleanup() {
    git -C "$REPO_ROOT" worktree remove --force "$SOURCE_ROOT" >/dev/null 2>&1 || true
    rm -rf -- "$WORKTREE_ROOT"
  }
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  git -C "$REPO_ROOT" worktree add --detach "$SOURCE_ROOT" "$COMMIT"
else
  COMMIT=$(git -C "$REPO_ROOT" rev-parse --verify HEAD)
fi

if [[ "$UNSIGNED" -eq 0 ]]; then
  PROJECT_FILE="${SOURCE_ROOT}/Dayflow/Dayflow.xcodeproj/project.pbxproj"
  PROJECT_TEAM_ID=$(grep -m1 -E 'DEVELOPMENT_TEAM = ' "$PROJECT_FILE" | sed -E 's/.*DEVELOPMENT_TEAM = ([^;]+);/\1/')
  TEAM_ID=${TEAM_OVERRIDE:-$PROJECT_TEAM_ID}
  if [[ -n "$TEAM_OVERRIDE" && ! "$TEAM_OVERRIDE" =~ ^[A-Z0-9]{10}$ ]]; then
    printf 'ERROR: Invalid Apple Developer team ID: %s\n' "$TEAM_OVERRIDE" >&2
    exit 2
  fi
  if [[ -n "$TEAM_OVERRIDE" && "$TEAM_ID" != "$PROJECT_TEAM_ID" && -z "$BUNDLE_ID_OVERRIDE" ]]; then
    printf 'ERROR: --bundle-id is required when using a different signing team.\n' >&2
    printf 'Choose a unique bundle ID for your Personal Team.\n' >&2
    exit 2
  fi
  if [[ -n "$BUNDLE_ID_OVERRIDE" && ! "$BUNDLE_ID_OVERRIDE" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
    printf 'ERROR: Invalid bundle identifier: %s\n' "$BUNDLE_ID_OVERRIDE" >&2
    exit 2
  fi
  if [[ -n "$TEAM_ID" ]] && ! security find-identity -v -p codesigning 2>/dev/null \
    | grep -E "(Apple|Mac) Development:.*\\(${TEAM_ID}\\)" >/dev/null; then
    cat >&2 <<EOF
ERROR: No valid Apple/Mac Development signing identity for team ${TEAM_ID}.
In Xcode, open Settings > Accounts, select that team, choose Manage
Certificates, and add a Mac Development (or Apple Development) certificate.
Then retry.

Use --unsigned only for a compile check. macOS can treat unsigned rebuilds as
different apps and repeatedly request Screen Recording permission.
EOF
    exit 1
  fi
fi

: "${HOME:?HOME must be set to locate Xcode DerivedData}"
DERIVED_DATA=${DERIVED_DATA:-"${HOME}/Library/Developer/Xcode/DerivedData/Dayflow-local-${COMMIT:0:12}"}
APP_PATH="${DERIVED_DATA}/Build/Products/Release/Dayflow.app"

printf 'Building Dayflow from %s (%s)\n' "$REF" "$COMMIT"
printf 'DerivedData: %s\n' "$DERIVED_DATA"
XCODEBUILD_ARGS=(
  -project "${SOURCE_ROOT}/Dayflow/Dayflow.xcodeproj" \
  -scheme Dayflow \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA"
)
if [[ "$UNSIGNED" -eq 1 ]]; then
  XCODEBUILD_ARGS+=(CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
else
  XCODEBUILD_ARGS+=(-allowProvisioningUpdates "DEVELOPMENT_TEAM=$TEAM_ID")
  if [[ -n "$BUNDLE_ID_OVERRIDE" ]]; then
    XCODEBUILD_ARGS+=("PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID_OVERRIDE")
  fi
fi
xcodebuild "${XCODEBUILD_ARGS[@]}" build

if [[ ! -d "$APP_PATH" ]]; then
  printf 'ERROR: Build succeeded but app was not found at %s\n' "$APP_PATH" >&2
  exit 1
fi

printf 'Built app: %s\n' "$APP_PATH"
if [[ "$OPEN_APP" -eq 1 ]]; then
  open "$APP_PATH"
fi
