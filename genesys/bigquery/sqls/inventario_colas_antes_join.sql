-- =============================================================================
-- Inventario de colas ANTES de joins CRM / end_processing (Tramo 2 / Speech)
-- Fuente cruda: genesys_audios_descarga_admision_raw
-- Sirve para confirmar cola_id faltantes a incorporar en el SP.
-- Location: US
-- =============================================================================

DECLARE d0 DATE DEFAULT DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 30 DAY);
DECLARE d1 DATE DEFAULT CURRENT_DATE('America/Lima');

-- Cola_ids ya incluidos en sp_utpbi_genesys_end_processing_admision_v2
-- (actualizar si el SP cambia)
CREATE TEMP TABLE tmp_colas_en_sp AS
SELECT cola_id FROM UNNEST([
  'ab0ae2ce-fa4b-413a-a45c-890c944fd143|e8c46f19-b9cb-4481-8a9a-e832c4fcf55e', -- ADA_CENTRAL|IN_CENTRAL
  '670c24d1-8145-48df-a691-2cc58383f43b', -- ADA_CENTRAL
  'ab0ae2ce-fa4b-413a-a45c-890c944fd143', -- ADA_CENTRAL saliente
  'c02c8cea-daf9-4198-81fa-c8cc97aeb023', -- ADA_MATRICULA
  '13b6658f-6152-4310-a810-cdaa2f4d3a75', -- ADA_CENTRAL_EXAMEN
  'c22a3757-44f7-494e-9cf5-bd2ef3dceb5a', -- ADA_CENTRAL_EXAMEN_SALIENTE
  '5fa39d89-8a30-423b-b146-bf69b4767248', -- ADA_CENTRAL_CONVALIDACION
  'c74c8e42-4596-418b-9e44-4dde730c0270'  -- ADA_CENTRAL_CONVALIDACION_SALIENTE
]) AS cola_id;

-- 1) Universo real de colas en descarga admisión (sin joins)
SELECT
  d.cola_nombre,
  d.cola_id,
  COUNT(*) AS n_audios,
  COUNT(DISTINCT d.conversation_id) AS n_conversations,
  MIN(d.fecha_descarga) AS primera_fecha,
  MAX(d.fecha_descarga) AS ultima_fecha,
  IF(sp.cola_id IS NULL, 'FALTA_EN_SP', 'EN_SP') AS estado_sp
FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_admision_raw` AS d
LEFT JOIN tmp_colas_en_sp AS sp
  ON d.cola_id = sp.cola_id
WHERE d.fecha_descarga BETWEEN d0 AND d1
GROUP BY 1, 2, 7
ORDER BY n_audios DESC;

-- 2) Solo las que NO están en el filtro del SP (candidatas a incorporar)
SELECT
  d.cola_nombre,
  d.cola_id,
  COUNT(*) AS n_audios,
  MAX(d.fecha_descarga) AS ultima_fecha
FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_admision_raw` AS d
LEFT JOIN tmp_colas_en_sp AS sp
  ON d.cola_id = sp.cola_id
WHERE d.fecha_descarga BETWEEN d0 AND d1
  AND sp.cola_id IS NULL
GROUP BY 1, 2
ORDER BY n_audios DESC;

-- 3) CRM genérico (hablado / otras colas) — también sin joins
SELECT
  cola_nombre,
  cola_id,
  COUNT(*) AS n,
  MAX(fecha_descarga) AS ultima_fecha
FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw`
WHERE fecha_descarga BETWEEN d0 AND d1
GROUP BY 1, 2
ORDER BY n DESC;
