-- =============================================================================
-- PATCH canal_counter_prompt v8_slim
-- Rebate efectivo: alinear argumentos/alternativas al sondeo de motivación
-- Fuente: prompts/canal_counter_prompt_v8_slim.txt (línea rebate efectivo)
--
-- Ejecutar:
--   bq query --use_legacy_sql=false --location=us-central1 \
--     --project_id=prd-utpbi-data-operation \
--     < update_sys_prompts_canal_counter_8_rebate_sondeo.sql
-- =============================================================================

UPDATE `prd-utpbi-data-operation.raw_queue_smart.sys_prompts`
SET
  prompt_text = REPLACE(
    prompt_text,
    'Presenta argumentos, alternativas o soluciones alineadas a la necesidad del prospecto.',
    'Presenta argumentos, alternativas o soluciones alineadas a la necesidad del prospecto de acuerdo al sondeo de motivación.'
  ),
  updated_at = CURRENT_TIMESTAMP()
WHERE prompt_name = 'canal_counter_prompt'
  AND STRPOS(
    prompt_text,
    'Presenta argumentos, alternativas o soluciones alineadas a la necesidad del prospecto.'
  ) > 0
  AND STRPOS(
    prompt_text,
    'Presenta argumentos, alternativas o soluciones alineadas a la necesidad del prospecto de acuerdo al sondeo de motivación.'
  ) = 0;

SELECT
  prompt_name,
  updated_at,
  LENGTH(prompt_text) AS chars,
  STRPOS(
    prompt_text,
    'Presenta argumentos, alternativas o soluciones alineadas a la necesidad del prospecto de acuerdo al sondeo de motivación.'
  ) > 0 AS rebate_alineado_sondeo
FROM `prd-utpbi-data-operation.raw_queue_smart.sys_prompts`
WHERE prompt_name = 'canal_counter_prompt';
