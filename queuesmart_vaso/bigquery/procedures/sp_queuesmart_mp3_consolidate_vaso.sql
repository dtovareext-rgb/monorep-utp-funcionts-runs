-- =============================================================================
-- SP: Consolidación QueeSmart VASO (legado-miss) + tickets_hist_raw
--
-- Lee:  hist_queesmart_mp3_catalog_vaso
-- Escribe: queuesmart_mp3_catalog_vaso + queuesmart_mp3_enriched_vaso
-- Tickets: raw_queue_smart.tickets_hist_raw (misma fuente prod)
-- NO toca consolidate / catalog / enriched de producción.
--
-- CALL:
--   CALL `prd-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_consolidate_vaso`(
--     DATE '2026-09-10'
--   );
-- Luego: cr_serialize_queuesmart (Whisper) → sp_queuesmart_audio_analisis_ia_vaso
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_consolidate_vaso`(
  p_fecha_proceso DATE
)
BEGIN
  DECLARE start_date DATE;
  DECLARE v_load_date DATETIME;

  -- Labels de costo: heredan a jobs hijos del SP.
  SET @@query_label = 'producto:queuesmart-vaso,etapa:consolidate,servicio:bq';

  SET start_date = DATE_SUB(p_fecha_proceso, INTERVAL 3 DAY);
  SET v_load_date = DATETIME(CURRENT_TIMESTAMP(), 'America/Lima');

  -- ==========================================
  -- 0. Reproceso: limpia catalog + enriched de la ventana
  -- ==========================================
  DELETE FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_catalog_vaso`
  WHERE process_day BETWEEN start_date AND p_fecha_proceso;

  DELETE FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched_vaso`
  WHERE process_day BETWEEN start_date AND p_fecha_proceso;

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
      duration_seconds,
      sync_mode,
      convert_method,
      ROW_NUMBER() OVER (
        PARTITION BY gcs_uri
        ORDER BY fecha_procesamiento DESC
      ) AS rn
    FROM `prd-utpbi-data-operation.raw_queue_smart.hist_queesmart_mp3_catalog_vaso`
    WHERE fecha_audio BETWEEN start_date AND p_fecha_proceso
  ),
  one_per_uri AS (
    SELECT * EXCEPT(rn)
    FROM base_ranked
    WHERE rn = 1
  ),
  prefer_flac AS (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY
          fecha_audio,
          campus_code,
          type_code,
          correlative,
          IF(
            REGEXP_CONTAINS(LOWER(file_name), r'_s\d+\.'),
            file_name,
            '__mono__'
          )
        ORDER BY
          CASE WHEN LOWER(file_name) LIKE '%.flac' THEN 0 ELSE 1 END,
          fecha_procesamiento DESC
      ) AS rn_stem
    FROM one_per_uri
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
    duration_seconds,
    sync_mode,
    convert_method,
    v_load_date AS load_date
  FROM prefer_flac
  WHERE rn_stem = 1;

  INSERT INTO `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_catalog_vaso` (
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
    duration_seconds,
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
    duration_seconds,
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
    FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_catalog_vaso`
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
      c.duration_seconds,
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

  DELETE FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched_vaso`
  WHERE process_day BETWEEN start_date AND p_fecha_proceso;

  INSERT INTO `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched_vaso` (
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
    duration_seconds,
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
    duration_seconds,
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

END;
