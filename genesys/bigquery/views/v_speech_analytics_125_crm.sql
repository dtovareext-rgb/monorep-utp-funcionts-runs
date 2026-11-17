-- Vista entrega: insights 125 + CRM Genesys + transcripción Markov
-- contact_id CRM = LeadID (mismo uso que sp_utpbi_genesys_end_processing_admision_v2)
CREATE OR REPLACE VIEW `prd-utpbi-data-operation.adf_speech_analytics.v_speech_analytics_125_crm` AS
SELECT
  p.*,
  c.gcs_audio_path,
  c.cola_nombre AS crm_cola_nombre,
  c.conversation_id AS crm_conversation_id,
  c.contact_id AS crm_contact_id,
  s.serialized_level_1 AS transcripcion
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_prd` AS p
LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw` AS c
  ON p.uri = c.gcs_audio_path
LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_serialize_markov` AS s
  ON p.uri = s.uri
 AND p.fecha_descarga = s.fecha_descarga;
