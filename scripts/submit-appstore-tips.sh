#!/usr/bin/env bash
# Submit Wanderer, with its tip in-app purchases, to App Store review.
#
#   scripts/submit-appstore-tips.sh            # dry run (default): plan + readiness, changes nothing
#   scripts/submit-appstore-tips.sh --submit   # really do it
#
# Steps (only --submit mutates anything):
#   1. Reuse the editable App Store version (PREPARE_FOR_SUBMISSION, etc.)
#      and set its version string to MARKETING_VERSION from project.yml, or
#      create that version. The marketing version is never bumped here.
#   2. Pick the newest VALID, unexpired build of that marketing version.
#   3. Attach the build to the version.
#   4. Run `asc validate`. Stop on blocking errors (see "Needs a human" below).
#   5. Reuse the open READY_FOR_REVIEW review draft (or create one) and stage
#      every READY_TO_SUBMIT tip's IAP version in it
#      (`asc review items add --item-type inAppPurchaseVersions`). This is the
#      public-API equivalent of ticking them on the version page; the old
#      POST /v1/inAppPurchaseSubmissions is refused for first-time IAPs
#      (STATE_ERROR.FIRST_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION).
#   6. Add the App Store version to the same draft, then submit that draft
#      (`asc review submissions-submit`). It never submits the version without
#      every tip: if Apple refuses any item, the draft is left unsubmitted and
#      the exact error is printed. Items already in the draft are skipped, so
#      re-running is safe.
#
# Needs: asc (https://github.com/rork/asc) logged in with the default profile
# (key 2VGQN75FV5), python3. Never prints credentials.
#
# Needs a human in App Store Connect first (the API can't answer these
# honestly for you): App Privacy answers, age rating questionnaire, content
# rights, app price + availability, App Store screenshots, and any account
# compliance item (e.g. EU trader status). If Apple refuses the version with
# "unfulfilled compliance requirement", clear it in App Store Connect and re-run.

set -euo pipefail

APP_ID="${ASC_APP_ID:-6833580006}"
TIP_PREFIX="dev.yoinklabs.wanderer.tip."
MODE="dry-run"
for arg in "$@"; do
  case "$arg" in
    --submit) MODE="submit" ;;
    --dry-run) MODE="dry-run" ;;
    --iaps-selected-in-asc) ;;  # obsolete: tips are now staged through the public API
    -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# --- 4. Readiness -------------------------------------------------------------
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
    if s["checkId"] == "iap.review_readiness.needs_attention": continue  # staged in step 5
    tag = "BLOCK" if s.get("blocking") else s["severity"][:4]
    blocking += bool(s.get("blocking"))
    check, msg = s["checkId"], s["message"][:100]
    print(f"  {tag:<5} {check}: {msg}", file=sys.stderr)
print(blocking)')"
echo "  blocking issues: $BLOCKING"
if [[ "$MODE" == "submit" && "$BLOCKING" != "0" ]]; then
  echo "error: $BLOCKING blocking issue(s); nothing staged or submitted." >&2
  exit 1
fi

# --- 5. Review draft + tips -----------------------------------------------------
step "Review draft"
DRAFT_ID="$(asc review submissions-list --app "$APP_ID" --output json 2>/dev/null | json '
import json, sys
rows = [r for r in json.load(sys.stdin).get("data", [])
        if r["attributes"].get("state") == "READY_FOR_REVIEW"
        and r["attributes"].get("platform", "IOS") == "IOS"]
print(rows[0]["id"] if rows else "")')"
STAGED=""
if [[ -n "$DRAFT_ID" ]]; then
  echo "  reusing open draft $DRAFT_ID"
  # Item ids encode "<submission>|<type>|<item id>"; read the staged item ids.
  STAGED="$(asc review submissions-get --id "$DRAFT_ID" --include items --output json 2>/dev/null | json '
import base64, json, sys
out = []
for i in json.load(sys.stdin).get("included", []):
    raw = i["id"] + "=" * (-len(i["id"]) % 4)
    try: out.append(base64.urlsafe_b64decode(raw).decode().split("|")[-1])
    except Exception: pass
print(" ".join(out))')"
else
  echo "  no open draft; would create one"
  echo "  \$ asc review submissions-create --app $APP_ID --platform IOS"
  if [[ "$MODE" == "submit" ]]; then
    DRAFT_ID="$(asc review submissions-create --app "$APP_ID" --platform IOS --output json | json 'import json,sys; print(json.load(sys.stdin)["data"]["id"])')"
    echo "  created draft $DRAFT_ID"
  fi
