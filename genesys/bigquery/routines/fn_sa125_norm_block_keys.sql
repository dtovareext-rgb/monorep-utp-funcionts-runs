-- Normaliza keys de bloque Paul (titulos largos) a A/B/.../P
-- Usa prefijo "X." para no depender de acentos / en-dash / \\uXXXX
-- Location: US

CREATE OR REPLACE FUNCTION `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_norm_block_keys`(json_text STRING)
RETURNS STRING
LANGUAGE js
AS r"""
  if (json_text === null || json_text === undefined || json_text === "") return null;
  let obj;
  try { obj = JSON.parse(json_text); } catch (e) { return null; }
  if (obj === null || typeof obj !== "object" || Array.isArray(obj)) return json_text;
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    let nk = k;
    if (/^[A-P]$/.test(k)) {
      nk = k;
    } else {
      const m = /^([A-P])\./.exec(k);
      if (m) nk = m[1];
    }
    out[nk] = v;
  }
  return JSON.stringify(out);
""";
