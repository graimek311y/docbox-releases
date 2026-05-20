#!/usr/bin/env bash
set -euo pipefail

# Field updater for Docbox appliances.
# Downloads a public, no-secrets release manifest + tarball, backs up the
# current app, syncs code, runs smoke checks, and reloads the kiosk browser.

MANIFEST_URL="${DOCBOX_UPDATE_MANIFEST_URL:-${1:-https://graimek311y.github.io/docbox-releases/stable/manifest.json}}"
WORKDIR="${WORKDIR:-/home/doogle/tvmed}"
BACKUP_ROOT="${BACKUP_ROOT:-$WORKDIR/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
TMPDIR="$(mktemp -d)"

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

json_get() {
  python3 - "$1" "$2" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
data = json.load(open(path))
value = data
for part in key.split('.'):
    value = value[part]
print(value)
PY
}

if [[ ! -d "$WORKDIR" ]]; then
  echo "ERROR: WORKDIR does not exist: $WORKDIR" >&2
  exit 1
fi

mkdir -p "$BACKUP_ROOT"

echo "Fetching Docbox update manifest: $MANIFEST_URL"
curl -fsSL "$MANIFEST_URL" -o "$TMPDIR/manifest.json"

VERSION="$(json_get "$TMPDIR/manifest.json" version)"
BUNDLE_URL="$(json_get "$TMPDIR/manifest.json" bundle.url)"
BUNDLE_SHA256="$(json_get "$TMPDIR/manifest.json" bundle.sha256)"
MIN_SCHEMA="$(python3 - "$TMPDIR/manifest.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1])).get('minUpdaterSchema', 1))
PY
)"

if [[ "$MIN_SCHEMA" -gt 1 ]]; then
  echo "ERROR: update requires newer updater schema $MIN_SCHEMA" >&2
  exit 1
fi

echo "Target version: $VERSION"
echo "Bundle: $BUNDLE_URL"

BACKUP="$BACKUP_ROOT/docbox-update-before-$STAMP.tgz"
echo "Backing up current Docbox app to $BACKUP"
tar -C "$WORKDIR" \
  --exclude='./backups' \
  --exclude='./.git' \
  --exclude='./.venv' \
  --exclude='./venv' \
  --exclude='./__pycache__' \
  --exclude='./*/__pycache__' \
  --exclude='./*.env' \
  --exclude='./tvmed-device.env' \
  --exclude='./web/tvmed-kvs-config.js' \
  -czf "$BACKUP" .

echo "Downloading release bundle"
curl -fsSL "$BUNDLE_URL" -o "$TMPDIR/update.tgz"
if command -v sha256sum >/dev/null 2>&1; then
  echo "$BUNDLE_SHA256  $TMPDIR/update.tgz" | sha256sum -c -
else
  actual="$(shasum -a 256 "$TMPDIR/update.tgz" | awk '{print $1}')"
  [[ "$actual" == "$BUNDLE_SHA256" ]] || { echo "ERROR: sha256 mismatch: $actual" >&2; exit 1; }
fi

mkdir -p "$TMPDIR/src"
tar -xzf "$TMPDIR/update.tgz" -C "$TMPDIR/src"

if [[ ! -f "$TMPDIR/src/tvmed_device_api.py" || ! -f "$TMPDIR/src/web/device-kiosk.html" ]]; then
  echo "ERROR: bundle does not look like a TVmed/Docbox app" >&2
  exit 1
fi

echo "Syncing release into $WORKDIR"
rsync -a --delete \
  --exclude='.git/' \
  --exclude='.herenow/' \
  --exclude='backups/' \
  --exclude='node_modules/' \
  --exclude='.venv/' \
  --exclude='venv/' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='*.env' \
  --exclude='tvmed-device.env' \
  --exclude='web/tvmed-kvs-config.js' \
  "$TMPDIR/src/" "$WORKDIR/"

cd "$WORKDIR"
echo "$VERSION" > .docbox-version

echo "Running smoke checks"
if command -v node >/dev/null 2>&1; then
  node --check web/device-kiosk.js
  node tests/device-kiosk-state.test.js
fi
python3 -m py_compile tvmed_device_api.py scripts/tvmed_prepare_call.py

python3 - <<'PY'
from pathlib import Path
html = Path('web/device-kiosk.html').read_text()
js = Path('web/device-kiosk.js').read_text()
assert 'docbox.tv Device Kiosk' in html, 'kiosk HTML marker missing'
assert 'id="headerConfirmEnd"' in html, 'header End Call button missing'
assert 'id="end"' not in html, 'body End Call button still present in HTML'
assert "el('end')" not in js, "body End Call JS references still present"
print('Verified: kiosk bundle smoke checks passed')
PY

echo "Reloading kiosk browser if CDP is available"
python3 - <<'PY' || true
import json
try:
    import tvmed_device_api as api
    result = api.websocket_eval(api.find_kiosk_ws_url(), "window.location.reload()")
    print(json.dumps({"reloaded": True, "result": result}))
except Exception as exc:
    print(json.dumps({"reloaded": False, "error": str(exc)}))
PY

echo "Docbox update complete. Version: $VERSION. Backup: $BACKUP"
