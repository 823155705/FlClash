#!/usr/bin/env bash
# Generate a release keystore for FlClash Widget APK signing.
# Usage:
#   ./scripts/generate-keystore.sh [output-dir]
# Then encode and paste into GitHub Secrets (see docs/ANDROID_SIGNING.md).

set -euo pipefail

OUT_DIR="${1:-./signing}"
ALIAS="${KEY_ALIAS:-flclash}"
STOREPASS="${STORE_PASSWORD:-}"
KEYPASS="${KEY_PASSWORD:-}"
DN="${KEY_DN:-CN=FlClash Widget, OU=Personal, O=Local, L=City, S=State, C=CN}"

mkdir -p "$OUT_DIR"
KS_PATH="$OUT_DIR/flclash-widget.jks"

if [[ -f "$KS_PATH" ]]; then
  echo "Keystore already exists: $KS_PATH" >&2
  echo "Delete it first if you want to regenerate (this would break upgrade installs)." >&2
  exit 1
fi

if [[ -z "$STOREPASS" ]]; then
  STOREPASS="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-16)"
  echo "Generated storePassword: $STOREPASS"
fi
if [[ -z "$KEYPASS" ]]; then
  KEYPASS="$STOREPASS"
  echo "keyPassword = storePassword"
fi

keytool -genkeypair \
  -v \
  -keystore "$KS_PATH" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10950 \
  -storepass "$STOREPASS" \
  -keypass "$KEYPASS" \
  -dname "$DN"

echo
echo "Keystore written to: $KS_PATH"
echo
echo "=== GitHub Secrets ==="
echo "KEYSTORE       (base64 of jks):"
base64 < "$KS_PATH" | tr -d '\n'
echo
echo "KEY_ALIAS      : $ALIAS"
echo "STORE_PASSWORD : $STOREPASS"
echo "KEY_PASSWORD   : $KEYPASS"
echo
echo "Keep this keystore and passwords safe. Losing them means future APKs"
echo "cannot upgrade-install over ones signed with this key."
