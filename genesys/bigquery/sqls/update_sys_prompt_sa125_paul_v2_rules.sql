-- =============================================================================
-- Patch de reglas al prompt speech_analytics_extraccion_125_paul_v1
-- (hallazgos validación 100 — sin cambiar el nombre del prompt)
-- Location: US | Ejecutar como script completo (BEGIN…END)
-- =============================================================================

BEGIN
  DECLARE v_marker STRING DEFAULT '<!-- SA125_POSTVAL_RULES -->';
  DECLARE v_block STRING;
  DECLARE v_current STRING;
  DECLARE v_name STRING DEFAULT 'speech_analytics_extraccion_125_paul_v1';

  SET v_block = '''<!-- SA125_POSTVAL_RULES -->
## REGLAS DURAS (validación 100 — obligatorias)

1) Cascada sin conversación: si calidad_transcripcion ∈ {VACIA, SIN_CONVERSACION, BUCLE_REPETICIONES} O el cliente no intercambia información más allá del saludo → contacto_efectivo=NO, estado_lead=SIN_CONTACTO. No uses RA/DS/SI ni motivos de no venta.
2) TRUNCADA solo si el audio/texto se corta a mitad de una frase (corte técnico). Saludo solo, un hablante sin respuesta o cuelgue tras hola → SIN_CONVERSACION (no TRUNCADA).
3) Evidencias (motivos_preferencia, comentario_mercado, motivos_rechazo, objeciones): cita SOLO líneas del [Cliente]/ nunca del asesor. Si el atributo lo dice solo el asesor → no lo marques / No se menciona.
4) tipificacion_ia y responsabilidad_no_venta: NUNCA "No se menciona". Sin catálogo claro o sin contacto → NA. En llamadas no uses submotivos CHAT_*.
5) periodo_ingreso: compara con campaña_vigente y fecha_hora_interaccion de entrada. Si el prospecto dice "marzo" y campaña_vigente es ese marzo → PERIODO_EN_CURSO (no PROXIMO_ANIO/SEMESTRE).
6) oferta_cotizada: si no hubo monto en soles → objeto null (no inventes concepto PENSION con monto null). Registra el PRIMER monto y todos los descuentos.
7) tiempo_hasta_precio_seg: solo con timestamps; si no hay precio → clasificacion SIN_PRECIO. No inventes segundos.
8) NA por condición: segundo_numero_obtenido solo si estado_lead ∈ {RA, SI}; carga_documento_llamada solo canal Admisión; senal_abandono solo con RA/DS/CDE y contacto efectivo; finalizacion_interaccion = NA si calidad ≠ VALIDA.
9) comentario_mercado: clave JSON "texto" (no "text").
10) zona_interes: última zona ACEPTADA por el prospecto; no inferir de residencia ni de sugerencia del asesor rechazada; si solo virtual → No se menciona.

<!-- /SA125_POSTVAL_RULES -->
''';

  SET v_current = (
    SELECT prompt_text
    FROM `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts_speech_analytics`
    WHERE prompt_name = v_name
    ORDER BY updated_at DESC
    LIMIT 1
  );

  IF v_current IS NULL THEN
    SELECT ERROR(FORMAT('No existe prompt %s', v_name));
  ELSEIF STRPOS(v_current, v_marker) > 0 THEN
    SELECT 'Prompt ya tiene SA125_POSTVAL_RULES — skip' AS status;
  ELSE
    INSERT INTO `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts_speech_analytics` (
      prompt_name,
      prompt_text,
      updated_at
    )
    VALUES (
      v_name,
      CONCAT(v_block, '\n\n', v_current),
      CURRENT_TIMESTAMP()
    );
    SELECT 'Prompt actualizado con SA125_POSTVAL_RULES' AS status;
  END IF;
END;
