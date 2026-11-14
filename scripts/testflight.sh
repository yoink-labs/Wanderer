#!/usr/bin/env bash
# Archive Wanderer and upload it to TestFlight.
#
#   scripts/testflight.sh            # build number = project.yml value + 1
#   scripts/testflight.sh 7          # explicit build number
#   scripts/testflight.sh --skip-tests
#   scripts/testflight.sh --no-upload   # archive + export an .ipa locally only
#
# Steps: set CURRENT_PROJECT_VERSION in project.yml, xcodegen, unit tests on an
# iOS simulator, xcodebuild archive (Release, automatic signing), then
# xcodebuild -exportArchive with scripts/ExportOptions.plist, which uploads to
# App Store Connect. Stops before uploading if the tests fail.
#
# App Store Connect API key (see README "TestFlight"):
#   ASC_KEY_ID     default 2VGQN75FV5 (needs cloud signing permission;
#                  23TY3H4W7Z fails with "Cloud signing permission error")
#   ASC_KEY_PATH   default ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
#   ASC_ISSUER_ID  required; may live in ~/.appstoreconnect/asc.env (or the
#                  file named by ASC_ENV_FILE), which is sourced if it exists.
# Optional:
#   TEST_DESTINATION  default "platform=iOS Simulator,name=iPhone 17 Pro"
#   BUILD_ROOT        default ~/Library/Developer/Wanderer-TestFlight
#                     (kept outside the repo: the File Provider-managed
#                     Documents folder adds xattrs that break codesign)

set -euo pipefail

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; }

BUILD_NUMBER=""
RUN_TESTS=1
UPLOAD=1
for arg in "$@"; do
  case "$arg" in
    --skip-tests) RUN_TESTS=0 ;;
    --no-upload) UPLOAD=0 ;;
    -h|--help) usage; exit 0 ;;
    ''|*[!0-9]*) echo "error: unknown argument '$arg'" >&2; usage >&2; exit 2 ;;
    *) BUILD_NUMBER="$arg" ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="${ASC_ENV_FILE:-$HOME/.appstoreconnect/asc.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi
ASC_KEY_ID="${ASC_KEY_ID:-2VGQN75FV5}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
TEST_DESTINATION="${TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
BUILD_ROOT="${BUILD_ROOT:-$HOME/Library/Developer/Wanderer-TestFlight}"

die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)"
[[ -f "$ASC_KEY_PATH" ]] || die "API key not found at $ASC_KEY_PATH (set ASC_KEY_PATH)"
[[ -n "$ASC_ISSUER_ID" ]] || die "ASC_ISSUER_ID is not set. Export it or put ASC_ISSUER_ID=<uuid> in $ENV_FILE (App Store Connect > Users and Access > Integrations > App Store Connect API)."

CURRENT="$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([0-9]+)"?.*/\1/p' project.yml | head -1)"
MARKETING="$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?.*/\1/p' project.yml | head -1)"
[[ -n "$CURRENT" ]] || die "CURRENT_PROJECT_VERSION not found in project.yml"
BUILD_NUMBER="${BUILD_NUMBER:-$((CURRENT + 1))}"

step "Wanderer $MARKETING ($BUILD_NUMBER)  [project.yml had $CURRENT]"
if [[ "$BUILD_NUMBER" != "$CURRENT" ]]; then
  sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: *)\"?[0-9]+\"?/\1\"$BUILD_NUMBER\"/" project.yml
fi

step "xcodegen generate"
xcodegen generate --quiet

STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$BUILD_ROOT/$MARKETING-$BUILD_NUMBER-$STAMP"
DERIVED="$BUILD_ROOT/DerivedData"
ARCHIVE="$WORK/Wanderer.xcarchive"
mkdir -p "$WORK"
LOG="$WORK/log.txt"
echo "Logs: $LOG"

AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

if [[ "$RUN_TESTS" == 1 ]]; then
  step "Unit tests ($TEST_DESTINATION)"
  if ! xcodebuild test -project Wanderer.xcodeproj -scheme Wanderer \
       -destination "$TEST_DESTINATION" -derivedDataPath "$DERIVED" \
       >>"$LOG" 2>&1; then
    grep -E "error:|failed|\*\* TEST" "$LOG" | tail -20 >&2 || true
    die "unit tests failed; nothing uploaded (full log: $LOG)"
  fi
  grep -E "Executed [0-9]+ tests" "$LOG" | tail -1
fi

step "Archive (Release, generic/platform=iOS)"
if ! xcodebuild archive -project Wanderer.xcodeproj -scheme Wanderer \
     -configuration Release -destination "generic/platform=iOS" \
     -archivePath "$ARCHIVE" -derivedDataPath "$DERIVED" \
     CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=64PUT29XZ8 \
     "${AUTH[@]}" >>"$LOG" 2>&1; then
  grep -E "error:|\*\* ARCHIVE" "$LOG" | tail -20 >&2 || true
  die "archive failed (full log: $LOG)"
fi
grep -E "\*\* ARCHIVE" "$LOG" | tail -1

EXPORT_OPTIONS="$REPO_ROOT/scripts/ExportOptions.plist"
if [[ "$UPLOAD" == 0 ]]; then
  EXPORT_OPTIONS="$WORK/ExportOptions.plist"
  cp "$REPO_ROOT/scripts/ExportOptions.plist" "$EXPORT_OPTIONS"
  plutil -replace destination -string export "$EXPORT_OPTIONS"
fi

step "Export$([[ "$UPLOAD" == 1 ]] && echo " + upload to App Store Connect")"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" \
     -exportPath "$WORK/export" -exportOptionsPlist "$EXPORT_OPTIONS" \
     "${AUTH[@]}" >>"$LOG" 2>&1; then
  grep -E "error|\*\* EXPORT" "$LOG" | tail -20 >&2 || true
  die "export/upload failed (full log: $LOG)"
fi
grep -E "Upload succeeded|Uploaded|\*\* EXPORT" "$LOG" | tail -3

echo
if [[ "$UPLOAD" == 1 ]]; then
  echo "Uploaded Wanderer $MARKETING ($BUILD_NUMBER). App Store Connect processes it"
  echo "for ~5-30 min before it appears in TestFlight."
else
  echo "Exported to $WORK/export (not uploaded)."
fi
echo "Commit the bump: git commit -am \"Build $BUILD_NUMBER\" (project.yml + Wanderer.xcodeproj)"
