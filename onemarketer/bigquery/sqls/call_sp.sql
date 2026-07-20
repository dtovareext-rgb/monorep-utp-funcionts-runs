-- PRD: ejecutar en BigQuery con región US (mismo dataset del SP)
-- Antes: desplegar tablas hist + vista + SPs (ver deploy/prd_gen_ia.sql)
-- Un CALL ejecuta etapa 1 (audios) + etapa 2 (conversación / canal_escrito_prompt)

CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_whatsapp_gen_ia`(
  DATE '2026-06-22'
);

-- Solo etapa 2 (re-analizar conversaciones sin re-transcribir):
-- CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_caso_conversacion_ia`(DATE '2026-06-22', NULL);
