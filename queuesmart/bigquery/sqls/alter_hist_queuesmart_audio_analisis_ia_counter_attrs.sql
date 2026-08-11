-- =============================================================================
-- ALTER hist QueeSmart audio análisis — subatributos Counter
-- Idempotente. location=US
--
-- bq query --use_legacy_sql=false --location=US \
--   --project_id=prd-utpbi-data-operation \
--   < queuesmart/bigquery/sqls/alter_hist_queuesmart_audio_analisis_ia_counter_attrs.sql
-- =============================================================================

ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
  ADD COLUMN IF NOT EXISTS tono_sarcastico_despectivo_marcacion STRING,
  ADD COLUMN IF NOT EXISTS tono_sarcastico_despectivo_descripcion STRING,
  ADD COLUMN IF NOT EXISTS confronta_prospecto_marcacion STRING,
  ADD COLUMN IF NOT EXISTS confronta_prospecto_descripcion STRING,
  ADD COLUMN IF NOT EXISTS tono_seguridad_marcacion STRING,
  ADD COLUMN IF NOT EXISTS tono_seguridad_descripcion STRING,
  ADD COLUMN IF NOT EXISTS escucha_activa_marcacion STRING,
  ADD COLUMN IF NOT EXISTS escucha_activa_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_seguro_estudiantil_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_seguro_estudiantil_descripcion STRING,
  ADD COLUMN IF NOT EXISTS plazo_entrega_documentos_marcacion STRING,
  ADD COLUMN IF NOT EXISTS plazo_entrega_documentos_descripcion STRING,
  ADD COLUMN IF NOT EXISTS plazo_pago_matricula_marcacion STRING,
  ADD COLUMN IF NOT EXISTS plazo_pago_matricula_descripcion STRING,
  ADD COLUMN IF NOT EXISTS otros_beneficios_marcacion STRING,
  ADD COLUMN IF NOT EXISTS otros_beneficios_descripcion STRING,
  ADD COLUMN IF NOT EXISTS sondeo_motivacion_marcacion STRING,
  ADD COLUMN IF NOT EXISTS sondeo_motivacion_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_completa_sondeo_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_completa_sondeo_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_becas_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_becas_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_descuentos_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_descuentos_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_convenios_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_convenios_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_convalidacion_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_convalidacion_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_carrera_campus_modalidad_turnos_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_carrera_campus_modalidad_turnos_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_inversion_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_inversion_descripcion STRING,
  ADD COLUMN IF NOT EXISTS pre_cierre_marcacion STRING,
  ADD COLUMN IF NOT EXISTS pre_cierre_descripcion STRING,
  ADD COLUMN IF NOT EXISTS resumen_venta_marcacion STRING,
  ADD COLUMN IF NOT EXISTS resumen_venta_descripcion STRING,
  ADD COLUMN IF NOT EXISTS informacion_falsa_marcacion STRING,
  ADD COLUMN IF NOT EXISTS informacion_falsa_descripcion STRING;

ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`
  ADD COLUMN IF NOT EXISTS tono_sarcastico_despectivo_marcacion STRING,
  ADD COLUMN IF NOT EXISTS tono_sarcastico_despectivo_descripcion STRING,
  ADD COLUMN IF NOT EXISTS confronta_prospecto_marcacion STRING,
  ADD COLUMN IF NOT EXISTS confronta_prospecto_descripcion STRING,
  ADD COLUMN IF NOT EXISTS tono_seguridad_marcacion STRING,
  ADD COLUMN IF NOT EXISTS tono_seguridad_descripcion STRING,
  ADD COLUMN IF NOT EXISTS escucha_activa_marcacion STRING,
  ADD COLUMN IF NOT EXISTS escucha_activa_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_seguro_estudiantil_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_seguro_estudiantil_descripcion STRING,
  ADD COLUMN IF NOT EXISTS plazo_entrega_documentos_marcacion STRING,
  ADD COLUMN IF NOT EXISTS plazo_entrega_documentos_descripcion STRING,
  ADD COLUMN IF NOT EXISTS plazo_pago_matricula_marcacion STRING,
  ADD COLUMN IF NOT EXISTS plazo_pago_matricula_descripcion STRING,
  ADD COLUMN IF NOT EXISTS otros_beneficios_marcacion STRING,
  ADD COLUMN IF NOT EXISTS otros_beneficios_descripcion STRING,
  ADD COLUMN IF NOT EXISTS sondeo_motivacion_marcacion STRING,
  ADD COLUMN IF NOT EXISTS sondeo_motivacion_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_completa_sondeo_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_completa_sondeo_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_becas_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_becas_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_descuentos_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_descuentos_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_convenios_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_convenios_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_convalidacion_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_convalidacion_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_carrera_campus_modalidad_turnos_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_carrera_campus_modalidad_turnos_descripcion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_inversion_marcacion STRING,
  ADD COLUMN IF NOT EXISTS info_correcta_inversion_descripcion STRING,
  ADD COLUMN IF NOT EXISTS pre_cierre_marcacion STRING,
  ADD COLUMN IF NOT EXISTS pre_cierre_descripcion STRING,
  ADD COLUMN IF NOT EXISTS resumen_venta_marcacion STRING,
  ADD COLUMN IF NOT EXISTS resumen_venta_descripcion STRING,
  ADD COLUMN IF NOT EXISTS informacion_falsa_marcacion STRING,
  ADD COLUMN IF NOT EXISTS informacion_falsa_descripcion STRING;

-- ---------------------------------------------------------------------------
-- DROP columnas Admisión no usadas en pauta Counter (ruido para el usuario)
-- ---------------------------------------------------------------------------

ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
  DROP COLUMN IF EXISTS empatia_marcacion,
  DROP COLUMN IF EXISTS empatia_descripcion,
  DROP COLUMN IF EXISTS actitud_comercial_marcacion,
  DROP COLUMN IF EXISTS actitud_comercial_descripcion,
  DROP COLUMN IF EXISTS sigue_flujo_gestion_marcacion,
  DROP COLUMN IF EXISTS sigue_flujo_gestion_descripcion,
  DROP COLUMN IF EXISTS ofrece_qr_marcacion,
  DROP COLUMN IF EXISTS ofrece_qr_descripcion,
  DROP COLUMN IF EXISTS valida_datos_postulante_marcacion,
  DROP COLUMN IF EXISTS valida_datos_postulante_descripcion,
  DROP COLUMN IF EXISTS t_ofrece_qr;

ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`
  DROP COLUMN IF EXISTS empatia_marcacion,
  DROP COLUMN IF EXISTS empatia_descripcion,
  DROP COLUMN IF EXISTS actitud_comercial_marcacion,
  DROP COLUMN IF EXISTS actitud_comercial_descripcion,
  DROP COLUMN IF EXISTS sigue_flujo_gestion_marcacion,
  DROP COLUMN IF EXISTS sigue_flujo_gestion_descripcion,
  DROP COLUMN IF EXISTS ofrece_qr_marcacion,
  DROP COLUMN IF EXISTS ofrece_qr_descripcion,
  DROP COLUMN IF EXISTS valida_datos_postulante_marcacion,
  DROP COLUMN IF EXISTS valida_datos_postulante_descripcion,
  DROP COLUMN IF EXISTS t_ofrece_qr;
