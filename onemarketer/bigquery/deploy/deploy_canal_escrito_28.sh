#!/usr/bin/env bash
# Deploy prompt canal escrito v28 (QA Detalle_Evas: abandono, Genesys, carrera no ofertada).
#
# Uso:
#   cd monorep-utp-funcionts-runs
#   bash onemarketer/bigquery/deploy/deploy_canal_escrito_28.sh
#
# Regenerar SQL desde docs/prompt_canal_escrito.txt si editaste el prompt:
#   python onemarketer/scripts/build_canal_escrito_prompt_sql.py 28

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PROJECT="${PROJECT_ID:-prd-utpbi-data-operation}"

echo "=== MERGE canal_escrito_prompt v28 (us-central1) ==="
bq query --use_legacy_sql=false --location=us-central1 --project_id="$PROJECT" \
  < "$ROOT/onemarketer/bigquery/sqls/update_sys_prompts_canal_escrito_28.sql"

echo "=== OK deploy canal escrito 28 ==="
