-- Reproceso Gemini — UN DÍA (solo etapa 2, no STT)
--
-- Cambia solo la fecha en --parameter=fecha:DATE:...
--
--   bq query --use_legacy_sql=false --location=US \
--     --project_id=prd-utpbi-data-operation \
--     --parameter=fecha:DATE:2026-08-17 \
--     < reprocess_gemini_por_fecha_call.sql

CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_audio_analisis_ia`(
  @fecha,
  NULL
);
