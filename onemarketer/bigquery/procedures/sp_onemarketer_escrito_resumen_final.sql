-- =============================================================================
-- SP: Resumen final canal escrito por asesor/día — PRODUCCIÓN
--
-- Fuente: hist_onemarketer_caso_conversacion_ia_process_data_prd
-- Destino: adf_speech_analytics.escrito_resumen_final
-- Modelo:  gemini-3-5-flash
--
-- CALL:
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_escrito_resumen_final`(
--     DATE '2026-10-16'
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_escrito_resumen_final`(
  v_fecha_proceso DATE
)
BEGIN
  DECLARE v_asesor_count INT64;

  SET @@query_label = 'producto:onemarketer,etapa:resumen-final,servicio:flash-3-5';

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.escrito_resumen_final`
  WHERE process_date = v_fecha_proceso;

  CREATE OR REPLACE TEMP TABLE tmp_escrito_resumen_input AS
  WITH base AS (
    SELECT
      process_date,
      COALESCE(NULLIF(TRIM(asesor_user), ''), 'SIN_ASESOR') AS agentes_ids,
      COALESCE(
        NULLIF(TRIM(agent_open), ''),
        NULLIF(TRIM(agent_close), ''),
        NULLIF(TRIM(asesor_user), ''),
        'SIN_ASESOR'
      ) AS agentes,
      idcase,
      tipificacion,
      tipificacion_detalle,
      rebate_score,
      cierre_score,
      sentido_de_urgencia_score,
      saludo_score,
      despedida_score,
      LEFT(IFNULL(resumen_evaluacion, ''), 700) AS resumen_evaluacion
    FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_prd`
    WHERE process_date = v_fecha_proceso
      AND NULLIF(TRIM(asesor_user), '') IS NOT NULL
  ),
  numbered AS (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY agentes_ids ORDER BY idcase) AS caso_n
    FROM base
  )
  SELECT
    process_date,
    agentes_ids,
    ANY_VALUE(agentes) AS agentes,
    COUNT(*) AS n_evaluaciones,
    CONCAT(
      'Eres un analista de calidad UTP (canal escrito / OneMarketer WhatsApp). ',
      'Lee el HISTORIAL DE EVALUACIONES del asesor y redacta UN resumen ejecutivo en español. ',
      'Reglas: menciona el total de casos; agrupa patrones (saludo, despedida, rebate, cierre, urgencia, abandono CDE); ',
      'cita casos como [CASO N] con idcase; lista fallas de rebate/cierre; ',
      'cierra con oportunidades de mejora. Si casi todos son chats sin desarrollo o abandono del cliente, dilo. ',
      'No inventes casos. Texto corrido, sin JSON.\n\n',
      'Asesor: ', ANY_VALUE(agentes), ' (id=', agentes_ids, '). ',
      'Fecha: ', CAST(process_date AS STRING), '. ',
      'Total casos: ', CAST(COUNT(*) AS STRING), '.\n\n',
      '=== HISTORIAL DE EVALUACIONES ===\n',
      STRING_AGG(
        CONCAT(
          '[CASO ', CAST(caso_n AS STRING), '] idcase=', CAST(idcase AS STRING),
          ' tipif=', IFNULL(tipificacion, 'N/D'),
          ' detalle=', IFNULL(tipificacion_detalle, 'N/D'),
          ' saludo=', IFNULL(saludo_score, 'N/D'),
          ' rebate=', IFNULL(rebate_score, 'N/D'),
          ' cierre=', IFNULL(cierre_score, 'N/D'),
          ' urgencia=', IFNULL(sentido_de_urgencia_score, 'N/D'),
          '\n', IFNULL(resumen_evaluacion, '(sin resumen)')
        ),
        '\n\n'
        ORDER BY caso_n
      )
    ) AS prompt
  FROM numbered
  GROUP BY process_date, agentes_ids;

  SET v_asesor_count = (SELECT COUNT(*) FROM tmp_escrito_resumen_input);

  IF v_asesor_count = 0 THEN
    SELECT FORMAT('Sin evaluaciones escritas con asesor para fecha %t — resumen final omite.', v_fecha_proceso);
    RETURN;
  END IF;

  CREATE OR REPLACE TEMP TABLE tmp_escrito_resumen_ia AS
  SELECT ia.*
  FROM AI.GENERATE_TABLE(
    MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-3-5-flash`,
    (
      SELECT
        STRUCT(prompt AS instruction) AS prompt,
        * EXCEPT(prompt)
      FROM tmp_escrito_resumen_input
    ),
    STRUCT(
      'resumen_evaluaciones STRING' AS output_schema,
      8192 AS max_output_tokens,
      0 AS temperature
    )
  ) AS ia;

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.escrito_resumen_final` (
    process_date,
    agentes_ids,
    agentes,
    n_evaluaciones,
    resumen_evaluaciones,
    load_date
  )
  SELECT
    process_date,
    agentes_ids,
    agentes,
    n_evaluaciones,
    resumen_evaluaciones,
    DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date
  FROM tmp_escrito_resumen_ia;

END;
