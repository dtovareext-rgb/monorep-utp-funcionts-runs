-- =============================================================================
-- SP: Consolidación QueeSmart MP3 + tickets_hist_raw — PRODUCCIÓN
--
-- Proyecto: prd-utpbi-data-operation
-- Dataset:  raw_queue_smart (US)
-- Tickets:  raw_queue_smart.tickets_hist_raw
--
-- Ventana: [p_fecha_proceso - 3 días, p_fecha_proceso]
--  1.1 Catálogo MP3 (hist → queuesmart_mp3_catalog), dedup por gcs_uri
--  1.2 Enriquecido GCS + tickets (→ queuesmart_mp3_enriched)
--      join: COALESCE(source_file_name, file_name) = tickets.audio
--
-- Ejecutar (diario, después de qs_s3_to_gcs; el Cloud Run lo invoca al terminar):
--   CALL `prd-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_consolidate`(
--     DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY)
--   );
-- Al final llama sp_queuesmart_mp3_gen_ia (misma location US).
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_consolidate`(
  p_fecha_proceso DATE
)
BEGIN
  DECLARE start_date DATE;
  DECLARE v_load_date DATETIME;

  SET start_date = DATE_SUB(p_fecha_proceso, INTERVAL 3 DAY);
  SET v_load_date = DATETIME(CURRENT_TIMESTAMP(), 'America/Lima');

  -- ==========================================
  -- 1.1 Catálogo MP3 en GCS (Método Vaso de Agua)
  -- ==========================================
  CREATE OR REPLACE TEMP TABLE temp_mp3_catalog AS
  WITH base_ranked AS (
    SELECT
      fecha_audio,
      fecha_procesamiento,
      file_name,
      source_file_name,
      gcs_uri,
      gcs_path,
      campus_code,
      type_code,
      correlative,
      s3_uri,
      s3_key,
      file_size_bytes,
      sync_mode,
      convert_method,
      ROW_NUMBER() OVER (
        PARTITION BY gcs_uri
        ORDER BY fecha_procesamiento DESC
      ) AS rn
    FROM `prd-utpbi-data-operation.raw_queue_smart.hist_queesmart_mp3_catalog`
    WHERE fecha_audio BETWEEN start_date AND p_fecha_proceso
  )
  SELECT
    fecha_audio AS process_day,
    fecha_procesamiento,
    file_name,
    COALESCE(source_file_name, file_name) AS source_file_name,
    gcs_uri,
    gcs_path,
    campus_code,
    type_code,
    correlative,
    s3_uri,
    s3_key,
    file_size_bytes,
    sync_mode,
    convert_method,
    v_load_date AS load_date
  FROM base_ranked
  WHERE rn = 1;

  DELETE FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_catalog`
  WHERE gcs_uri IN (SELECT DISTINCT gcs_uri FROM temp_mp3_catalog);

  INSERT INTO `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_catalog` (
    process_day,
    fecha_procesamiento,
    file_name,
    source_file_name,
    gcs_uri,
    gcs_path,
    campus_code,
    type_code,
    correlative,
    s3_uri,
    s3_key,
    file_size_bytes,
    sync_mode,
    convert_method,
    load_date
  )
  SELECT
    process_day,
    fecha_procesamiento,
    file_name,
    source_file_name,
    gcs_uri,
    gcs_path,
    campus_code,
    type_code,
    correlative,
    s3_uri,
    s3_key,
    file_size_bytes,
    sync_mode,
    convert_method,
    load_date
  FROM temp_mp3_catalog;

  DROP TABLE temp_mp3_catalog;

  -- ==========================================
  -- 1.2 MP3 enriquecido GCS + tickets_hist_raw
  -- ==========================================
  CREATE OR REPLACE TEMP TABLE temp_mp3_enriched AS
  WITH catalog AS (
    SELECT *
    FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_catalog`
    WHERE process_day BETWEEN start_date AND p_fecha_proceso
  ),
  tickets AS (
    SELECT *
    FROM (
      SELECT
        t.*,
        ROW_NUMBER() OVER (
          PARTITION BY t.audio
          ORDER BY t.process_datatime DESC, t.endtimestamp DESC, t.starttimestamp DESC
        ) AS rn
      FROM `prd-utpbi-data-operation.raw_queue_smart.tickets_hist_raw` AS t
      WHERE t.audio IS NOT NULL
        AND NULLIF(TRIM(t.audio), '') IS NOT NULL
        AND DATE(COALESCE(t.starttimestamp, t.creationtimestamp, t.process_datatime))
            BETWEEN start_date AND p_fecha_proceso
    )
    WHERE rn = 1
  ),
  joined AS (
    SELECT
      COALESCE(
        c.process_day,
        DATE(COALESCE(r.starttimestamp, r.creationtimestamp, r.process_datatime))
      ) AS process_day,
      CASE
        WHEN c.gcs_uri IS NOT NULL AND r.audio IS NOT NULL THEN 'BOTH'
        WHEN c.gcs_uri IS NOT NULL THEN 'GCS_ONLY'
        ELSE 'TICKET_ONLY'
      END AS match_status,
      c.gcs_uri,
      COALESCE(c.file_name, REGEXP_REPLACE(r.audio, r'(?i)\.(webm|ogg|opus|wav|flac|m4a|aac)$', '.mp3')) AS file_name,
      COALESCE(c.source_file_name, r.audio) AS source_file_name,
      COALESCE(r.audio, c.source_file_name, c.file_name) AS audio,
      r.recordid,
      r.rowid,
      r.codagencia,
      c.campus_code,
      c.type_code,
      c.correlative,
      c.file_size_bytes,
      c.convert_method,
      r.asesornombre,
      r.asesorusuario,
      r.asesorcodigo,
      r.ndoc,
      r.nombresusuario,
      r.numcelular,
      r.clienteprimernombre,
      r.clienteapellidopaterno,
      r.clientetipo,
      r.clienteestado,
      r.creationtimestamp,
      r.starttimestamp,
      r.endtimestamp,
      r.`database`,
      c.fecha_procesamiento AS catalog_fecha_procesamiento,
      r.process_datatime AS ticket_process_datatime,
      v_load_date AS load_date
    FROM catalog AS c
    FULL OUTER JOIN tickets AS r
      ON COALESCE(c.source_file_name, c.file_name) = r.audio
  ),
  ranked AS (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY COALESCE(recordid, gcs_uri, audio)
        ORDER BY catalog_fecha_procesamiento DESC, ticket_process_datatime DESC
      ) AS rn
    FROM joined
  )
  SELECT * EXCEPT(rn)
  FROM ranked
  WHERE rn = 1;

  DELETE FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
  WHERE process_day BETWEEN start_date AND p_fecha_proceso;

  INSERT INTO `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched` (
    process_day,
    match_status,
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
    convert_method,
    asesornombre,
    asesorusuario,
    asesorcodigo,
    ndoc,
    nombresusuario,
    numcelular,
    clienteprimernombre,
    clienteapellidopaterno,
    clientetipo,
    clienteestado,
    creationtimestamp,
    starttimestamp,
    endtimestamp,
    `database`,
    catalog_fecha_procesamiento,
    ticket_process_datatime,
    load_date
  )
  SELECT
    process_day,
    match_status,
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
    convert_method,
    asesornombre,
    asesorusuario,
    asesorcodigo,
    ndoc,
    nombresusuario,
    numcelular,
    clienteprimernombre,
    clienteapellidopaterno,
    clientetipo,
    clienteestado,
    creationtimestamp,
    starttimestamp,
    endtimestamp,
    `database`,
    catalog_fecha_procesamiento,
    ticket_process_datatime,
    load_date
  FROM temp_mp3_enriched;

  DROP TABLE temp_mp3_enriched;

  -- ==========================================
  -- 1.3 Gen IA (transcribe + análisis) — misma location US
  -- ==========================================
  CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia`(
    p_fecha_proceso
  );

END;
