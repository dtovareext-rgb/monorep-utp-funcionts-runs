-- Hallazgo: no existe firstagentwrapup. Equivalente en CRM:
--   genesys_audios_descarga_crm_raw.conclusion_nombres  (label wrapup)
--   genesys_audios_descarga_crm_raw.tipificacion         (familia homologada)
-- Flatten usa COALESCE(c.conclusion_nombres, a.conclusion_nombres, c.tipificacion, ...)

-- Cobertura tipificación CRM vs sample SA-125 (ajusta fecha):
SELECT
  COUNT(*) AS flat_candidatos,
  COUNTIF(NULLIF(TRIM(c.conclusion_nombres), '') IS NOT NULL) AS crm_con_conclusion_nombres,
  COUNTIF(NULLIF(TRIM(c.tipificacion), '') IS NOT NULL) AS crm_con_tipificacion,
  COUNTIF(NULLIF(TRIM(c.conclusion_codigos), '') IS NOT NULL) AS crm_con_conclusion_codigos
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_prd` AS p
LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw` AS c
  ON p.uri = c.gcs_audio_path
WHERE p.process_date = DATE '2026-11-18';
