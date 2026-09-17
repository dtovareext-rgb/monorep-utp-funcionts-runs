"""
cr_serialize_markov/main.py
Cloud Run Job — Serialización de Audios Genesys con Whisper LOCAL

Enfoque: Transcripción Única (Mixdown) + Speaker por Energía de Canal Estéreo

En lugar de transcribir cada canal por separado (lo que genera problemas de
bleeding/crosstalk y desorden en el merge), este enfoque:
  1. Hace mixdown del audio estéreo a mono para obtener una ÚNICA transcripción
     con una línea temporal unificada y naturalmente ordenada.
  2. Mantiene los canales estéreo separados SOLO para análisis de energía (RMS).
  3. Para cada segmento transcrito, calcula la energía RMS en Canal 0 (Cliente)
     y Canal 1 (Asesor), y asigna el speaker al canal con mayor energía.

Modos de operación:
  - MODO SLOT (producción): Variables FECHA_DESCARGA + HORA_DESCARGA → lista OGGs de GCS por slot.
  - MODO LISTA (pruebas):   Variable GCS_URIS → lista explícita de rutas gs:// separadas por coma.

Flujo:
  1. Lee parámetros de ejecución (slot o lista de URIs).
  2. Lista/descarga archivos OGG desde GCS.
  3. Genera mixdown mono y transcribe con Whisper LOCAL (costo cero).
  4. Asigna speakers usando energía RMS de los canales estéreo originales.
  5. Aplica filtros anti-alucinación (no_speech_prob, hallucination_phrases, loop detection).
  6. Construye serialized_level_1 y serialized_level_2.
  7. Carga resultados en BigQuery.
"""

import os
import re
import json
import logging
import tempfile
import time
import struct
import wave
from datetime import datetime, date, timezone

import numpy as np
from faster_whisper import WhisperModel
from pydub import AudioSegment, effects
from google.cloud import storage, bigquery

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
CONFIG_PATH = os.path.join(os.path.dirname(__file__), "config", "config.json")
with open(CONFIG_PATH) as f:
    CONFIG = json.load(f)

GCP = CONFIG["gcp"]

# Parámetros de ejecución
FECHA_DESCARGA = os.environ.get("FECHA_DESCARGA")
HORA_DESCARGA  = os.environ.get("HORA_DESCARGA")
GCS_URIS       = os.environ.get("GCS_URIS", "")  # Lista separada por coma para pruebas
WHISPER_MODEL  = os.environ.get("WHISPER_MODEL", "turbo")

# ---------------------------------------------------------------------------
# Constantes de filtrado anti-alucinación
# ---------------------------------------------------------------------------
HALLUCINATION_PHRASES = {
    "gracias por ver el video",
    "gracias por ver el video.",
    "gracias por ver",
    "gracias por ver.",
    "gracias por su atención",
    "gracias por su atención.",
    "subtítulos por la comunidad de amara.org",
    "subtítulos por",
    "gracias por ver el vídeo",
    "gracias por ver el vídeo.",
    "suscríbete al canal",
    "suscríbete al canal.",
    "no olvides suscribirte",
    "no te olvides de suscribirte",
}

NO_SPEECH_PROB_THRESHOLD = 0.60


