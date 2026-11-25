-- =============================================================================
-- SP: QueeSmart MP3 STT — init (borra hist opcional + materializa candidatos)
--
-- Staging: adf_speech_analytics.stg_queuesmart_mp3_stt_candidates
--   (CREATE OR REPLACE por corrida; batch_rn estable ORDER BY gcs_uri)
--
-- CALL:
--   -- Día limpio (borra raw/prd del día):
--   CALL `...sp_queuesmart_mp3_gen_ia_init`(DATE '2026-11-17', FALSE);
--   -- Reanudar (no borra hist; refresca staging):
--   CALL `...sp_queuesmart_mp3_gen_ia_init`(DATE '2026-11-17', TRUE);
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia_init`(
  v_fecha_proceso DATE,
  p_skip_delete BOOL
)
BEGIN
  DECLARE v_fecha_proceso_str STRING;
  DECLARE v_audio_count INT64;

  SET @@query_label = 'producto:queuesmart,etapa:stt,sp:gen_ia_init';
  SET v_fecha_proceso_str = FORMAT_DATE('%Y-%m-%d', v_fecha_proceso);

  IF p_skip_delete IS NOT TRUE THEN
    DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
    WHERE process_date = v_fecha_proceso;

    DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
    WHERE process_date = v_fecha_proceso;
  END IF;

  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE `prd-utpbi-data-operation.adf_speech_analytics.stg_queuesmart_mp3_stt_candidates` AS
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

  SET v_audio_count = (
    SELECT COUNT(*)
    FROM `prd-utpbi-data-operation.adf_speech_analytics.stg_queuesmart_mp3_stt_candidates`
    WHERE process_date = v_fecha_proceso
  );

  SELECT FORMAT(
    'STT init QueeSmart fecha %s: candidatos=%d skip_delete=%t',
    v_fecha_proceso_str,
    v_audio_count,
    p_skip_delete
  );
END;
