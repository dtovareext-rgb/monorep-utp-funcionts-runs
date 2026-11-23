-- Post-proceso SA-125 (validación 100 / hallazgos Data)
-- Cascada SIN_CONTACTO, NA estado/canal, oferta, encoding, TRUNCADA.
-- Location: US
--
-- FIX: mutaciones deben ir sobre los mismos objetos que se serializan en root
-- (antes walkFix dejaba root.* apuntando a copias sin cascada).

CREATE OR REPLACE FUNCTION `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_postprocess`(
  json_text STRING,
  cola_nombre STRING,
  transcript_len INT64
)
RETURNS STRING
LANGUAGE js
AS r"""
  if (json_text === null || json_text === undefined || json_text === "") return null;
  let root;
  try { root = JSON.parse(json_text); } catch (e) { return json_text; }
  if (!root || typeof root !== "object" || Array.isArray(root)) return json_text;

  function ensureObj(key) {
    if (!root[key] || typeof root[key] !== "object" || Array.isArray(root[key])) root[key] = {};
    return root[key];
  }

  const A = ensureObj("A");
  const B = ensureObj("B");
  const C = ensureObj("C");
  const D = ensureObj("D");
  const E = ensureObj("E");
  const F = ensureObj("F");
  const G = ensureObj("G");
  const H = ensureObj("H");
  const I = ensureObj("I");
  const J = ensureObj("J");
  const K = ensureObj("K");
  const L = ensureObj("L");
  const N = ensureObj("N");
  const P = ensureObj("P");

  const NA = "NA";
  const cola = (cola_nombre || "").toString();
  const isAdmision = /admisi[oó]n/i.test(cola);
  const tlen = transcript_len == null ? 0 : Number(transcript_len);

  function isBlank(v) {
    return v === null || v === undefined || (typeof v === "string" && v.trim() === "");
  }
  function isNA(v) {
    if (isBlank(v)) return true;
    if (typeof v === "string" && v.trim().toUpperCase() === "NA") return true;
    return false;
  }
  function eq(v, ...opts) {
    if (v === null || v === undefined) return false;
    const s = String(v).trim().toUpperCase();
    return opts.some(o => String(o).trim().toUpperCase() === s);
  }
  function looksNoMenciona(v) {
    return typeof v === "string" && /no\s*se\s*menciona/i.test(v);
  }

  // --- Encoding in-place ---
  function fixText(s) {
    if (typeof s !== "string") return s;
    let t = s;
    // URL-encoding residual (%C3%A1, +)
    for (let i = 0; i < 2; i++) {
      if (!/%[0-9A-Fa-f]{2}/.test(t)) break;
      try { t = decodeURIComponent(t.replace(/\+/g, " ")); } catch (e) { break; }
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
    const moji = [
      ["Ã¡","á"],["Ã©","é"],["Ã­","í"],["Ã³","ó"],["Ãº","ú"],["Ã±","ñ"],
      ["Ã","Á"],["Ã‰","É"],["Ã","Í"],["Ã“","Ó"],["Ãš","Ú"],["Ã‘","Ñ"],
      ["Â¿","¿"],["Â¡","¡"]
    ];
    for (const [a, b] of moji) t = t.split(a).join(b);
    // Residuo Gemini: vocal → dígito (todo el día). 0→o|ó 1→á|í 2→í|ú|á 3→e|ó|í 4→a 9→é
    const specials = [
      [/despu[3194]s/gi, "después"],
      [/matr[123]cula/gi, "matrícula"],
      [/matrácula/gi, "matrícula"],
      [/Ingenier[12]a/gi, "Ingeniería"],
      [/ingenier[12]a/gi, "ingeniería"],
      [/Ingenieráa/gi, "Ingeniería"],
      [/ingenieráa/gi, "ingeniería"],
      [/hab3a/gi, "había"],
      [/Dom3nguez/gi, "Domínguez"],
      [/confundi3/gi, "confundí"],
      [/rind3/gi, "rindió"],
      [/inter9s/gi, "interés"],
      [/ofrecenci3/gi, "ofreció"],
      [/telef[03]n/gi, "teléfon"],
      [/n[uú]?mer[023]/gi, "númer"],
      [/v2lido/gi, "válido"],
      [/c[oó]dig[03]/gi, "códig"],
      [/\best3\b/gi, "está"],
      [/\bm4s\b/gi, "más"],
      [/\bp4r4\b/gi, "para"],
      [/\b4si\b/gi, "así"],
      [/\bqu3\b/gi, "que"],
      [/\bd3\b/gi, "de"],
      [/\b3l\b/gi, "el"],
      [/\b3n\b/gi, "en"],
      [/\b3s\b/gi, "es"],
      [/\bm3\b/gi, "me"],
      [/\bs3\b/gi, "se"],
      [/\bt3\b/gi, "te"],
      [/\bl3\b/gi, "le"],
      [/\bl4\b/gi, "la"],
      [/\b4l\b/gi, "al"],
      [/\b3sta\b/gi, "esta"],
      [/\b3ste\b/gi, "este"],
      [/\b3sto\b/gi, "esto"],
      [/\bn0\b/gi, "no"],
      [/\bl0\b/gi, "lo"],
      [/\bc0m0\b/gi, "como"],
      [/\bs0l0\b/gi, "solo"],
      [/\bt0d0\b/gi, "todo"]
    ];
    for (const [re, rep] of specials) t = t.replace(re, rep);
    // 3 = e (antes de asumir ó)
    t = t.replace(/([Dd])3(?=[A-Za-záéíóúñÁÉÍÓÚÑ])/g, "$1e");
    t = t.replace(/([Qq])u3(?=[A-Za-záéíóúñÁÉÍÓÚÑ]|$)/g, "$1ue");
    t = t.replace(/\b3([lns])\b/gi, "e$1");
    // Sufijos -ción / -sión
    t = t.replace(/ci3n/gi, "ción").replace(/si3n/gi, "sión");
    // Futuro -rá (3 o 1 al final: pagar3 / realizar1)
    t = t.replace(/([aei]r)[13]\b/gi, "$1á");
    // 0/3 final → ó | 4 final → a
    t = t.replace(/([A-Za-záéíóúñÁÉÍÓÚÑ])[03]\b/g, "$1ó");
    t = t.replace(/([A-Za-záéíóúñÁÉÍÓÚÑ])4\b/g, "$1a");
    // Entre letras: 0→o, 2→í, 3→ó, 9→é, 1→á, 4→a
    t = t.replace(/([A-Za-záéíóúñÁÉÍÓÚÑ])0([A-Za-záéíóúñÁÉÍÓÚÑ])/g, "$1o$2");
    t = t.replace(/([A-Za-záéíóúñÁÉÍÓÚÑ])2([A-Za-záéíóúñÁÉÍÓÚÑ])/g, "$1í$2");
    t = t.replace(/([A-Za-záéíóúñÁÉÍÓÚÑ])3([A-Za-záéíóúñÁÉÍÓÚÑ])/g, "$1ó$2");
    t = t.replace(/([A-Za-záéíóúñÁÉÍÓÚÑ])9([A-Za-záéíóúñÁÉÍÓÚÑ])/g, "$1é$2");
    t = t.replace(/([A-Za-záéíóúñÁÉÍÓÚÑ])1([A-Za-záéíóúñÁÉÍÓÚÑ])/g, "$1á$2");
    t = t.replace(/([A-Za-záéíóúñÁÉÍÓÚÑ])4([A-Za-záéíóúñÁÉÍÓÚÑ])/g, "$1a$2");
    return t;
  }
  function walkFixInPlace(node) {
    if (typeof node === "string") return fixText(node);
    if (Array.isArray(node)) {
      for (let i = 0; i < node.length; i++) node[i] = walkFixInPlace(node[i]);
      return node;
    }
    if (node && typeof node === "object") {
      for (const k of Object.keys(node)) node[k] = walkFixInPlace(node[k]);
      return node;
    }
    return node;
  }
  walkFixInPlace(root);

  // comentario_mercado: text → texto
  if (I.comentario_mercado && typeof I.comentario_mercado === "object" && !Array.isArray(I.comentario_mercado)) {
    if (I.comentario_mercado.text != null && I.comentario_mercado.texto == null) {
      I.comentario_mercado.texto = I.comentario_mercado.text;
      delete I.comentario_mercado.text;
    }
  }

  // --- calidad / TRUNCADA ---
  let calidad = (A.calidad_transcripcion || "").toString().trim().toUpperCase();
  if (calidad === "TRUNCADA" && tlen > 0 && tlen < 180) {
    calidad = "SIN_CONVERSACION";
    A.calidad_transcripcion = "SIN_CONVERSACION";
  }
  const calidadInvalida = eq(calidad, "VACIA", "SIN_CONVERSACION", "BUCLE_REPETICIONES");

  let contacto = (A.contacto_efectivo || "").toString().trim().toUpperCase();
  if (calidadInvalida) {
    contacto = "NO";
    A.contacto_efectivo = "NO";
  }

  let estado = (D.estado_lead || "").toString().trim().toUpperCase();
  if (calidadInvalida || eq(contacto, "NO")) {
    estado = "SIN_CONTACTO";
    D.estado_lead = "SIN_CONTACTO";
  }

  const sinContacto = eq(estado, "SIN_CONTACTO") || eq(contacto, "NO") || calidadInvalida;
  const esRA = eq(estado, "RA");
  const esSI = eq(estado, "SI");
  const esDS = eq(estado, "DS");
  const esCDE = eq(estado, "CDE");
  const esRAoSI = esRA || esSI;

  function clearOferta() {
    L.oferta_cotizada = null;
  }

  if (sinContacto) {
    A.interlocutor = NA;
    A.motivo_contacto = NA;
    A.tipo_contacto = NA;
    D.resultado_real = NA;
    D.tipificacion_ia = NA;
    D.compromisos = NA;
    D.responsabilidad_no_venta = NA;
    E.motivos_rechazo = NA;
    E.motivo_rechazo_principal = NA;
    E.senal_abandono = NA;
    E.objeciones_textuales = NA;
    E.grupo_friccion = NA;
    E.momento_objecion = NA;
    N.finalizacion_interaccion = NA;
    N.segundo_numero_obtenido = NA;
    N.carga_documento_llamada = NA;
    N.argumentos_urgencia = NA;
    N.informacion_complementaria_brindada = NA;
    clearOferta();
    L.tiempo_hasta_precio_seg = { segundos: null, clasificacion: "SIN_PRECIO" };
    F.recontacto_solicitado = NA;
    F.informacion_solicitada = NA;
    F.canal_preferido = NA;
  }

  if (!esRAoSI) N.segundo_numero_obtenido = NA;
  if (!isAdmision) N.carga_documento_llamada = NA;
  if (!(esRA || esDS || esCDE) || sinContacto) E.senal_abandono = NA;
  if (esDS) N.informacion_complementaria_brindada = NA;
  if (!eq(calidad, "VALIDA")) N.finalizacion_interaccion = NA;
  if (!isAdmision) J.riesgo_desercion = NA;

  // tipificacion / responsabilidad
  if (looksNoMenciona(D.tipificacion_ia)) D.tipificacion_ia = NA;
  if (sinContacto) D.tipificacion_ia = NA;

  if (D.responsabilidad_no_venta && typeof D.responsabilidad_no_venta === "object") {
    const m = String(D.responsabilidad_no_venta.motivo || "");
    const sm = String(D.responsabilidad_no_venta.submotivo || "");
    if (looksNoMenciona(m) || looksNoMenciona(sm) || /CHAT_/i.test(sm) || eq(m, "NA")) {
      D.responsabilidad_no_venta = NA;
    }
  }
  if (sinContacto || esSI) D.responsabilidad_no_venta = NA;

  // oferta_cotizada: sin monto → null; normalizar concepto a enum mayúsculas
  if (L.oferta_cotizada && typeof L.oferta_cotizada === "object") {
    const monto = L.oferta_cotizada.monto_cotizado;
    const hasMonto = monto !== null && monto !== undefined && String(monto).trim() !== "" && !isNaN(Number(monto));
    if (!hasMonto) {
      clearOferta();
    } else if (typeof L.oferta_cotizada.concepto === "string") {
      const c = L.oferta_cotizada.concepto.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toUpperCase();
      if (c.indexOf("MATRIC") >= 0) L.oferta_cotizada.concepto = "MATRICULA";
      else if (c.indexOf("PENSION") >= 0) L.oferta_cotizada.concepto = "PENSION";
      else if (c.indexOf("DERECHO") >= 0 || c.indexOf("POSTUL") >= 0) L.oferta_cotizada.concepto = "DERECHO_POSTULACION";
    }
  }
  if (sinContacto) clearOferta();

  if (L.oferta_cotizada == null) {
    L.tiempo_hasta_precio_seg = { segundos: null, clasificacion: "SIN_PRECIO" };
  } else if (L.tiempo_hasta_precio_seg && typeof L.tiempo_hasta_precio_seg === "object") {
    const seg = Number(L.tiempo_hasta_precio_seg.segundos);
    if (!isNaN(seg) && seg >= 0) {
      let clas = "TARDIO";
      if (seg < 120) clas = "TEMPRANO";
      else if (seg <= 300) clas = "MEDIO";
      L.tiempo_hasta_precio_seg.clasificacion = clas;
    }
  }

  return JSON.stringify(root);
""";
