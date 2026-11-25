-- =============================================================================
-- Catálogo vivo: colas del mail Speech Analytics → cola_id (queues_raw)
-- Fuente UUID: prd-utpbi-data-operation.raw_genesys.queues_raw.raw_data
-- Uso:
--   - Admisión → sp_utpbi_genesys_end_processing_admision_v2 (filtro cola_id IN)
--   - Voz     → descarga CRM/prompt/eval (NO este SP); si n_crm=0 → falta descarga
--   - Escritos→ otro pipeline (OM / WhatsApp)
-- =============================================================================

-- ---------- ADMISIÓN ----------
-- YA EN SP end_processing_admision_v2:
--   ADA_CENTRAL                         670c24d1-8145-48df-a691-2cc58383f43b
--   ADA_CENTRAL_ID_SALIENTE             ab0ae2ce-fa4b-413a-a45c-890c944fd143
--   ADA_CENTRAL|IN_CENTRAL (compuesta)  ab0ae2ce-…|e8c46f19-…
--   ADA_MATRICULA                       c02c8cea-daf9-4198-81fa-c8cc97aeb023
--   ADA_CENTRAL_EXAMEN                  13b6658f-6152-4310-a810-cdaa2f4d3a75
--   ADA_CENTRAL_EXAMEN_SALIENTE         c22a3757-44f7-494e-9cf5-bd2ef3dceb5a
--   ADA_CENTRAL_CONVALIDACION           5fa39d89-8a30-423b-b146-bf69b4767248
--   ADA_CENTRAL_CONVALIDACION_SALIENTE  c74c8e42-4596-418b-9e44-4dde730c0270
--   ADA_NACIONAL                        a54d2f9f-818e-45fb-91ea-02822b1360db  (alta 2026-11-24)
--   ADA_CENTRAL_MEDICINA                807f46d9-c0bd-481a-8c6d-5875d3c2d81d  (alta 2026-11-24)
--   ADA_EVENTOS                         43981e28-4b8a-4956-8ea8-ddebe0d89bb1  (alta 2026-11-24)
--   ADA_EVENTOS_CENTRAL                 26121bce-f286-4714-ab75-d35a0d9749f3  (alta 2026-11-24)
--   ADA_EVENTOS_CONVALIDACION           16c5973e-16b7-40d8-a87e-3320fc1fe3a3  (alta 2026-11-24)
--   ADA_EVENTOS_EXAMEN                  bbe6a18b-d9c9-418d-823c-f7ccce8b5057  (alta 2026-11-24)
--
-- Nota: si n=0 en admision_raw tras deploy → habilitar descarga Genesys para esos UUID.

-- ---------- VOZ (existen en queues_raw; funnel CRM→prompt→eval) ----------
-- YA CON EVAL (30d):
--   ANeutros_1A7_Hablados     5d248f68-ecff-4d1d-b259-e48f21208bf0
--   ANeutros_16+_Hablados     b48c5f2b-eae9-459a-887a-05edc8eaee8d
--   Nacional General 2027     5428a893-dc5c-42b6-bd1e-8c824946018c
--   Nacional Top 2027         7d27ddfe-039b-477c-b3e7-cf939cfc37d3
--   Nacional RA 2027          ee861238-639a-410e-b947-b53f751e9310
--
-- EN GENESYS pero sin volumen CRM 30d (revisar descarga / routing):
--   ANeutros_8A15_Hablados    39a527df-62d9-4a22-994c-15b39fee9e57  (!! distinta de 16+)
--   ANeutros_Enriquecida      0ff1c4f8-9b69-44f6-a401-7d4623a88497
--   Hablados_UCI              8537ba72-0d12-42c3-94b6-2798601490ac
--   Nacional Mixta            02894427-3919-48dd-b74d-94341519f715
--   Nacional Prioridad 2027   81f64ab7-88b1-42e9-a832-faf6b887a9ab
--   Nacional UCI              04ca11da-4d92-4737-abe8-fe9661c42581
--   NacionalNS                dcddae43-89bc-4144-9780-2486b14c4817
--
-- No salió en el filtro queues (buscar aparte): Hablados_Respaldo

-- ---------- ESCRITOS ----------
--   Whatsapp_* / WAE / Gupshup → otro pipeline