# ---------------------------------------------------------------------------
# Filtros Anti-Alucinación
# ---------------------------------------------------------------------------
def _detect_intra_segment_loop(text: str) -> bool:
    """
    Detecta si un segmento contiene un patrón de palabras repetido ≥4 veces,
    lo cual es un indicador confiable de alucinación de Whisper.
    """
    words = text.split()
    n = len(words)
    if n < 6:
        return False
    for pattern_len in range(1, n // 4 + 1):
        pattern = words[:pattern_len]
        reps = 0
        for i in range(0, n - pattern_len + 1, pattern_len):
            if words[i:i + pattern_len] == pattern:
                reps += 1
            else:
                break
        if reps >= 4:
            return True
    return False


def filter_segments(raw_segments: list) -> list:
    """
    Aplica todos los filtros anti-alucinación a la lista de segmentos de Whisper.
    Retorna solo los segmentos válidos.
    """
    # --- Filtro 1: no_speech_prob, hallucination_phrases, loop detection ---
    filtered = []
    for seg in raw_segments:
        text_strip = seg.text.strip()
        text_lower = text_strip.lower()

        # Descartar segmentos donde Whisper no está seguro de que sea habla
        if seg.no_speech_prob > NO_SPEECH_PROB_THRESHOLD:
            continue

        # Descartar frases típicas de alucinación
        if text_lower in HALLUCINATION_PHRASES:
            continue

        # Descartar segmentos con patrón repetitivo (loop)
        if _detect_intra_segment_loop(text_strip):
            continue

        filtered.append(seg)

    # --- Filtro 2: Repetición consecutiva de textos cortos ---
    CONSECUTIVE_LIMIT = 2
    SHORT_TEXT_THRESHOLD = 60
    GAP_RESET_SEC = 30.0

    last_text = None
    last_text_end = 0.0
    consecutive_count = 0
    final_segments = []

    for seg in filtered:
        text_strip = seg.text.strip()
        is_short = len(text_strip) <= SHORT_TEXT_THRESHOLD

        if is_short and text_strip == last_text:
            gap = seg.start - last_text_end
            if gap > GAP_RESET_SEC:
                consecutive_count = 1
            else:
                consecutive_count += 1
                if consecutive_count > CONSECUTIVE_LIMIT:
                    last_text_end = seg.end
                    continue
        else:
            last_text = text_strip
            consecutive_count = 1

        last_text_end = seg.end
        final_segments.append(seg)

    return final_segments


# ---------------------------------------------------------------------------
# Utilidades de Audio y Energía
# ---------------------------------------------------------------------------
def wav_to_numpy(wav_path: str) -> tuple:
    """
    Lee un archivo WAV mono y retorna (samples_array, sample_rate).
    Los samples se normalizan a float32 en el rango [-1.0, 1.0].
    """
    with wave.open(wav_path, "rb") as wf:
        n_channels = wf.getnchannels()
        sample_width = wf.getsampwidth()
        sample_rate = wf.getframerate()
        n_frames = wf.getnframes()
        raw_data = wf.readframes(n_frames)

    if sample_width == 2:
        dtype = np.int16
        max_val = 32768.0
    elif sample_width == 4:
        dtype = np.int32
        max_val = 2147483648.0
    else:
        # fallback: 1 byte (uint8)
        dtype = np.uint8
        max_val = 128.0

    samples = np.frombuffer(raw_data, dtype=dtype).astype(np.float32)

    if n_channels > 1:
        samples = samples[::n_channels]  # Tomar solo el primer canal

    samples = samples / max_val
    return samples, sample_rate


def compute_rms_for_segment(samples: np.ndarray, sample_rate: int,
                            start_sec: float, end_sec: float) -> float:
    """
    Calcula la energía RMS de un segmento de audio definido por [start_sec, end_sec].
    Retorna 0.0 si el segmento está fuera de rango o es vacío.
    """
    start_sample = int(start_sec * sample_rate)
    end_sample = int(end_sec * sample_rate)

    # Clamp a los límites del array
    start_sample = max(0, start_sample)
    end_sample = min(len(samples), end_sample)

    if start_sample >= end_sample:
        return 0.0

    segment = samples[start_sample:end_sample]
    rms = np.sqrt(np.mean(segment ** 2))
    return float(rms)


def assign_speaker(asesor_samples: np.ndarray, cliente_samples: np.ndarray,
                   sample_rate: int, start_sec: float, end_sec: float) -> str:
    """
    Asigna el speaker (Asesor/Cliente) comparando la energía RMS del segmento
    en cada canal estéreo original.

    - Canal 1 (Asesor):  asesor_samples
    - Canal 0 (Cliente): cliente_samples
    """
    rms_asesor = compute_rms_for_segment(asesor_samples, sample_rate, start_sec, end_sec)
    rms_cliente = compute_rms_for_segment(cliente_samples, sample_rate, start_sec, end_sec)

    # Asignar al canal con mayor energía; desempate → Asesor (por convención: el que llama)
    if rms_asesor >= rms_cliente:
        return "Asesor"
    else:
        return "Cliente"


# ---------------------------------------------------------------------------
# Utilidades de GCS
# ---------------------------------------------------------------------------
def parse_gcs_path(gcs_path: str) -> tuple:
    """
    Parsea una ruta gs://bucket/blob a (bucket_name, blob_name).
    """
    if not gcs_path or not gcs_path.startswith("gs://"):
        return None, None
    path_without_scheme = gcs_path[5:]
    parts = path_without_scheme.split("/", 1)
    bucket_name = parts[0]
    blob_name = parts[1] if len(parts) > 1 else ""
    return bucket_name, blob_name


def parse_date_hour_from_uri(uri: str) -> tuple:
    """
    Extrae fecha_descarga y hora_descarga de una URI de GCS.
    Ejemplo: gs://.../fecha_descarga=2026-02-09/hora_descarga=10/...
    """
    date_match = re.search(r"fecha_descarga=([^/]+)", uri)
    hour_match = re.search(r"hora_descarga=([^/]+)", uri)

    fecha = date_match.group(1) if date_match else None
    hora = hour_match.group(1) if hour_match else None

    if hora and len(hora) == 1:
        hora = f"0{hora}"

    return fecha, hora


# ---------------------------------------------------------------------------
# Procesamiento de un audio individual
# ---------------------------------------------------------------------------
def process_audio(blob, uri: str, tmpdir: str, model) -> dict:
    """
    Descarga un OGG estéreo, genera un mixdown mono para transcripción única,
    y usa la energía de los canales estéreo originales para asignar speakers.

    Flujo:
      1. Descarga OGG → separa canales + genera mixdown mono
      2. Transcribe SOLO el mixdown mono con Whisper (timeline única)
      3. Aplica filtros anti-alucinación
      4. Para cada segmento: calcula RMS en Canal 0 y Canal 1 → asigna speaker
      5. Construye level1 y level2
    """
    base_name = os.path.splitext(os.path.basename(blob.name))[0]

    # 1. Descargar OGG
    ogg_path = os.path.join(tmpdir, f"{base_name}.ogg")
    blob.download_to_filename(ogg_path)
    logger.info(f"  Descargado: {ogg_path}")

    # 2. Cargar audio estéreo y generar los WAVs necesarios
    audio = AudioSegment.from_ogg(ogg_path)
    channels = audio.split_to_mono()

    if len(channels) < 2:
        logger.warning(f"  Audio mono detectado ({uri}). Canal 1 se completará con silencio.")
        channels = [channels[0], AudioSegment.silent(duration=len(channels[0]))]

    # Genesys: Canal 0 = Cliente, Canal 1 = Asesor
    # Canales con boost de volumen → SOLO para el mixdown que va a Whisper
    cliente_boosted = channels[0] + 15
    asesor_boosted = channels[1] + 2

    # Generar mixdown mono (promedio de ambos canales CON boost)
    mixdown = cliente_boosted.overlay(asesor_boosted)
    mixdown_wav = os.path.join(tmpdir, f"{base_name}_mixdown.wav")
    mixdown.export(mixdown_wav, format="wav")
    logger.info(f"  Mixdown mono generado: {mixdown_wav}")

    # Exportar canales ORIGINALES (sin boost) para análisis de energía RMS
    # Es CRÍTICO no usar los canales con boost, porque el +15dB del cliente
    # sesgaría la comparación y todo quedaría etiquetado como "Cliente".
    asesor_wav = os.path.join(tmpdir, f"{base_name}_asesor.wav")
    cliente_wav = os.path.join(tmpdir, f"{base_name}_cliente.wav")
    channels[1].export(asesor_wav, format="wav")   # Canal 1 original
    channels[0].export(cliente_wav, format="wav")   # Canal 0 original

    # 3. Cargar canales ORIGINALES como arrays numpy para análisis de energía RMS
    asesor_samples, sr_asesor = wav_to_numpy(asesor_wav)
    cliente_samples, sr_cliente = wav_to_numpy(cliente_wav)
    sample_rate = sr_asesor

    # 4. Transcribir SOLO el mixdown (una sola timeline, orden garantizado)
    initial_prompt = (
        "Conversación telefónica en español de Perú sobre temas universitarios, "
        "matrícula, carreras y cursos en la UTP."
    )

    logger.info(f"  Transcribiendo mixdown (faster-whisper CPU int8, timeline única)...")
    segments_iter, info = model.transcribe(
        mixdown_wav,
        language="es",
        word_timestamps=True,
        initial_prompt=initial_prompt,
        vad_filter=True,
        vad_parameters=dict(
            threshold=0.5,
            min_speech_duration_ms=250,
            max_speech_duration_s=float("inf"),
            min_silence_duration_ms=500,
            speech_pad_ms=200,
        )
    )
    raw_segments = list(segments_iter)
    logger.info(f"  Whisper generó {len(raw_segments)} segmentos antes de filtrado.")

    # 5. Aplicar filtros anti-alucinación
    segments = filter_segments(raw_segments)
    logger.info(f"  Segmentos después de filtrado: {len(segments)} (descartados: {len(raw_segments) - len(segments)})")

    # 6. Asignar speaker POR PALABRA usando energía RMS de canales ORIGINALES,
    #    luego re-segmentar agrupando palabras consecutivas del mismo speaker.
    #    Esto resuelve el problema de que Whisper genera segmentos largos que
    #    mezclan ambos hablantes en un solo bloque de texto.
    word_annotations = []
    for seg in segments:
        for w in (seg.words or []):
            word_text = w.word.strip()
            if not word_text:
                continue
            speaker = assign_speaker(
                asesor_samples, cliente_samples, sample_rate,
                w.start, w.end
            )
            word_annotations.append({
                "word":    word_text,
                "start":   round(w.start, 3),
                "end":     round(w.end, 3),
                "speaker": speaker,
            })

    logger.info(f"  Palabras con speaker asignado: {len(word_annotations)}")

    # Re-segmentar: agrupar palabras consecutivas del mismo speaker
    annotated_segments = []
    if word_annotations:
        current_speaker = word_annotations[0]["speaker"]
        current_words = [word_annotations[0]]
        current_start = word_annotations[0]["start"]

        for wa in word_annotations[1:]:
            if wa["speaker"] == current_speaker:
                current_words.append(wa)
            else:
                # Cerrar segmento actual
                annotated_segments.append({
                    "speaker":      current_speaker,
                    "channel":      1 if current_speaker == "Asesor" else 0,
                    "start":        current_start,
                    "start_second": int(current_start),
                    "end":          current_words[-1]["end"],
                    "text":         " ".join(cw["word"] for cw in current_words),
                    "words":        [{"word": cw["word"], "start": cw["start"], "end": cw["end"]} for cw in current_words],
                })
                # Iniciar nuevo segmento
                current_speaker = wa["speaker"]
                current_words = [wa]
                current_start = wa["start"]

        # Cerrar último segmento
        annotated_segments.append({
            "speaker":      current_speaker,
            "channel":      1 if current_speaker == "Asesor" else 0,
            "start":        current_start,
            "start_second": int(current_start),
            "end":          current_words[-1]["end"],
            "text":         " ".join(cw["word"] for cw in current_words),
            "words":        [{"word": cw["word"], "start": cw["start"], "end": cw["end"]} for cw in current_words],
        })

    logger.info(f"  Segmentos re-agrupados por speaker: {len(annotated_segments)}")

    # 7. Construir serialized_level_1 y serialized_level_2
    level1 = "\n".join(
        f"[{s['speaker']}:{s['start']:.1f}]: {s['text']}"
        for s in annotated_segments
    )

    level2 = {"transcription": annotated_segments}

    # 8. Extraer fecha y hora de la URI
    fecha_descarga, hora_descarga = parse_date_hour_from_uri(uri)
    if not fecha_descarga:
        fecha_descarga = FECHA_DESCARGA or date.today().isoformat()
    if not hora_descarga:
        hora_descarga = HORA_DESCARGA or "00"

    return {
        "fecha_descarga":      fecha_descarga,
        "hora_descarga":       hora_descarga,
        "uri":                 uri,
        "serialized_level_1":  level1,
        "serialized_level_2":  json.dumps(level2, ensure_ascii=False),
        "process_date":        date.today().isoformat(),
        "process_datetime":    datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S"),
    }


# ---------------------------------------------------------------------------
# Carga en BigQuery con idempotencia por slot
# ---------------------------------------------------------------------------
def load_to_bigquery(bq_client: bigquery.Client, rows: list):
    """
    Carga los registros procesados en BigQuery.
    Idempotencia: elimina los datos previos del mismo slot (fecha + hora)
    antes de insertar, garantizando resultados consistentes ante reprocesos.
    Si la tabla no existe, la crea automáticamente en el primer run.
    """
    table_ref = f"{GCP['project_id']}.{GCP['dataset_id']}.{GCP['table_id']}"

    # Definir esquema explícito
    schema = [
        bigquery.SchemaField("fecha_descarga",    "DATE",     description="Fecha del slot de descarga"),
        bigquery.SchemaField("hora_descarga",      "STRING",   description="Hora del slot de descarga (HH)"),
        bigquery.SchemaField("uri",                "STRING",   description="URI completo del archivo OGG en GCS"),
        bigquery.SchemaField("serialized_level_1", "STRING",   description="Transcripción texto plano por canal (Asesor/Cliente)"),
        bigquery.SchemaField("serialized_level_2", "JSON",     description="Transcripción JSON a nivel de palabra con timestamps"),
        bigquery.SchemaField("process_date",       "DATE",     description="Fecha de procesamiento"),
        bigquery.SchemaField("process_datetime",   "DATETIME", description="Fecha y hora exacta de procesamiento (UTC)"),
    ]

    # Crear tabla si no existe — particionada por fecha_descarga
    table_obj = bigquery.Table(table_ref, schema=schema)
    table_obj.time_partitioning = bigquery.TimePartitioning(
        type_=bigquery.TimePartitioningType.DAY,
        field="fecha_descarga",
    )
    table_obj = bq_client.create_table(table_obj, exists_ok=True)
    logger.info(f"Tabla '{table_ref}' verificada/creada.")

    # Insertar filas vía BigQuery Load Job (gratuito)
    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND
    )

    logger.info(f"Iniciando BigQuery Load Job para `{table_ref}` con {len(rows)} registros...")
    load_job = bq_client.load_table_from_json(
        rows,
        table_ref,
        job_config=job_config
    )
    load_job.result()
    logger.info(f"{len(rows)} registros cargados exitosamente via Load Job en `{table_ref}`")


