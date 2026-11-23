-- =============================================================================
-- Diagnóstico: colas pedidas vs presencia en BQ Genesys / Speech Analytics
-- Location: US | Proyecto: prd-utpbi-data-operation
-- Ajusta el rango de fechas si hace falta.
-- =============================================================================

DECLARE d0 DATE DEFAULT DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 14 DAY);
DECLARE d1 DATE DEFAULT CURRENT_DATE('America/Lima');

CREATE TEMP TABLE tmp_colas_solicitadas AS
SELECT cola_nombre FROM UNNEST([
  -- Voz / Prospección
  'ANeutros_1A7_Hablados',
  'ANeutros_8A15_Hablados',
  'Neutros_Enriquecida',
  'Hablados_Respaldo',
  'Hablados_UCI',
  'Nacional General 2027',
  'Nacional Mixta',
  'Nacional Prioridad 2027',
  'Nacional Top 2027',
  'Nacional UCI',
  'NacionalNS',
  -- Admisión
  'ADA_CENTRAL',
  'ADA_CENTRAL_CONVALIDACION',
  'ADA_CENTRAL_EXAMEN',
  'ADA_CENTRAL_MEDICINA',
  'ADA_EVENTOS_CENTRAL',
  'ADA_EVENTOS_CONVALIDACION',
  'ADA_EVENTOS_EXAMEN',
  'ADA_NACIONAL',
  -- Escritos
  'WAE DIGITAL',
  'Gupshup conversaciones',
  'Escritos_Mixta',
  'WAE_C2C',
  'WAEINCOMPLETOFACE',
  'WAE_NEUTROS_3_CDE'
]) AS cola_nombre;

-- 1) CRM / descarga (dónde nace cola_nombre)
SELECT
  s.cola_nombre,
  COUNTIF(c.cola_nombre IS NOT NULL) AS n_crm_14d,
  COUNT(DISTINCT c.cola_id) AS n_cola_id,
  ANY_VALUE(c.cola_id) AS ejemplo_cola_id,
  MAX(c.fecha_descarga) AS ultima_fecha_crm
FROM tmp_colas_solicitadas s
LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw` c
  ON c.cola_nombre = s.cola_nombre
 AND c.fecha_descarga BETWEEN d0 AND d1
GROUP BY 1
ORDER BY n_crm_14d DESC, s.cola_nombre;

-- 2) Prompt raw (entrada Speech / Gen IA hablado)
SELECT
  s.cola_nombre,
  COUNTIF(p.cola_nombre IS NOT NULL) AS n_prompt_14d,
  MAX(p.fecha_descarga) AS ultima_fecha_prompt
FROM tmp_colas_solicitadas s
LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_prompt_raw` p
  ON p.cola_nombre = s.cola_nombre
 AND p.fecha_descarga BETWEEN d0 AND d1
GROUP BY 1
ORDER BY n_prompt_14d DESC, s.cola_nombre;

-- 3) Evaluaciones finales (si la tabla tiene cola_nombre; si no, comentar)
-- SELECT
--   s.cola_nombre,
--   COUNT(*) AS n_eval
-- FROM tmp_colas_solicitadas s
-- LEFT JOIN `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd` e
--   ON e.cola_nombre = s.cola_nombre
--  AND e.process_date BETWEEN d0 AND d1
-- GROUP BY 1;

-- 4) Colas ADA presentes en descarga_admision pero filtradas por end_processing
--    (SP actual solo deja 4 cola_id fijos)
SELECT
  d.cola_nombre,
  d.cola_id,
  COUNT(*) AS n
FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_admision_raw` d
WHERE d.fecha_descarga BETWEEN d0 AND d1
  AND (
    d.cola_nombre LIKE 'ADA_%'
    OR d.cola_nombre IN (
      'ADA_CENTRAL', 'ADA_CENTRAL_CONVALIDACION', 'ADA_CENTRAL_EXAMEN',
      'ADA_CENTRAL_MEDICINA', 'ADA_EVENTOS_CENTRAL', 'ADA_EVENTOS_CONVALIDACION',
      'ADA_EVENTOS_EXAMEN', 'ADA_NACIONAL'
    )
  )
GROUP BY 1, 2
ORDER BY n DESC;

-- 5) Inventario real de colas en CRM últimos 14d (para ver nombres exactos / typos)
SELECT cola_nombre, COUNT(*) AS n
FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw`
WHERE fecha_descarga BETWEEN d0 AND d1
GROUP BY 1
ORDER BY n DESC;
