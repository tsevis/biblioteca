#!/bin/bash
#
# sign-and-notarize.sh — Developer ID sign, notarize and staple a macOS .app
#
# Usage:
#   ./sign-and-notarize.sh <path/to/App.app> [--python] [--entitlements FILE]
#                          [--version X.Y.Z] [--no-dmg] [--sign-only]
#
#   --python     add entitlements required by Python/PyInstaller bundles
#   --entitlements FILE
#                sign with this entitlements plist. REQUIRED for a sandboxed
#                app: `codesign --force` without it re-signs with *no*
#                entitlements, so a bundle built with the sandbox ships
#                without it, silently. Verified after signing.
#   --version    version string used in the DMG filename (default: from Info.plist)
#   --no-dmg     sign and notarize the .app only; skip DMG packaging
#   --sign-only  sign and package, but stop before submitting to Apple
#
# Environment:
#   APPLE_TEAM_ID  your Apple Developer team ID (required; it is part of the
#                  Developer ID signing identity name)
#
# The source .app is never modified. A signed copy is written to
# <app-dir>/signed/ alongside the notarized, stapled DMG.

set -euo pipefail

# SIGN_ID is built in the preflight checks below, from APPLE_TEAM_ID.
readonly NOTARY_PROFILE="crewlistr-notary"
readonly NOTARY_TIMEOUT="30m"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[32m  ok\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------- arguments

APP=""; IS_PYTHON=0; VERSION=""; MAKE_DMG=1; SIGN_ONLY=0; ENTITLEMENTS_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --python)    IS_PYTHON=1; shift ;;
    --no-dmg)    MAKE_DMG=0; shift ;;
    --sign-only) SIGN_ONLY=1; shift ;;
    --entitlements)
      ENTITLEMENTS_FILE="${2:-}"
      [ -n "$ENTITLEMENTS_FILE" ] || die "--entitlements needs a path"
      shift 2 ;;
    --version) VERSION="${2:-}"; [ -n "$VERSION" ] || die "--version needs a value"; shift 2 ;;
    -*)        die "unknown option: $1" ;;
    *)         [ -z "$APP" ] || die "only one .app may be given"; APP="$1"; shift ;;
  esac
done

[ -n "$APP" ] || die "usage: $0 <path/to/App.app> [--python] [--entitlements FILE] [--version X.Y.Z] [--no-dmg]"
[ -d "$APP" ] || die "not a directory: $APP"
[[ "$APP" == *.app ]] || die "not an .app bundle: $APP"

# The two entitlement sources would have to be merged to be combined, and
# guessing at a merge is worse than saying so.
if [ "$IS_PYTHON" -eq 1 ] && [ -n "$ENTITLEMENTS_FILE" ]; then
  die "--python and --entitlements are alternatives; pass one or the other"
fi
if [ -n "$ENTITLEMENTS_FILE" ]; then
  [ -f "$ENTITLEMENTS_FILE" ] || die "no such entitlements file: $ENTITLEMENTS_FILE"
  plutil -lint "$ENTITLEMENTS_FILE" >/dev/null 2>&1 \
    || die "not a readable plist: $ENTITLEMENTS_FILE"
  ENTITLEMENTS_FILE=$(cd "$(dirname "$ENTITLEMENTS_FILE")" && pwd)/$(basename "$ENTITLEMENTS_FILE")
fi

# ------------------------------------------------------- preflight checks

[ -n "${APPLE_TEAM_ID:-}" ] \
  || die "APPLE_TEAM_ID is not set: export your Apple Developer team ID first"
readonly SIGN_ID="Developer ID Application: CHARALAMPOS TSEVIS (${APPLE_TEAM_ID})"

security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID" \
  || die "signing identity not found in keychain: $SIGN_ID"

if [ "$SIGN_ONLY" -eq 0 ]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notary profile '$NOTARY_PROFILE' missing or invalid; run notarytool store-credentials"
fi

APP=$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")
readonly APP_NAME=$(basename "$APP" .app)
readonly OUT_DIR=$(dirname "$APP")/signed
readonly SIGNED_APP="$OUT_DIR/$APP_NAME.app"

