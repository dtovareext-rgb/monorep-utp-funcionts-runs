-- =============================================================================
-- SP: Gen IA MP3 WhatsApp/OneMarketer — PRODUCCIÓN
--
-- Propósito:
--   Procesar audios MP3 de conversaciones WhatsApp (OneMarketer) con Gemini y
--   persistir transcripción + metadatos de análisis en tablas históricas.
--
-- Proyecto:  prd-utpbi-data-operation
-- Fuente:    raw_onemarketer.reporte_whatsapp_mp3 + reporte_chats (us-central1)
-- SP + hist: adf_speech_analytics (US) — misma región que conexión y modelo
-- Modelo:    adf_speech_analytics.gemini-2-5-flash
-- Conexión:  US.utp_gen_ia_process (lectura GCS del bucket OneMarketer)
--
-- Prerrequisitos (ejecutar ANTES del SP):
--   1. Cloud Function onemarketer del día → reporte_whatsapp_mp3 con MP3 en GCS
--   2. Tablas hist creadas: hist_onemarketer_whatsapp_gen_ia_process_data_raw/prd
--   3. Modelo gemini-2-5-flash y conexión utp_gen_ia_process desplegados en US
--
-- Desplegar (--location=US):
--   bq query --use_legacy_sql=false --location=US < procedures/sp_onemarketer_whatsapp_gen_ia.sql
--
-- Ejecutar:
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_whatsapp_gen_ia`(
--     DATE '2026-06-22'
--   );
--
-- Flujo (2 etapas, un solo CALL externo):
--   Etapa 1 (pasos 1–6): transcripción/análisis por audio → hist_gen_ia_*
--   Etapa 2 (CALL):      conversación completa por idcase → hist_caso_conversacion_ia_*
--                        prompt: raw_onemarketer.sys_prompts.canal_escrito_prompt
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_whatsapp_gen_ia`(
  v_fecha_proceso DATE
)
BEGIN
  -- Variables de control del SP
  DECLARE v_fecha_proceso_str STRING;       -- Fecha como 'YYYY-MM-DD' para SQL dinámico
  DECLARE external_table STRING;            -- Nombre fully-qualified de la external table tmp
  DECLARE conexion STRING;                  -- Conexión BQ → GCS (utp_gen_ia_process)
  DECLARE v_uris STRING;                    -- Array JSON de URIs gs://... para OPTIONS(uris=...)
  DECLARE v_sql STRING;                     -- SQL dinámico armado con FORMAT + EXECUTE IMMEDIATE
  DECLARE min_duration_seconds FLOAT64 DEFAULT 0.0;  -- Filtro mínimo de duración de audio

  SET v_fecha_proceso_str = FORMAT_DATE('%Y-%m-%d', v_fecha_proceso);
  SET external_table = '`prd-utpbi-data-operation.adf_speech_analytics.tmp_utp_external_table_onemarketer_whatsapp`';
  SET conexion = '`prd-utpbi-data-operation.US.utp_gen_ia_process`';

  -- ---------------------------------------------------------------------------
  -- PASO 1: Armar URIs desde reporte_whatsapp_mp3 (MP3 OK del día)
  --
  -- Lee el catálogo de audios ya convertidos por la Cloud Function (ffmpeg).
  -- Solo incluye filas con conversión exitosa y gcs_uri válido.
  -- Si no hay audios, se omite la etapa 1 pero igual se ejecuta la etapa 2
  -- (conversaciones solo texto vía sys_prompts).
  -- ---------------------------------------------------------------------------
  SET v_uris = (
    WITH base AS (
      SELECT mp3.gcs_uri AS uri
      FROM `prd-utpbi-data-operation.raw_onemarketer.reporte_whatsapp_mp3` AS mp3
      WHERE mp3.fecha_evento = v_fecha_proceso
        AND mp3.conversion_status IN ('OK', 'SKIPPED_EXISTS', 'SKIPPED_ALREADY_MP3')
        AND mp3.gcs_uri IS NOT NULL
        AND IFNULL(mp3.duration_seconds, 0) >= min_duration_seconds
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
      'Sin URIs MP3 para fecha %s — se omite etapa 1 (audios).',
      v_fecha_proceso_str
    );
  ELSE

  -- ---------------------------------------------------------------------------
  -- PASO 2: External table con las URIs (conexión GCS)
  --
  -- BigQuery no lee gs:// directamente en AI.GENERATE_TABLE; necesita una
  -- external table con object_metadata=SIMPLE para exponer cada archivo como fila.
  -- La conexión utp_gen_ia_process autoriza el acceso al bucket de staging.
  -- La tabla se recrea cada ejecución (REPLACE) con solo los MP3 del día.
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
  -- PASO 3: Metadata MP3 + chat + referencia al objeto audio
  --
  -- Une tres fuentes:
  --   - reporte_whatsapp_mp3  → metadata del audio (idcase, idmessage, gcs_uri…)
  --   - external table (ext)   → objeto BQ ref al archivo (ext.ref → paso 4)
  --   - reporte_chats          → contexto escrito del hilo (texto del mensaje)
  --
  -- prompt: instrucción enviada a Gemini. Hoy está hardcodeada en el CONCAT.
  --   Pide transcripción + resumen + intención + tono + entidades en un JSON.
  --
  -- NOTA: el análisis de conversación completa (sys_prompts) va en la etapa 2,
  --   vía sp_onemarketer_caso_conversacion_ia (al final de este SP).
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
      ext.ref AS audio,
      CONCAT(
        'Analiza el audio de WhatsApp adjunto a esta conversación OneMarketer. ',
        'Devuelve UN objeto JSON con las claves: ',
        'transcripcion (texto literal del audio en español si aplica), ',
        'resumen (máx 3 oraciones), intencion (consulta, reclamo, interés académico, otro), ',
        'idioma, tono (neutral, positivo, negativo, urgente), ',
        'entidades (nombres, carreras, campus mencionados; string), ',
        'observaciones (string). ',
        'Contexto del hilo (puede estar vacío): ',
        IFNULL(chats.text, '(sin texto en reporte_chats)')
      ) AS prompt
    FROM `prd-utpbi-data-operation.raw_onemarketer.reporte_whatsapp_mp3` AS mp3
    INNER JOIN %s AS ext
      ON ext.uri = mp3.gcs_uri
    LEFT JOIN `prd-utpbi-data-operation.raw_onemarketer.reporte_chats` AS chats
      ON chats.fecha_evento = mp3.fecha_evento
     AND chats.idcase = mp3.idcase
     AND chats.idmessage = mp3.idmessage
    WHERE mp3.fecha_evento = DATE('%s')
      AND mp3.conversion_status IN ('OK', 'SKIPPED_EXISTS', 'SKIPPED_ALREADY_MP3')
      AND IFNULL(mp3.duration_seconds, 0) >= %f
  """, external_table, v_fecha_proceso_str, min_duration_seconds);

  -- ---------------------------------------------------------------------------
  -- PASO 4: Gen IA con Gemini (multimodal)
  --
  -- AI.GENERATE_TABLE procesa cada fila de tmp_onemarketer_whatsapp_audios:
  --   - instruction: texto del prompt (paso 3)
  --   - audio_url:   URL firmada temporal vía OBJ.GET_ACCESS_URL(ext.ref)
  --
  -- Gemini devuelve ml_generate_text_llm_result (texto con JSON embebido),
  -- full_response (JSON nativo de la API) y status por fila.
  --
  -- temperature=0 para respuestas más determinísticas en extracción estructurada.
  -- Este paso es el más costoso en tiempo y cómputo del SP.
  -- ---------------------------------------------------------------------------
  CREATE OR REPLACE TEMP TABLE tmp_onemarketer_whatsapp_gen_ia_results AS
  SELECT ia.*
  FROM AI.GENERATE_TABLE(
    MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,
    (
      SELECT
        STRUCT(
          prompt AS instruction,
          OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
        ) AS prompt,
        * EXCEPT(prompt, audio)
      FROM tmp_onemarketer_whatsapp_audios
    ),
    STRUCT(
      'ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,
      0 AS temperature
    )
  ) AS ia;

  -- ---------------------------------------------------------------------------
  -- PASO 5: Parseo JSON → hist RAW
  --
  -- Gemini a veces envuelve el JSON en markdown o backticks; se limpia con
  -- REGEXP_REPLACE + REGEXP_EXTRACT antes de JSON_VALUE.
  --
  -- full_response viene como tipo JSON desde AI.GENERATE_TABLE; la tabla hist
  -- espera STRING → TO_JSON_STRING para compatibilidad de tipos.
  --
  -- Se hace DELETE + INSERT por process_date (idempotencia por día).
  -- ---------------------------------------------------------------------------
  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_raw`
  WHERE process_date = v_fecha_proceso;

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_raw`
  WITH cte_cleaned_json AS (
    SELECT
      ia.*,
      CONCAT(
        '[',
        REGEXP_EXTRACT(
          REGEXP_REPLACE(ml_generate_text_llm_result, r'`', '"'),
          r'(?s)\{.*\}'
        ),
        ']'
      ) AS json_text
    FROM tmp_onemarketer_whatsapp_gen_ia_results AS ia
  ),
  cte_parsed AS (
    SELECT
      process_date,
      gcs_uri,
      idcase,
      idmessage,
      waid,
      duration_seconds,
      chat_text,
      chat_origin,
      chat_user,
      json_text,
      TO_JSON_STRING(full_response) AS full_response,
      status,
      JSON_VALUE(json_text, '$[0].transcripcion') AS transcripcion,
      JSON_VALUE(json_text, '$[0].resumen') AS resumen,
      JSON_VALUE(json_text, '$[0].intencion') AS intencion,
      JSON_VALUE(json_text, '$[0].idioma') AS idioma,
      JSON_VALUE(json_text, '$[0].tono') AS tono,
      JSON_VALUE(json_text, '$[0].entidades') AS entidades,
      JSON_VALUE(json_text, '$[0].observaciones') AS observaciones,
      DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date
    FROM cte_cleaned_json
  )
  SELECT * FROM cte_parsed;

  -- ---------------------------------------------------------------------------
  -- PASO 6: Capa PRD (consumo)
  --
  -- Proyección simplificada para dashboards, vistas CRM y reportes.
  -- Omite campos técnicos (json_text, full_response, status, chat_user).
  -- Misma lógica idempotente: DELETE + INSERT por process_date.
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

  -- ---------------------------------------------------------------------------
  -- ETAPA 2: Análisis de conversación completa por idcase (sys_prompts)
  --
  -- Invoca sp_onemarketer_caso_conversacion_ia siempre (con o sin audios).
  -- Re-ejecutable solo: CALL sp_onemarketer_caso_conversacion_ia(fecha);
  -- ---------------------------------------------------------------------------
  CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_caso_conversacion_ia`(
    v_fecha_proceso,
    NULL
  );

END;
