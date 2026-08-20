-- =============================================================================
-- SP: Genesys Admisión — capa PRD (después de todos los lotes)
--
-- CALL:
--   CALL `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_do_ia_speech_admision_prd`(
--     DATE '2026-08-18'
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_do_ia_speech_admision_prd`(
  v_fecha_proceso DATE
)
BEGIN
  SET @@query_label = 'pipeline:genesys_admision,sp:do_ia_prd';

  DELETE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd_admision`
  WHERE process_date = v_fecha_proceso;

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd_admision`
  SELECT
    pecuf.process_date,
    pecuf.conversation_id,
    pecuf.uri,
    pecuf.agentes,
    pecuf.agentes_ids,
    pecuf.json_text AS json_text_pecuf,
    pecuf.full_response AS full_response_pecuf,
    pecuf.status AS status_pecuf,
    pecneg.json_text AS json_text_pecneg,
    pecneg.full_response AS full_response_pecneg,
    pecneg.status AS status_pecneg,
    COALESCE(pecuf.tipo_contacto, pecneg.tipo_contacto) AS tipo_contacto,
    COALESCE(pecuf.gestion_principal, pecneg.gestion_principal) AS gestion_principal,
    pecuf.saludo_descripcion,
    pecuf.saludo_marcacion,
    pecuf.despedida_descripcion,
    pecuf.despedida_marcacion,
    pecuf.aclara_duda_cliente_descripcion,
    pecuf.aclara_duda_cliente_marcacion,
    pecuf.presenta_vacio_descripcion,
    pecuf.presenta_vacio_marcacion,
    pecuf.deja_en_espera_descripcion,
    pecuf.deja_en_espera_marcacion,
    pecuf.empatia_descripcion,
    pecuf.empatia_marcacion,
    pecuf.actitud_comercial_descripcion,
    pecuf.actitud_comercial_marcacion,
    pecuf.lenguaje_grosero_descripcion,
    pecuf.lenguaje_grosero_marcacion,
    pecneg.sigue_flujo_gestion_descripcion,
    pecneg.sigue_flujo_gestion_marcacion,
    pecneg.brinda_informacion_correcta_descripcion,
    pecneg.brinda_informacion_correcta_marcacion,
    pecneg.ofrece_qr_descripcion,
    pecneg.ofrece_qr_marcacion,
    pecneg.valida_datos_postulante_descripcion,
    pecneg.valida_datos_postulante_marcacion,
    pecneg.sondea_interes_postulante_descripcion,
    pecneg.sondea_interes_postulante_marcacion,
    pecneg.rebate_descripcion,
    pecneg.rebate_marcacion,
    pecneg.rebate_efectivo_descripcion,
    pecneg.rebate_efectivo_marcacion,
    pecneg.cierre_comercial_descripcion,
    pecneg.cierre_comercial_marcacion,
    pecneg.sentido_urgencia_descripcion,
    pecneg.sentido_urgencia_marcacion,
    pecneg.responsabilidad_no_conversion,
    pecneg.motivo_no_conversion,
    pecneg.afecta_imagen_negocio_descripcion,
    pecneg.afecta_imagen_negocio_marcacion,
    pecneg.objecion_cliente_1_descripcion,
    pecneg.gestion_objecion_1_descripcion,
    pecneg.objecion_cliente_2_descripcion,
    pecneg.gestion_objecion_2_descripcion,
    pecneg.objecion_cliente_3_descripcion,
    pecneg.gestion_objecion_3_descripcion,
    pecneg.tipificacion_segun_casuistica,
    pecneg.carreras_interes,
    pecneg.resultado_final_llamada,
    pecneg.conclusion_final_llamada,
    pecuf.resumen_evaluacion_pecuf,
    pecneg.resumen_evaluacion_pecneg,
    pecneg.submotivo_no_conversion,
    pecuf.conclusion_codigos,
    pecuf.conclusion_nombres,
    pecneg.conclusion_nombres_ia,
    CASE
      WHEN UPPER(TRIM(pecuf.conclusion_nombres)) = UPPER(TRIM(pecneg.conclusion_nombres_ia))
      THEN '1'
      ELSE '0'
    END AS tipificacion_marcacion
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_pecuf` AS pecuf
  INNER JOIN `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_pecneg` AS pecneg
    ON pecuf.conversation_id = pecneg.conversation_id
   AND pecuf.process_date = pecneg.process_date
  WHERE pecuf.process_date = v_fecha_proceso
    AND pecneg.process_date = v_fecha_proceso;
END;
