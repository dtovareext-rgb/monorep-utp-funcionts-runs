# Optimizar vistas CRM lead (QueueSmart + OneMarketer)

Guía para aplicar en otra PC: el slot time alto no es “poca data”, es el **join con `OR`** a `leads` (DNI o teléfono). BigQuery no hace hash join limpio con `OR`.

## Qué cambiar (patrón)

1. Quitar el `LEFT/INNER JOIN … ON (dni = …) OR (phone = …)`.
2. Match en **dos pasos de igualdad**:
   - `match_dni`: join solo por `dni_norm`
   - `match_phone`: join solo por `phone_norm`, **solo si el lado caso/audio no trae DNI** (`dni_norm IS NULL OR dni_norm = ''`) — misma semántica que hoy
3. Si hay varios leads, `QUALIFY ROW_NUMBER()` por cercanía a la fecha del caso/audio (`match_time_delta_sec`).
4. Unir `systemusers` / `opportunities` **después** del match (no sobre todo el CRM).
5. Slim: no `SELECT l.*`; castear llaves una vez; quitar `UPPER(...)` en los joins.

Referencia ya aplicada: `queuesmart/bigquery/views/v_queuesmart_counter_crm_lead.sql`.

---

## 1) QueueSmart — solo deploy

El SQL ya está reescrito en el repo.

```bash
cd /ruta/al/monorep-utp-funcionts-runs

bq query --use_legacy_sql=false --location=us-central1 \
  --project_id=prd-utpbi-data-operation \
  < queuesmart/bigquery/views/v_queuesmart_counter_crm_lead.sql
```

Check:

```sql
SELECT *
FROM `prd-utpbi-data-operation.raw_queue_smart.v_queuesmart_counter_crm_lead`
WHERE process_day = '2026-10-01'
LIMIT 100;
```

Comparar en Job info: **slot time** (antes ~2 h 42 min con ~48 s de reloj).

Vista dependiente (no hace falta tocarla): `v_queuesmart_lead_conversaciones` solo lee esta.

---

## 2) OneMarketer — reescribir + deploy

Mismo anti-patrón en **dos** vistas:

| Vista | Dataset | Archivo |
|-------|---------|---------|
| `v_onemarketer_caso_crm_lead` | `raw_onemarketer` | `onemarketer/bigquery/views/v_onemarketer_caso_crm_lead.sql` |
| `v_onemarketer_lead_conversaciones` | `raw_onemarketer` | `onemarketer/bigquery/views/v_onemarketer_lead_conversaciones.sql` |

### Bloque a reemplazar (ejemplo en `v_onemarketer_caso_crm_lead`)

Hoy (caro):

```sql
FROM casos_norm AS c
LEFT JOIN leads_crm AS l
  ON (
    c.dni_norm IS NOT NULL
    AND l.dni_norm IS NOT NULL
    AND c.dni_norm = l.dni_norm
  )
  OR (
    (c.dni_norm IS NULL OR c.dni_norm = '')
    AND c.phone_norm IS NOT NULL
    AND l.phone_norm IS NOT NULL
    AND c.phone_norm = l.phone_norm
  )
```

Sustituir por el esquema de QueueSmart (adaptando nombres):

