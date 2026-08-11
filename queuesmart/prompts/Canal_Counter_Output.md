# Canal Counter — Formato de salida (QueeSmart)

Contrato JSON para `sp_queuesmart_audio_analisis_ia` / prompt `canal_counter_prompt`.

- Respuesta: arreglo JSON con **un** objeto: `[{ ... }]`
- Marcaciones (`*_marcacion`): **`"SI"`** | **`"NO"`** | **`"NA"`**
- Descripciones: máximo 15 palabras, terminan en `(SI)`, `(NO)` o `(NA)`
- `T_*` y `MAYOR_REBATE`: enteros (`0` si no aplica)

## Retirados de Counter (no devolver / columnas DROP en hist)

`empatia_*`, `actitud_comercial_*`, `sigue_flujo_gestion_*`, `ofrece_qr_*`, `valida_datos_postulante_*`, `T_OFRECE_QR` / `t_ofrece_qr`

## Subatributos Counter (nuevos)

| Campo base | Pauta |
|---|---|
| tono_sarcastico_despectivo | TONO_DESPECTIVO_O_SARCASTICO |
| confronta_prospecto | CONFRONTA_AL_PROSPECTO |
| tono_seguridad | TONO_Y_SEGURIDAD |
| escucha_activa | ESCUCHA_ACTIVA |
| info_seguro_estudiantil | INFORMACION_COMPLEMENTARIA |
| plazo_entrega_documentos | INFORMACION_COMPLEMENTARIA |
| plazo_pago_matricula | INFORMACION_COMPLEMENTARIA |
| otros_beneficios | INFORMACION_COMPLEMENTARIA |
| sondeo_motivacion | MOTIVACION |
| info_correcta_completa_sondeo | SONDEO |
| info_correcta_becas / descuentos / convenios / convalidacion | VALIDACION_INFORMACION_ARGUMENTARIO |
| info_correcta_carrera_campus_modalidad_turnos | VALIDACION_INFORMACION_ARGUMENTARIO |
| info_correcta_inversion | INVERSION sin descuentos |
| pre_cierre | PRE_CIERRE |
| resumen_venta | RESUMEN_DE_VENTA |
| informacion_falsa | INFORMACION_FALSA + info fuera de proceso |

## Reglas clave de marcación

- **Rebate**: todas las objeciones relevantes deben rebatirse (no solo la 1ª).
- **Rebate efectivo**: cada rebate acorde a su objeción (no basta “hubo rebate”).
- **Cierre**: no válido = pregunta abierta / agendar / quedar a la espera.
- **presenta_vacio**: sin demora → `SI` (no `NA`).
- **sondeo**: sin evidencia cuando aplica → `NO` (no `NA`).

Fuente completa: `queuesmart/prompts/canal_counter_prompt_completo.txt`
