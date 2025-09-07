#!/bin/bash
# Development: Alvaro León <alvaro@flownexai.com>
# Import n8n workflows and credentials into a running container.
# Accepts a folder or a .tar.gz. Handles .json.gz. Tries file-first then dir fallback.
# Usage:
#   ./import-n8n.sh ./n8n-backup-YYYYMMDD_HHMMSSUTC
#   ./import-n8n.sh ./n8n-backup-YYYYMMDD_HHMMSSUTC.tar.gz

set -euo pipefail

abort() { echo "ERROR: $*" >&2; exit 1; }
need()  { command -v "$1" >/dev/null 2>&1 || abort "'$1' not found"; }

BACKUP_SRC="${1:-}"
[[ -n "$BACKUP_SRC" ]] || abort "Provide backup path (dir or .tar.gz). Example: ./import-n8n.sh ./n8n-backup-20250101_120000UTC[.tar.gz]"

need docker
need tar
need gzip

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
  abort "Destination container has no encryption key. Set N8N_ENCRYPTION_KEY or ensure /home/node/.n8n/config contains 'encryptionKey'."
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

# Locate JSON or JSON.GZ
WF_SRC="$(find "$SRC_DIR" -maxdepth 2 -type f \( -name 'workflows.json' -o -name 'workflows.json.gz' \) | head -n1 || true)"
CR_SRC="$(find "$SRC_DIR" -maxdepth 2 -type f \( -name 'credentials.json' -o -name 'credentials.json.gz' \) | head -n1 || true)"
[[ -n "$WF_SRC" ]] || abort "Missing workflows.json(.gz) in backup source"
[[ -n "$CR_SRC" ]] || abort "Missing credentials.json(.gz) in backup source"

# Build staging with directories expected (and keep file paths too)
STAGE_DIR="$(mktemp -d)"
mkdir -p "${STAGE_DIR}/workflows" "${STAGE_DIR}/credentials"

# Normalize/decompress to staging
WF_FILE="${STAGE_DIR}/workflows/workflows.json"
CR_FILE="${STAGE_DIR}/credentials/credentials.json"

[[ "$WF_SRC" == *.gz ]] && gzip -dc "$WF_SRC" > "$WF_FILE" || cp -f "$WF_SRC" "$WF_FILE"
[[ "$CR_SRC" == *.gz ]] && gzip -dc "$CR_SRC" > "$CR_FILE" || cp -f "$CR_SRC" "$CR_FILE"

# temp folder name inside container
BASE_NAME="$(basename "${BACKUP_SRC%.tar.gz}")"
TEMP_IN_CONT="${SHARED_DIR%/}/${BASE_NAME}"

# create target dir inside container and copy staging
docker exec -u node "$CID" sh -lc "mkdir -p '$TEMP_IN_CONT'"
docker cp "${STAGE_DIR}/." "$CID:$TEMP_IN_CONT"

# Import helpers (file-first, fallback to dir)
run_in_cont() {
  docker exec -u node "$CID" sh -lc "$1"
}

echo "[*] Verifying files in container..."
run_in_cont "
  set -e
  test -s '${TEMP_IN_CONT}/credentials/credentials.json'
  test -s '${TEMP_IN_CONT}/workflows/workflows.json'
"

echo "[*] Importing credentials (file-first, then dir fallback)..."
set +e
run_in_cont "n8n import:credentials --input='${TEMP_IN_CONT}/credentials/credentials.json'"
RC_CR=$?
if [[ $RC_CR -ne 0 ]]; then
  echo '[i] Credentials import via FILE failed, retrying with DIRECTORY...'
  run_in_cont "n8n import:credentials --input='${TEMP_IN_CONT}/credentials'"
  RC_CR=$?
fi
set -e
[[ $RC_CR -eq 0 ]] || abort "Credentials import failed"

echo "[*] Importing workflows (file-first, then dir fallback)..."
set +e
run_in_cont "n8n import:workflow --input='${TEMP_IN_CONT}/workflows/workflows.json' --overwrite"
RC_WF=$?
if [[ $RC_WF -ne 0 ]]; then
  echo '[i] Workflows import via FILE failed, retrying with DIRECTORY...'
  run_in_cont "n8n import:workflow --input='${TEMP_IN_CONT}/workflows' --overwrite"
  RC_WF=$?
fi
set -e
[[ $RC_WF -eq 0 ]] || abort "Workflows import failed"

echo "[OK] Imported from: ${BACKUP_SRC}"
echo "[OK] Used container path: ${TEMP_IN_CONT}"

# cleanup
rm -rf "$STAGE_DIR"
if [[ "$CLEANUP_TMP" == true ]]; then
  rm -rf "$TMP_DIR"
fi

