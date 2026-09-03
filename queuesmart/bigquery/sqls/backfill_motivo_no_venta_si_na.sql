-- =============================================================================
-- Backfill motivo_no_venta (solo tipificación SI → NA)
-- Estrategia: no reprocesar; RA/DS históricos quedan NULL.
-- Requiere columnas ya creadas (alter_hist_..._motivo_no_venta.sql).
--
-- bq query --use_legacy_sql=false --location=US \
--   --project_id=prd-utpbi-data-operation \
--   < queuesmart/bigquery/sqls/backfill_motivo_no_venta_si_na.sql
-- =============================================================================

-- Preview (opcional): cuántas filas se actualizarían
-- SELECT
--   'raw' AS capa,
--   COUNT(*) AS n_si_a_actualizar
-- FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
-- WHERE UPPER(TRIM(IFNULL(tipificacion_segun_casuistica, ''))) = 'SI'
--   AND (
--     motivo_no_venta IS NULL
--     OR submotivo_no_venta IS NULL
--     OR detalle_submotivo_no_venta IS NULL
--     OR observaciones_no_venta IS NULL
--     OR UPPER(TRIM(motivo_no_venta)) != 'NA'
--     OR UPPER(TRIM(submotivo_no_venta)) != 'NA'
--     OR UPPER(TRIM(detalle_submotivo_no_venta)) != 'NA'
--     OR UPPER(TRIM(observaciones_no_venta)) != 'NA'
--   );

UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
SET
  motivo_no_venta = 'NA',
  submotivo_no_venta = 'NA',
  detalle_submotivo_no_venta = 'NA',
  observaciones_no_venta = 'NA'
WHERE UPPER(TRIM(IFNULL(tipificacion_segun_casuistica, ''))) = 'SI'
  AND (
    motivo_no_venta IS NULL
    OR submotivo_no_venta IS NULL
    OR detalle_submotivo_no_venta IS NULL
    OR observaciones_no_venta IS NULL
    OR UPPER(TRIM(motivo_no_venta)) != 'NA'
    OR UPPER(TRIM(submotivo_no_venta)) != 'NA'
    OR UPPER(TRIM(detalle_submotivo_no_venta)) != 'NA'
    OR UPPER(TRIM(observaciones_no_venta)) != 'NA'
  );

UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`
SET
  motivo_no_venta = 'NA',
  submotivo_no_venta = 'NA',
  detalle_submotivo_no_venta = 'NA',
  observaciones_no_venta = 'NA'
WHERE UPPER(TRIM(IFNULL(tipificacion_segun_casuistica, ''))) = 'SI'
  AND (
    motivo_no_venta IS NULL
    OR submotivo_no_venta IS NULL
    OR detalle_submotivo_no_venta IS NULL
    OR observaciones_no_venta IS NULL
    OR UPPER(TRIM(motivo_no_venta)) != 'NA'
    OR UPPER(TRIM(submotivo_no_venta)) != 'NA'
    OR UPPER(TRIM(detalle_submotivo_no_venta)) != 'NA'
    OR UPPER(TRIM(observaciones_no_venta)) != 'NA'
  );

-- Control post-update
SELECT
  'raw' AS capa,
  COUNTIF(UPPER(TRIM(IFNULL(tipificacion_segun_casuistica, ''))) = 'SI') AS n_si,
  COUNTIF(
    UPPER(TRIM(IFNULL(tipificacion_segun_casuistica, ''))) = 'SI'
    AND motivo_no_venta = 'NA'
    AND submotivo_no_venta = 'NA'
    AND detalle_submotivo_no_venta = 'NA'
    AND observaciones_no_venta = 'NA'
  ) AS n_si_con_na,
  COUNTIF(UPPER(TRIM(IFNULL(tipificacion_segun_casuistica, ''))) IN ('RA', 'DS')
    AND motivo_no_venta IS NULL) AS n_ra_ds_null_motivo
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`

UNION ALL

SELECT
  'prd' AS capa,
  COUNTIF(UPPER(TRIM(IFNULL(tipificacion_segun_casuistica, ''))) = 'SI') AS n_si,
  COUNTIF(
    UPPER(TRIM(IFNULL(tipificacion_segun_casuistica, ''))) = 'SI'
    AND motivo_no_venta = 'NA'
    AND submotivo_no_venta = 'NA'
    AND detalle_submotivo_no_venta = 'NA'
    AND observaciones_no_venta = 'NA'
  ) AS n_si_con_na,
  COUNTIF(UPPER(TRIM(IFNULL(tipificacion_segun_casuistica, ''))) IN ('RA', 'DS')
    AND motivo_no_venta IS NULL) AS n_ra_ds_null_motivo
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`;