fi

step "Tip in-app purchases"
TIPS="$(asc iap list --app "$APP_ID" --paginate --output json 2>/dev/null | TIP_PREFIX="$TIP_PREFIX" json '
import json, os, sys
d = json.load(sys.stdin)
items = d["data"] if isinstance(d, dict) else d
for i in sorted(items, key=lambda x: x["attributes"]["productId"]):
    a = i["attributes"]
    if a["productId"].startswith(os.environ["TIP_PREFIX"]):
        print(i["id"], a["productId"], a["state"])')"
FAILED=0
TIP_COUNT=0
while read -r IAP_ID PRODUCT STATE; do
  [[ -n "$IAP_ID" ]] || continue
  TIP_COUNT=$((TIP_COUNT + 1))
  IAP_VERSION="$(asc iap versions list --iap-id "$IAP_ID" --output json 2>/dev/null | json '
import json, sys
rows = json.load(sys.stdin).get("data", [])
rows = [r for r in rows if r["attributes"].get("state") in ("PREPARE_FOR_SUBMISSION", "READY_TO_SUBMIT", "DEVELOPER_ACTION_NEEDED", "REJECTED")] or rows
print(rows[-1]["id"] if rows else "-")')"
  if [[ " $STAGED " == *" $IAP_VERSION "* ]]; then
    printf '  %-36s %-16s already in draft\n' "$PRODUCT" "$STATE"; continue
  fi
  if [[ "$STATE" != "READY_TO_SUBMIT" || "$IAP_VERSION" == "-" ]]; then
    printf '  %-36s %-16s not stageable\n' "$PRODUCT" "$STATE"; FAILED=$((FAILED + 1)); continue
  fi
  printf '  %-36s %-16s stage IAP version %s\n' "$PRODUCT" "$STATE" "$IAP_VERSION"
  if [[ "$MODE" == "submit" ]]; then
    if ! OUT="$(asc review items add --submission "$DRAFT_ID" --item-type inAppPurchaseVersions --item-id "$IAP_VERSION" --if-exists skip --output json 2>&1)"; then
      echo "$OUT" | grep -vE '^\s*$' | head -6 | sed 's/^/    /' >&2
      FAILED=$((FAILED + 1))
    fi
  fi
done <<<"$TIPS"
[[ "$TIP_COUNT" -gt 0 ]] || { echo "error: no tip IAPs found ($TIP_PREFIX*)" >&2; exit 1; }
if [[ "$FAILED" != "0" ]]; then
  echo "error: $FAILED tip(s) could not be staged; draft ${DRAFT_ID:-<none>} left unsubmitted." >&2
  [[ "$MODE" == "submit" ]] && exit 1
fi

# --- 6. Version + submit ----------------------------------------------------------
step "Add version to draft and submit"
if [[ " $STAGED " == *" $VERSION_ID "* ]]; then
  echo "  version $VERSION_ID already in draft"
else
  echo "  \$ asc review items add --submission ${DRAFT_ID:-<new>} --item-type appStoreVersions --item-id $VERSION_ID"
fi
echo "  \$ asc review submissions-submit --id ${DRAFT_ID:-<new>} --confirm"
if [[ "$MODE" == "dry-run" ]]; then
  echo
  if [[ "$BLOCKING" == "0" && "$FAILED" == "0" ]]; then
    echo "Dry run only. Ready: re-run with --submit (Apple may still refuse the version for an"
    echo "account compliance item that asc validate can't see; the draft is then left unsubmitted)."
  else
    echo "Dry run only. Fix the issues above before --submit."
  fi
  exit 0
fi
if ! OUT="$(asc review items add --submission "$DRAFT_ID" --item-type appStoreVersions --item-id "$VERSION_ID" --if-exists skip --output json 2>&1)"; then
  echo "$OUT" | grep -vE '^\s*$' | head -8 | sed 's/^/    /' >&2
  echo "error: Apple refused the App Store version; draft $DRAFT_ID left unsubmitted with the tips staged." >&2
  exit 1
fi
asc review submissions-submit --id "$DRAFT_ID" --confirm --output json >/dev/null
STATE="$(asc review submissions-get --id "$DRAFT_ID" --output json 2>/dev/null | json 'import json,sys; print(json.load(sys.stdin)["data"]["attributes"].get("state"))')"
echo "Submitted Wanderer $MARKETING ($BUILD_NUMBER) with $TIP_COUNT tips: review submission $DRAFT_ID ($STATE)."
