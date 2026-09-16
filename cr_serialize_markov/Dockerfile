# ============================================================
# Dockerfile — cr_serialize_markov
# Cloud Run Job: Serialización de Audios Genesys con Whisper LOCAL
#
# NOTA IMPORTANTE SOBRE COSTOS DE IA:
#   - openai-whisper se ejecuta LOCALMENTE dentro de este contenedor.
#   - NO se realiza ninguna llamada a APIs externas de pago.
#   - NO se requiere OPENAI_API_KEY ni ninguna clave de tercero.
#   - Costo en IA = $0.
# ============================================================

FROM python:3.11-slim

# Metadatos
LABEL maintainer="data-team@utpbi"
LABEL description="Cloud Run Job para serialización de audios Genesys con Whisper LOCAL (mixdown + speaker por energía de canal)"

# -----------------------------------------------------------
# Dependencias del sistema
# ffmpeg: requerido por pydub para procesar audio
# libgomp1: requerido por ctranslate2 (faster-whisper) para paralelismo OpenMP
# -----------------------------------------------------------
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------
# Directorio de trabajo
# -----------------------------------------------------------
WORKDIR /app

# -----------------------------------------------------------
# Dependencias Python
# Se instala primero para aprovechar la caché de Docker layers.
# -----------------------------------------------------------
COPY requirements.txt .
RUN pip install --upgrade pip setuptools && \
    pip install --no-cache-dir -r requirements.txt

# -----------------------------------------------------------
# Pre-descargar el modelo Whisper durante el BUILD de la imagen.
# Esto evita la descarga en tiempo de ejecución del Cloud Run Job,
# garantizando arranque rápido y comportamiento determinista.
# El modelo "turbo" (~800M params, ~800MB) en formato CTranslate2.
RUN python -c "from faster_whisper import WhisperModel; WhisperModel('deepdml/faster-whisper-large-v3-turbo-ct2', device='cpu', compute_type='int8')"

# -----------------------------------------------------------
# Código fuente
# -----------------------------------------------------------
COPY config/ ./config/
COPY main.py .

# -----------------------------------------------------------
# Variables de entorno con valores por defecto
# FECHA_DESCARGA y HORA_DESCARGA son inyectadas por la CF en runtime.
# -----------------------------------------------------------
ENV WHISPER_MODEL=turbo
ENV FECHA_DESCARGA=""
ENV HORA_DESCARGA=""
ENV GCS_URIS=""

# -----------------------------------------------------------
# Comando de inicio del Cloud Run Job
# -----------------------------------------------------------
CMD ["python", "main.py"]
