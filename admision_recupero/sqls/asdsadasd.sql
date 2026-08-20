-- Dedup PRD Admisión: 1 fila por conversation_id (los 13 IDs con duplicados).
-- Criterio: se queda la más reciente (process_date DESC).
-- Corre TODO el archivo en una sola sesión (el temp no sobrevive a otro job).
--
-- bq query --use_legacy_sql=false --location=US \
--   --project_id=prd-utpbi-data-operation \
--   < admision_recupero/sqls/asdsadasd.sql

CREATE OR REPLACE TEMP TABLE tmp_ids AS
SELECT conversation_id FROM UNNEST([
  '9b1b5850-32de-4635-a921-888f38f28996',
  '258bdeb5-7bf1-4502-aa4a-cf103b730cb9',
  '1bb78e3e-fb75-4152-8903-0e325691f65c',
  '888a00a7-1dec-4713-bac5-708e13d7c57c',
  '79169198-ce5d-4a58-8c7a-3ed0b971b736',
  '923fbb4f-674d-4863-9d90-a00175dc08b0',
  'f76a3d4c-8209-451f-9dd0-332c19994b92',
  'f89aa43e-b7a6-4904-b533-0f048e8dd23e',
  '8b73253b-ad9e-44f2-a94e-c0cab5c39485',
  '5ece915e-5167-4508-b7c2-b9b870776f09',
  'd414fa9a-0962-411d-b509-7f6ff1adf31f',
  '93fe107d-97ca-43a8-995d-ffcde51a2c94',
  '15f095ea-b4a3-4fd4-8e95-aa9a577e272e'
]) AS conversation_id;

-- Antes: cuántos duplicados hay (solo lectura)
SELECT
  conversation_id,
  COUNT(*) AS cantidad
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd_admision`
WHERE conversation_id IN (SELECT conversation_id FROM tmp_ids)
GROUP BY conversation_id
ORDER BY cantidad DESC;

CREATE OR REPLACE TEMP TABLE tmp_keep AS
SELECT t.*
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd_admision` AS t
INNER JOIN tmp_ids AS i
  ON t.conversation_id = i.conversation_id
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY t.conversation_id
  ORDER BY t.process_date DESC
) = 1;

-- Si no están los 13, el script se DETIENE y no borra nada.
ASSERT (
  (SELECT COUNT(*) FROM tmp_keep) = 13
  AND (SELECT COUNT(DISTINCT conversation_id) FROM tmp_keep) = 13
) AS 'Se esperaban 13 filas (1 por conversation_id). Revisa que los 13 existan en PRD.';

BEGIN TRANSACTION;

DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd_admision`
WHERE conversation_id IN (SELECT conversation_id FROM tmp_keep);

INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd_admision`
SELECT *
FROM tmp_keep;

COMMIT TRANSACTION;

-- Después: todos deben ser cantidad = 1
SELECT
  conversation_id,
  COUNT(*) AS cantidad
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd_admision`
WHERE conversation_id IN (SELECT conversation_id FROM tmp_ids)
GROUP BY conversation_id
ORDER BY conversation_id;
