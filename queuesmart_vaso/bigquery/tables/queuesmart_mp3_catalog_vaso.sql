-- =============================================================================
-- VASO: catálogo MP3 consolidado (dedup) desde hist_queesmart_mp3_catalog_vaso
-- NO toca queuesmart_mp3_catalog prod.
--
--   bq query --use_legacy_sql=false --location=US \
--     --project_id=prd-utpbi-data-operation \
--     < queuesmart_vaso/bigquery/tables/queuesmart_mp3_catalog_vaso.sql
-- =============================================================================

CREATE TABLE IF NOT EXISTS `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_catalog_vaso` (
  process_day DATE NOT NULL,
  fecha_procesamiento TIMESTAMP NOT NULL,
  file_name STRING NOT NULL,
  source_file_name STRING,
  gcs_uri STRING NOT NULL,
  gcs_path STRING,
  campus_code STRING,
  type_code STRING,
  correlative STRING,
  s3_uri STRING,
  s3_key STRING,
  file_size_bytes INT64,
  duration_seconds FLOAT64,
  sync_mode STRING,
  convert_method STRING,
  load_date DATETIME
)
PARTITION BY process_day
OPTIONS (
  description = 'VASO QueeSmart MP3 consolidado (legado-miss). Fuente: hist_queesmart_mp3_catalog_vaso. Pipeline queuesmart_vaso.'
);
