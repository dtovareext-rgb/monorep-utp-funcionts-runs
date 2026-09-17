#!/usr/bin/env bash
# Extrae utp_pront_instruccions → un .txt por fila en genesys/docs/prompts_canal_hablado/
#
# Uso (Cloud Shell):
#   bash extract_utp_pront_instruccions.sh
#   # o con carpeta destino:
#   OUT_DIR=~/prompts_canal_hablado bash extract_utp_pront_instruccions.sh

set -euo pipefail

PROJECT="${PROJECT_ID:-prd-utpbi-data-operation}"
OUT_DIR="${OUT_DIR:-$(cd "$(dirname "$0")/.." && pwd)/docs/prompts_canal_hablado}"
TMP_JSON="$(mktemp)"

mkdir -p "$OUT_DIR"

echo "=== Query utp_pront_instruccions (project=$PROJECT) ==="
bq query --use_legacy_sql=false --format=json --max_rows=100 \
  --project_id="$PROJECT" \
  "SELECT tipificacion, cmr_rango, instrucciones
   FROM \`${PROJECT}.raw_genesys_audios.utp_pront_instruccions\`
   ORDER BY tipificacion, cmr_rango" > "$TMP_JSON"

python3 - <<'PY' "$TMP_JSON" "$OUT_DIR"
import json, re, sys
from pathlib import Path

src, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
rows = json.loads(src.read_text(encoding="utf-8"))

def slug(s: str) -> str:
    s = (s or "NA").strip()
    s = s.replace("<=", "le").replace(">=", "ge").replace("<", "lt").replace(">", "gt")
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", s)
    return s.strip("_") or "NA"

index_lines = ["# Prompts canal hablado — utp_pront_instruccions", ""]
for i, row in enumerate(rows, 1):
    tip = row.get("tipificacion") or "NA"
    rango = row.get("cmr_rango") or "NA"
    text = row.get("instrucciones") or ""
    name = f"{i:02d}_{slug(tip)}_{slug(rango)}.txt"
    path = out_dir / name
    path.write_text(text, encoding="utf-8")
    index_lines.append(f"- `{name}` — tipificacion={tip} | cmr_rango={rango} | chars={len(text)}")
    print(f"Wrote {path} ({len(text)} chars)")

(out_dir / "INDEX.md").write_text("\n".join(index_lines) + "\n", encoding="utf-8")
print(f"\nOK: {len(rows)} archivos en {out_dir}")
PY

rm -f "$TMP_JSON"
echo "=== Listo: $OUT_DIR ==="
ls -la "$OUT_DIR"
