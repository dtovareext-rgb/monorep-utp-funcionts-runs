# SA-125 — Corrección según validación 100

## Qué se corrigió en código

| Hallazgo | Fix |
|----------|-----|
| Cascada SIN_CONTACTO / sin conversación | `fn_sa125_postprocess` |
| NA por estado/canal (`segundo_numero`, `carga_documento`, `senal_abandono`, …) | idem |
| `oferta_cotizada` inventada / `tiempo_hasta_precio` | idem |
| Encoding mojibake + entidades HTML | idem |
| TRUNCADA en saludos cortos | idem (usa `LENGTH(transcripción)`) |
| `campaña_vigente` = cola (bug) | `sp_speech_analytics_125_batch` → `YYYY-MARZO` |
| Reglas tipificación / evidencias / periodo | patch prompt `update_sys_prompt_sa125_paul_v2_rules.sql` |

## Cloud Shell (orden)

```bash
# Location US
bq query --project_id=prd-utpbi-data-operation --location=US --use_legacy_sql=false \
  < genesys/bigquery/routines/fn_sa125_postprocess.sql

bq query --project_id=prd-utpbi-data-operation --location=US --use_legacy_sql=false \
  < genesys/bigquery/procedures/sp_speech_analytics_125_parse.sql

bq query --project_id=prd-utpbi-data-operation --location=US --use_legacy_sql=false \
  < genesys/bigquery/procedures/sp_speech_analytics_125_batch.sql

# Reglas en prompt (nuevas corridas Gemini)
bq query --project_id=prd-utpbi-data-operation --location=US --use_legacy_sql=false \
  < genesys/bigquery/sqls/update_sys_prompt_sa125_paul_v2_rules.sql

# Re-parse día muestra (sin gastar Gemini)
bq query --project_id=prd-utpbi-data-operation --location=US --use_legacy_sql=false \
  < genesys/bigquery/sqls/reparse_sa125_postprocess_day.sql
```

## Qué NO arregla el re-parse solo

Campos que el LLM inventó con lógica de negocio (p.ej. tipificación concreta, periodo mal razonado en el RAW) mejoran del todo al **regenerar** el día con el prompt parcheado + `campaña_vigente` correcta:

```bash
# Cuidado: borra RAW del día y vuelve a llamar Gemini
gcloud workflows run genesys-sa125-daily --location=us-central1 \
  --data='{"process_date":"2026-11-02","batch_size":20}'
```

Recomendación: primero **re-parse** (gratis) → medir cascada/NA/oferta; luego regenerar si tipificación/periodo siguen flojos.
