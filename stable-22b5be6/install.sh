#!/usr/bin/env bash
set -euo pipefail
curl -fsSL https://graimek311y.github.io/docbox-releases/stable-22b5be6/docbox_device_update.sh -o /tmp/docbox_device_update.sh 2>/dev/null || true
if [[ -s /tmp/docbox_device_update.sh ]]; then
  bash /tmp/docbox_device_update.sh https://graimek311y.github.io/docbox-releases/stable/manifest.json
else
  curl -fsSL https://graimek311y.github.io/docbox-releases/stable-22b5be6/docbox-update-stable-22b5be6.tgz -o /tmp/docbox-update.tgz
  echo 'Installer helper missing; use scripts/docbox_device_update.sh from an already-installed Docbox app.' >&2
  exit 1
fi
