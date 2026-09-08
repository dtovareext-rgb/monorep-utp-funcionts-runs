#!/usr/bin/env bash
# Reproceso Gemini QueueSmart — un día por job (evita timeout en rangos largos)
#
# Uso:
#   bash reprocess_gemini_rango.sh 2026-08-17 2026-08-26
#   bash reprocess_gemini_rango.sh 2026-08-17 2026-08-26 --dry-run
#
set -euo pipefail

PROJECT_ID="${BQ_PROJECT_ID:-prd-utpbi-data-operation}"
LOCATION="${BQ_LOCATION:-US}"
DESDE="${1:?Uso: $0 FECHA_DESDE FECHA_HASTA [--dry-run]  (YYYY-MM-DD)}"
HASTA="${2:?Uso: $0 FECHA_DESDE FECHA_HASTA [--dry-run]  (YYYY-MM-DD)}"
DRY_RUN="${3:-}"

if [[ "$DESDE" > "$HASTA" ]]; then
  echo "Error: FECHA_DESDE ($DESDE) no puede ser posterior a FECHA_HASTA ($HASTA)" >&2
  exit 1
fi

current="$DESDE"
while [[ "$current" < "$HASTA" || "$current" == "$HASTA" ]]; do
  echo ""
  echo "=== Gemini reproceso: $current ==="
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "DRY-RUN: CALL sp_queuesmart_audio_analisis_ia(DATE '$current', NULL)"
  else
    bq query \
      --use_legacy_sql=false \
      --location="$LOCATION" \
      --project_id="$PROJECT_ID" \
      "CALL \`${PROJECT_ID}.adf_speech_analytics.sp_queuesmart_audio_analisis_ia\`(DATE '${current}', NULL);"
  fi
  current="$(date -I -d "${current} + 1 day")"
done

echo ""
echo "Listo: rango ${DESDE} .. ${HASTA}"
