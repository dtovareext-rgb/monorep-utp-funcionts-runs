-- Vista candidatos Gen IA desde hist catálogo — PRODUCCIÓN
-- Incluye source_file_name para join con tickets_hist_raw.audio

CREATE OR REPLACE VIEW `prd-utpbi-data-operation.raw_queue_smart.v_hist_queesmart_mp3_catalog_ia_input` AS
SELECT
  c.fecha_audio AS process_date,
  c.gcs_uri,
  c.file_name,
  COALESCE(c.source_file_name, c.file_name) AS source_file_name,
  c.gcs_path,
  c.campus_code,
  c.type_code,
  c.correlative,
  c.file_size_bytes,
  c.duration_seconds,
  c.sync_mode,
  c.convert_method,
  c.s3_uri,
  c.fecha_procesamiento
FROM `prd-utpbi-data-operation.raw_queue_smart.hist_queesmart_mp3_catalog` AS c
WHERE c.gcs_uri IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY c.gcs_uri
  ORDER BY c.fecha_procesamiento DESC
) = 1;
