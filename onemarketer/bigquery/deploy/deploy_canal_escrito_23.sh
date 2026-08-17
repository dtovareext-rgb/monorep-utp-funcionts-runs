#!/usr/bin/env bash
# Deploy lote canal escrito QA (prompt + vista hilo).
# Ejecutar desde Cloud Shell / entorno con gcloud autenticado en prd-utpbi-data-operation.
#
# Uso:
#   cd monorep-utp-funcionts-runs
#   bash onemarketer/bigquery/deploy/deploy_canal_escrito_23.sh
#
# Opcional (Cloud Shell con impersonation, como en sesiones previas):
#   export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=genesys-audio-processor@prd-utpbi-data-operation.iam.gserviceaccount.com

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PROJECT="${PROJECT_ID:-prd-utpbi-data-operation}"

echo "=== 1/2 MERGE canal_escrito_prompt (us-central1) ==="
bq query --use_legacy_sql=false --location=us-central1 --project_id="$PROJECT" \
  < "$ROOT/onemarketer/bigquery/sqls/update_sys_prompts_canal_escrito_23.sql"

echo "=== 2/2 Vista v_onemarketer_caso_hilo_completo (us-central1) ==="
bq query --use_legacy_sql=false --location=us-central1 --project_id="$PROJECT" \
  < "$ROOT/onemarketer/bigquery/views/v_onemarketer_caso_hilo_completo_22.sql"

echo "=== OK deploy canal escrito 23 ==="
