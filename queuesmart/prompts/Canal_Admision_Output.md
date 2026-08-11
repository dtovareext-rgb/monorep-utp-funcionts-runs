> QueeSmart Counter: ver Canal_Counter_Output.md y prompt canal_counter_prompt.

En caso el postulante corte la llamada, abandone la interacción, impida al asesor continuar la gestión o no brinde oportunidad razonable para completar algún punto de evaluación, se considera que el asesor no incumplió dicho atributo y la marcación será "NA".

El análisis de la conversación siempre devolverá la respuesta respetando estrictamente la estructura de un JSON válido, sin omitir ningún campo.

##################################################
REGLA OBLIGATORIA PARA EVITAR MAX_TOKENS
##################################################

Todas las descripciones (*_descripcion) deben ser EXTREMADAMENTE CORTAS: máximo 15 palabras.

Sé directo y concreto. No escribas justificaciones largas ni explicaciones extensas.

Ejemplo correcto:

"Asesor se presentó correctamente mencionando su nombre y UTP. (1)"

Ejemplo incorrecto:

Oraciones largas con detalles, explicaciones o justificaciones extensas.

Mantén siempre el JSON completo.

##################################################
IMPORTANTE PARA EL FORMATO DE RESPUESTA
##################################################

1. DEBES RESPONDER ÚNICA Y ESTRICTAMENTE CON UN ARREGLO JSON VÁLIDO QUE CONTENGA EXACTAMENTE UN SOLO OBJETO CON TODAS LAS CLAVES DEFINIDAS A CONTINUACIÓN.

2. NO devuelvas texto adicional antes o después del JSON.

3. NO uses bloques de código ni formato Markdown para envolver la respuesta (por ejemplo: `json o `).

4. Devuelve únicamente el JSON crudo iniciando con [ y finalizando con ].

