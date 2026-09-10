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

- **Rebate**: solo objeciones reales (resistencia a inscribirse/pagar). Consulta informativa ≠ objeción. Sin objeción real → `objecion_*` = `NA` y `rebate` = **`SI`** (RA/DS). Objeción real no rebatida / no identificada por el asesor → **`NO`** (nunca `NA` en RA/DS). **`rebate` = `NA` solo si tipificación = SI (venta).**
- **Rebate efectivo**: cada rebate acorde a su objeción. `NA` solo si venta SI (igual que rebate); RA/DS → `SI` o `NO`, nunca `NA`.
- **Cierre**: no válido = pregunta abierta / agendar / quedar a la espera. No copiar `SI` del ejemplo.
- **Saludo**: sin evidencia en el audio → `NO` (castigo). `NA` solo en retoma explícita (no aplica re-saludar). No inventar `SI`.
- **Espera**: si `[MM:SS]` retrocede (STT), no restar huecos. Reloj monótono: &lt;15 s → `SI`; ≥30 s sin aviso → `NO`.
- **T_\***: entero del bloque; nunca mayor que el `[MM:SS]` máximo.
- **tipo_contacto**: `PRIMER_CONTACTO` | `SEGUIMIENTO` (inferir; no copiar el ejemplo).
- **gestion_principal**: `INFORMACION_CARRERA` | `DOCUMENTOS_REGULAR` | `DOCUMENTOS_CONVALIDACION` | `PAGO_MATRICULA` | `RECORDATORIO_EXAMEN`.
- **tipificacion / resultado_final_llamada**: solo `RA` | `DS` | `SI`.
- **plazo documentos**: default `NA`. `NO` solo si se habló de entregar documentos y no dio plazo.
- **presenta_vacio**: sin demora → `SI` (no `NA`), salvo grabación que arranca en gestión.
- **sondeo**: sin evidencia cuando aplica → `NO` (no `NA`).
- **Motivación (`sondeo_motivacion`)**: en **AG**, mide solo si el asesor **hizo la pregunta** (metas, por qué estudiar). No exige que el prospecto respondiera ni acompañamiento. RA/AD/OP → **`NA`**.

Fuente completa: `queuesmart/prompts/canal_counter_prompt_completo.txt`