SELECT *
FROM UNNEST([
  STRUCT('Admision' AS canal, 'ADA_CENTRAL' AS cola_nombre, '670c24d1-8145-48df-a691-2cc58383f43b' AS cola_id, 'EN_SP' AS estado),
  ('Admision', 'ADA_CENTRAL_ID_SALIENTE', 'ab0ae2ce-fa4b-413a-a45c-890c944fd143', 'EN_SP'),
  ('Admision', 'ADA_MATRICULA', 'c02c8cea-daf9-4198-81fa-c8cc97aeb023', 'EN_SP'),
  ('Admision', 'ADA_CENTRAL_EXAMEN', '13b6658f-6152-4310-a810-cdaa2f4d3a75', 'EN_SP'),
  ('Admision', 'ADA_CENTRAL_EXAMEN_SALIENTE', 'c22a3757-44f7-494e-9cf5-bd2ef3dceb5a', 'EN_SP'),
  ('Admision', 'ADA_CENTRAL_CONVALIDACION', '5fa39d89-8a30-423b-b146-bf69b4767248', 'EN_SP'),
  ('Admision', 'ADA_CENTRAL_CONVALIDACION_SALIENTE', 'c74c8e42-4596-418b-9e44-4dde730c0270', 'EN_SP'),
  ('Admision', 'ADA_NACIONAL', 'a54d2f9f-818e-45fb-91ea-02822b1360db', 'EN_SP'),
  ('Admision', 'ADA_CENTRAL_MEDICINA', '807f46d9-c0bd-481a-8c6d-5875d3c2d81d', 'EN_SP'),
  ('Admision', 'ADA_EVENTOS', '43981e28-4b8a-4956-8ea8-ddebe0d89bb1', 'EN_SP'),
  ('Admision', 'ADA_EVENTOS_CENTRAL', '26121bce-f286-4714-ab75-d35a0d9749f3', 'EN_SP'),
  ('Admision', 'ADA_EVENTOS_CONVALIDACION', '16c5973e-16b7-40d8-a87e-3320fc1fe3a3', 'EN_SP'),
  ('Admision', 'ADA_EVENTOS_EXAMEN', 'bbe6a18b-d9c9-418d-823c-f7ccce8b5057', 'EN_SP'),
  ('Voz', 'ANeutros_1A7_Hablados', '5d248f68-ecff-4d1d-b259-e48f21208bf0', 'EN_EVAL'),
  ('Voz', 'ANeutros_16+_Hablados', 'b48c5f2b-eae9-459a-887a-05edc8eaee8d', 'EN_EVAL'),
  ('Voz', 'ANeutros_8A15_Hablados', '39a527df-62d9-4a22-994c-15b39fee9e57', 'EN_QUEUES_SIN_CRM'),
  ('Voz', 'ANeutros_Enriquecida', '0ff1c4f8-9b69-44f6-a401-7d4623a88497', 'EN_QUEUES_SIN_CRM'),
  ('Voz', 'Hablados_UCI', '8537ba72-0d12-42c3-94b6-2798601490ac', 'EN_QUEUES_SIN_CRM'),
  ('Voz', 'Nacional General 2027', '5428a893-dc5c-42b6-bd1e-8c824946018c', 'EN_EVAL'),
  ('Voz', 'Nacional Top 2027', '7d27ddfe-039b-477c-b3e7-cf939cfc37d3', 'EN_EVAL'),
  ('Voz', 'Nacional RA 2027', 'ee861238-639a-410e-b947-b53f751e9310', 'EN_EVAL'),
  ('Voz', 'Nacional Mixta', '02894427-3919-48dd-b74d-94341519f715', 'EN_QUEUES_SIN_CRM'),
  ('Voz', 'Nacional Prioridad 2027', '81f64ab7-88b1-42e9-a832-faf6b887a9ab', 'EN_QUEUES_SIN_CRM'),
  ('Voz', 'Nacional UCI', '04ca11da-4d92-4737-abe8-fe9661c42581', 'EN_QUEUES_SIN_CRM'),
  ('Voz', 'NacionalNS', 'dcddae43-89bc-4144-9780-2486b14c4817', 'EN_QUEUES_SIN_CRM')
]);