5. Asegúrate de escapar cualquier comilla doble (") que pueda invalidar el JSON. No incluyas saltos de línea ni caracteres inválidos dentro de los campos de texto. Utiliza una sola línea por campo.

6. Para los campos *_marcacion devuelve obligatoriamente:

   * 1
   * 0
   * "NA"

   No uses formatos como:

   * "1 | 0 | NA"
   * "Cumple"
   * "No cumple"

7. Los atributos de "clasificacion" o "carreras_interes" deben ser estrictamente ARREGLOS DE STRINGS EN FORMATO JSON. Ejemplo: ["clasificacion1", "clasificacion2"]. Si no identificaste la clasificación, devuelve un arreglo vacío []. NO LOS RETORNES COMO TEXTO.

8. Mantén siempre el JSON completo y respeta el tipo de dato definido para cada campo.

9. Los campos de secuencia de conversación deben devolverse obligatoriamente como números enteros. Si un evento no ocurre, devuelve 0.

10. Si un atributo no aplica según las reglas de la pauta, devuelve una descripción terminada en (NA) y una marcación igual a "NA".

11. Evalúa únicamente información presente en la conversación y en el contexto proporcionado. No realices inferencias externas ni supongas acciones no evidenciadas.

12. Todos los campos deben respetar estrictamente el tipo de dato definido en el formato de salida.

ESTE ES EL FORMATO DE SALIDA (Usa exactamente estas llaves y reemplaza las explicaciones con tus conclusiones en base a la conversación evaluada):

[
{
"tipo_contacto": "La definición se encuentra en <<<TIPO_CONTACTO>>>. Ejemplo: PRIMER_CONTACTO o SEGUIMIENTO.",

"gestion_principal": "La definición se encuentra en <<<GESTION_PRINCIPAL>>>. Ejemplo: DOCUMENTOS_REGULAR, DOCUMENTOS_CONVALIDACION, PAGO_MATRICULA o RECORDATORIO_EXAMEN.",

"saludo_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<SALUDO>>>. Si cumple marcar 1.",
"saludo_marcacion": 1,

"despedida_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<DESPEDIDA>>>. Si cumple marcar 1.",
"despedida_marcacion": 1,

"aclara_duda_cliente_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<ACLARA_DUDA_DEL_CLIENTE>>>. Si cumple marcar 1.",
"aclara_duda_cliente_marcacion": 1,

"presenta_vacio_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<SE_PRESENTA_VACIO_AL_INICIO_Y_DURANTE_LA_LLAMADA>>>. Si cumple marcar 1.",
"presenta_vacio_marcacion": 1,

"deja_en_espera_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<DEJA_AL_PROSPECTO_EN_ESPERA_DE_MANERA_INJUSTIFICADA>>>. Si cumple marcar 1.",
"deja_en_espera_marcacion": 1,

"empatia_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<EMPATIA>>>. Si cumple marcar 1.",
"empatia_marcacion": 1,

"actitud_comercial_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<ACTITUD_COMERCIAL>>>. Si cumple marcar 1.",
"actitud_comercial_marcacion": 1,

"lenguaje_grosero_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<LENGUAJE_GROSERO>>>. Si cumple marcar 1.",
"lenguaje_grosero_marcacion": 1,

"sigue_flujo_gestion_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<SIGUE_FLUJO_DE_GESTION_EN_LLAMADA>>>. Si cumple marcar 1.",
"sigue_flujo_gestion_marcacion": 1,

"brinda_informacion_correcta_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<BRINDA_INFORMACION_CORRECTA>>>. Si cumple marcar 1.",
"brinda_informacion_correcta_marcacion": 1,

"ofrece_qr_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<OFRECE_ENVIO_DE_QR>>>. Si cumple marcar 1.",
"ofrece_qr_marcacion": 1,

"valida_datos_postulante_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<VALIDA_DATOS_CON_EL_POSTULANTE>>>. Si cumple marcar 1.",
"valida_datos_postulante_marcacion": 1,

"sondea_interes_postulante_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<SONDEA_DE_ACUERDO_AL_INTERES_DEL_POSTULANTE>>>. Si cumple marcar 1.",
"sondea_interes_postulante_marcacion": 1,

"rebate_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<AGENTE_NO_REBATE>>>. Si cumple marcar 1.",
"rebate_marcacion": 1,

"rebate_efectivo_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<REBATE_NO_EFECTIVO>>>. Si cumple marcar 1.",
"rebate_efectivo_marcacion": 1,

"cierre_comercial_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<CIERRE_COMERCIAL>>>. Si cumple marcar 1.",
"cierre_comercial_marcacion": 1,

"sentido_urgencia_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<SENTIDO_DE_URGENCIA>>>. Si cumple marcar 1.",
"sentido_urgencia_marcacion": 1,

"afecta_imagen_negocio_descripcion": "Justificación breve y concreta. Lo que se espera está en <<<COMENTARIOS_NEGATIVOS_DE_LA_UNIVERSIDAD_O_SUS_EMPLEADOS>>>. Si cumple marcar 1.",
"afecta_imagen_negocio_marcacion": 1,

"tipificacion_segun_casuistica": "La definición se encuentra en <<<TIPIFICACION_SEGUN_CASUISTICA>>>. Ejemplo: DOCUMENTOS_REGULAR.",

"carreras_interes": ["Lista de carreras identificadas según <<<CARRERAS_DE_INTERES>>>. Ejemplo de valor: ingenieria_sistemas_informatica. Usa arreglo vacío [] si no hay."],

"resultado_final_llamada": "Resultado final de la gestión según <<<RESULTADO_FINAL_LLAMADA>>>. Debe contener únicamente uno de los valores definidos en dicho atributo.",
"conclusion_final_llamada": "Descripción breve del desenlace de la gestión según <<<CONCLUSION_FINAL_LLAMADA>>>.",

"objecion_cliente_1_texto": "Resumen de la primera objeción identificada según <<<OBJECION_CLIENTE_1_TEXTO>>>. Debe devolver 'NA' si no existe.",
"rebate_asesor_1_texto": "Resumen del primer rebate identificado según <<<REBATE_ASESOR_1_TEXTO>>>. Debe devolver 'NA' si no existe.",

"objecion_cliente_2_texto": "Resumen de la segunda objeción identificada según <<<OBJECION_CLIENTE_2_TEXTO>>>. Debe devolver 'NA' si no existe.",
"rebate_asesor_2_texto": "Resumen del segundo rebate identificado según <<<REBATE_ASESOR_2_TEXTO>>>. Debe devolver 'NA' si no existe.",

"objecion_cliente_3_texto": "Resumen de la tercera objeción identificada según <<<OBJECION_CLIENTE_3_TEXTO>>>. Debe devolver 'NA' si no existe.",
"rebate_asesor_3_texto": "Resumen del tercer rebate identificado según <<<REBATE_ASESOR_3_TEXTO>>>. Debe devolver 'NA' si no existe.",

"resumen_evaluacion": "La definición se encuentra en <<<RESUMEN_EVALUACION>>>.",

"T_SALUDO": "Momento del saludo según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no ocurre.",
"T_VALIDACION_DATOS": "Momento de validación de datos según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no ocurre.",
"T_SONDEO": "Momento del sondeo principal según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no ocurre.",
"T_ACLARA_DUDA": "Momento en que se atiende una consulta relevante según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no ocurre.",
"T_OBJECION_CLIENTE_1": "Momento de la primera objeción del postulante según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no hay.",
"T_REBATE_1": "Momento del primer rebate del asesor según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no hay.",
"T_CIERRE_1": "Momento del primer cierre posterior al rebate según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no hay.",
"T_OBJECION_CLIENTE_2": "Momento de la segunda objeción del postulante según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no hay.",
"T_REBATE_2": "Momento del segundo rebate del asesor según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no hay.",
"T_CIERRE_2": "Momento del segundo cierre posterior al rebate según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no hay.",
"T_OBJECION_CLIENTE_3": "Momento de la tercera objeción del postulante según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no hay.",
"T_REBATE_3": "Momento del tercer rebate del asesor según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no hay.",
"T_CIERRE_3": "Momento del tercer cierre posterior al rebate según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no hay.",
"T_SENTIDO_DE_URGENCIA": "Momento del sentido de urgencia según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no ocurre.",
"T_CIERRE": "Momento del cierre principal según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no ocurre.",
"T_DESPEDIDA": "Momento de la despedida según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no ocurre.",
"T_OFRECE_QR": "Momento en que el asesor ofrece QR según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no ocurre.",
"T_COMENTARIO_NEGATIVO_UTP": "Momento en que el asesor realiza comentarios negativos sobre UTP según <<<SECUENCIA_CONVERSACION>>>. Número entero, 0 si no ocurre.",
"MAYOR_REBATE": "1 si se detectan 4 o más rebates durante la interacción; 0 en caso contrario."
}
]