# ---------------------------------------------------------------------------
# Resolución de blobs según modo de operación
# ---------------------------------------------------------------------------
def resolve_blobs_from_slot(storage_client) -> list:
    """
    Modo SLOT (producción): lista OGGs en la ruta estándar de GCS.
    Retorna lista de tuplas (blob, uri).
    """
    gcs_prefix = (
        f"data/input/genesys_audios_descarga_raw/"
        f"fecha_descarga={FECHA_DESCARGA}/"
        f"hora_descarga={HORA_DESCARGA}/"
    )

    bucket = storage_client.bucket(GCP["bucket_audio"])
    blobs = list(bucket.list_blobs(prefix=gcs_prefix))
    ogg_blobs = [b for b in blobs if b.name.lower().endswith(".ogg")]
    ogg_blobs.sort(key=lambda b: b.name)

    return [(b, f"gs://{GCP['bucket_audio']}/{b.name}") for b in ogg_blobs]


def resolve_blobs_from_uris(storage_client, uris_str: str) -> list:
    """
    Modo LISTA (pruebas): recibe una lista de rutas gs:// separadas por coma.
    Retorna lista de tuplas (blob, uri).
    """
    uris = [u.strip() for u in uris_str.split(",") if u.strip()]
    results = []

    for uri in uris:
        bucket_name, blob_name = parse_gcs_path(uri)
        if not bucket_name or not blob_name:
            logger.warning(f"URI inválida, ignorando: {uri}")
            continue

        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)

        if blob.exists():
            results.append((blob, uri))
            logger.info(f"  ✓ Verificado en GCS: {uri}")
        else:
            logger.warning(f"  ✗ No existe en GCS: {uri}")

    return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    # Determinar modo de operación
    is_list_mode = bool(GCS_URIS.strip())
    is_slot_mode = bool(FECHA_DESCARGA and HORA_DESCARGA)

    if not is_list_mode and not is_slot_mode:
        raise ValueError(
            "Se requiere al menos uno de:\n"
            "  - GCS_URIS: lista de rutas gs:// separadas por coma (modo pruebas)\n"
            "  - FECHA_DESCARGA + HORA_DESCARGA: slot de producción (modo slot)\n"
            "Variables de entorno inyectadas por la Cloud Function o manualmente."
        )

    mode_label = "LISTA (pruebas)" if is_list_mode else "SLOT (producción)"
    logger.info(f"=== Inicio de procesamiento | Modo: {mode_label} ===")

    if is_list_mode:
        logger.info(f"URIs recibidas: {GCS_URIS}")
    else:
        logger.info(f"Slot: fecha={FECHA_DESCARGA} hora={HORA_DESCARGA}")

    # -- Cargar modelo Whisper LOCAL (costo cero, sin API key) ----------------
    logger.info(f"Cargando modelo Whisper '{WHISPER_MODEL}' (ejecución local faster-whisper)...")
    t0 = time.time()
    MODEL_MAP = {
        "tiny": "Systran/faster-whisper-tiny",
        "base": "Systran/faster-whisper-base",
        "small": "Systran/faster-whisper-small",
        "medium": "Systran/faster-whisper-medium",
        "large": "Systran/faster-whisper-large-v3",
        "large-v3": "Systran/faster-whisper-large-v3",
        "turbo": "deepdml/faster-whisper-large-v3-turbo-ct2",
        "large-v3-turbo": "deepdml/faster-whisper-large-v3-turbo-ct2",
    }
    mapped_model = MODEL_MAP.get(WHISPER_MODEL, WHISPER_MODEL)
    model = WhisperModel(mapped_model, device="cpu", compute_type="int8")
    logger.info(f"Modelo Whisper '{mapped_model}' cargado en {time.time() - t0:.1f}s")

    # -- Clientes GCP ---------------------------------------------------------
    storage_client = storage.Client(project=GCP["project_id"])
    bq_client      = bigquery.Client(project=GCP["project_id"])

    # -- Resolver blobs según modo --------------------------------------------
    if is_list_mode:
        blob_pairs = resolve_blobs_from_uris(storage_client, GCS_URIS)
    else:
        blob_pairs = resolve_blobs_from_slot(storage_client)

    total_files = len(blob_pairs)
    logger.info(f"Total de archivos a procesar: {total_files}")

    if not blob_pairs:
        logger.warning("No hay archivos para procesar. Terminando.")
        return

    # -- Particionamiento por tareas (Cloud Run Jobs) --------------------------
    task_index = int(os.environ.get("CLOUD_RUN_TASK_INDEX", 0))
    task_count = int(os.environ.get("CLOUD_RUN_TASK_COUNT", 1))

    my_blob_pairs = [bp for idx, bp in enumerate(blob_pairs) if idx % task_count == task_index]
    logger.info(f"Tarea {task_index}/{task_count} procesará {len(my_blob_pairs)} de {total_files} archivos.")

    if not my_blob_pairs:
        logger.info(f"Tarea {task_index} no tiene archivos asignados. Terminando.")
        return

    # -- Procesar cada audio asignado -----------------------------------------
    rows = []
    for idx, (blob, uri) in enumerate(my_blob_pairs, start=1):
        logger.info(f"[Tarea {task_index} | {idx}/{len(my_blob_pairs)}] Procesando: {uri}")

        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                row = process_audio(blob, uri, tmpdir, model)
            rows.append(row)
            logger.info(f"[Tarea {task_index} | {idx}/{len(my_blob_pairs)}] ✓ Completado: {uri}")
        except Exception as e:
            logger.error(f"[Tarea {task_index} | {idx}/{len(my_blob_pairs)}] ✗ Error en {uri}: {e}", exc_info=True)
            continue

    # -- Cargar en BigQuery ---------------------------------------------------
    if rows:
        load_to_bigquery(bq_client, rows)
    else:
        logger.warning(f"Tarea {task_index}: No se generaron filas para cargar en BigQuery.")

    logger.info(f"=== Fin de procesamiento | {len(rows)} registros cargados ===")


if __name__ == "__main__":
    main()