if [ -z "$VERSION" ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$APP/Contents/Info.plist" 2>/dev/null || echo "1.0")
fi
readonly DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"

log "app      $APP"
log "version  $VERSION"
log "output   $OUT_DIR"

# --------------------------------------------------------- copy the bundle

mkdir -p "$OUT_DIR"
rm -rf "$SIGNED_APP"
cp -R "$APP" "$SIGNED_APP"
ok "copied (source left untouched)"

# ------------------------------------------------------------ entitlements

ENTITLEMENTS=""
if [ -n "$ENTITLEMENTS_FILE" ]; then
  ENTITLEMENTS="$ENTITLEMENTS_FILE"
  ok "entitlements $(basename "$ENTITLEMENTS_FILE")"
fi
if [ "$IS_PYTHON" -eq 1 ]; then
  ENTITLEMENTS=$(mktemp -t entitlements).plist
  cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key><true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
PLIST
  ok "python entitlements prepared"
fi

sign_one() {
  if [ -n "$ENTITLEMENTS" ]; then
    codesign --force --options runtime --timestamp \
             --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$1"
  else
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$1"
  fi
}

# ------------------------------------------------- sign inner code, bottom-up
# Nested binaries must be signed before the bundle that contains them.
# Apple discourages --deep for signing; sign each item explicitly instead.

# Apple validates EVERY Mach-O executable in the bundle, not just libraries.
# Matching on *.dylib / *.so misses bare helper binaries with no extension
# (e.g. an embedded ffmpeg or a vendored CLI in Resources/), which then keep
# their ad-hoc signature and fail notarization. Detect by content instead.
log "finding nested mach-o binaries"

MAIN_EXE=""
_main=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" \
        "$SIGNED_APP/Contents/Info.plist" 2>/dev/null || true)
[ -n "$_main" ] && MAIN_EXE="$SIGNED_APP/Contents/MacOS/$_main"

# Test EVERY regular file. Filtering on the executable bit misses Mach-O files
# that ship without it — PyInstaller's bootloaders (run, runw), framework
# binaries like Python — and Apple rejects those just the same. `file` is
# batched through xargs because per-file invocation is far too slow on a
# bundle carrying a full CPython.
MACHO_LIST=$(mktemp)
find "$SIGNED_APP" -type f -print0 2>/dev/null \
  | xargs -0 -n 200 file 2>/dev/null \
  | grep "Mach-O" \
  | sed 's/:[[:space:]]*Mach-O.*$//' \
  | while IFS= read -r f; do
      [ -e "$f" ] || continue
      printf '%s\t%s\n' "$(printf '%s' "$f" | tr -cd '/' | wc -c)" "$f"
    done > "$MACHO_LIST"

# Deepest paths first: nested code must be signed before its container.
NESTED=0; FAILED=0
while IFS=$'\t' read -r _depth item; do
  [ -n "$item" ] || continue
  # Skip only the bundle's own main executable — it is signed with the bundle.
  # Testing "is it inside Contents/MacOS" instead wrongly skips sibling
  # libraries that live there too (e.g. Xcode's __preview.dylib).
  [ -n "$MAIN_EXE" ] && [ "$item" = "$MAIN_EXE" ] && continue
  if sign_one "$item" >/dev/null 2>&1; then NESTED=$((NESTED + 1))
  else FAILED=$((FAILED + 1)); printf '  \033[33mwarn\033[0m could not sign %s\n' "$(basename "$item")"; fi
done < <(sort -rn "$MACHO_LIST")
rm -f "$MACHO_LIST"

# Frameworks and bundles are signed as units, after their contents.
while IFS= read -r item; do
  [ -n "$item" ] || continue
  sign_one "$item" >/dev/null 2>&1 && NESTED=$((NESTED + 1)) || true
done < <(find "$SIGNED_APP" -maxdepth 6 \( -name "*.framework" -o -name "*.bundle" \) 2>/dev/null)

ok "$NESTED nested item(s) signed${FAILED:+, $FAILED failed}"
[ "$FAILED" -eq 0 ] || die "$FAILED nested binary/binaries could not be signed — notarization would be rejected"

# ------------------------------------------------------- sign the app bundle

log "signing app bundle"
sign_one "$SIGNED_APP"
codesign --verify --deep --strict --verbose=2 "$SIGNED_APP" 2>&1 | sed 's/^/  /'

# Capture once and test the string. Piping into `grep -q` under `set -o pipefail`
# reports failure on success: grep exits at the first match, codesign then dies
# of SIGPIPE, and pipefail surfaces that as a non-zero pipeline.
SIG_INFO=$(codesign -dv --verbose=4 "$SIGNED_APP" 2>&1)

case "$SIG_INFO" in
  *flags=*runtime*) ;;
  *) die "hardened runtime not enabled — notarization would be rejected" ;;
esac

