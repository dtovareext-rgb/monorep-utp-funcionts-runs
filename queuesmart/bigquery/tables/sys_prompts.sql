-- Catálogo de prompts Gen IA QueeSmart — PRODUCCIÓN
-- Dataset: prd-utpbi-data-operation.raw_queue_smart (US)
--
-- bq query --use_legacy_sql=false --location=US \
--   < queuesmart/bigquery/tables/sys_prompts.sql
--
-- Luego cargar el prompt Counter:
--   bq query --use_legacy_sql=false --location=US \
--     < queuesmart/bigquery/sqls/update_sys_prompts_canal_counter.sql

CREATE TABLE IF NOT EXISTS `prd-utpbi-data-operation.raw_queue_smart.sys_prompts` (
  prompt_name STRING NOT NULL,
  prompt_text STRING NOT NULL,
  updated_at TIMESTAMP NOT NULL
)
OPTIONS (
  description = 'Catálogo de system prompts Gen IA QueeSmart (p.ej. canal_counter_prompt)'
);
