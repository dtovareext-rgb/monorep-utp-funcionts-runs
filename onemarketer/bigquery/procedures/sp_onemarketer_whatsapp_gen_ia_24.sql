-- =============================================================================
-- SP: OneMarketer WhatsApp — Etapa 1 (transcripción STT) — PRODUCCIÓN
--
-- Propósito:
--   Transcribir audios/videos MP3 de WhatsApp (OneMarketer) con speech-to-text-v2
--   y persistir en hist_onemarketer_whatsapp_gen_ia_*.
--
-- Técnica anti-timeout:
--   ML.TRANSCRIBE por LOTES (v_batch_size, default 25) en un WHILE.
--
-- Proyecto:  prd-utpbi-data-operation
-- Fuente:    raw_onemarketer.reporte_whatsapp_mp3 + reporte_chats (us-central1)
-- SP + hist: adf_speech_analytics (US)
-- STT:       adf_speech_analytics.speech-to-text-v2  (ML.TRANSCRIBE / Chirp)
-- Conexión:  US.utp_gen_ia_process
--
-- Desplegar (--location=US):
--   bq query --use_legacy_sql=false --location=US \
--     < onemarketer/bigquery/procedures/sp_onemarketer_whatsapp_gen_ia_24.sql
--
-- Flujo (reproceso por fecha):
--   0) DELETE hist raw/prd del día
--   1) Metadata + ML.TRANSCRIBE por lotes → hist
-- Etapa 2 la orquesta Cloud Workflows → sp_onemarketer_caso_conversacion_ia
--
-- Ejecutar (solo etapa 1; etapa 2 la orquesta el Workflow):
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_whatsapp_gen_ia`(
--     DATE '2026-06-22'
--   );
--
-- STT: se transcriben audios y videos convertidos a MP3 de asesor y de cliente.
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
  DECLARE v_batch_size INT64 DEFAULT 25;
  DECLARE v_offset INT64 DEFAULT 0;
  DECLARE v_batch_num INT64 DEFAULT 0;
  DECLARE v_batch_count INT64;

  -- Labels de costo: heredan a jobs hijos (ML.TRANSCRIBE por lote).
  SET @@query_label = 'producto:onemarketer,etapa:stt,servicio:chirp';

  SET v_fecha_proceso_str = FORMAT_DATE('%Y-%m-%d', v_fecha_proceso);
  SET external_table = '`prd-utpbi-data-operation.adf_speech_analytics.tmp_utp_external_table_onemarketer_whatsapp`';
  SET conexion = '`prd-utpbi-data-operation.US.utp_gen_ia_process`';

  -- ---------------------------------------------------------------------------
  -- 0. Reproceso por fecha: borra hist del día (permite re-ejecutar limpio)
  -- ---------------------------------------------------------------------------
  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_raw`
  WHERE process_date = v_fecha_proceso;

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_prd`
  WHERE process_date = v_fecha_proceso;

  -- ---------------------------------------------------------------------------
  -- PASO 1: Metadata MP3 + chat (+ batch_rn para lotes)
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
      chats.`user` AS chat_user,
      ROW_NUMBER() OVER (ORDER BY mp3.gcs_uri) - 1 AS batch_rn
    FROM `prd-utpbi-data-operation.raw_onemarketer.reporte_whatsapp_mp3` AS mp3
    LEFT JOIN `prd-utpbi-data-operation.raw_onemarketer.reporte_chats` AS chats
      ON chats.fecha_evento = mp3.fecha_evento
     AND chats.idcase = mp3.idcase
     AND chats.idmessage = mp3.idmessage
    WHERE mp3.fecha_evento = DATE('%s')
      AND mp3.conversion_status IN ('OK', 'SKIPPED_EXISTS', 'SKIPPED_ALREADY_MP3')
      AND mp3.gcs_uri IS NOT NULL
      AND IFNULL(mp3.duration_seconds, 0) >= %f
  """, v_fecha_proceso_str, min_duration_seconds);

  SET v_audio_count = (SELECT COUNT(*) FROM tmp_onemarketer_whatsapp_audios);

  IF v_audio_count = 0 THEN
    SELECT FORMAT(
      'Sin URIs MP3 elegibles para fecha %s — se omite etapa 1 (audios).',
      v_fecha_proceso_str
    );
  ELSE
    SELECT FORMAT(
      'STT OneMarketer fecha %s: %d audios en lotes de %d',
      v_fecha_proceso_str,
      v_audio_count,
      v_batch_size
    );

    -- ---------------------------------------------------------------------------
    -- PASO 2: Loop por lotes — external table → ML.TRANSCRIBE → hist raw
    -- ---------------------------------------------------------------------------
    WHILE v_offset < v_audio_count DO
      SET v_batch_num = v_batch_num + 1;

      SET v_uris = (
        SELECT CONCAT(
          '[',
          STRING_AGG(CONCAT('"', gcs_uri, '"'), ', ' ORDER BY batch_rn),
          ']'
        )
        FROM tmp_onemarketer_whatsapp_audios
        WHERE batch_rn >= v_offset
          AND batch_rn < v_offset + v_batch_size
      );

      SET v_batch_count = (
        SELECT COUNT(*)
        FROM tmp_onemarketer_whatsapp_audios
        WHERE batch_rn >= v_offset
          AND batch_rn < v_offset + v_batch_size
      );

      SELECT FORMAT(
        'STT lote %d: offset=%d count=%d',
        v_batch_num,
        v_offset,
        v_batch_count
      );

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

      EXECUTE IMMEDIATE FORMAT("""
        CREATE OR REPLACE TEMP TABLE tmp_onemarketer_whatsapp_stt_batch AS
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
      INNER JOIN tmp_onemarketer_whatsapp_stt_batch AS s
        ON s.uri = m.gcs_uri
      WHERE m.batch_rn >= v_offset
        AND m.batch_rn < v_offset + v_batch_size;

      SET v_offset = v_offset + v_batch_size;
    END WHILE;

    -- ---------------------------------------------------------------------------
    -- PASO 3: Capa PRD (día completo desde raw)
    -- ---------------------------------------------------------------------------
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

    SELECT FORMAT(
      'STT OneMarketer OK fecha %s: %d audios en %d lotes',
      v_fecha_proceso_str,
      v_audio_count,
      v_batch_num
    );
  END IF;

  -- Etapa 2 (Gemini) YA NO se llama aquí.
  -- Orquesta Cloud Workflows → sp_onemarketer_caso_conversacion_ia

END;
