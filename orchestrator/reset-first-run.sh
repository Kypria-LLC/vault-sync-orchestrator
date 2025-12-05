#!/usr/bin/env bash
set -euo pipefail

# Emergency reset for forcing re-ingestion
# Removes the persistent first-run flag so the next sync will perform full ingestion.

FLAG_PATH="orchestrator/state/firstrun.flag"

if [ -f "$FLAG_PATH" ]; then
  rm -f "$FLAG_PATH"
  echo "Removed $FLAG_PATH — next sync will perform full ingestion."
else
  echo "$FLAG_PATH not present — nothing to remove."
fi
