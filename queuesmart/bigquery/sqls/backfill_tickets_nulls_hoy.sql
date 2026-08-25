-- =============================================================================
-- ONE-SHOT: rellenar tickets tardíos (database NULL) en tablas actuales
-- No espera al workflow de mañana. Misma lógica que
--   sp_queuesmart_mp3_backfill_tickets
-- sin recortar por ventana de 14 días: todos los NULL de hoy.
--
-- bq query --use_legacy_sql=false --location=US \
--   --project_id=prd-utpbi-data-operation \
--   --impersonate_service_account=genesys-audio-processor@prd-utpbi-data-operation.iam.gserviceaccount.com \
--   < queuesmart/bigquery/sqls/backfill_tickets_nulls_hoy.sql
-- =============================================================================

CREATE OR REPLACE TEMP TABLE tmp_tickets_late AS
SELECT * EXCEPT(rn)
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
    AND NULLIF(TRIM(t.`database`), '') IS NOT NULL
)
WHERE rn = 1;

-- Antes
SELECT
  'enriched' AS tabla,
  COUNTIF(`database` IS NULL OR TRIM(`database`) = '') AS n_database_null
FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
UNION ALL
SELECT 'stt_raw', COUNTIF(`database` IS NULL OR TRIM(`database`) = '')
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
UNION ALL
SELECT 'stt_prd', COUNTIF(`database` IS NULL OR TRIM(`database`) = '')
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
UNION ALL
SELECT 'analisis_raw', COUNTIF(`database` IS NULL OR TRIM(`database`) = '')
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
UNION ALL
SELECT 'analisis_prd', COUNTIF(`database` IS NULL OR TRIM(`database`) = '')
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`;

UPDATE `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched` AS e
SET
  match_status = IF(e.gcs_uri IS NOT NULL, 'BOTH', e.match_status),
  audio = COALESCE(t.audio, e.audio),
  recordid = t.recordid,
  rowid = t.rowid,
  codagencia = t.codagencia,
  asesornombre = t.asesornombre,
  asesorusuario = t.asesorusuario,
  asesorcodigo = t.asesorcodigo,
  ndoc = t.ndoc,
  nombresusuario = t.nombresusuario,
  numcelular = t.numcelular,
  clienteprimernombre = t.clienteprimernombre,
  clienteapellidopaterno = t.clienteapellidopaterno,
  clientetipo = t.clientetipo,
  clienteestado = t.clienteestado,
  creationtimestamp = t.creationtimestamp,
  starttimestamp = t.starttimestamp,
  endtimestamp = t.endtimestamp,
  `database` = t.`database`,
  ticket_process_datatime = t.process_datatime,
  load_date = DATETIME(CURRENT_TIMESTAMP(), 'America/Lima')
FROM tmp_tickets_late AS t
WHERE (e.`database` IS NULL OR TRIM(e.`database`) = '')
  AND COALESCE(e.source_file_name, e.file_name) = t.audio;

UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw` AS h
SET
  match_status = IF(h.gcs_uri IS NOT NULL, 'BOTH', h.match_status),
  audio = COALESCE(t.audio, h.audio),
  recordid = t.recordid,
  rowid = t.rowid,
  codagencia = t.codagencia,
  asesornombre = t.asesornombre,
  asesorusuario = t.asesorusuario,
  asesorcodigo = t.asesorcodigo,
  ndoc = t.ndoc,
  nombresusuario = t.nombresusuario,
  numcelular = t.numcelular,
  clientetipo = t.clientetipo,
  `database` = t.`database`
FROM tmp_tickets_late AS t
WHERE (h.`database` IS NULL OR TRIM(h.`database`) = '')
  AND COALESCE(h.source_file_name, h.file_name) = t.audio;

UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd` AS h
SET
  match_status = IF(h.gcs_uri IS NOT NULL, 'BOTH', h.match_status),
  audio = COALESCE(t.audio, h.audio),
  recordid = t.recordid,
  rowid = t.rowid,
  codagencia = t.codagencia,
  asesornombre = t.asesornombre,
  asesorusuario = t.asesorusuario,
  asesorcodigo = t.asesorcodigo,
  ndoc = t.ndoc,
  nombresusuario = t.nombresusuario,
  numcelular = t.numcelular,
  clientetipo = t.clientetipo,
  `database` = t.`database`
FROM tmp_tickets_late AS t
WHERE (h.`database` IS NULL OR TRIM(h.`database`) = '')
  AND COALESCE(h.source_file_name, h.file_name) = t.audio;

UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw` AS h
SET
  audio = COALESCE(t.audio, h.audio),
  recordid = t.recordid,
  rowid = t.rowid,
  codagencia = t.codagencia,
  asesornombre = t.asesornombre,
  asesorusuario = t.asesorusuario,
  asesorcodigo = t.asesorcodigo,
  ndoc = t.ndoc,
  nombresusuario = t.nombresusuario,
  numcelular = t.numcelular,
  clientetipo = t.clientetipo,
  `database` = t.`database`
FROM tmp_tickets_late AS t
WHERE (h.`database` IS NULL OR TRIM(h.`database`) = '')
  AND COALESCE(h.source_file_name, h.file_name) = t.audio;

UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd` AS h
SET
  audio = COALESCE(t.audio, h.audio),
  recordid = t.recordid,
  rowid = t.rowid,
  codagencia = t.codagencia,
  asesornombre = t.asesornombre,
  asesorusuario = t.asesorusuario,
  asesorcodigo = t.asesorcodigo,
  ndoc = t.ndoc,
  nombresusuario = t.nombresusuario,
  numcelular = t.numcelular,
  clientetipo = t.clientetipo,
  `database` = t.`database`
FROM tmp_tickets_late AS t
WHERE (h.`database` IS NULL OR TRIM(h.`database`) = '')
  AND COALESCE(h.source_file_name, h.file_name) = t.audio;

-- Después: los que siguen NULL no tenían ticket.audio coincidente
SELECT
  'enriched' AS tabla,
  COUNTIF(`database` IS NULL OR TRIM(`database`) = '') AS n_database_null
FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
UNION ALL
SELECT 'stt_raw', COUNTIF(`database` IS NULL OR TRIM(`database`) = '')
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
UNION ALL
SELECT 'stt_prd', COUNTIF(`database` IS NULL OR TRIM(`database`) = '')
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
UNION ALL
SELECT 'analisis_raw', COUNTIF(`database` IS NULL OR TRIM(`database`) = '')
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
UNION ALL
SELECT 'analisis_prd', COUNTIF(`database` IS NULL OR TRIM(`database`) = '')
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`;