```sql
-- Tras leads_latest (solo columnas usadas, sin l.*):
leads_by_dni AS (
  SELECT * FROM leads_latest WHERE dni_norm IS NOT NULL
),
leads_by_phone AS (
  SELECT * FROM leads_latest WHERE phone_norm IS NOT NULL
),

match_dni AS (
  SELECT
    c.idcase,
    c.start_time,
    /* columnas CRM del lead + */
    'dni' AS match_method,
    ABS(TIMESTAMP_DIFF(c.start_time, l.createdon, SECOND)) AS match_time_delta_sec,
    l.usuario_primera_key,
    l.parentcontact_key
    /* + resto de campos CRM que ya proyectabas */
  FROM casos_norm AS c
  INNER JOIN leads_by_dni AS l
    ON c.dni_norm = l.dni_norm
  WHERE c.dni_norm IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY c.idcase, c.start_time
    ORDER BY ABS(TIMESTAMP_DIFF(c.start_time, l.createdon, SECOND)) ASC NULLS LAST
  ) = 1
),

match_phone AS (
  SELECT
    c.idcase,
    c.start_time,
    'telefono' AS match_method,
    ABS(TIMESTAMP_DIFF(c.start_time, l.createdon, SECOND)) AS match_time_delta_sec,
    l.usuario_primera_key,
    l.parentcontact_key
    /* + mismos campos CRM que match_dni */
  FROM casos_norm AS c
  INNER JOIN leads_by_phone AS l
    ON c.phone_norm = l.phone_norm
  WHERE c.phone_norm IS NOT NULL
    AND (c.dni_norm IS NULL OR c.dni_norm = '')
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY c.idcase, c.start_time
    ORDER BY ABS(TIMESTAMP_DIFF(c.start_time, l.createdon, SECOND)) ASC NULLS LAST
  ) = 1
),

lead_hits AS (
  SELECT * FROM match_dni
  UNION ALL
  SELECT * FROM match_phone
),

-- Enriquecer DESPUÉS del match (no leads_crm masivo):
matched_best AS (
  SELECT
    c.*,
    h.* EXCEPT(idcase, start_time, usuario_primera_key, parentcontact_key),
    su.utp_equipo_trabajoname AS crm_equipo_de_trabajo,
    su.utp_supervisorasignadoidname AS crm_supervisor_asignado,
    op.ownerid,
    op.owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
    op.owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
    op.owneridname,
    op.owneridtype,
    op.owneridyominame,
    op.customerid
  FROM casos_norm AS c
  LEFT JOIN lead_hits AS h
    ON h.idcase = c.idcase
   AND h.start_time = c.start_time
  LEFT JOIN systemusers_latest AS su
    ON su.systemuserid_key = h.usuario_primera_key
  LEFT JOIN opportunities_latest AS op
    ON op.customerid_key = h.parentcontact_key
)
```

En `leads_latest` / `systemusers_latest` / `opportunities_latest` preparar llaves una sola vez:

```sql
NULLIF(TRIM(SAFE_CAST(utp_usuario_primera_actividad_exitosa AS STRING)), '') AS usuario_primera_key,
NULLIF(TRIM(SAFE_CAST(parentcontactid AS STRING)), '') AS parentcontact_key
-- systemusers: systemuserid_key
-- opportunities: customerid_key
```

Joins sin `UPPER(...)`.

En `v_onemarketer_caso_crm_lead` el `UNION ALL` de “casos sin match” deja de hacer falta si usás `LEFT JOIN lead_hits` desde `casos_norm` (los sin lead quedan con CRM en NULL).

En `v_onemarketer_lead_conversaciones` aplicar el mismo split en el CTE que hoy hace `INNER JOIN leads_crm … OR …` (aprox. líneas 222–234); el resto del agregate por `leadid` puede quedarse.

### Deploy OneMarketer

```bash
bq query --use_legacy_sql=false --location=us-central1 \
  --project_id=prd-utpbi-data-operation \
  < onemarketer/bigquery/views/v_onemarketer_caso_crm_lead.sql

bq query --use_legacy_sql=false --location=us-central1 \
  --project_id=prd-utpbi-data-operation \
  < onemarketer/bigquery/views/v_onemarketer_lead_conversaciones.sql
```

Checks:

```sql
SELECT *
FROM `prd-utpbi-data-operation.raw_onemarketer.v_onemarketer_caso_crm_lead`
WHERE case_date = '2026-10-01'
LIMIT 100;

SELECT *
FROM `prd-utpbi-data-operation.raw_onemarketer.v_onemarketer_lead_conversaciones`
LIMIT 100;
```

Spot-check semántica (mismo día, antes vs después):

```sql
SELECT idcase, start_time, leadid, match_method
FROM `prd-utpbi-data-operation.raw_onemarketer.v_onemarketer_caso_crm_lead`
WHERE case_date = '2026-10-01'
ORDER BY idcase
LIMIT 200;
```

---

## Checklist rápida

- [ ] Pull del monorepo en la otra PC
- [ ] Deploy QueueSmart `v_queuesmart_counter_crm_lead`
- [ ] Reescribir OneMarketer `v_onemarketer_caso_crm_lead` (sin OR)
- [ ] Reescribir OneMarketer `v_onemarketer_lead_conversaciones` (sin OR)
- [ ] Deploy ambas vistas OM
- [ ] Comparar slot time + `leadid` / `match_method` en un día muestra

## Nota

Los snapshots de `leads` / `systemusers` / `opportunities` siguen escaneándose enteros en cada query (limitación de vista). Si el slot time sigue alto después de quitar el OR, el siguiente paso es materializar un snapshot CRM diario.
