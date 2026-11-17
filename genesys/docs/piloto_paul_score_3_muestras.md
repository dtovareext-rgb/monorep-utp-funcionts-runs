# Piloto prompt Paul — 3 muestras

| Muestra | Cola | Campos | Externos "" | Bloque P | Historia |
|---|---|---:|---:|---|---|
| 01 | ALeadsDiaCero | 125/125 | 8/8 | NA | Electrónica / SI / ficha |
| 02 | ANeutros | 125/125 | 8/8 | NA | Farmacia / RA / madre |
| 03 | Nacional RA 2027 | 125/125 | 8/8 | NA | RA / POSTERGA |

## Veredicto
Prompt oficial de Paul estable en 3 colas. Listo para BQ ML.

## Siguiente
1. Cargar `Prompt_Completo_Speech_Analytics.md` a `sys_prompts_speech_analytics`
2. `AI.GENERATE_TABLE` con `gemini-3-5-flash` sobre `serialized_level_1`
3. Parse JSON anidado → tabla tipada + join CRM
