-- =============================================================================
-- SP: QueeSmart MP3 — Etapa 1 (transcripción STT) — PRODUCCIÓN
--
-- Proyecto:  prd-utpbi-data-operation
-- Input:     raw_queue_smart.queuesmart_mp3_enriched (BOTH / GCS_ONLY)
-- SP + hist: adf_speech_analytics (US)
-- STT:       adf_speech_analytics.speech-to-text-v2  (ML.TRANSCRIBE / Chirp)
-- Conexión:  US.utp_gen_ia_process
--
-- Flujo (incremental por gcs_uri):
--   1) Candidatos del día SIN transcripción OK en hist_*_mp3_gen_ia_*
--   2) External table + ML.TRANSCRIBE solo pendientes
--   3) DELETE/INSERT solo esos gcs_uri (no borra el día completo)
--   4) CALL etapa 2: sp_queuesmart_audio_analisis_ia
--
-- Ejecutar (diario, después de sp_queuesmart_mp3_consolidate):
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia`(
--     DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY)
--   );
--
-- Nota: si speech-to-text-v2 NO tiene SPEECH_RECOGNIZER, agregar recognition_config:
--   recognition_config => (JSON '{"language_codes":["es-US"],"model":"chirp","auto_decoding_config":{}}')
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia`(
  v_fecha_proceso DATE
)
BEGIN
  DECLARE v_fecha_proceso_str STRING;
  DECLARE external_table STRING;
  DECLARE conexion STRING;
  DECLARE v_uris STRING;
  DECLARE v_sql STRING;
  DECLARE v_audio_count INT64;

  SET v_fecha_proceso_str = FORMAT_DATE('%Y-%m-%d', v_fecha_proceso);
  SET external_table = '`prd-utpbi-data-operation.adf_speech_analytics.tmp_utp_external_table_queuesmart_mp3`';
  SET conexion = '`prd-utpbi-data-operation.US.utp_gen_ia_process`';

  -- ---------------------------------------------------------------------------
  -- 1. URIs pendientes: día + sin transcripción no vacía en hist PRD
  -- ---------------------------------------------------------------------------
  SET v_uris = (
    WITH base_ranked AS (
      SELECT
        gcs_uri,
        ROW_NUMBER() OVER (
          PARTITION BY gcs_uri
          ORDER BY catalog_fecha_procesamiento DESC, ticket_process_datatime DESC
        ) AS rn
      FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
      WHERE process_day = v_fecha_proceso
        AND match_status IN ('BOTH', 'GCS_ONLY')
        AND gcs_uri IS NOT NULL
    ),
    already_ok AS (
      SELECT DISTINCT gcs_uri
      FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
      WHERE NULLIF(TRIM(transcripcion), '') IS NOT NULL
    )
    SELECT CONCAT(
      '[',
      STRING_AGG(CONCAT('"', b.gcs_uri, '"'), ', '),
      ']'
    )
    FROM base_ranked AS b
    LEFT JOIN already_ok AS a
      ON a.gcs_uri = b.gcs_uri
    WHERE b.rn = 1
      AND a.gcs_uri IS NULL
  );

  IF v_uris IS NULL OR v_uris = '[]' THEN
    SET v_uris = (
      WITH base_ranked AS (
        SELECT
          gcs_uri,
          ROW_NUMBER() OVER (
            PARTITION BY gcs_uri
            ORDER BY fecha_procesamiento DESC
          ) AS rn
        FROM `prd-utpbi-data-operation.raw_queue_smart.hist_queesmart_mp3_catalog`
        WHERE fecha_audio = v_fecha_proceso
          AND gcs_uri IS NOT NULL
      ),
      already_ok AS (
        SELECT DISTINCT gcs_uri
        FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
        WHERE NULLIF(TRIM(transcripcion), '') IS NOT NULL
      )
      SELECT CONCAT(
        '[',
        STRING_AGG(CONCAT('"', b.gcs_uri, '"'), ', '),
        ']'
      )
      FROM base_ranked AS b
      LEFT JOIN already_ok AS a
        ON a.gcs_uri = b.gcs_uri
      WHERE b.rn = 1
        AND a.gcs_uri IS NULL
    );
  END IF;

  IF v_uris IS NULL OR v_uris = '[]' THEN
    SELECT FORMAT(
      'Sin URIs QueeSmart pendientes de STT para fecha %s — etapa 1 omite; se llama etapa 2.',
      v_fecha_proceso_str
    );
  ELSE
    -- ---------------------------------------------------------------------------
    -- 2. External table (solo pendientes)
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
    -- 3. Metadata enriched/catalog (solo pendientes de STT)
    -- ---------------------------------------------------------------------------
    EXECUTE IMMEDIATE FORMAT("""
      CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_audios AS
      WITH enriched AS (
        SELECT *
        FROM (
          SELECT
            e.*,
            ROW_NUMBER() OVER (
              PARTITION BY e.gcs_uri
              ORDER BY e.catalog_fecha_procesamiento DESC, e.ticket_process_datatime DESC
            ) AS rn
          FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched` AS e
          WHERE e.process_day = DATE('%s')
            AND e.match_status IN ('BOTH', 'GCS_ONLY')
            AND e.gcs_uri IS NOT NULL
        )
        WHERE rn = 1
      ),
      catalog_fallback AS (
        SELECT *
        FROM (
          SELECT
            c.fecha_audio AS process_day,
            c.gcs_uri,
            c.file_name,
            COALESCE(c.source_file_name, c.file_name) AS source_file_name,
            COALESCE(c.source_file_name, c.file_name) AS audio,
            CAST(NULL AS STRING) AS recordid,
            CAST(NULL AS INT64) AS rowid,
            CAST(NULL AS STRING) AS codagencia,
            c.gcs_path,
            c.campus_code,
            c.type_code,
            c.correlative,
            c.file_size_bytes,
            c.duration_seconds,
            c.sync_mode,
            c.convert_method,
            c.s3_uri,
            'GCS_ONLY' AS match_status,
            CAST(NULL AS STRING) AS asesornombre,
            CAST(NULL AS STRING) AS asesorusuario,
            CAST(NULL AS STRING) AS asesorcodigo,
            CAST(NULL AS STRING) AS ndoc,
            CAST(NULL AS STRING) AS nombresusuario,
            CAST(NULL AS STRING) AS numcelular,
            CAST(NULL AS STRING) AS clientetipo,
            CAST(NULL AS STRING) AS `database`,
            ROW_NUMBER() OVER (
              PARTITION BY c.gcs_uri
              ORDER BY c.fecha_procesamiento DESC
            ) AS rn
          FROM `prd-utpbi-data-operation.raw_queue_smart.hist_queesmart_mp3_catalog` AS c
          WHERE c.fecha_audio = DATE('%s')
            AND c.gcs_uri IS NOT NULL
            AND c.gcs_uri NOT IN (SELECT gcs_uri FROM enriched)
        )
        WHERE rn = 1
      ),
      base AS (
        SELECT
          process_day,
          gcs_uri,
          file_name,
          source_file_name,
          audio,
          recordid,
          rowid,
          codagencia,
          CAST(NULL AS STRING) AS gcs_path,
          campus_code,
          type_code,
          correlative,
          file_size_bytes,
          duration_seconds,
          CAST(NULL AS STRING) AS sync_mode,
          convert_method,
          CAST(NULL AS STRING) AS s3_uri,
          match_status,
          asesornombre,
          asesorusuario,
          asesorcodigo,
          ndoc,
          nombresusuario,
          numcelular,
          clientetipo,
          `database`
        FROM enriched
        UNION ALL
        SELECT
          process_day,
          gcs_uri,
          file_name,
          source_file_name,
          audio,
          recordid,
          rowid,
          codagencia,
          gcs_path,
          campus_code,
          type_code,
          correlative,
          file_size_bytes,
          duration_seconds,
          sync_mode,
          convert_method,
          s3_uri,
          match_status,
          asesornombre,
          asesorusuario,
          asesorcodigo,
          ndoc,
          nombresusuario,
          numcelular,
          clientetipo,
          `database`
        FROM catalog_fallback
      ),
      already_ok AS (
        SELECT DISTINCT gcs_uri
        FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
        WHERE NULLIF(TRIM(transcripcion), '') IS NOT NULL
      )
      SELECT
        b.process_day AS process_date,
        b.gcs_uri,
        b.file_name,
        b.source_file_name,
        b.audio,
        b.recordid,
        b.rowid,
        b.codagencia,
        b.gcs_path,
        b.campus_code,
        b.type_code,
        b.correlative,
        b.file_size_bytes,
        b.duration_seconds,
        b.sync_mode,
        b.convert_method,
        b.s3_uri,
        b.match_status,
        b.asesornombre,
        b.asesorusuario,
        b.asesorcodigo,
        b.ndoc,
        b.nombresusuario,
        b.numcelular,
        b.clientetipo,
        b.`database`
      FROM base AS b
      LEFT JOIN already_ok AS a
        ON a.gcs_uri = b.gcs_uri
      WHERE a.gcs_uri IS NULL
    """, v_fecha_proceso_str, v_fecha_proceso_str);

    SET v_audio_count = (SELECT COUNT(*) FROM tmp_queuesmart_mp3_audios);

    IF v_audio_count > 0 THEN
      -- ---------------------------------------------------------------------------
      -- 4. Speech-to-Text v2 (Chirp) — solo pendientes
      -- ---------------------------------------------------------------------------
      EXECUTE IMMEDIATE FORMAT("""
        CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_stt_results AS
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
      -- 5. Persistencia incremental: DELETE/INSERT solo gcs_uri procesados
      -- ---------------------------------------------------------------------------
      DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
      WHERE gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_mp3_audios);

      INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw` (
        process_date,
        gcs_uri,
        file_name,
        source_file_name,
        audio,
        recordid,
        rowid,
        codagencia,
        gcs_path,
        campus_code,
        type_code,
        correlative,
        file_size_bytes,
        duration_seconds,
        sync_mode,
        convert_method,
        s3_uri,
        match_status,
        asesornombre,
        asesorusuario,
        asesorcodigo,
        ndoc,
        nombresusuario,
        numcelular,
        clientetipo,
        `database`,
        json_text,
        full_response,
        status,
        transcripcion,
        resumen,
        intencion,
        idioma,
        tono,
        entidades,
        observaciones,
        load_date
      )
      SELECT
        m.process_date,
        m.gcs_uri,
        m.file_name,
        m.source_file_name,
        m.audio,
        m.recordid,
        m.rowid,
        m.codagencia,
        m.gcs_path,
        m.campus_code,
        m.type_code,
        m.correlative,
        m.file_size_bytes,
        m.duration_seconds,
        m.sync_mode,
        m.convert_method,
        m.s3_uri,
        m.match_status,
        m.asesornombre,
        m.asesorusuario,
        m.asesorcodigo,
        m.ndoc,
        m.nombresusuario,
        m.numcelular,
        m.clientetipo,
        m.`database`,
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
      FROM tmp_queuesmart_mp3_audios AS m
      INNER JOIN tmp_queuesmart_mp3_stt_results AS s
        ON s.uri = m.gcs_uri;

      DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
      WHERE gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_mp3_audios);

      INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd` (
        process_date,
        gcs_uri,
        file_name,
        source_file_name,
        audio,
        recordid,
        rowid,
        codagencia,
        campus_code,
        type_code,
        correlative,
        file_size_bytes,
        duration_seconds,
        match_status,
        asesornombre,
        asesorusuario,
        asesorcodigo,
        ndoc,
        nombresusuario,
        numcelular,
        clientetipo,
        `database`,
        transcripcion,
        resumen,
        intencion,
        idioma,
        tono,
        entidades,
        observaciones,
        load_date
      )
      SELECT
        process_date,
        gcs_uri,
        file_name,
        source_file_name,
        audio,
        recordid,
        rowid,
        codagencia,
        campus_code,
        type_code,
        correlative,
        file_size_bytes,
        duration_seconds,
        match_status,
        asesornombre,
        asesorusuario,
        asesorcodigo,
        ndoc,
        nombresusuario,
        numcelular,
        clientetipo,
        `database`,
        transcripcion,
        resumen,
        intencion,
        idioma,
        tono,
        entidades,
        observaciones,
        load_date
      FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
      WHERE gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_mp3_audios);
    END IF;
  END IF;

  -- ---------------------------------------------------------------------------
  -- Etapa 2: análisis vs sys_prompts con Gemini (raw_queue_smart)
  -- ---------------------------------------------------------------------------
  CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_audio_analisis_ia`(
    v_fecha_proceso,
    NULL
  );

END;
