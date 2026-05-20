#!/usr/bin/env bash
set -euo pipefail
curl -fsSL https://raw.githubusercontent.com/graimek311y/docbox-releases/main/stable/docbox_device_update.sh -o /tmp/docbox_device_update.sh 2>/dev/null || true
if [[ -s /tmp/docbox_device_update.sh ]]; then
  bash /tmp/docbox_device_update.sh https://raw.githubusercontent.com/graimek311y/docbox-releases/main/stable/manifest.json
else
  curl -fsSL https://raw.githubusercontent.com/graimek311y/docbox-releases/main/stable/docbox-update-stable-ccc6f48.tgz -o /tmp/docbox-update.tgz
  echo 'Installer helper missing; use scripts/docbox_device_update.sh from an already-installed Docbox app.' >&2
  exit 1
fi
