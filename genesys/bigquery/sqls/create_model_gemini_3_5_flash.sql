-- Remote model Gemini 3.5 Flash (BQ ML) — PRODUCCIÓN
-- Dataset adf_speech_analytics está en US (multi-región); requerido por gemini-3.5-flash.
--
-- Ejecutar ANTES de redeployar los SPs que apuntan a gemini-3-5-flash:
--   bq query --use_legacy_sql=false --location=US \
--     --project_id=prd-utpbi-data-operation \
--     < genesys/bigquery/sqls/create_model_gemini_3_5_flash.sql
--
-- Endpoint Vertex: gemini-3.5-flash
-- Objeto BQ:      gemini-3-5-flash  (misma convención que gemini-2-5-flash)

CREATE OR REPLACE MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-3-5-flash`
REMOTE WITH CONNECTION `prd-utpbi-data-operation.US.utp_gen_ia_process`
OPTIONS (ENDPOINT = 'gemini-3.5-flash');
