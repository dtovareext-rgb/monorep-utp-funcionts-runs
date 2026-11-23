-- Limpia texto free-form para capa flat: HTML entities + URL-encoding.
-- Location: US

CREATE OR REPLACE FUNCTION `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(
  txt STRING
)
RETURNS STRING
LANGUAGE js
AS r"""
  if (txt === null || txt === undefined) return null;
  let t = String(txt);
  if (t === "") return t;

  for (let i = 0; i < 2; i++) {
    if (!/%[0-9A-Fa-f]{2}/.test(t)) break;
    try {
      t = decodeURIComponent(t.replace(/\+/g, " "));
    } catch (e) {
      break;
    }
  }

  t = t.replace(/&#x([0-9a-fA-F]+);/g, (_, h) => {
    try { return String.fromCharCode(parseInt(h, 16)); } catch (e) { return _; }
  });
  t = t.replace(/&#(\d+);/g, (_, n) => {
    try { return String.fromCharCode(parseInt(n, 10)); } catch (e) { return _; }
  });
  t = t.replace(/&([a-zA-Z]+);/g, (_, name) => {
    const map = {
      aacute:"á", eacute:"é", iacute:"í", oacute:"ó", uacute:"ú", ntilde:"ñ",
      Aacute:"Á", Eacute:"É", Iacute:"Í", Oacute:"Ó", Uacute:"Ú", Ntilde:"Ñ",
      uuml:"ü", Uuml:"Ü", quot:'"', amp:"&", lt:"<", gt:">", nbsp:" ",
      apos:"'", rsquo:"'", lsquo:"'", rdquo:'"', ldquo:'"'
    };
    return map[name] != null ? map[name] : _;
  });

  return t;
""";
