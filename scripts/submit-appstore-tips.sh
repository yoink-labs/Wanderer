#!/usr/bin/env bash
# Submit Wanderer, with its tip in-app purchases, to App Store review.
#
#   scripts/submit-appstore-tips.sh            # dry run (default): plan + readiness, changes nothing
#   scripts/submit-appstore-tips.sh --submit   # really do it
#   scripts/submit-appstore-tips.sh --submit --iaps-selected-in-asc
#       # after ticking the tips on the version page in App Store Connect
#       # (Apple rejects the API attach for first-time IAPs with
#       # STATE_ERROR.FIRST_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION)
#
# Steps (only --submit mutates anything):
#   1. Reuse the editable App Store version (PREPARE_FOR_SUBMISSION, etc.)
#      and set its version string to MARKETING_VERSION from project.yml, or
#      create that version. The marketing version is never bumped here.
#   2. Pick the newest VALID, unexpired build of that marketing version.
#   3. Attach the build to the version.
#   4. Mark every tip IAP in READY_TO_SUBMIT to go with this version
#      (POST /v1/inAppPurchaseSubmissions).
#   5. Run `asc validate`. Stop on blocking errors (see "Needs a human" below).
#   6. Submit the version for review with `asc review submit --confirm`.
#
# Needs: asc (https://github.com/rork/asc) logged in with the default profile
# (key 2VGQN75FV5), python3. Never prints credentials.
#
# Needs a human in App Store Connect first (the API can't answer these
# honestly for you): App Privacy answers, age rating questionnaire, content
# rights, app price + availability, and the App Store screenshots if missing.
# The dry run lists whatever is still blocking.

set -euo pipefail

APP_ID="${ASC_APP_ID:-6833580006}"
TIP_PREFIX="dev.yoinklabs.wanderer.tip."
MODE="dry-run"
IAPS_SELECTED=0
for arg in "$@"; do
  case "$arg" in
    --submit) MODE="submit" ;;
    --dry-run) MODE="dry-run" ;;
    --iaps-selected-in-asc) IAPS_SELECTED=1 ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETING="$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?.*/\1/p' "$REPO_ROOT/project.yml" | head -1)"
[[ -n "$MARKETING" ]] || { echo "error: MARKETING_VERSION not found in project.yml" >&2; exit 1; }
command -v asc >/dev/null || { echo "error: asc not found" >&2; exit 1; }

step() { printf '\n==> %s\n' "$*"; }
json() { python3 -c "$1"; }
run() {
  # Print a mutating command; run it only with --submit.
  echo "  \$ $*"
  if [[ "$MODE" == "submit" ]]; then "$@" >/dev/null; fi
}

echo "Wanderer App Store submission  [mode: $MODE]  app $APP_ID  marketing $MARKETING"

