# Prompts canal hablado (`utp_pront_instruccions`)

Fuente BQ: `prd-utpbi-data-operation.raw_genesys_audios.utp_pront_instruccions`  
Export: `bq-results-20260915-140410-1789481057840.csv` (15-sep-2026)

Archivos en [`prompts_canal_hablado/`](./prompts_canal_hablado/) — ver [`INDEX.md`](./prompts_canal_hablado/INDEX.md).

| # | Archivo | tipificacion | cmr_rango |
|---|---------|--------------|-----------|
| 01–04 | `RA_*` | RA | <=18, 19-23, >=24, Sin Edad |
| 05–08 | `DS-SI_*` | DS-SI | <=18, 19-23, >=24, Sin Edad |
| 09 | `OUTPUT_NA` | OUTPUT | NA (formato salida; se concatena siempre en `sp_utpbi_genesys_update_prompt`) |
| 10 | `OUTPUT_2_NA` | OUTPUT_2 | NA |
| 11 | `GEN_2_NA` | GEN_2 | NA |

El SP `sp_utpbi_genesys_update_prompt` junta: instrucciones (tipificación+rango) + ficha transversal + ficha carrera + bloque `OUTPUT`.
