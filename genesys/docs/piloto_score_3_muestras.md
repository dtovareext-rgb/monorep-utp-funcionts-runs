# Score piloto 3 muestras — extracción 125 (A–L+N)

| Muestra | Cola | Keys | Fill |
|---|---|---:|---:|
| 01 | ALeadsDiaCero | 89/89 | ~80% |
| 02 | ANeutros_1A7_Hablados | 89/89 | ~85% |
| 03 | Nacional RA 2027 | 89/89 | 78.7% |

## Veredicto
Prompt estable en 3 colas distintas. Listo para pasar a BQ ML (`AI.GENERATE_TABLE` + `gemini-3-5-flash`).

## Ajustes pendientes (post-proceso / prompt v2)
1. Normalizar "No se menciona" → null
2. `consistencia_tipificacion` / `residencia_coincide_crm` con join CRM
3. Timestamps desde serialize_level_2 / momentos, no LLM
4. Revisar enums vs catálogos Excel en muestra ampliada
