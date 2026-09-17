"""Generate BQ UPDATEs for utp_pront_instruccions from patched txt prompts."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROMPTS = ROOT / "docs" / "prompts_canal_hablado"
OUT = ROOT / "bigquery" / "sqls" / "update_utp_pront_instruccions_pecneg_sae_otra_u.sql"

# filename → (tipificacion, cmr_rango)
MAP = {
    "01_RA_le18.txt": ("RA", "<=18"),
    "02_RA_19-23.txt": ("RA", "19-23"),
    "03_RA_ge24.txt": ("RA", ">=24"),
    "04_RA_Sin_Edad.txt": ("RA", "Sin Edad"),
    "05_DS-SI_le18.txt": ("DS-SI", "<=18"),
    "06_DS-SI_19-23.txt": ("DS-SI", "19-23"),
    "07_DS-SI_ge24.txt": ("DS-SI", ">=24"),
    "08_DS-SI_Sin_Edad.txt": ("DS-SI", "Sin Edad"),
    "09_OUTPUT_NA.txt": ("OUTPUT", "NA"),
}


def to_bq_triple_quoted(text: str) -> str:
    # BigQuery '''...''': escape only the ''' sequence if present.
    safe = text.replace("'''", r"\'\'\'")
    return f"'''{safe}'''"


def main() -> None:
    parts: list[str] = [
        "-- =============================================================================",
        "-- UPDATE utp_pront_instruccions — calibración PECNEG (SAE + otra universidad)",
        "-- Generado desde genesys/docs/prompts_canal_hablado/*.txt",
        "--",
        "-- Cloud Shell (región us-central1 — dataset raw_genesys_audios):",
        "--   bq query --use_legacy_sql=false --location=us-central1 \\",
        "--     --project_id=prd-utpbi-data-operation \\",
        "--     < update_utp_pront_instruccions_pecneg_sae_otra_u.sql",
        "--",
        "-- Luego refrescar prompts en audios del día y reprocesar Gen IA:",
        "--   CALL sp_utpbi_genesys_update_prompt(...);",
        "--   CALL sp_utpbi_do_ia_speech(...);",
        "-- =============================================================================",
        "",
    ]

    for fname, (tip, rango) in MAP.items():
        text = (PROMPTS / fname).read_text(encoding="utf-8")
        lit = to_bq_triple_quoted(text)
        parts.append(
            f"""UPDATE `prd-utpbi-data-operation.raw_genesys_audios.utp_pront_instruccions`
SET instrucciones = {lit}
WHERE tipificacion = '{tip}'
  AND cmr_rango = '{rango}';
"""
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(parts), encoding="utf-8")
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
