-- =============================================================================
-- VASO: MP3 + tickets (join source_file_name ↔ tickets_hist_raw.audio)
-- NO toca queuesmart_mp3_enriched prod.
--
--   bq query --use_legacy_sql=false --location=US \
--     --project_id=prd-utpbi-data-operation \
--     < queuesmart_vaso/bigquery/tables/queuesmart_mp3_enriched_vaso.sql
-- =============================================================================

CREATE TABLE IF NOT EXISTS `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched_vaso` (
  process_day DATE NOT NULL,
  match_status STRING NOT NULL,
  gcs_uri STRING,
  file_name STRING,
  source_file_name STRING,
  audio STRING,
  recordid STRING,
  rowid INT64,
  codagencia STRING,
  campus_code STRING,
  type_code STRING,
  correlative STRING,
  file_size_bytes INT64,
  duration_seconds FLOAT64,
  convert_method STRING,
  asesornombre STRING,
  asesorusuario STRING,
  asesorcodigo STRING,
  ndoc STRING,
  nombresusuario STRING,
  numcelular STRING,
  clienteprimernombre STRING,
  clienteapellidopaterno STRING,
  clientetipo STRING,
  clienteestado STRING,
  creationtimestamp TIMESTAMP,
  starttimestamp TIMESTAMP,
  endtimestamp TIMESTAMP,
  `database` STRING,
  catalog_fecha_procesamiento TIMESTAMP,
  ticket_process_datatime TIMESTAMP,
  load_date DATETIME
)
PARTITION BY process_day
OPTIONS (
  description = 'VASO QueeSmart MP3 + tickets_hist_raw. Input de cr_serialize_queuesmart (Whisper).'
);
