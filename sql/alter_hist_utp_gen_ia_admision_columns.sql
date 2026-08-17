-- =============================================================================
-- ALTER — columnas nuevas Gen IA Admisión (PECUF / PECNEG / PRD)
--
-- Proyecto:  prd-utpbi-data-operation
-- Dataset:   adf_speech_analytics  (location US)
-- Idempotente: ADD COLUMN IF NOT EXISTS (se puede re-ejecutar sin error)
--
-- bq query --use_legacy_sql=false --location=US \
--   --project_id=prd-utpbi-data-operation \
--   < sql/alter_hist_utp_gen_ia_admision_columns.sql
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RAW — Admisión PECUF
-- ---------------------------------------------------------------------------
ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_pecuf`
  ADD COLUMN IF NOT EXISTS conclusion_codigos STRING,
  ADD COLUMN IF NOT EXISTS conclusion_nombres STRING;

-- ---------------------------------------------------------------------------
-- RAW — Admisión PECNEG
-- ---------------------------------------------------------------------------
ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_pecneg`
  ADD COLUMN IF NOT EXISTS submotivo_no_conversion STRING,
  ADD COLUMN IF NOT EXISTS conclusion_codigos STRING,
  ADD COLUMN IF NOT EXISTS conclusion_nombres STRING,
  ADD COLUMN IF NOT EXISTS codigo_tipificacion STRING,
  ADD COLUMN IF NOT EXISTS nombre_tipificacion STRING,
  ADD COLUMN IF NOT EXISTS conclusion_nombres_ia STRING;

-- ---------------------------------------------------------------------------
-- PRD — Admisión
-- ---------------------------------------------------------------------------
ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd_admision`
  ADD COLUMN IF NOT EXISTS submotivo_no_conversion STRING,
  ADD COLUMN IF NOT EXISTS conclusion_codigos STRING,
  ADD COLUMN IF NOT EXISTS conclusion_nombres STRING,
  ADD COLUMN IF NOT EXISTS conclusion_nombres_ia STRING,
  ADD COLUMN IF NOT EXISTS tipificacion_marcacion STRING;
