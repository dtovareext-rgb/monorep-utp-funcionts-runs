-- =============================================================================
-- SP: QueeSmart MP3 — Etapa 1 (transcripción STT) — PRODUCCIÓN
--
-- Proyecto:  prd-utpbi-data-operation
-- Input:     raw_queue_smart.queuesmart_mp3_enriched (BOTH / GCS_ONLY)
-- SP + hist: adf_speech_analytics (US)
-- STT:       adf_speech_analytics.speech-to-text-v2  (ML.TRANSCRIBE / Chirp)
-- Conexión:  US.utp_gen_ia_process
--
-- Técnica anti-timeout:
--   ML.TRANSCRIBE por LOTES (v_batch_size, default 25) en un WHILE.
--   Con ~138 audios: ~6 lotes en vez de 1 job gigante que se cae por tiempo.
--
-- Flujo (reproceso por fecha):
--   0) DELETE hist raw/prd del día
--   1) Metadata candidatos → tmp_queuesmart_mp3_audios
--   2) Loop: external table del lote → ML.TRANSCRIBE → INSERT hist raw
--   3) Speaker tags (si hay) + copia a hist prd
-- Etapa 2 (Gemini): Cloud Workflows → sp_queuesmart_audio_analisis_ia
--
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia`(
--     DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY)
--   );
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
  DECLARE v_batch_size INT64 DEFAULT 25;
  DECLARE v_offset INT64 DEFAULT 0;
  DECLARE v_batch_num INT64 DEFAULT 0;
  DECLARE v_batch_count INT64;

  SET v_fecha_proceso_str = FORMAT_DATE('%Y-%m-%d', v_fecha_proceso);
  SET external_table = '`prd-utpbi-data-operation.adf_speech_analytics.tmp_utp_external_table_queuesmart_mp3`';
  SET conexion = '`prd-utpbi-data-operation.US.utp_gen_ia_process`';

  -- ---------------------------------------------------------------------------
  -- 0. Reproceso por fecha: borra hist del día para poder re-ejecutar limpio
  -- ---------------------------------------------------------------------------
  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
  WHERE process_date = v_fecha_proceso;

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
  WHERE process_date = v_fecha_proceso;

  -- ---------------------------------------------------------------------------
  -- 1. Metadata enriched/catalog del día (+ batch_rn para lotes)
  -- ---------------------------------------------------------------------------
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_audios AS
    WITH catalog_dur AS (
      SELECT
        gcs_uri,
        duration_seconds,
        ROW_NUMBER() OVER (
          PARTITION BY gcs_uri
          ORDER BY fecha_procesamiento DESC
        ) AS rn
      FROM `prd-utpbi-data-operation.raw_queue_smart.hist_queesmart_mp3_catalog`
      WHERE fecha_audio = DATE('%s')
        AND gcs_uri IS NOT NULL
    ),
    enriched AS (
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
        e.process_day,
        e.gcs_uri,
        e.file_name,
        e.source_file_name,
        e.audio,
        e.recordid,
        e.rowid,
        e.codagencia,
        CAST(NULL AS STRING) AS gcs_path,
        e.campus_code,
        e.type_code,
        e.correlative,
        e.file_size_bytes,
        COALESCE(e.duration_seconds, d.duration_seconds) AS duration_seconds,
        CAST(NULL AS STRING) AS sync_mode,
        e.convert_method,
        CAST(NULL AS STRING) AS s3_uri,
        e.match_status,
        e.asesornombre,
        e.asesorusuario,
        e.asesorcodigo,
        e.ndoc,
        e.nombresusuario,
        e.numcelular,
        e.clientetipo,
        e.`database`
      FROM enriched AS e
      LEFT JOIN catalog_dur AS d
        ON d.gcs_uri = e.gcs_uri
       AND d.rn = 1
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
      b.`database`,
      ROW_NUMBER() OVER (ORDER BY b.gcs_uri) - 1 AS batch_rn
    FROM base AS b
  """, v_fecha_proceso_str, v_fecha_proceso_str, v_fecha_proceso_str);

  SET v_audio_count = (SELECT COUNT(*) FROM tmp_queuesmart_mp3_audios);

  IF v_audio_count = 0 THEN
    SELECT FORMAT(
      'Sin URIs QueeSmart para STT en fecha %s — etapa 1 omite.',
      v_fecha_proceso_str
    );
  ELSE
    -- Acumulador de resultados STT de todos los lotes
    CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_stt_results (
      uri STRING,
      transcripts STRING,
      ml_transcribe_result JSON,
      ml_transcribe_status STRING
    );

    SELECT FORMAT(
      'STT QueeSmart fecha %s: %d audios en lotes de %d',
      v_fecha_proceso_str,
      v_audio_count,
      v_batch_size
    );

    -- ---------------------------------------------------------------------------
    -- 2. Loop por lotes: external table → ML.TRANSCRIBE → hist raw
    -- ---------------------------------------------------------------------------
    WHILE v_offset < v_audio_count DO
      SET v_batch_num = v_batch_num + 1;

      SET v_uris = (
        SELECT CONCAT(
          '[',
          STRING_AGG(CONCAT('"', gcs_uri, '"'), ', ' ORDER BY batch_rn),
          ']'
        )
        FROM tmp_queuesmart_mp3_audios
        WHERE batch_rn >= v_offset
          AND batch_rn < v_offset + v_batch_size
      );

      SET v_batch_count = (
        SELECT COUNT(*)
        FROM tmp_queuesmart_mp3_audios
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

      -- Chirp (sin diarization_config: BQ ML no lo soporta en recognition_config)
      EXECUTE IMMEDIATE FORMAT(
      """CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_stt_batch AS
         SELECT uri, transcripts, ml_transcribe_result, ml_transcribe_status
         FROM ML.TRANSCRIBE(
           MODEL `prd-utpbi-data-operation.adf_speech_analytics.speech-to-text-v2`,
           TABLE %s,
           recognition_config => JSON '{\"language_codes\":[\"es-US\"],\"model\":\"chirp\",\"auto_decoding_config\":{}}'
         )""", external_table);

      INSERT INTO tmp_queuesmart_mp3_stt_results
      SELECT uri, transcripts, ml_transcribe_result, ml_transcribe_status
      FROM tmp_queuesmart_mp3_stt_batch;

      -- Persistencia del lote (idempotente por gcs_uri del lote)
      DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
      WHERE gcs_uri IN (
        SELECT gcs_uri FROM tmp_queuesmart_mp3_audios
        WHERE batch_rn >= v_offset AND batch_rn < v_offset + v_batch_size
      );

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
        transcripcion_con_hablantes,
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
        CAST(NULL AS STRING) AS transcripcion_con_hablantes,
        CAST(NULL AS STRING) AS resumen,
        CAST(NULL AS STRING) AS intencion,
        CAST(NULL AS STRING) AS idioma,
        CAST(NULL AS STRING) AS tono,
        CAST(NULL AS STRING) AS entidades,
        CAST(NULL AS STRING) AS observaciones,
        DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date
      FROM tmp_queuesmart_mp3_audios AS m
      INNER JOIN tmp_queuesmart_mp3_stt_batch AS s
        ON s.uri = m.gcs_uri
      WHERE m.batch_rn >= v_offset
        AND m.batch_rn < v_offset + v_batch_size;

      SET v_offset = v_offset + v_batch_size;
    END WHILE;

    -- ---------------------------------------------------------------------------
    -- 3. Reconstruir speakers (si el JSON trae tags; con chirp suele quedar NULL)
    -- ---------------------------------------------------------------------------
    CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_speaker_tx AS
    WITH flat_words AS (
      SELECT
        s.uri,
        COALESCE(
          SAFE_CAST(JSON_VALUE(w, '$.speakerLabel') AS INT64),
          SAFE_CAST(JSON_VALUE(w, '$.speaker_label') AS INT64),
          SAFE_CAST(JSON_VALUE(w, '$.speakerTag') AS INT64),
          SAFE_CAST(JSON_VALUE(w, '$.speaker_tag') AS INT64)
        ) AS speaker_tag,
        JSON_VALUE(w, '$.word') AS word,
        result_ord,
        word_ord
      FROM tmp_queuesmart_mp3_stt_results AS s
      CROSS JOIN UNNEST(JSON_QUERY_ARRAY(TO_JSON_STRING(s.ml_transcribe_result), '$.results')) AS result WITH OFFSET AS result_ord
      CROSS JOIN UNNEST(JSON_QUERY_ARRAY(result, '$.alternatives[0].words')) AS w WITH OFFSET AS word_ord
      WHERE s.ml_transcribe_result IS NOT NULL
        AND JSON_VALUE(w, '$.word') IS NOT NULL
    ),
    with_prev AS (
      SELECT
        uri,
        speaker_tag,
        word,
        result_ord,
        word_ord,
        LAG(speaker_tag) OVER (
          PARTITION BY uri
          ORDER BY result_ord, word_ord
        ) AS prev_speaker
      FROM flat_words
      WHERE speaker_tag IS NOT NULL
    ),
    turns AS (
      SELECT
        uri,
        speaker_tag,
        result_ord,
        word_ord,
        word,
        COUNTIF(prev_speaker IS NULL OR prev_speaker != speaker_tag) OVER (
          PARTITION BY uri
          ORDER BY result_ord, word_ord
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS turn_id
      FROM with_prev
    ),
    turn_text AS (
      SELECT
        uri,
        turn_id,
        ANY_VALUE(speaker_tag) AS speaker_tag,
        MIN(result_ord * 100000 + word_ord) AS turn_ord,
        STRING_AGG(word, ' ' ORDER BY result_ord, word_ord) AS text
      FROM turns
      GROUP BY uri, turn_id
    )
    SELECT
      uri,
      STRING_AGG(
        CONCAT('Persona ', CAST(speaker_tag AS STRING), ': ', text),
        '\n'
        ORDER BY turn_ord
      ) AS transcripcion_con_hablantes
    FROM turn_text
    GROUP BY uri;

    UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw` AS t
    SET transcripcion_con_hablantes = f.transcripcion_con_hablantes
    FROM tmp_queuesmart_mp3_speaker_tx AS f
    WHERE t.gcs_uri = f.uri
      AND t.gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_mp3_audios)
      AND f.transcripcion_con_hablantes IS NOT NULL;

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
      transcripcion_con_hablantes,
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
      transcripcion_con_hablantes,
      resumen,
      intencion,
      idioma,
      tono,
      entidades,
      observaciones,
      load_date
    FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
    WHERE gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_mp3_audios);

    SELECT FORMAT(
      'STT QueeSmart OK fecha %s: %d audios en %d lotes',
      v_fecha_proceso_str,
      v_audio_count,
      v_batch_num
    );
  END IF;

END;
