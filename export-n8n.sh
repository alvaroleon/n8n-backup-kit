#!/bin/bash
# Development: Alvaro León <alvaro@flownexai.com>
# Export n8n workflows and credentials, then compress into a .tar.gz file.
# Usage:
#   ./export-n8n.sh
#
# Produces:
#   ./n8n-backup-YYYYMMDD_HHMMSSUTC.tar.gz
set -euo pipefail

abort() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || abort "'$1' not found"; }

need docker
need tar

# --- env ---
if [[ -f .env ]]; then
  set -o allexport
  source .env
  set +o allexport
else
  abort "'.env' not found. Copy '.env.example' to '.env' and adjust values."
fi

: "${CID:?CID is required in .env}"
: "${N8N_ENCRYPTION_KEY:?N8N_ENCRYPTION_KEY is required in .env}"
: "${SHARED_DIR:?SHARED_DIR is required in .env}"

# container exists & running?
docker inspect "$CID" >/dev/null 2>&1 || abort "Container '$CID' not found"
if [[ "$(docker inspect -f '{{.State.Running}}' "$CID")" != "true" ]]; then
  abort "Container '$CID' is not running"
fi

# timestamped backup name
TIMESTAMP="$(date -u +%Y%m%d_%H%M%SUTC)"
BACKUP_NAME="n8n-backup-${TIMESTAMP}"
BACKUP_IN_CONT="${SHARED_DIR%/}/${BACKUP_NAME}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[INFO] Creating backup inside container: $BACKUP_IN_CONT"
docker exec -u node "$CID" sh -lc "mkdir -p '$BACKUP_IN_CONT'"

# export workflows + credentials (decrypted)
docker exec -u node \
  -e N8N_ENCRYPTION_KEY="$N8N_ENCRYPTION_KEY" \
  -e N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true \
  "$CID" sh -lc "
    n8n export:workflow --all --output='${BACKUP_IN_CONT}/workflows.json' &&
    n8n export:credentials --all --decrypted --output='${BACKUP_IN_CONT}/credentials.json'
  "

# copy from container to temp folder
docker cp "$CID:${BACKUP_IN_CONT}/." "$TMP_DIR"

# compress to tar.gz
ARCHIVE_NAME="${BACKUP_NAME}.tar.gz"
tar -czf "$ARCHIVE_NAME" -C "$TMP_DIR" .

echo "[OK] Backup created: ${ARCHIVE_NAME}"