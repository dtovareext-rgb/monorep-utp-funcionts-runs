-- =============================================================================
-- Diagnóstico colas mail Speech Analytics (Paul / TI)
-- Lista pedida vs:
--   1) descarga (admision + CRM) → cola_id
--   2) prompt_raw (entrada Gen IA hablado)
--   3) hist evaluaciones
-- Location: US
-- =============================================================================

DECLARE d0 DATE DEFAULT DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 30 DAY);
DECLARE d1 DATE DEFAULT CURRENT_DATE('America/Lima');

CREATE TEMP TABLE tmp_mail AS
SELECT canal, cola_nombre FROM UNNEST([
  STRUCT('Voz' AS canal, 'ANeutros_1A7_Hablados' AS cola_nombre),
  ('Voz', 'ANeutros_8A15_Hablados'),
  ('Voz', 'Neutros_Enriquecida'),
  ('Voz', 'Hablados_Respaldo'),
  ('Voz', 'Hablados_UCI'),
  ('Voz', 'Nacional General 2027'),
  ('Voz', 'Nacional Mixta'),
  ('Voz', 'Nacional Prioridad 2027'),
  ('Voz', 'Nacional Top 2027'),
  ('Voz', 'Nacional UCI'),
  ('Voz', 'NacionalNS'),
  ('Admision', 'ADA_CENTRAL'),
  ('Admision', 'ADA_CENTRAL_CONVALIDACION'),
  ('Admision', 'ADA_CENTRAL_EXAMEN'),
  ('Admision', 'ADA_CENTRAL_MEDICINA'),
  ('Admision', 'ADA_EVENTOS_CENTRAL'),
  ('Admision', 'ADA_EVENTOS_CONVALIDACION'),
  ('Admision', 'ADA_EVENTOS_EXAMEN'),
  ('Admision', 'ADA_NACIONAL'),
  ('Escritos', 'WAE DIGITAL'),
  ('Escritos', 'Gupshup conversaciones'),
  ('Escritos', 'Escritos_Mixta'),
  ('Escritos', 'WAE_C2C'),
  ('Escritos', 'WAEINCOMPLETOFACE'),
  ('Escritos', 'WAE_NEUTROS_3_CDE')
]);

-- Cola_ids ya en end_processing_admision_v2 (repo)
CREATE TEMP TABLE tmp_sp_admision AS
SELECT cola_id FROM UNNEST([
  'ab0ae2ce-fa4b-413a-a45c-890c944fd143|e8c46f19-b9cb-4481-8a9a-e832c4fcf55e',
  '670c24d1-8145-48df-a691-2cc58383f43b',
  'ab0ae2ce-fa4b-413a-a45c-890c944fd143',
  'c02c8cea-daf9-4198-81fa-c8cc97aeb023',
  '13b6658f-6152-4310-a810-cdaa2f4d3a75',
  'c22a3757-44f7-494e-9cf5-bd2ef3dceb5a',
  '5fa39d89-8a30-423b-b146-bf69b4767248',
  'c74c8e42-4596-418b-9e44-4dde730c0270'
]) AS cola_id;

-- Resumen 1 fila por cola del mail
WITH adm AS (
  SELECT
    cola_nombre,
    ANY_VALUE(cola_id) AS cola_id,
    COUNT(*) AS n_admision
  FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_admision_raw`
  WHERE fecha_descarga BETWEEN d0 AND d1
  GROUP BY 1
),
crm AS (
  SELECT
    cola_nombre,
    ANY_VALUE(cola_id) AS cola_id,
    COUNT(*) AS n_crm
  FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw`
  WHERE fecha_descarga BETWEEN d0 AND d1
  GROUP BY 1
),
prompt AS (
  SELECT cola_nombre, COUNT(*) AS n_prompt
  FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_prompt_raw`
  WHERE fecha_descarga BETWEEN d0 AND d1
  GROUP BY 1
),
eval AS (
  SELECT cola_nombre, COUNT(*) AS n_eval
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd`
  WHERE process_date BETWEEN d0 AND d1
  GROUP BY 1
)
SELECT
  m.canal,
  m.cola_nombre,
  COALESCE(a.cola_id, c.cola_id) AS cola_id,
  IFNULL(a.n_admision, 0) AS n_admision_30d,
  IFNULL(c.n_crm, 0) AS n_crm_30d,
  IFNULL(p.n_prompt, 0) AS n_prompt_30d,
  IFNULL(e.n_eval, 0) AS n_eval_30d,
  CASE
    WHEN sp.cola_id IS NOT NULL THEN 'EN_SP_ADMISION'
    WHEN COALESCE(a.cola_id, c.cola_id) IS NULL THEN 'SIN_DATO_DESCARGA'
    WHEN m.canal = 'Admision' THEN 'FALTA_COLA_ID_EN_SP'
    WHEN m.canal = 'Voz' AND IFNULL(p.n_prompt, 0) > 0 THEN 'VOZ_YA_EN_PROMPT'
    WHEN m.canal = 'Voz' AND IFNULL(c.n_crm, 0) > 0 THEN 'VOZ_EN_CRM_SIN_PROMPT'
    WHEN m.canal = 'Escritos' THEN 'ESCRITOS_OTRO_PIPELINE'
    ELSE 'REVISAR'
  END AS estado
FROM tmp_mail AS m
LEFT JOIN adm AS a ON a.cola_nombre = m.cola_nombre
LEFT JOIN crm AS c ON c.cola_nombre = m.cola_nombre
LEFT JOIN prompt AS p ON p.cola_nombre = m.cola_nombre
LEFT JOIN eval AS e ON e.cola_nombre = m.cola_nombre
LEFT JOIN tmp_sp_admision AS sp
  ON sp.cola_id = COALESCE(a.cola_id, c.cola_id)
ORDER BY m.canal, estado, m.cola_nombre;

-- Match aproximado por nombre (typos / variantes Genesys)
SELECT
  m.canal,
  m.cola_nombre AS pedida,
  d.cola_nombre AS encontrada,
  d.cola_id,
  d.n
FROM tmp_mail AS m
LEFT JOIN (
  SELECT cola_nombre, ANY_VALUE(cola_id) AS cola_id, COUNT(*) AS n
  FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_admision_raw`
  WHERE fecha_descarga BETWEEN d0 AND d1
  GROUP BY 1
  UNION ALL
  SELECT cola_nombre, ANY_VALUE(cola_id), COUNT(*)
  FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw`
  WHERE fecha_descarga BETWEEN d0 AND d1
  GROUP BY 1
) AS d
  ON LOWER(d.cola_nombre) LIKE CONCAT('%', LOWER(REPLACE(m.cola_nombre, ' ', '%')), '%')
 OR LOWER(m.cola_nombre) LIKE CONCAT('%', LOWER(REPLACE(d.cola_nombre, ' ', '%')), '%')
WHERE d.cola_nombre IS NOT NULL
  AND d.cola_nombre != m.cola_nombre
ORDER BY m.canal, m.cola_nombre, d.n DESC;
