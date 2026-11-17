-- =============================================================================
-- Pipeline queuesmart_vaso — un día (manual BQ)
-- Preferido: Cloud Workflow queuesmart-vaso-pipeline (ver README).
--
-- Orden:
--   1) qs_s3_gap_vaso (gap_prepare + worker)  — fuera de BQ / Workflow
--   2) consolidate_vaso
--   3) qsmart_transcribe STT Chirp           — fuera de BQ / Workflow
--   4) analisis_ia_vaso
--
-- Cambiar v_fecha según el día a procesar.
-- =============================================================================

DECLARE v_fecha DATE DEFAULT DATE '2026-09-10';

-- 2) Consolidate: hist_queesmart_mp3_catalog_vaso
--    → queuesmart_mp3_catalog_vaso + queuesmart_mp3_enriched_vaso
CALL `prd-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_consolidate_vaso`(v_fecha);

-- 3) STT Chirp (Cloud Run qsmart_transcribe; el Workflow lo orquesta):
-- gcloud run jobs execute prd-utpbi-qsmart-transcribe \
--   --region=us-central1 --project=prd-utpbi-data-operation --tasks=1 \
--   --update-env-vars=QS_JOB_ROLE=prepare,SYNC_PROCESS_DATE=2026-09-10,QS_ENRICHED_TABLE=prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched_vaso,QS_HIST_RAW_TABLE=prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_whisper_vaso_raw,QS_HIST_PRD_TABLE=prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_whisper_vaso_prd,QS_MANIFEST_PREFIX=state/stt_manifests_vaso
-- # luego worker con tasks=N del meta

-- 4) Análisis Counter sobre STT vaso
CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_audio_analisis_ia_vaso`(
  v_fecha,
  NULL  -- canal_counter_prompt
);

-- Checks rápidos
SELECT 'catalog_vaso' AS etapa, COUNT(*) AS n
FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_catalog_vaso`
WHERE process_day = v_fecha
UNION ALL
SELECT 'enriched_vaso', COUNT(*)
FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched_vaso`
WHERE process_day = v_fecha AND gcs_uri IS NOT NULL
UNION ALL
SELECT 'stt_vaso_prd', COUNT(*)
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_whisper_vaso_prd`
WHERE process_date = v_fecha
UNION ALL
SELECT 'analisis_vaso_prd', COUNT(*)
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_vaso_prd`
WHERE process_date = v_fecha;
