#!/usr/bin/env bash
# ============================================================
# deploy.sh — Cloud Run Job: cr_serialize_markov
#
# Este script:
#   1. Lee la configuración desde config/config.json
#   2. Construye y sube la imagen Docker a GCR
#   3. Crea o actualiza el Cloud Run Job
#
# Prerrequisitos:
#   - gcloud CLI autenticado (gcloud auth login / ADC)
#   - Docker instalado y en ejecución
#   - Habilitados: Cloud Run API, Container Registry API
#   - Service Account con roles: Storage, BigQuery, Cloud Run
#
# Uso:
#   chmod +x deploy.sh
#   ./deploy.sh
# ============================================================

set -euo pipefail

# -----------------------------------------------------------
# Leer configuración desde config.json
# -----------------------------------------------------------
CONFIG_FILE="$(dirname "$0")/config/config.json"

PROJECT_ID=$(jq -r '.gcp.project_id'           "$CONFIG_FILE")
REGION=$(jq -r '.gcp.region'                   "$CONFIG_FILE")
JOB_NAME=$(jq -r '.gcp.cloud_run_job_name'     "$CONFIG_FILE")
IMAGE=$(jq -r '.gcp.docker_image_repository'   "$CONFIG_FILE")
SA_EMAIL=$(jq -r '.gcp.service_account_email'  "$CONFIG_FILE")

# Modelo Whisper a empaquetar en la imagen (turbo = ~800MB, costo cero en CPU)
WHISPER_MODEL="${WHISPER_MODEL:-turbo}"

echo "============================================================"
echo "  Deploy: Cloud Run Job — cr_serialize_markov"
echo "============================================================"
echo "  Proyecto  : $PROJECT_ID"
echo "  Región    : $REGION"
echo "  Job       : $JOB_NAME"
echo "  Imagen    : $IMAGE"
echo "  SA Email  : $SA_EMAIL"
echo "  Whisper   : $WHISPER_MODEL (LOCAL, costo cero)"
echo "============================================================"

# -----------------------------------------------------------
# 1. Activar APIs necesarias
# -----------------------------------------------------------
echo ""
echo "[1/4] Activando APIs de GCP..."
gcloud services enable \
    run.googleapis.com \
    containerregistry.googleapis.com \
    bigquery.googleapis.com \
    storage.googleapis.com \
    --project="$PROJECT_ID"

# -----------------------------------------------------------
# 2. Construir imagen Docker (incluye pre-descarga del modelo Whisper)
# -----------------------------------------------------------
echo ""
echo "[2/4] Construyendo imagen Docker (pre-empaquetando Whisper '$WHISPER_MODEL')..."
echo "      Nota: el modelo Whisper se descarga durante el BUILD, no en runtime."

gcloud builds submit "$(dirname "$0")" \
    --project="$PROJECT_ID" \
    --tag="$IMAGE" \
    --timeout="1800s"

echo "      ✓ Imagen subida: $IMAGE"

# -----------------------------------------------------------
# 3. Crear o actualizar el Cloud Run Job
# -----------------------------------------------------------
echo ""
echo "[3/4] Creando / actualizando Cloud Run Job '$JOB_NAME'..."

# Verificar si el job ya existe
JOB_EXISTS=$(gcloud run jobs describe "$JOB_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(name)" 2>/dev/null || echo "")

if [[ -z "$JOB_EXISTS" ]]; then
    echo "      Job no existe — creando nuevo..."
    gcloud run jobs create "$JOB_NAME" \
        --image="$IMAGE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --service-account="$SA_EMAIL" \
        --memory="16Gi" \
        --cpu="4" \
        --task-timeout="14400s" \
        --max-retries="1" \
        --set-env-vars="WHISPER_MODEL=$WHISPER_MODEL" \
        --labels="project=markov,component=serializer,env=prd,team=data-engineering,cost-center=utpbi"
else
    echo "      Job existe — actualizando..."
    gcloud run jobs update "$JOB_NAME" \
        --image="$IMAGE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --service-account="$SA_EMAIL" \
        --memory="16Gi" \
        --cpu="4" \
        --task-timeout="14400s" \
        --max-retries="1" \
        --set-env-vars="WHISPER_MODEL=$WHISPER_MODEL" \
        --labels="project=markov,component=serializer,env=prd,team=data-engineering,cost-center=utpbi"
fi

echo "      ✓ Cloud Run Job '$JOB_NAME' listo."

# -----------------------------------------------------------
# 4. Verificar despliegue
# -----------------------------------------------------------
echo ""
echo "[4/4] Verificando despliegue..."
gcloud run jobs describe "$JOB_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="table(
        name,
        spec.template.spec.containers[0].image,
        spec.template.spec.serviceAccountName,
        spec.template.spec.containers[0].resources.limits.memory,
        spec.template.spec.containers[0].resources.limits.cpu
    )"

echo ""
echo "============================================================"
echo "  ✓ Deploy completado exitosamente."
echo "  Job: $JOB_NAME en $REGION"
echo ""
echo "  Para ejecutar en MODO SLOT (producción):"
echo "    gcloud run jobs execute $JOB_NAME \\"
echo "      --region=$REGION \\"
echo "      --project=$PROJECT_ID \\"
echo "      --update-env-vars=FECHA_DESCARGA=YYYY-MM-DD,HORA_DESCARGA=HH"
echo ""
echo "  Para ejecutar en MODO LISTA (pruebas con audios específicos):"
echo "    gcloud run jobs execute $JOB_NAME \\"
echo "      --region=$REGION \\"
echo "      --project=$PROJECT_ID \\"
echo "      --update-env-vars=GCS_URIS='gs://bucket/path1.ogg,gs://bucket/path2.ogg'"
echo "============================================================"
