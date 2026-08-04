-- PRD: ejecutar en BigQuery con región US (mismo dataset del SP)
-- Orquestación recomendada: Cloud Workflows (onemarketer/docs/guia-workflow.txt)
--
-- Etapa 1 sola (STT por lotes; ya NO llama etapa 2):
CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_whatsapp_gen_ia`(
  DATE '2026-06-22'
);

-- Etapa 2 sola (Gemini / canal_escrito_prompt):
CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_caso_conversacion_ia`(
  DATE '2026-06-22',
  NULL
);
