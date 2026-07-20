-- Validar cruce MP3 GCS ↔ tickets_hist_raw y Gen IA

-- 1) Match status enriched
SELECT
  process_day,
  match_status,
  COUNT(*) AS n
FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
WHERE process_day >= DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 7 DAY)
GROUP BY 1, 2
ORDER BY 1 DESC, 2;

-- 2) BOTH listos para IA
SELECT
  process_day,
  gcs_uri,
  file_name,
  source_file_name,
  audio,
  recordid,
  asesornombre
FROM `prd-utpbi-data-operation.raw_queue_smart.v_queuesmart_mp3_ia_input`
WHERE process_day = DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY)
  AND match_status = 'BOTH'
LIMIT 20;

-- 3) Tickets sin audio en GCS
SELECT audio, recordid, asesornombre, numcelular
FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
WHERE match_status = 'TICKET_ONLY'
  AND process_day >= DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 3 DAY)
LIMIT 20;

-- 4) Prompt etapa 2
SELECT
  prompt_name,
  updated_at,
  LENGTH(prompt_text) AS chars,
  STRPOS(prompt_text, 'saludo_marcacion') > 0 AS tiene_formato_salida,
  STRPOS(prompt_text, '{{transcripcion}}') > 0 AS tiene_placeholder
FROM `prd-utpbi-data-operation.raw_queue_smart.sys_prompts`
WHERE prompt_name = 'canal_counter_prompt';
