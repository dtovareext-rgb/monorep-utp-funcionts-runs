-- Corrida manual día completo SA-125
-- Location: US | Proyecto: prd-utpbi-data-operation
--
-- 1) Conteo 02 y 03
-- 2) CALL día 2026-11-02 (lote 20)
-- 3) Verificación

-- ---------------------------------------------------------------------------
-- Conteo candidatos
-- ---------------------------------------------------------------------------
SELECT
  fecha_descarga,
  COUNT(*) AS n
FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_serialize_markov`
WHERE fecha_descarga IN (DATE '2026-11-02', DATE '2026-11-03')
  AND uri IS NOT NULL
  AND NULLIF(TRIM(serialized_level_1), '') IS NOT NULL
GROUP BY fecha_descarga
ORDER BY fecha_descarga;

-- ---------------------------------------------------------------------------
-- Día completo (cambiar fecha si prefieres 2026-11-03)
-- ---------------------------------------------------------------------------
CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_run_day`(
  DATE '2026-11-02',
  20
);

-- ---------------------------------------------------------------------------
-- Verificación
-- ---------------------------------------------------------------------------
SELECT
  COUNT(*) AS n_prd,
  COUNTIF(calidad_transcripcion IS NOT NULL) AS con_calidad,
  COUNTIF(estado_lead IS NOT NULL) AS con_estado
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_prd`
WHERE process_date = DATE '2026-11-02';

SELECT
  calidad_transcripcion,
  estado_lead,
  resultado_real,
  zona_interes,
  crm_conversation_id,
  crm_cola_nombre
FROM `prd-utpbi-data-operation.adf_speech_analytics.v_speech_analytics_125_crm`
WHERE process_date = DATE '2026-11-02'
LIMIT 10;