# --- 1. Version -------------------------------------------------------------
step "App Store version"
VERSIONS="$(asc api GET "/v1/apps/$APP_ID/appStoreVersions?filter[platform]=IOS&limit=20" 2>/dev/null)"
read -r VERSION_ID VERSION_STRING VERSION_STATE < <(printf '%s' "$VERSIONS" | json '
import json, sys
editable = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
for v in json.load(sys.stdin)["data"]:
    a = v["attributes"]
    if a["appStoreState"] in editable:
        print(v["id"], a["versionString"], a["appStoreState"]); break
else:
    print("- - -")')
if [[ "$VERSION_ID" == "-" ]]; then
  echo "  no editable version; would create $MARKETING"
  run asc versions create --app "$APP_ID" --version "$MARKETING" --platform IOS --release-type AFTER_APPROVAL
  if [[ "$MODE" == "submit" ]]; then
    VERSION_ID="$(asc api GET "/v1/apps/$APP_ID/appStoreVersions?filter[versionString]=$MARKETING&filter[platform]=IOS" 2>/dev/null \
      | json 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')"
  fi
else
  echo "  reusing $VERSION_ID ($VERSION_STRING, $VERSION_STATE)"
  if [[ "$VERSION_STRING" != "$MARKETING" ]]; then
    echo "  version string $VERSION_STRING != build's $MARKETING; would rename the version record (not the app's marketing version)"
    run asc versions update --version-id "$VERSION_ID" --version "$MARKETING"
  fi
fi

# --- 2. Build ---------------------------------------------------------------
step "Newest valid build of $MARKETING"
read -r BUILD_ID BUILD_NUMBER < <(asc api GET "/v1/builds?filter[app]=$APP_ID&filter[preReleaseVersion.version]=$MARKETING&filter[processingState]=VALID&filter[expired]=false&sort=-uploadedDate&limit=1" 2>/dev/null \
  | json '
import json, sys
d = json.load(sys.stdin)["data"]
print(d[0]["id"], d[0]["attributes"]["version"]) if d else print("- -")')
[[ "$BUILD_ID" != "-" ]] || { echo "error: no VALID build of $MARKETING in App Store Connect" >&2; exit 1; }
echo "  build $MARKETING ($BUILD_NUMBER)  id $BUILD_ID"

# --- 3. Attach build ---------------------------------------------------------
step "Attach build"
run asc versions attach-build --version-id "${VERSION_ID}" --build-id "$BUILD_ID"

# --- 4. Tip IAPs --------------------------------------------------------------
step "Tip in-app purchases"
IAPS="$(asc iap list --app "$APP_ID" --paginate --output json 2>/dev/null)"
READY_IDS="$(printf '%s' "$IAPS" | TIP_PREFIX="$TIP_PREFIX" json '
import json, os, sys
d = json.load(sys.stdin)
items = d["data"] if isinstance(d, dict) else d
ready = []
for i in sorted(items, key=lambda x: x["attributes"]["productId"]):
    a = i["attributes"]
    if not a["productId"].startswith(os.environ["TIP_PREFIX"]): continue
    pid, kind, state = a["productId"], a["inAppPurchaseType"], a["state"]
    print(f"  {pid:<36} {kind:<12} {state}", file=sys.stderr)
    if a["state"] == "READY_TO_SUBMIT": ready.append(i["id"])
print(" ".join(ready))')"
if [[ -z "$READY_IDS" ]]; then
  echo "  none READY_TO_SUBMIT (already submitted, or not ready)"
fi
if [[ "$IAPS_SELECTED" == 1 && -n "$READY_IDS" ]]; then
  echo "  skipping the API attach: tips were selected on the version page in App Store Connect"
  READY_IDS=""
fi
for iap in $READY_IDS; do
  echo "  \$ asc api POST /v1/inAppPurchaseSubmissions  (inAppPurchaseV2 $iap)"
  if [[ "$MODE" == "submit" ]]; then
    BODY="{\"data\":{\"type\":\"inAppPurchaseSubmissions\",\"relationships\":{\"inAppPurchaseV2\":{\"data\":{\"type\":\"inAppPurchases\",\"id\":\"$iap\"}}}}}"
    if ! OUT="$(asc api POST /v1/inAppPurchaseSubmissions --body "$BODY" --confirm 2>&1)"; then
      if grep -q "FIRST_.*MUST_BE_SUBMITTED_ON_VERSION" <<<"$OUT"; then
        echo "  Apple requires first-time IAPs to be ticked on the version page:" >&2
        echo "  App Store Connect > Wanderer > $MARKETING > In-App Purchases and Subscriptions > select the tips," >&2
        echo "  then re-run with --submit --iaps-selected-in-asc." >&2
      else
        echo "$OUT" | tail -3 >&2
      fi
      exit 1
    fi
  fi
done

# --- 5. Readiness -------------------------------------------------------------
step "Readiness (asc validate)"
BLOCKING="$(asc validate --app "$APP_ID" --version-id "$VERSION_ID" --output json 2>/dev/null | MODE="$MODE" json '
import json, os, sys
d = json.load(sys.stdin)
# In a dry run the build and version string are fixed by the steps above.
planned = {"build.required.missing"} if os.environ["MODE"] == "dry-run" else set()
seen, blocking = set(), 0
for s in d["remediation"]["steps"]:
    key = (s["checkId"], s["message"])
    if key in seen: continue
    seen.add(key)
    if s["checkId"] in planned:
        print("  ok    " + s["checkId"] + " (handled by --submit)", file=sys.stderr); continue
    tag = "BLOCK" if s.get("blocking") else s["severity"][:4]
    blocking += bool(s.get("blocking"))
    check, msg = s["checkId"], s["message"][:100]
    print(f"  {tag:<5} {check}: {msg}", file=sys.stderr)
print(blocking)')"
echo "  blocking issues: $BLOCKING"

# --- 6. Submit ----------------------------------------------------------------
step "Submit for review"
if [[ "$MODE" == "dry-run" ]]; then
  echo "  \$ asc review submit --app $APP_ID --version $MARKETING --build-id $BUILD_ID --confirm"
  echo
  if [[ "$BLOCKING" == "0" ]]; then
    echo "Dry run only. Ready: re-run with --submit."
  else
    echo "Dry run only. $BLOCKING blocking issue(s) above must be fixed before --submit."
  fi
  exit 0
fi
if [[ "$BLOCKING" != "0" ]]; then
  echo "error: $BLOCKING blocking issue(s); not submitting." >&2
  exit 1
fi
asc review submit --app "$APP_ID" --version "$MARKETING" --build-id "$BUILD_ID" --confirm
echo "Submitted Wanderer $MARKETING ($BUILD_NUMBER) with tips for App Store review."