# An entitlements file that was asked for and did not land is the failure this
# flag exists to prevent: the app runs, notarizes and ships, with the sandbox
# quietly gone.
if [ -n "$ENTITLEMENTS" ]; then
  SIGNED_ENTS=$(codesign -d --entitlements - --xml "$SIGNED_APP" 2>/dev/null || true)
  while IFS= read -r key; do
    case "$SIGNED_ENTS" in
      *"$key"*) ;;
      *) die "entitlement '$key' did not survive signing" ;;
    esac
  done < <(plutil -convert xml1 -o - "$ENTITLEMENTS" \
           | grep -o '<key>[^<]*</key>' | sed 's|</\?key>||g')
  ok "entitlements verified on the signed bundle"
fi
case "$SIG_INFO" in
  *"Timestamp="*) ;;
  *) die "no secure timestamp — notarization would be rejected" ;;
esac
ok "hardened runtime + secure timestamp confirmed"

# `codesign --deep --strict` above is not sufficient: an ad-hoc signature IS a
# signature, so a nested binary that never got re-signed still passes it. Apple
# rejects on the identity, so check the identity on every Mach-O we can find.
log "auditing every nested binary (identity, timestamp, hardened runtime)"

# Rebuild the Mach-O list from the signed bundle: signing rewrites files, so
# this must reflect the bundle as it now stands, not as it was before signing.
AUDIT_LIST=$(mktemp)
find "$SIGNED_APP" -type f -print0 2>/dev/null \
  | xargs -0 -n 200 file 2>/dev/null \
  | grep "Mach-O" \
  | sed 's/:[[:space:]]*Mach-O.*$//' \
  | while IFS= read -r f; do
      [ -e "$f" ] || continue
      printf '%s\t%s\n' "$(printf '%s' "$f" | tr -cd '/' | wc -c)" "$f"
    done > "$AUDIT_LIST"

BAD=0; CHECKED=0
while IFS=$'\t' read -r _d f; do
  [ -n "$f" ] || continue
  CHECKED=$((CHECKED + 1))
  info=$(codesign -dv --verbose=4 "$f" 2>&1)
  why=""
  case "$info" in *"Developer ID Application"*) ;; *) why="identity" ;; esac
  case "$info" in *"Timestamp="*) ;; *) why="${why:+$why,}timestamp" ;; esac
  case "$info" in *flags=*runtime*) ;; *) why="${why:+$why,}runtime" ;; esac
  if [ -n "$why" ]; then
    BAD=$((BAD + 1))
    [ "$BAD" -le 10 ] && printf '  \033[31mbad\033[0m %-58s (%s)\n' "${f#"$SIGNED_APP"/}" "$why"
  fi
done < <(sort -rn "$AUDIT_LIST")
rm -f "$AUDIT_LIST"

[ "$BAD" -eq 0 ] || die "$BAD of $CHECKED nested binaries would be rejected by Apple"
ok "all $CHECKED nested binaries pass identity + timestamp + runtime"

# ------------------------------------------------------------------- package

if [ "$MAKE_DMG" -eq 0 ]; then
  TARGET="$SIGNED_APP"
  ZIP="$OUT_DIR/$APP_NAME-$VERSION.zip"
  log "packaging zip for submission (app-only mode)"
  ditto -c -k --keepParent "$SIGNED_APP" "$ZIP"
  SUBMIT="$ZIP"
else
  log "building dmg"
  STAGE=$(mktemp -d)
  trap 'rm -rf "$STAGE"' EXIT
  cp -R "$SIGNED_APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" \
                 -ov -format UDZO "$DMG" >/dev/null
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
  codesign --verify --strict "$DMG"
  ok "dmg signed: $(basename "$DMG")"
  TARGET="$DMG"
  SUBMIT="$DMG"
fi

# ------------------------------------------------------------------ notarize

if [ "$SIGN_ONLY" -eq 1 ]; then
  echo
  ok "signed and packaged, not submitted — $TARGET"
  echo "     to notarize later:"
  echo "       xcrun notarytool submit '$SUBMIT' --keychain-profile $NOTARY_PROFILE --wait"
  echo "       xcrun stapler staple '$TARGET'"
  exit 0
fi

log "submitting to apple notary service (this can take several minutes)"
if ! xcrun notarytool submit "$SUBMIT" \
       --keychain-profile "$NOTARY_PROFILE" --wait --timeout "$NOTARY_TIMEOUT"; then
  echo
  die "notarization failed — run: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
fi

# -------------------------------------------------------------------- staple

log "stapling ticket"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"

# --------------------------------------------------------------- final check

log "gatekeeper assessment (as a freshly downloaded copy would see it)"
if [ "$MAKE_DMG" -eq 1 ]; then
  spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/  /'
fi
spctl -a -t exec -vv "$SIGNED_APP" 2>&1 | sed 's/^/  /'

echo
ok "done — $TARGET"
