-- =============================================================================
-- SP: OneMarketer WhatsApp — Etapa 1 (transcripción STT) — PRODUCCIÓN
--
-- Propósito:
--   Transcribir audios MP3 de WhatsApp (OneMarketer) con speech-to-text-v2
--   y persistir en hist_onemarketer_whatsapp_gen_ia_*.
--   Luego CALL etapa 2 (Gemini + canal_escrito_prompt) por idcase.
--
-- Proyecto:  prd-utpbi-data-operation
-- Fuente:    raw_onemarketer.reporte_whatsapp_mp3 + reporte_chats (us-central1)
-- SP + hist: adf_speech_analytics (US)
-- STT:       adf_speech_analytics.speech-to-text-v2  (ML.TRANSCRIBE / Chirp)
-- Conexión:  US.utp_gen_ia_process
--
-- Prerrequisitos:
--   1. Cloud Function onemarketer del día → reporte_whatsapp_mp3 con MP3 en GCS
--   2. Tablas hist creadas
--   3. Modelo speech-to-text-v2 y conexión utp_gen_ia_process en US
--
-- Desplegar (--location=US):
--   bq query --use_legacy_sql=false --location=US < procedures/sp_onemarketer_whatsapp_gen_ia.sql
--
-- Ejecutar:
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_whatsapp_gen_ia`(
--     DATE '2026-06-22'
--   );
--
-- Flujo:
--   Etapa 1: ML.TRANSCRIBE → hist_gen_ia_*
--   Etapa 2: CALL sp_onemarketer_caso_conversacion_ia (Gemini + sys_prompts)
--
-- Filtro STT (videos):
--   - Notas de voz / audio puro → se transcriben siempre (asesor o cliente).
--   - Contenedores VIDEO (mime video/* o ext .mp4/.mpeg/...) → SOLO si origin
--     es operador/asesor (promos). Videos de cliente se omiten (spam / tokens).
--
-- Nota: si speech-to-text-v2 NO tiene SPEECH_RECOGNIZER, agregar recognition_config:
--   recognition_config => (JSON '{"language_codes":["es-US"],"model":"chirp","auto_decoding_config":{}}')
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_whatsapp_gen_ia`(
  v_fecha_proceso DATE
)
BEGIN
  DECLARE v_fecha_proceso_str STRING;
  DECLARE external_table STRING;
  DECLARE conexion STRING;
  DECLARE v_uris STRING;
  DECLARE v_sql STRING;
  DECLARE min_duration_seconds FLOAT64 DEFAULT 0.0;
  DECLARE v_audio_count INT64;

  SET v_fecha_proceso_str = FORMAT_DATE('%Y-%m-%d', v_fecha_proceso);
  SET external_table = '`prd-utpbi-data-operation.adf_speech_analytics.tmp_utp_external_table_onemarketer_whatsapp`';
  SET conexion = '`prd-utpbi-data-operation.US.utp_gen_ia_process`';

  -- ---------------------------------------------------------------------------
  -- PASO 1: URIs elegibles (MP3 OK + filtro video solo asesor/operador)
  -- ---------------------------------------------------------------------------
  SET v_uris = (
    WITH base AS (
      SELECT mp3.gcs_uri AS uri
      FROM `prd-utpbi-data-operation.raw_onemarketer.reporte_whatsapp_mp3` AS mp3
      LEFT JOIN `prd-utpbi-data-operation.raw_onemarketer.reporte_chats` AS chats
        ON chats.fecha_evento = mp3.fecha_evento
       AND chats.idcase = mp3.idcase
       AND chats.idmessage = mp3.idmessage
      WHERE mp3.fecha_evento = v_fecha_proceso
        AND mp3.conversion_status IN ('OK', 'SKIPPED_EXISTS', 'SKIPPED_ALREADY_MP3')
        AND mp3.gcs_uri IS NOT NULL
        AND IFNULL(mp3.duration_seconds, 0) >= min_duration_seconds
        AND (
          -- Audio / nota de voz: siempre
          NOT (
            STARTS_WITH(LOWER(IFNULL(mp3.mime, '')), 'video/')
            OR REGEXP_CONTAINS(LOWER(IFNULL(mp3.mime, '')), r'(^|/)video(/|$)')
            OR REGEXP_CONTAINS(
              LOWER(IFNULL(mp3.source_file_name, IFNULL(mp3.file_name, ''))),
              r'\.(mp4|m4v|mpeg|mpg|mpe|m2v|mov|qt|avi|mkv|webm|wmv|flv|3gp)(\.|$)'
            )
            OR REGEXP_CONTAINS(LOWER(IFNULL(mp3.source_file_name, '')), r'(^|_)video(_|\.|$)')
          )
          -- Video: solo operador / asesor
          OR REGEXP_CONTAINS(
            LOWER(TRIM(IFNULL(chats.origin, ''))),
            r'^(operador|asesor)$'
          )
        )
    )
    SELECT CONCAT(
      '[',
      STRING_AGG(CONCAT('"', uri, '"'), ', '),
      ']'
    )
    FROM base
  );

  IF v_uris IS NULL OR v_uris = '[]' THEN
    SELECT FORMAT(
      'Sin URIs MP3 elegibles para fecha %s — se omite etapa 1 (audios).',
      v_fecha_proceso_str
    );
  ELSE

  -- ---------------------------------------------------------------------------
  -- PASO 2: External table con las URIs (conexión GCS)
  -- ---------------------------------------------------------------------------
  SET v_sql = FORMAT("""
    CREATE OR REPLACE EXTERNAL TABLE %s
    WITH CONNECTION %s
    OPTIONS (
      object_metadata = 'SIMPLE',
      uris = %s,
      max_staleness = INTERVAL 30 MINUTE,
      metadata_cache_mode = AUTOMATIC
    )
  """, external_table, conexion, v_uris);
  EXECUTE IMMEDIATE v_sql;

  -- ---------------------------------------------------------------------------
  -- PASO 3: Metadata MP3 + chat (mismo filtro que paso 1)
  -- ---------------------------------------------------------------------------
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TEMP TABLE tmp_onemarketer_whatsapp_audios AS
    SELECT
      mp3.fecha_evento AS process_date,
      mp3.gcs_uri,
      mp3.idcase,
      mp3.idmessage,
      mp3.waid,
      mp3.duration_seconds,
      mp3.file_name,
      chats.text AS chat_text,
      chats.origin AS chat_origin,
      chats.`user` AS chat_user
    FROM `prd-utpbi-data-operation.raw_onemarketer.reporte_whatsapp_mp3` AS mp3
    LEFT JOIN `prd-utpbi-data-operation.raw_onemarketer.reporte_chats` AS chats
      ON chats.fecha_evento = mp3.fecha_evento
     AND chats.idcase = mp3.idcase
     AND chats.idmessage = mp3.idmessage
    WHERE mp3.fecha_evento = DATE('%s')
      AND mp3.conversion_status IN ('OK', 'SKIPPED_EXISTS', 'SKIPPED_ALREADY_MP3')
      AND mp3.gcs_uri IS NOT NULL
      AND IFNULL(mp3.duration_seconds, 0) >= %f
      AND (
        NOT (
          STARTS_WITH(LOWER(IFNULL(mp3.mime, '')), 'video/')
          OR REGEXP_CONTAINS(LOWER(IFNULL(mp3.mime, '')), r'(^|/)video(/|$)')
          OR REGEXP_CONTAINS(
            LOWER(IFNULL(mp3.source_file_name, IFNULL(mp3.file_name, ''))),
            r'\\.(mp4|m4v|mpeg|mpg|mpe|m2v|mov|qt|avi|mkv|webm|wmv|flv|3gp)(\\.|$)'
          )
          OR REGEXP_CONTAINS(LOWER(IFNULL(mp3.source_file_name, '')), r'(^|_)video(_|\\.|$)')
        )
        OR REGEXP_CONTAINS(
          LOWER(TRIM(IFNULL(chats.origin, ''))),
          r'^(operador|asesor)$'
        )
      )
  """, v_fecha_proceso_str, min_duration_seconds);

  SET v_audio_count = (SELECT COUNT(*) FROM tmp_onemarketer_whatsapp_audios);

  IF v_audio_count > 0 THEN
    -- ---------------------------------------------------------------------------
    -- PASO 4: Speech-to-Text v2 (Chirp) — transcripción literal
    -- ---------------------------------------------------------------------------
    EXECUTE IMMEDIATE FORMAT("""
      CREATE OR REPLACE TEMP TABLE tmp_onemarketer_whatsapp_stt_results AS
      SELECT
        uri,
        transcripts,
        ml_transcribe_result,
        ml_transcribe_status
      FROM ML.TRANSCRIBE(
        MODEL `prd-utpbi-data-operation.adf_speech_analytics.speech-to-text-v2`,
        TABLE %s,
        recognition_config => (
          JSON '{"language_codes":["es-US"],"model":"chirp","auto_decoding_config":{}}'
        )
      )
    """, external_table);

    -- ---------------------------------------------------------------------------
    -- PASO 5: Join STT + metadata → hist RAW
    -- ---------------------------------------------------------------------------
    DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_raw`
    WHERE process_date = v_fecha_proceso;

    INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_raw`
    SELECT
      m.process_date,
      m.gcs_uri,
      m.idcase,
      m.idmessage,
      m.waid,
      m.duration_seconds,
      m.chat_text,
      m.chat_origin,
      m.chat_user,
      TO_JSON_STRING(s.ml_transcribe_result) AS json_text,
      TO_JSON_STRING(s.ml_transcribe_result) AS full_response,
      IFNULL(NULLIF(TRIM(s.ml_transcribe_status), ''), 'OK') AS status,
      s.transcripts AS transcripcion,
      CAST(NULL AS STRING) AS resumen,
      CAST(NULL AS STRING) AS intencion,
      CAST(NULL AS STRING) AS idioma,
      CAST(NULL AS STRING) AS tono,
      CAST(NULL AS STRING) AS entidades,
      CAST(NULL AS STRING) AS observaciones,
      DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date
    FROM tmp_onemarketer_whatsapp_audios AS m
    INNER JOIN tmp_onemarketer_whatsapp_stt_results AS s
      ON s.uri = m.gcs_uri;

    -- ---------------------------------------------------------------------------
    -- PASO 6: Capa PRD (consumo)
    -- ---------------------------------------------------------------------------
    DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_prd`
    WHERE process_date = v_fecha_proceso;

    INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_prd`
    SELECT
      process_date,
      gcs_uri,
      idcase,
      idmessage,
      waid,
      duration_seconds,
      transcripcion,
      resumen,
      intencion,
      idioma,
      tono,
      entidades,
      observaciones,
      chat_text,
      chat_origin,
      load_date
    FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_raw`
    WHERE process_date = v_fecha_proceso;
  END IF;

  END IF;

  -- ---------------------------------------------------------------------------
  -- ETAPA 2: Análisis de conversación completa por idcase (Gemini + sys_prompts)
  -- ---------------------------------------------------------------------------
  CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_caso_conversacion_ia`(
    v_fecha_proceso,
    NULL
  );

END;
