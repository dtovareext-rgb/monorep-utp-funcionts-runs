-- Normaliza flags / booleanos a SI | NO | NA (capa flat BI).
-- Location: US

CREATE OR REPLACE FUNCTION `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_flag_si_no`(
  v STRING
)
RETURNS STRING
AS (
  CASE
    WHEN v IS NULL OR TRIM(v) = '' THEN NULL
    WHEN UPPER(TRIM(v)) IN ('1', 'TRUE', 'SI', 'SÍ', 'YES', 'Y', 'S') THEN 'SI'
    WHEN UPPER(TRIM(v)) IN ('0', 'FALSE', 'NO', 'N') THEN 'NO'
    WHEN UPPER(TRIM(v)) IN ('NA', 'N/A', 'NULL', 'NONE') THEN 'NA'
    ELSE UPPER(TRIM(v))
  END
);
