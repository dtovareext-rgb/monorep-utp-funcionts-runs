#!/usr/bin/env bash
# Backfill prd-utpbi-mentores-gcs-copy — un día a la vez (2–5 min c/u).
# Uso Cloud Shell:
#   bash backfill_fechas_cloudshell.sh
#   bash backfill_fechas_cloudshell.sh 2026-10-08 2026-11-09
# Opcional: RUN_WHISPER=false bash ...

set -euo pipefail

PROJECT="${PROJECT:-prd-utpbi-data-operation}"
LOC="${LOC:-us-central1}"
WF="${WF:-prd-utpbi-mentores-gcs-copy}"
START="${1:-2026-10-08}"
END="${2:-2026-11-09}"
RUN_WHISPER="${RUN_WHISPER:-true}"
LOG="${LOG:-$HOME/mentores_backfill_${START}_${END}.log}"

echo "Backfill mentores ${START} → ${END} whisper=${RUN_WHISPER}" | tee -a "$LOG"
echo "log=$LOG"

# Genera fechas YYYY-MM-DD inclusive
d="$START"
while [[ "$d" < "$END" || "$d" == "$END" ]]; do
  echo "========== START ${d} $(date -u +%Y-%m-%dT%H:%M:%SZ) ==========" | tee -a "$LOG"

  EXEC=$(gcloud workflows run "$WF" \
    --project="$PROJECT" \
    --location="$LOC" \
    --data="{\"process_date\":\"${d}\",\"run_whisper\":${RUN_WHISPER}}" \
    --format='value(name)')

  echo "execution: $EXEC" | tee -a "$LOG"

  while true; do
    STATE=$(gcloud workflows executions describe "$EXEC" \
      --project="$PROJECT" \
      --location="$LOC" \
      --format='value(state)')
    echo "  ${d} state=${STATE}" | tee -a "$LOG"
    case "$STATE" in
      SUCCEEDED|FAILED|CANCELLED) break ;;
    esac
    sleep 30
  done

  if [[ "$STATE" != "SUCCEEDED" ]]; then
    echo "ABORT ${d} state=${STATE}" | tee -a "$LOG"
    exit 1
  fi

  echo "========== OK ${d} ==========" | tee -a "$LOG"

  # siguiente día (GNU date en Cloud Shell)
  d=$(date -I -d "${d} + 1 day")
done

echo "DONE ${START}→${END}" | tee -a "$LOG"
