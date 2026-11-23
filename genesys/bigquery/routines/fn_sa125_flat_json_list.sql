-- JSON array → texto "a | b | c" (sin corchetes JSON). Objetos se serializan.
-- Location: US

CREATE OR REPLACE FUNCTION `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(
  j JSON
)
RETURNS STRING
AS (
  (
    SELECT STRING_AGG(
      `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(
        CASE
          WHEN x IS NULL THEN NULL
          WHEN JSON_TYPE(x) = 'string' THEN JSON_VALUE(x)
          WHEN JSON_TYPE(x) IN ('number', 'boolean', 'null') THEN JSON_VALUE(x)
          ELSE TO_JSON_STRING(x)
        END
      ),
      ' | '
      ORDER BY off
    )
    FROM UNNEST(IFNULL(JSON_QUERY_ARRAY(j), [])) AS x WITH OFFSET AS off
  )
);
