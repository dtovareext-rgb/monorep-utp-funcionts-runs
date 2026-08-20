-- =============================================================================
-- SP: Genesys Admisión — limpia hist IA del día (una vez, antes de los lotes)
--
-- No toca genesys_audios_admision_prompt_raw ni descarga_crm (eso es end_processing).
-- Tampoco arma PRD: eso es sp_utpbi_do_ia_speech_admision_prd al final del workflow.
--
-- CALL:
--   CALL `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_do_ia_speech_admision_init`(
--     DATE '2026-08-18'
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_do_ia_speech_admision_init`(
  v_fecha_proceso DATE
)
BEGIN
  SET @@query_label = 'pipeline:genesys_admision,sp:do_ia_init';

  DELETE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_clasif`
  WHERE process_date = v_fecha_proceso;

  DELETE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_pecuf`
  WHERE process_date = v_fecha_proceso;

  DELETE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_pecneg`
  WHERE process_date = v_fecha_proceso;

  DELETE FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw_pecuf`
  WHERE fecha_descarga = v_fecha_proceso;

  DELETE FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw_pecneg`
  WHERE fecha_descarga = v_fecha_proceso;
END;
