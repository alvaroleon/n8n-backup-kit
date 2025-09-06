#!/bin/bash
# Development: Alvaro León <alvaro@flownexai.com>
# Import n8n workflows and credentials into a running container.
# Usage:
#   ./import-n8n.sh ./n8n-backup-YYYYMMDD_HHMMSSUTC
#   ./import-n8n.sh ./n8n-backup-YYYYMMDD_HHMMSSUTC.tar.gz
#
# The backup must contain:
#   - workflows.json
#   - credentials.json
set -euo pipefail

abort() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || abort "'$1' not found"; }

BACKUP_SRC="${1:-}"
[[ -n "$BACKUP_SRC" ]] || abort "Provide backup path (dir or .tar.gz). Example: ./import-n8n.sh ./n8n-backup-20250101_120000UTC[.tar.gz]"

need docker
need tar

# --- env (CID, SHARED_DIR) ---
if [[ -f .env ]]; then
  set -o allexport
  # shellcheck disable=SC1091
  source .env
  set +o allexport
else
  abort "'.env' not found. Copy '.env.example' to '.env' and adjust values."
fi

: "${CID:?CID is required in .env}"
: "${SHARED_DIR:?SHARED_DIR is required in .env}"

# container exists & running?
docker inspect "$CID" >/dev/null 2>&1 || abort "Container '$CID' not found"
if [[ "$(docker inspect -f '{{.State.Running}}' "$CID")" != "true" ]]; then
  abort "Container '$CID' is not running"
fi

# ensure destination container has an encryption key (env or ~/.n8n/config)
HAS_ENV_KEY="$(docker exec "$CID" sh -lc 'test -n "${N8N_ENCRYPTION_KEY:-}" && echo yes || echo no')"
HAS_CFG_KEY="$(docker exec "$CID" sh -lc 'grep -q \"encryptionKey\" /home/node/.n8n/config 2>/dev/null && echo yes || echo no')"
if [[ "$HAS_ENV_KEY" != "yes" && "$HAS_CFG_KEY" != "yes" ]]; then
  abort "Destination container has no encryption key. Set N8N_ENCRYPTION_KEY env or ensure /home/node/.n8n/config contains 'encryptionKey'."
fi

# --- prepare source on host ---
CLEANUP_TMP=false
if [[ -f "$BACKUP_SRC" && "$BACKUP_SRC" == *.tar.gz ]]; then
  TMP_DIR="$(mktemp -d)"
  CLEANUP_TMP=true
  echo "[INFO] Extracting archive to: $TMP_DIR"
  tar -xzf "$BACKUP_SRC" -C "$TMP_DIR"
  SRC_DIR="$TMP_DIR"
elif [[ -d "$BACKUP_SRC" ]]; then
  SRC_DIR="${BACKUP_SRC%/}"
else
  abort "Backup path must be an existing directory or a .tar.gz file"
fi

[[ -f "${SRC_DIR}/workflows.json" ]] || abort "Missing workflows.json in backup source"
[[ -f "${SRC_DIR}/credentials.json" ]] || abort "Missing credentials.json in backup source"

# temp folder name inside container
BASE_NAME="$(basename "${BACKUP_SRC%.tar.gz}")"
TEMP_IN_CONT="${SHARED_DIR%/}/${BASE_NAME}"

# create target dir inside container
docker exec -u node "$CID" sh -lc "mkdir -p '$TEMP_IN_CONT'"

# copy source into container
docker cp "${SRC_DIR}/." "$CID:$TEMP_IN_CONT"

# import (re-encrypts automatically with the container's own key)
docker exec -u node "$CID" sh -lc "
  test -f '${TEMP_IN_CONT}/workflows.json' &&
  test -f '${TEMP_IN_CONT}/credentials.json' &&
  n8n import:workflow --separate --input='${TEMP_IN_CONT}/workflows.json' &&
  n8n import:credentials --separate --input='${TEMP_IN_CONT}/credentials.json'
"

echo "[OK] Imported from: ${BACKUP_SRC}"
echo "[OK] Used container path: ${TEMP_IN_CONT}"

# cleanup temp
if [[ "$CLEANUP_TMP" == true ]]; then
  rm -rf "$TMP_DIR"
fi