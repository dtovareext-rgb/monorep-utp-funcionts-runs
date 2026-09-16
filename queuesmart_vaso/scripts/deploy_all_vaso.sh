#!/usr/bin/env bash
# Deploy completo stacks VASO QueeSmart (BQ + Workflow).
# No despliega Cloud Run Jobs (gap / Whisper): usar sus cloudbuild.
#
# Uso:
#   cd monorep-utp-funcionts-runs
#   bash queuesmart_vaso/scripts/deploy_all_vaso.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="${PROJECT_ID:-prd-utpbi-data-operation}"
LOCATION_BQ="${BQ_LOCATION:-US}"
LOCATION_WF="${WF_LOCATION:-us-central1}"
SA="${SERVICE_ACCOUNT:-genesys-audio-processor@${PROJECT}.iam.gserviceaccount.com}"
WF_NAME="${WF_NAME:-queuesmart-vaso-pipeline}"

echo "=== queuesmart_vaso deploy ALL (project=$PROJECT) ==="

run_bq() {
  local f="$1"
  echo "--- bq: $f"
  bq query --use_legacy_sql=false --location="$LOCATION_BQ" --project_id="$PROJECT" < "$ROOT/$f"
}

# 1) Tablas (orden: hist ingest → consolidated → whisper → analisis)
run_bq "queuesmart_vaso/bigquery/tables/hist_queesmart_mp3_catalog_vaso.sql"
run_bq "queuesmart_vaso/bigquery/tables/queuesmart_mp3_catalog_vaso.sql"
run_bq "queuesmart_vaso/bigquery/tables/queuesmart_mp3_enriched_vaso.sql"
run_bq "queuesmart_vaso/bigquery/tables/hist_queuesmart_mp3_whisper_vaso.sql"
run_bq "queuesmart_vaso/bigquery/tables/hist_queuesmart_audio_analisis_ia_vaso.sql"

# 2) SPs
run_bq "queuesmart_vaso/bigquery/procedures/sp_queuesmart_mp3_consolidate_vaso.sql"
run_bq "queuesmart_vaso/bigquery/procedures/sp_queuesmart_audio_analisis_ia_vaso.sql"

# 3) Workflow
echo "--- workflow: $WF_NAME"
gcloud workflows deploy "$WF_NAME" \
  --source="$ROOT/queuesmart_vaso/workflows/vaso_pipeline.yaml" \
  --location="$LOCATION_WF" \
  --project="$PROJECT" \
  --service-account="$SA"

echo "=== OK deploy_all_vaso ==="
echo "Jobs Cloud Run (si faltan):"
echo "  qs_s3_gap_vaso/cloudbuild.yaml  → prd-utpbi-s3-gap-vaso"
echo "  cr_serialize_queuesmart/cloudbuild.yaml → prd-utpbi-queuesmart-audio-serialize-whisper-vaso"
echo "Run:"
echo "  gcloud workflows run $WF_NAME --location=$LOCATION_WF --project=$PROJECT --data='{\"process_date\":\"YYYY-MM-DD\"}'"
