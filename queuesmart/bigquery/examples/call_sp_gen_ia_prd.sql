-- Pipeline Gen IA QueeSmart PRD (después de qs_s3_to_gcs)

DECLARE v_fecha DATE DEFAULT DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY);

-- 0) Candidatos enriched
SELECT
  process_day,
  match_status,
  COUNT(*) AS n
FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
WHERE process_day = v_fecha
GROUP BY 1, 2
ORDER BY 2;

-- 1) Consolidar (si aún no corrió)
CALL `prd-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_consolidate`(v_fecha);

-- 2) Etapa 1 + etapa 2
CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia`(v_fecha);

-- 3) Resultados transcripción
SELECT
  process_date,
  COUNT(*) AS n,
  COUNTIF(transcripcion IS NOT NULL) AS con_transcripcion,
  COUNTIF(recordid IS NOT NULL) AS con_ticket
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
WHERE process_date = v_fecha
GROUP BY 1;

-- 4) Resultados análisis (schema Canal_Admision_Output)
SELECT
  process_date,
  prompt_name,
  COUNT(*) AS n,
  COUNTIF(evaluacion_json IS NOT NULL) AS con_json,
  COUNTIF(saludo_marcacion IS NOT NULL) AS con_saludo,
  COUNTIF(tipificacion_segun_casuistica IS NOT NULL) AS con_tipificacion
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`
WHERE process_date = v_fecha
GROUP BY 1, 2;
