// Nova 2 for the web: the same code-drawn, rigged character as the app
// (ported from docs/character/index.html, the approved prototype).
// Exposes window.Nova2 = { LiveNova, Scenes, Snd, Music, nova, SKINS, MOODS, R }.
(() => {
"use strict";
const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
const C = { amber: "#FFB454", coral: "#FF7A8A", mint: "#5BE49B", cyan: "#53E7FF", pink: "#FF9EC2", violet: "#A36CFF" };
const SKINS = {
  aurora:   { name: "Aurora",   note: "Default",              fur1: "#FFFFFF", fur2: "#E4E1FA", rim: "#A99CF5", glow1: "#5FE3FF", glow2: "#8B6CFF", visor1: "#1C1F38", visor2: "#05060D", eye: "#78CFFF", collar: "#22264A" },
  midnight: { name: "Midnight", note: "Charcoal, cyan glow",  fur1: "#5A5F78", fur2: "#2B2F47", rim: "#53E7FF", glow1: "#53E7FF", glow2: "#2F86FF", visor1: "#0E1426", visor2: "#000000", eye: "#86F4FF", collar: "#0B0E1A" },
  sakura:   { name: "Sakura",   note: "Pale pink, warm eyes", fur1: "#FFF7F9", fur2: "#F7D6E1", rim: "#FF9EC2", glow1: "#FFC4D8", glow2: "#FF7FAF", visor1: "#2B1A25", visor2: "#0C0609", eye: "#FFEBD9", collar: "#3B2331" },
  neon:     { name: "Neon",     note: "Magenta and green rim", fur1: "#34343F", fur2: "#16161D", rim: "#FF4FD8", glow1: "#4FFFA8", glow2: "#FF4FD8", visor1: "#101017", visor2: "#000000", eye: "#4FFFA8", collar: "#000000" },
  gold:     { name: "Gold",     note: "Pearl and gold trim",  fur1: "#FFFDF6", fur2: "#EEE3C8", rim: "#E2B04E", glow1: "#FFE08A", glow2: "#E8A93C", visor1: "#201B12", visor2: "#060504", eye: "#FFD978", collar: "#B98A2E" },
};
const MOODS = {
  idle:         { eyes: "pill",   tilt: 0,   turn: 0,    earL: 0,   earR: 0,   gaze: 0,    paws: "rest",  tail: "",      note: "breathes, blinks, fidgets" },
  happy:        { eyes: "arc",    tilt: -5,  turn: 0,    earL: 8,   earR: 8,   gaze: 0,    paws: "rest",  tail: "fast",  chest: "mint", note: "hops, wags its tail" },
  thinking:     { eyes: "lookup", tilt: 9,   turn: 0.3,  earL: -2,  earR: 6,   gaze: 0.5,  paws: "chin",  tail: "",      fx: "dots", note: "paw to chin, looks up" },
  coding:       { eyes: "focus",  tilt: 0,   turn: 0,    earL: 4,   earR: 4,   gaze: 0,    paws: "type",  tail: "still", fx: "code", note: "focused, paws typing" },
  typing:       { eyes: "focus",  tilt: 3,   turn: -0.2, earL: 2,   earR: 2,   gaze: -0.3, paws: "type",  tail: "still", note: "taps a tiny keyboard" },
  listening:    { eyes: "tall",   tilt: -9,  turn: -0.25,earL: 14,  earR: 10,  gaze: -0.4, paws: "rest",  tail: "",      fx: "waves", note: "ears up, head cocked" },
  surprised:    { eyes: "wide",   tilt: 0,   turn: 0,    earL: 16,  earR: 16,  gaze: 0,    paws: "cover", tail: "still", fx: "bang", note: "startles, paws up" },
  warning:      { eyes: "pill",   tilt: 4,   turn: 0,    earL: -6,  earR: -4,  gaze: 0,    paws: "rest",  tail: "still", eye: "amber", chest: "amber", fx: "sweat", note: "amber eyes and chest" },
  error:        { eyes: "x",      tilt: 6,   turn: 0,    earL: -16, earR: -16, gaze: 0,    paws: "cover", tail: "still", eye: "coral", chest: "coral", note: "flinches, ears flat" },
  sleepy:       { eyes: "half",   tilt: 7,   turn: 0,    earL: -10, earR: -8,  gaze: 0,    paws: "rest",  tail: "",      note: "heavy lids, ears sag" },
  sleeping:     { eyes: "closed", tilt: 11,  turn: 0,    earL: -18, earR: -18, gaze: 0,    paws: "rest",  tail: "still", fx: "zzz", drop: 6, note: "curled down, zzz" },
  excited:      { eyes: "arc",    tilt: 0,   turn: 0,    earL: 15,  earR: 15,  gaze: 0,    paws: "up",    tail: "fast",  fx: "sparkle", hop: true, note: "hops, both paws up" },
  confused:     { eyes: "uneven", tilt: -12, turn: 0.2,  earL: 10,  earR: -10, gaze: 0.2,  paws: "rest",  tail: "",      fx: "q", note: "head shake, one ear down" },
  annoyed:      { eyes: "flat",   tilt: 0,   turn: 0.35, earL: -9,  earR: -9,  gaze: 0.6,  paws: "rest",  tail: "fast",  note: "flat eyes, side glance" },
  success:      { eyes: "arc",    tilt: -4,  turn: 0,    earL: 12,  earR: 12,  gaze: 0,    paws: "wave",  tail: "fast",  eye: "mint", chest: "mint", hop: true, note: "cheers, confetti" },
  loading:      { eyes: "dots",   tilt: 0,   turn: 0,    earL: 3,   earR: 3,   gaze: 0,    paws: "rest",  tail: "",      note: "dots run across visor" },
  dizzy:        { eyes: "spiral", tilt: 13,  turn: 0,    earL: 6,   earR: -12, gaze: 0,    paws: "rest",  tail: "still", fx: "stars", note: "spiral eyes, stars" },
  notification: { eyes: "pill",   tilt: -4,  turn: 0,    earL: 12,  earR: 12,  gaze: 0,    paws: "wave",  tail: "",      fx: "badge", note: "waves, badge pops" },
};
const PAWS = { rest: [12, -12], type: [-6, 6], wave: [12, -132], up: [128, -128], chin: [12, 132], cover: [-158, 158] };
const col = (v, fb) => (v && C[v]) || v || fb;
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const TAU = Math.PI * 2;
let uid = 0;

function poseFor(mood) {
  const m = MOODS[mood] || MOODS.idle, pw = PAWS[m.paws] || PAWS.rest;
  return { mood, eyes: m.eyes, eyeC: col(m.eye, null), chestC: col(m.chest, null), fx: m.fx, tilt: m.tilt, turn: m.turn, earL: m.earL, earR: m.earR,
    gx: m.gaze, gy: 0, pawL: pw[0], pawR: pw[1], pawState: m.paws, tail: 0, tailMode: m.tail, sy: 1, bx: 0, dy: m.drop || 0, lean: 0, hy: 0,
    chest: 1, blink: 1, laptop: m.paws === "type", hop: !!m.hop, variant: "pearl", skin: "aurora" };
}

/* ---------- Drawing ---------- */
function eyes(type, x0, y, c, gx, gy, min, t) {
  const d = 19, ox = gx * 7, oy = gy * 5, w = min ? 13 : 11, h = min ? 24 : 22, sw = min ? 6.5 : 5;
  y += oy;
  const at = (f) => [-1, 1].map((s) => f(x0 + s * d + ox, s)).join("");
  const stroke = (p, wd = sw) => `<path d="${p}" fill="none" stroke="${c}" stroke-width="${wd}" stroke-linecap="round" stroke-linejoin="round"/>`;
  const pill = (x, yy, ww, hh) => `<rect x="${x - ww / 2}" y="${yy - hh / 2}" width="${ww}" height="${hh}" rx="${ww / 2}" fill="${c}"/>`;
  switch (type) {
    case "arc": return at((x) => stroke(`M${x - 9} ${y + 4} Q${x} ${y - 9} ${x + 9} ${y + 4}`));
    case "closed": return at((x) => stroke(`M${x - 9} ${y + 1} Q${x} ${y + 7} ${x + 9} ${y + 1}`));
    case "half": return at((x) => pill(x, y + 4, w, h * 0.45));
    case "focus": return at((x) => pill(x, y + 1, w, h * 0.62));
    case "tall": return at((x) => pill(x, y - 1, w + 1, h + 4));
    case "wide": return at((x) => `<circle cx="${x}" cy="${y}" r="10" fill="${c}"/><circle cx="${x + 3}" cy="${y - 3}" r="3" fill="#fff" opacity=".85"/>`);
    case "lookup": return at((x) => pill(x + 3, y - 6, w, h * 0.8));
    case "x": return at((x) => stroke(`M${x - 7} ${y - 7} L${x + 7} ${y + 7} M${x + 7} ${y - 7} L${x - 7} ${y + 7}`));
    case "flat": return at((x, s) => pill(x, y + 4, w + 2, h * 0.42) + stroke(`M${x - 8} ${y - 6 - s * 2} L${x + 8} ${y - 6 + s * 2}`, sw * 0.6));
    case "uneven": return pill(x0 - d + ox, y, w, h) + `<circle cx="${x0 + d + ox}" cy="${y + 2}" r="6" fill="${c}"/>`;
    case "dots": return `<g class="n-dots">${[-20, 0, 20].map((o) => `<circle cx="${x0 + o}" cy="${y}" r="5.5" fill="${c}"/>`).join("")}</g>`;
    case "spiral": return at((x) => stroke(`M${x} ${y} m-2 0 a2 2 0 1 1 4 0 a4 4 0 1 1 -8 0 a6 6 0 1 1 12 0`, 3));
    case "hum": {
      let p = "";
      for (let i = 0; i <= 28; i++) { const u = i / 28, xx = x0 - 34 + u * 68, env = Math.sin(u * Math.PI); p += `${i ? "L" : "M"}${xx.toFixed(1)} ${(y + Math.sin(u * 14 + (t || 0) * 9) * 8 * env).toFixed(1)}`; }
      return stroke(p, 4);
    }
    default: return at((x) => pill(x, y, w, h));
  }
}
function star(x, y, r, c, op = 1) {
  const k = r * 0.32;
  return `<path d="M${x} ${y - r} Q${x + k} ${y - k} ${x + r} ${y} Q${x + k} ${y + k} ${x} ${y + r} Q${x - k} ${y + k} ${x - r} ${y} Q${x - k} ${y - k} ${x} ${y - r}Z" fill="${c}" opacity="${op}"/>`;
}
function heart(x, y, r, c, op) {
  return `<path d="M${x} ${y + r * .9} C${x - r * 1.6} ${y - r * .2} ${x - r * .7} ${y - r * 1.4} ${x} ${y - r * .4} C${x + r * .7} ${y - r * 1.4} ${x + r * 1.6} ${y - r * .2} ${x} ${y + r * .9}Z" fill="${c}" opacity="${op}"/>`;
}
function fx(kind, s) {
  const g = s.glow1;
  switch (kind) {
    case "sparkle": return star(40, 58, 9, g) + star(204, 70, 7, s.glow2) + star(196, 30, 5, g);
    case "dots": return `<g class="n-dots"><circle cx="186" cy="46" r="4" fill="${g}"/><circle cx="198" cy="34" r="5.5" fill="${g}"/><circle cx="214" cy="20" r="7.5" fill="${g}"/></g>`;
    case "code": return `<text x="198" y="44" text-anchor="middle" font-family="ui-monospace, Menlo, monospace" font-weight="700" font-size="15" fill="${g}">&lt;/&gt;</text>`;
    case "waves": return `<g fill="none" stroke="${g}" stroke-width="3" stroke-linecap="round"><path d="M200 70 q8 12 0 24" opacity=".9"/><path d="M210 62 q13 20 0 40" opacity=".55"/></g>`;
    case "bang": return `<circle cx="196" cy="40" r="13" fill="${C.amber}"/><rect x="194" y="30" width="4" height="12" rx="2" fill="#1A1206"/><circle cx="196" cy="47.5" r="2.3" fill="#1A1206"/>`;
    case "sweat": return `<path d="M188 64 q-7 10 0 14 q7 -4 0 -14Z" fill="${C.cyan}" opacity=".9"/>`;
    case "zzz": return `<g class="n-z" font-family="Bricolage Grotesque, system-ui, sans-serif" font-weight="800" fill="${g}"><text x="182" y="62" font-size="14">z</text><text x="194" y="46" font-size="18">z</text><text x="208" y="26" font-size="23">Z</text></g>`;
    case "q": return `<text x="200" y="52" text-anchor="middle" font-family="Bricolage Grotesque, system-ui, sans-serif" font-weight="800" font-size="30" fill="${g}">?</text>`;
    case "badge": return `<circle cx="190" cy="38" r="15" fill="${C.coral}" opacity=".25"/><circle cx="190" cy="38" r="9" fill="${C.coral}"/>`;
    case "stars": return `<g class="n-spin">${star(84, 30, 7, C.amber)}${star(156, 30, 6, g)}${star(120, 12, 5, C.amber)}</g>`;
    default: return "";
  }
}
function arm(side, ang, cls, id, s, min) {
  const sh = [120 + side * 31, 170];
  const pad = min ? "" : `<circle cx="0" cy="31" r="3.6" fill="${s.glow1}" filter="url(#${id}g)"/>`;
  const reach = 1 + clamp((Math.abs(ang) - 60) / 60, 0, 1) * 0.3;
  return { svg: `<g transform="translate(${sh[0]} ${sh[1]}) rotate(${ang.toFixed(2)}) scale(1 ${reach.toFixed(3)})"><g class="${cls}" style="transform-origin:0 0"><ellipse cx="0" cy="17" rx="10.5" ry="18" fill="url(#${id}f)"/>${pad}</g></g>`, front: Math.abs(ang) > 90 };
}

// Draw one frame of Nova 2 from a numeric pose. css: use CSS loops (static drawings) instead of script-driven motion.
function draw(p, o = {}) {
  const s = SKINS[p.skin] || SKINS.aurora, v = p.variant, min = !!o.min, id = "n" + uid++, css = !!o.css;
  const turn = p.turn, vx = 120 + turn * 11, ex = 120 + turn * 15, vy = 100;
  const eyeC = p.eyeC || s.eye, chestC = p.chestC || s.glow1;
  const defs = `<defs>
    <radialGradient id="${id}f" cx="36%" cy="28%" r="78%"><stop offset="0" stop-color="${s.fur1}"/><stop offset=".72" stop-color="${s.fur2}"/><stop offset="1" stop-color="${s.rim}"/></radialGradient>
    <linearGradient id="${id}e" x1="0" y1="1" x2=".4" y2="0"><stop offset="0" stop-color="${s.glow2}"/><stop offset="1" stop-color="${s.glow1}"/></linearGradient>
    <linearGradient id="${id}v" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${s.visor1}"/><stop offset="1" stop-color="${s.visor2}"/></linearGradient>
    <clipPath id="${id}c"><ellipse cx="${vx}" cy="${vy}" rx="51" ry="37"/></clipPath>
    <filter id="${id}g" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="${min ? 1.4 : 2.6}" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>`;
  const earPath = (a) => `<g transform="rotate(${(-a).toFixed(2)} 72 84)"><path d="M54 92 C46 60 52 32 66 16 C82 30 98 48 106 62 Z" fill="url(#${id}f)"/><path d="M64 80 C60 60 63 42 69 30 C79 41 89 52 95 62 Z" fill="url(#${id}e)" opacity=".95"/></g>`;
  const ears = `<g transform="translate(${(-turn * 4).toFixed(2)} 0)">${earPath(p.earL)}<g transform="translate(240 0) scale(-1 1)">${earPath(p.earR)}</g></g>`;
  const tufts = min ? "" : `<path d="M54 112 l-14 -4 l10 10 l-12 2 l16 8Z M186 112 l14 -4 l-10 10 l12 2 l-16 8Z" fill="url(#${id}f)"/>`;
  const shine = min ? "" : `<path d="M${vx - 36 - turn * 6} ${vy - 14} Q${vx - 26 - turn * 6} ${vy - 30} ${vx - 4 - turn * 6} ${vy - 32}" fill="none" stroke="#fff" stroke-opacity=".32" stroke-width="5" stroke-linecap="round"/>`;
  const shield = p.shield != null ? `<g clip-path="url(#${id}c)"><rect x="${vx - 80 + p.shield * 160}" y="40" width="16" height="120" fill="#fff" opacity=".35" transform="rotate(20 ${vx} ${vy})"/></g><ellipse cx="${vx}" cy="${vy}" rx="53" ry="39" fill="none" stroke="${C.coral}" stroke-width="2" opacity="${(.4 + .3 * Math.sin(p.shield * TAU)).toFixed(2)}"/>` : "";
  const phonesBand = p.phones ? `<path d="M${54 - turn * 3} 92 C${54 - turn * 3} 14 ${186 - turn * 3} 14 ${186 - turn * 3} 92" fill="none" stroke="${s.collar}" stroke-width="8" stroke-linecap="round"/>` : "";
  const phonesCups = p.phones ? [-1, 1].map((sd) => { const x = 120 + sd * 68 - turn * 3; return `<rect x="${x - 11}" y="78" width="22" height="40" rx="10" fill="${s.collar}"/><rect x="${x - 4}" y="86" width="8" height="24" rx="4" fill="${s.glow1}" opacity=".85" filter="url(#${id}g)"/>`; }).join("") : "";
  const blinkT = `translate(0 ${vy}) scale(1 ${clamp(p.blink, 0.06, 1).toFixed(3)}) translate(0 ${-vy})`;
  const head = `${ears}${tufts}
    <ellipse cx="120" cy="96" rx="${70 - Math.abs(turn) * 4}" ry="58" fill="url(#${id}f)"/>
    <ellipse cx="${120 - turn * 2}" cy="42" rx="15" ry="9" fill="url(#${id}f)"/>
    ${phonesBand}
    <ellipse cx="${vx}" cy="${vy}" rx="51" ry="37" fill="url(#${id}v)" stroke="${s.rim}" stroke-opacity=".35" stroke-width="1.5"/>
    ${shine}${shield}
    <g filter="url(#${id}g)"><g transform="${blinkT}"><g class="${css ? "n-blink" : ""}">${eyes(p.eyes, ex, vy, eyeC, p.gx || 0, p.gy || 0, min, p.t)}</g></g></g>
    ${phonesCups}`;
  const chestGlow = clamp(p.chest, 0, 3);
  const collar = `<path d="M82 148 Q120 166 158 148 L156 160 Q120 180 84 160Z" fill="${s.collar}"/>
    ${chestGlow > 1.05 ? `<circle cx="120" cy="167" r="${8 + chestGlow * 5}" fill="${chestC}" opacity="${((chestGlow - 1) * .25).toFixed(2)}"/>` : ""}
    <path d="M113 163 L127 163 L120 174Z" fill="${chestC}" opacity="${clamp(.55 + chestGlow * .45, 0, 1).toFixed(2)}" filter="url(#${id}g)"/>`;
  const ox = (o.offX || 0), oy = (o.offY || 0);
  let back = "", body = "", wrapCls = css && p.hop ? "n-hop" : "";

  if (v === "peek") {
    const liftL = clamp((p.pawL - 12) * 0.1, -4, 16), liftR = clamp(-(p.pawR + 12) * 0.1, -4, 16);
    const head2 = `<g transform="translate(${p.bx + ox} ${34 + p.dy + p.hy + oy}) rotate(${(p.tilt + p.lean).toFixed(2)} 120 150)">${head}</g>`;
    const paws = [[-1, liftL], [1, liftR]].map(([sd, l]) => { const x = 120 + sd * 34 + p.bx + ox, y = 186 - l; return `<ellipse cx="${x}" cy="${y}" rx="12" ry="9" fill="url(#${id}f)"/>${min ? "" : `<circle cx="${x}" cy="${y + 3}" r="3" fill="${s.glow1}" filter="url(#${id}g)"/>`}`; }).join("");
    body = `${head2}<rect x="6" y="186" width="228" height="54" rx="22" fill="#000"/><rect x="6" y="186" width="228" height="10" fill="#000"/>${paws}`;
    wrapCls = "";
  } else {
    const isWave = p.pawState === "wave", isType = p.pawState === "type";
    const a = [arm(-1, p.pawL, css && isType ? "n-type" : "", id, s, min), arm(1, p.pawR, css ? (isWave ? "n-wave" : isType ? "n-type b" : "") : "", id, s, min)];
    const armsBack = a.filter((x) => !x.front).map((x) => x.svg).join(""), armsFront = a.filter((x) => x.front).map((x) => x.svg).join("");
    const laptop = p.laptop ? `<path d="M84 206 L156 206 L164 216 L76 216Z" fill="${s.collar}"/><rect x="92" y="200" width="56" height="7" rx="2" fill="${s.glow1}" opacity=".55"/>` : "";
    const lift = clamp(-(p.dy) / 40, 0, 0.6);
    if (v === "orbit") {
      back = `<ellipse cx="${120 + p.bx + ox}" cy="224" rx="${44 * (1 - lift * .4)}" ry="7" fill="none" stroke="${s.glow1}" stroke-width="3" opacity=".7" filter="url(#${id}g)"/><ellipse cx="${120 + p.bx + ox}" cy="224" rx="26" ry="4" fill="${s.glow1}" opacity=".25"/>`;
      body = `<path d="M90 160 C86 196 106 214 120 214 C134 214 154 196 150 160Z" fill="url(#${id}f)"/><ellipse cx="120" cy="152" rx="44" ry="8" fill="#000" opacity=".14"/><g transform="translate(0 4)">${armsBack}</g>${collar}${laptop}`;
      if (css) wrapCls = (wrapCls + " n-float").trim();
    } else {
      back = `<ellipse cx="${120 + p.bx + ox}" cy="226" rx="${54 * (1 - lift * .5)}" ry="7" fill="#000" opacity="${(.28 * (1 - lift)).toFixed(2)}"/>`;
      const tailCls = css ? `n-tail ${p.tailMode || ""}` : "";
      body = `<g transform="translate(150 206) rotate(${p.tail.toFixed(2)})"><g class="${tailCls}" style="transform-origin:0 0">
          <path d="M0 0 C40 2 52 -36 34 -56" fill="none" stroke="url(#${id}f)" stroke-width="17" stroke-linecap="round"/>
          <circle cx="34" cy="-58" r="11" fill="url(#${id}e)" ${min ? "" : `filter="url(#${id}g)"`}/></g></g>
        <ellipse cx="120" cy="188" rx="45" ry="36" fill="url(#${id}f)"/>
        <ellipse cx="120" cy="194" rx="25" ry="19" fill="#fff" opacity=".35"/>
        <ellipse cx="120" cy="153" rx="46" ry="8" fill="#000" opacity=".13"/>
        ${[-1, 1].map((sd) => `<ellipse cx="${120 + sd * 23}" cy="218" rx="15" ry="9" fill="url(#${id}f)"/>${min ? "" : `<circle cx="${120 + sd * 23}" cy="220" r="3.6" fill="${s.glow1}" filter="url(#${id}g)"/>`}`).join("")}
        ${armsBack}${collar}${laptop}`;
    }
    body += `<g transform="translate(0 ${p.hy.toFixed(2)}) rotate(${p.tilt.toFixed(2)} 120 150)">${head}</g>${armsFront}`;
    const sx = 1 / Math.sqrt(p.sy);
    body = `<g transform="translate(${(p.bx + ox).toFixed(2)} ${(p.dy + oy).toFixed(2)}) translate(120 228) rotate(${p.lean.toFixed(2)}) scale(${sx.toFixed(4)} ${p.sy.toFixed(4)}) translate(-120 -228)">${body}</g>`;
  }
  const vb = o.crop === "head" ? "44 10 152 140" : (o.viewBox || "0 0 240 240");
  const extras = o.extras || "";
  return `<svg viewBox="${vb}" role="img" aria-label="Nova 2, ${p.mood}">${defs}${o.under || ""}<g class="${wrapCls}"><g class="${css ? "n-breathe" : ""}">${back}${body}</g></g>${o.noFx ? "" : fx(p.fx, s)}${extras}</svg>`;
}
function nova(o) {
  const p = Object.assign(poseFor(o.mood || "idle"), o.rig || {});
  p.variant = o.variant || "pearl"; p.skin = o.skin || "aurora";
  return draw(p, { css: !o.still && !reduce, min: o.detail === "min", crop: o.crop, noFx: o.noFx });
}

/* ---------- Animation maths ---------- */
function kf(u, pts) {
  if (u <= pts[0][0]) return pts[0][1];
  for (let i = 1; i < pts.length; i++) {
    if (u <= pts[i][0]) { const [u0, v0] = pts[i - 1], [u1, v1] = pts[i], s = (u - u0) / (u1 - u0 || 1), e = s * s * (3 - 2 * s); return v0 + (v1 - v0) * e; }
  }
  return pts[pts.length - 1][1];
}
// Spring constants per joint: [stiffness, damping ratio]. Low ratio = more overshoot.
const SPR = { tilt: [140, .8], turn: [170, .9], hy: [260, .5], earL: [110, .3], earR: [110, .3], gx: [700, 1], gy: [700, 1],
  pawL: [130, .5], pawR: [130, .5], tail: [45, .28], sy: [320, .32], dy: [240, .45], bx: [160, .6], lean: [90, .4], chest: [60, 1] };

const hopY = [[0, 0], [.15, 3], [.34, -22], [.5, -24], [.68, 0], [1, 0]];
const R = {
  hop:      { dur: .75, ev: [[.12, "pop"]], f: (u) => ({ mul: { sy: kf(u, [[0, 1], [.15, .86], [.3, 1.08], [.62, 1.02], [.72, .9], [.86, 1.03], [1, 1]]) }, add: { dy: kf(u, hopY) } }) },
  aha:      { dur: 1.1, ev: [[.2, "burst"], [.2, "chime"]], f: (u) => { const e = kf(u, [[0, 0], [.1, -6], [.25, 18], [1, 0]]); return { add: { earL: e, earR: e, chest: kf(u, [[0, 0], [.2, 1.6], [1, 0]]) }, mul: { sy: kf(u, [[0, 1], [.12, .94], [.28, 1.06], [1, 1]]) }, eyes: u < .3 ? "wide" : "arc" }; } },
  startle:  { dur: .9, ev: [[.04, "pop"]], f: (u) => { const w = kf(u, [[0, 0], [.1, 1], [.55, 1], [1, 0]]), e = kf(u, [[0, 0], [.08, 20], [1, 0]]); return { add: { dy: kf(u, [[0, 0], [.08, -14], [.3, 0]]), earL: e, earR: e }, to: { pawL: [128, w], pawR: [-128, w] }, eyes: u < .65 ? "wide" : null }; } },
  flinch:   { dur: 1.5, ev: [[.06, "boop"]], f: (u) => { const w = kf(u, [[0, 0], [.12, 1], [.8, 1], [1, 0]]); return { add: { tilt: 9 * w, earL: -18 * w, earR: -18 * w }, mul: { sy: 1 - .07 * w }, to: { pawL: [-158, w], pawR: [158, w] }, eyes: u < .85 ? "closed" : null }; } },
  cheer:    { dur: 1.6, ev: [[.25, "burst"], [.25, "chime"], [.62, "burst"]], f: (u) => { const w = kf(u, [[0, 0], [.1, 1], [.85, 1], [1, 0]]); return { to: { pawL: [128, w], pawR: [-128, w] }, add: { dy: kf(u, [[0, 0], [.12, 2], [.25, -18], [.4, 0], [.5, 2], [.62, -18], [.78, 0], [1, 0]]), earL: 10 * w, earR: 10 * w }, mul: { sy: kf(u, [[0, 1], [.12, .9], [.22, 1.06], [.4, .92], [.5, .9], [.6, 1.06], [.78, .92], [.9, 1]]) }, eyes: "arc" }; } },
  nod:      { dur: .9, f: (u) => ({ add: { hy: kf(u, [[0, 0], [.15, 4], [.3, -1], [.45, 4], [.6, -1], [.75, 3], [1, 0]]) }, set: { gy: kf(u, [[0, 0], [.15, .5], [.3, 0], [.45, .5], [.6, 0], [1, 0]]) } }) },
  headShake:{ dur: .9, f: (u) => ({ add: { turn: kf(u, [[0, 0], [.15, -.5], [.35, .5], [.55, -.45], [.75, .3], [1, 0]]) } }) },
  knock:    { dur: 1.3, ev: [[.3, "knock"], [.5, "knock"], [.7, "knock"]], f: (u) => { const w = kf(u, [[0, 0], [.15, 1], [.85, 1], [1, 0]]); return { to: { pawR: [-112, w] }, add: { pawR: kf(u, [[.2, 0], [.27, -24], [.3, 0], [.47, -24], [.5, 0], [.67, -24], [.7, 0], [1, 0]]) }, set: { gx: 0, gy: 0 } }; } },
  boop:     { dur: .55, ev: [[0, "boop"]], f: (u) => { const e = kf(u, [[0, 0], [.1, -9], [1, 0]]); return { mul: { sy: kf(u, [[0, 1], [.12, .86], [.4, 1.04], [1, 1]]) }, add: { earL: e, earR: e }, eyes: u < .85 ? "flat" : null, set: u < .85 ? { gx: .6 } : {} }; } },
  stretch:  { dur: 2.2, f: (u) => { const w = kf(u, [[0, 0], [.25, 1], [.7, 1], [1, 0]]); return { to: { pawL: [128, w], pawR: [-128, w] }, mul: { sy: 1 + .08 * w }, add: { dy: -4 * w, earL: 10 * w, earR: 10 * w, tilt: -4 * w }, eyes: u > .2 && u < .8 ? "closed" : null }; } },
  yawn:     { dur: 2.2, f: (u) => { const w = kf(u, [[0, 0], [.3, 1], [.7, 1], [1, 0]]), pw = kf(u, [[.3, 0], [.45, 1], [.7, 1], [.85, 0]]); return { add: { tilt: -9 * w, earL: -10 * w, earR: -10 * w }, mul: { sy: 1 + .05 * w }, to: { pawR: [150, pw] }, eyes: u > .2 && u < .85 ? "closed" : null }; } },
  shakeOff: { dur: 1.1, ev: [[.1, "drops"]], f: (u) => { const l = kf(u, [[0, 0], [.1, 8], [.25, -8], [.4, 7], [.55, -6], [.7, 4], [1, 0]]); return { add: { lean: l, tilt: l * .8 }, eyes: u < .7 ? "closed" : "arc" }; } },
  stamp:    { dur: .9, ev: [[.2, "stamp"]], f: (u) => ({ add: { chest: kf(u, [[0, 0], [.2, 2.2], [1, 0]]), hy: kf(u, [[0, 0], [.2, 3], [.45, 0]]) } }) },
  spinHop:  { dur: 1.0, ev: [[.12, "pop"], [.3, "burst"]], f: (u) => ({ add: { dy: kf(u, [[0, 0], [.12, 3], [.35, -26], [.6, -20], [.8, 0]]), turn: kf(u, [[0, 0], [.2, -1], [.4, 1], [.6, -1], [.8, 0]]) }, mul: { sy: kf(u, [[0, 1], [.12, .85], [.3, 1.08], [.8, .9], [1, 1]]) }, eyes: "arc" }) },
};
const F = {
  earFlick:   { dur: .6, f: (u) => ({ add: { earR: kf(u, [[0, 0], [.2, -16], [.45, 10], [1, 0]]) } }) },
  tailCurl:   { dur: 1.5, f: (u) => ({ add: { tail: kf(u, [[0, 0], [.35, 34], [.7, 30], [1, 0]]) } }) },
  lookAround: { dur: 2.6, f: (u) => ({ set: { gx: kf(u, [[0, 0], [.15, -.8], [.45, -.8], [.6, .8], [.85, .8], [1, 0]]) }, add: { turn: kf(u, [[0, 0], [.2, -.45], [.45, -.45], [.65, .45], [.85, .45], [1, 0]]) } }) },
  groom:      { dur: 2, f: (u) => { const w = kf(u, [[0, 0], [.2, 1], [.8, 1], [1, 0]]); return { to: { pawR: [132, w] }, add: { pawR: 6 * Math.sin(u * 40) * w, tilt: 5 * w }, eyes: w > .5 ? "closed" : null }; } },
  peekEdge:   { dur: 1.8, f: (u) => { const w = kf(u, [[0, 0], [.25, 1], [.75, 1], [1, 0]]); return { set: { gy: .9 * w }, add: { hy: 3 * w, tilt: 2 * w } }; } },
  hum:        { dur: 2.4, f: (u) => ({ eyes: u > .1 && u < .9 ? "hum" : null, add: { tilt: 3 * Math.sin(u * Math.PI * 4) } }) },
  stretch: R.stretch, yawn: R.yawn,
};
const SLOW_FIDGETS = ["stretch", "yawn"];
function pickFidget(recent, idleSec, hour) {
  const pool = Object.keys(F).filter((k) => !recent.includes(k) && (!SLOW_FIDGETS.includes(k) || idleSec >= 120));
  const wts = pool.map((k) => (k === "stretch" && hour >= 5 && hour < 11) || (k === "yawn" && (hour >= 22 || hour < 4)) ? 3 : 1);
  let r = Math.random() * wts.reduce((a, b) => a + b, 0);
  for (let i = 0; i < pool.length; i++) { r -= wts[i]; if (r <= 0) return pool[i]; }
  return pool[0];
}
function bridge(a, b) {
  if ((a === "sleeping" || a === "sleepy") && b !== "sleeping" && b !== "sleepy") return "startle";
  if (a === "thinking" && (b === "success" || b === "happy")) return "aha";
  if (b === "error") return "flinch";
  if (b === "success") return "cheer";
  if (b === "surprised") return "startle";
  if (b === "confused" || b === "dizzy") return "headShake";
  if (b === "excited" || b === "happy" || b === "listening") return "hop";
  return null;
}

/* ---------- Sound (only after the viewer turns it on) ---------- */
const Snd = {
  ctx: null, on: false, purr: null, noise: null,
  context() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return null;
      this.ctx = new AC();
      const len = this.ctx.sampleRate * 2, buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate), d = buf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
      this.noise = buf;
    }
    if (this.ctx.state === "suspended") this.ctx.resume();
    return this.ctx;
  },
  enable(on) {
    this.on = on;
    if (on && this.context() && !this.purr) {
      const c = this.ctx, src = c.createBufferSource(); src.buffer = this.noise; src.loop = true;
      const lp = c.createBiquadFilter(); lp.type = "lowpass"; lp.frequency.value = 260;
      const am = c.createGain(); am.gain.value = .5;
      const lfo = c.createOscillator(); lfo.frequency.value = 23; const lg = c.createGain(); lg.gain.value = .5; lfo.connect(lg).connect(am.gain);
      const out = c.createGain(); out.gain.value = 0;
      src.connect(lp).connect(am).connect(out).connect(c.destination); src.start(); lfo.start();
      this.purr = out;
    }
    if (!on && this.purr) this.purr.gain.value = 0;
  },
  setPurr(v) { if (this.purr && this.on) this.purr.gain.setTargetAtTime(v * .22, this.ctx.currentTime, .1); },
  tone(f1, f2, dur, type = "sine", vol = .12, delay = 0) {
    const c = this.ctx, t = c.currentTime + delay, o = c.createOscillator(), g = c.createGain();
    o.type = type; o.frequency.setValueAtTime(f1, t); o.frequency.exponentialRampToValueAtTime(f2, t + dur);
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(.0005, t + dur);
    o.connect(g).connect(c.destination); o.start(t); o.stop(t + dur + .02);
  },
  play(name) {
    if (!this.on || !this.ctx) return;
    switch (name) {
      case "pop": this.tone(520, 900, .09, "sine", .1); break;
      case "boop": this.tone(760, 420, .1, "sine", .1); break;
      case "knock": this.tone(180, 70, .1, "sine", .35); break;
      case "chime": this.tone(1046, 1046, .35, "triangle", .07); this.tone(1318, 1318, .4, "triangle", .06, .09); this.tone(1568, 1568, .5, "triangle", .05, .18); break;
      case "stamp": this.tone(330, 660, .14, "triangle", .1); break;
    }
  },
};

/* ---------- Music: demo beat, your own song, beat tracking ---------- */
class BeatTracker {
  constructor() { this.reset(); }
  reset() { this.env = []; this.prevLow = null; this.period = 60 / 110; this.phase0 = 0; this.tracked = false; this.lastEst = 0; this.eS = 0; this.eL = 0; this.dropAt = -99; this.dropped = false; }
  push(time, spec, rms) {
    let low = 0; for (let i = 1; i < 10; i++) low += spec[i]; low /= 9;
    const flux = this.prevLow == null ? 0 : Math.max(0, low - this.prevLow); this.prevLow = low;
    this.env.push([time, flux]); while (this.env.length && time - this.env[0][0] > 8) this.env.shift();
    this.eS += (rms - this.eS) * .12; this.eL += (rms - this.eL) * .006;
    if (this.eS > this.eL * 1.45 && this.eS > .06 && time - this.dropAt > 8 && time > 3) { this.dropAt = time; this.dropped = true; }
    if (time - this.lastEst > 1) { this.estimate(time); this.lastEst = time; }
  }
  estimate(now) {
    const Rr = 100, n = 800, start = now - 8, g = new Float32Array(n);
    for (const [t, f] of this.env) { const i = Math.floor((t - start) * Rr); if (i >= 0 && i < n) g[i] = Math.max(g[i], f); }
    const sm = new Float32Array(n); for (let i = 1; i < n - 1; i++) sm[i] = g[i - 1] * .5 + g[i] + g[i + 1] * .5;
    let total = 0; for (let i = 0; i < n; i++) total += sm[i] * sm[i];
    if (total < 1) { this.tracked = false; return; }
    let best = 0, bestLag = 0;
    for (let lag = 33; lag <= 86; lag++) {
      let s = 0; for (let i = lag; i < n; i++) s += sm[i] * sm[i - lag];
      const bpm = 60 * Rr / lag; s *= Math.exp(-.5 * Math.pow(Math.log2(bpm / 120) / .9, 2));
      if (s > best) { best = s; bestLag = lag; }
    }
    if (!bestLag) return;
    const P0 = bestLag / Rr; this.period += (P0 - this.period) * (this.tracked ? .35 : 1); this.tracked = true;
    const P = this.period; let bs = -1, bphi = 0;
    for (let k = 0; k < 32; k++) {
      const phi = k / 32 * P; let s = 0;
      for (let tt = now - phi; tt > now - 4; tt -= P) { const i = Math.round((tt - start) * Rr); for (let dd = -2; dd <= 2; dd++) s += sm[i + dd] || 0; }
      if (s > bs) { bs = s; bphi = phi; }
    }
    const target = now - bphi;
    let diff = ((target - this.phase0) % P + P) % P; if (diff > P / 2) diff -= P;
    this.phase0 += diff * .5;
  }
  beatAt(now) { return (now - this.phase0) / this.period; }
  get bpm() { return 60 / this.period; }
}
const Music = {
  on: false, src: null, analyser: null, master: null, timer: null, el: null, tracker: new BeatTracker(), spec: null, td: null, startedAt: 0, energy: 0,
  setup() {
    const c = Snd.context(); if (!c) return null;
    if (!this.master) {
      this.master = c.createGain(); this.master.gain.value = .8;
      this.analyser = c.createAnalyser(); this.analyser.fftSize = 1024; this.analyser.smoothingTimeConstant = .2;
      this.master.connect(this.analyser); this.analyser.connect(c.destination);
      this.spec = new Uint8Array(this.analyser.frequencyBinCount); this.td = new Float32Array(this.analyser.fftSize);
    }
    return c;
  },
  stop() {
    clearInterval(this.timer); this.timer = null;
    if (this.el) { this.el.pause(); this.el = null; }
    this.on = false; this.tracker.reset();
  },
  demo() {
    const c = this.setup(); if (!c) return;
    this.stop(); this.on = true; this.startedAt = c.currentTime;
    const bpm = 120, sx = 60 / bpm / 4; let next = c.currentTime + .1, step = 0;
    const bassNotes = [55, 55, 65.4, 73.4, 55, 82.4, 73.4, 65.4];
    const hit = (t, fn) => fn(t);
    const kick = (t) => { const o = c.createOscillator(), g = c.createGain(); o.frequency.setValueAtTime(150, t); o.frequency.exponentialRampToValueAtTime(45, t + .12); g.gain.setValueAtTime(.95, t); g.gain.exponentialRampToValueAtTime(.001, t + .2); o.connect(g).connect(this.master); o.start(t); o.stop(t + .22); };
    const noise = (t, type, f, vol, dur) => { const s = c.createBufferSource(); s.buffer = Snd.noise; const fl = c.createBiquadFilter(); fl.type = type; fl.frequency.value = f; const g = c.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(.001, t + dur); s.connect(fl).connect(g).connect(this.master); s.start(t, Math.random()); s.stop(t + dur + .02); };
    const bass = (t, f) => { const o = c.createOscillator(), fl = c.createBiquadFilter(), g = c.createGain(); o.type = "sawtooth"; o.frequency.value = f; fl.type = "lowpass"; fl.frequency.value = 520; g.gain.setValueAtTime(.2, t); g.gain.exponentialRampToValueAtTime(.001, t + .2); o.connect(fl).connect(g).connect(this.master); o.start(t); o.stop(t + .22); };
    const pad = (t) => [261.6, 329.6, 392].forEach((f) => { const o = c.createOscillator(), g = c.createGain(); o.type = "triangle"; o.frequency.value = f; g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(.035, t + .3); g.gain.exponentialRampToValueAtTime(.0001, t + 1.9); o.connect(g).connect(this.master); o.start(t); o.stop(t + 2); });
    const schedule = () => {
      while (next < c.currentTime + .15) {
        const s16 = step % 16, bar = Math.floor(step / 16) % 16, full = bar >= 8;
        if (s16 % 4 === 0) hit(next, kick);
        if (s16 % 4 === 2) noise(next, "highpass", 7000, .14, .04);
        if (full && s16 % 2 === 1) noise(next, "highpass", 8000, .06, .03);
        if (full && (s16 === 4 || s16 === 12)) noise(next, "bandpass", 1800, .45, .15);
        if (full && s16 % 2 === 0) bass(next, bassNotes[(s16 / 2) % 8] * (bar % 2 ? 1 : 1.0));
        if (s16 === 0 && bar % 2 === 0) pad(next);
        next += sx; step++;
      }
    };
    schedule(); this.timer = setInterval(schedule, 25);
  },
  file(f) {
    const c = this.setup(); if (!c) return;
    this.stop();
    const el = new Audio(URL.createObjectURL(f)); el.crossOrigin = "anonymous";
    c.createMediaElementSource(el).connect(this.master);
    el.play().then(() => { this.on = true; this.startedAt = c.currentTime; }).catch(() => { this.on = false; });
    el.addEventListener("ended", () => this.stop());
    this.el = el;
  },
  update() {
    if (!this.on || !this.analyser) return null;
    const c = Snd.ctx, now = c.currentTime - this.startedAt;
    this.analyser.getByteFrequencyData(this.spec); this.analyser.getFloatTimeDomainData(this.td);
    let s = 0; for (let i = 0; i < this.td.length; i += 2) s += this.td[i] * this.td[i]; const rms = Math.sqrt(s / (this.td.length / 2));
    this.energy += (rms - this.energy) * .1;
    this.tracker.push(now, this.spec, rms);
    const tr = this.tracker, beat = tr.tracked ? tr.beatAt(now) : now / (60 / 110);
    const drop = tr.dropped; tr.dropped = false;
    return { beat, bpm: tr.tracked ? tr.bpm : 110, tracked: tr.tracked, energy: this.energy, drop, spec: this.spec };
  },
};
const COMBOS = [["bob", "sway", "earBop"], ["bob", "pawPump", "tailWag"], ["sideStep", "earBop", "tailWag", "bob"], ["bob", "sway", "pawPump", "earBop"]];

/* ---------- Scene backgrounds ---------- */
function sceneFor(mood, n) {
  if (n.sim.guard) return "guard";
  if (n.dancing) return "music";
  switch (mood) {
    case "coding": case "typing": return "code";
    case "thinking": case "loading": case "confused": case "dizzy": return "thinking";
    case "success": case "excited": return "success";
    case "error": return "error";
    case "warning": case "annoyed": return "warning";
    case "sleeping": case "sleepy": return "night";
    default: return "aurora";
  }
}
class Scenes {
  constructor(cv) {
    this.cv = cv; this.ctx = cv.getContext("2d"); this.cur = "aurora"; this.prev = null; this.mix = 1; this.rings = []; this.confetti = []; this.lastBeat = -1;
    this.stars = Array.from({ length: 70 }, () => ({ x: Math.random(), y: Math.random(), r: Math.random() * 1.4 + .3, p: Math.random() * TAU, z: Math.random() }));
    this.cols = Array.from({ length: 26 }, (_, i) => ({ y: Math.random(), v: .05 + Math.random() * .08, chars: Array.from({ length: 14 }, () => "{}<>/=;()[]01λ$#"[Math.floor(Math.random() * 16)]) }));
    const ro = new ResizeObserver(() => this.resize()); ro.observe(cv); this.resize();
  }
  resize() { const r = this.cv.getBoundingClientRect(), d = Math.min(2, devicePixelRatio || 1); this.cv.width = Math.max(1, r.width * d); this.cv.height = Math.max(1, r.height * d); this.w = this.cv.width; this.h = this.cv.height; }
  set(name) {
    if (name === this.cur) return;
    this.prev = this.cur; this.cur = name; this.mix = 0;
    if (name === "success") this.spawnConfetti();
  }
  spawnConfetti() {
    const cs = [C.mint, C.cyan, C.amber, C.pink, C.violet];
    for (let i = 0; i < 90; i++) this.confetti.push({ x: .5 + (Math.random() - .5) * .2, y: .45, vx: (Math.random() - .5) * .9, vy: -Math.random() * 1.1 - .3, r: Math.random() * TAU, vr: (Math.random() - .5) * 12, c: cs[i % cs.length], life: 3 + Math.random() * 1.5 });
  }
  frame(t, dt, info) {
    const { ctx, w, h } = this;
    this.mix = Math.min(1, this.mix + dt / .6);
    ctx.globalAlpha = 1; ctx.fillStyle = "#0B1033"; ctx.fillRect(0, 0, w, h);
    if (this.prev && this.mix < 1) { ctx.globalAlpha = 1 - this.mix; this.paint(this.prev, t, dt, info); }
    ctx.globalAlpha = this.mix; this.paint(this.cur, t, dt, info); ctx.globalAlpha = 1;
  }
  paint(name, t, dt, info) {
    const { ctx, w, h } = this, base = ctx.globalAlpha, u = Math.min(w, h) / 400;
    const bg = (a, b) => { const g = ctx.createRadialGradient(w / 2, h * .1, 0, w / 2, h * .4, h * .9); g.addColorStop(0, a); g.addColorStop(1, b); ctx.fillStyle = g; ctx.fillRect(0, 0, w, h); };
    ctx.save();
    switch (name) {
      case "aurora": {
        bg("#22307A", "#0B1033");
        ctx.globalCompositeOperation = "lighter";
        [[C.cyan, .30, 0], [C.violet, .42, 2], [C.mint, .55, 4]].forEach(([c, yy, ph]) => {
          ctx.strokeStyle = c; ctx.lineCap = "round";
          for (const [lw, a] of [[70, .05], [36, .07], [12, .1]]) {
            ctx.lineWidth = lw * u; ctx.globalAlpha = base * a; ctx.beginPath();
            for (let x = -20; x <= w + 20; x += 12) { const y = h * yy + Math.sin(x / w * 5 + t * .25 + ph) * 34 * u + Math.sin(x / w * 11 - t * .4 + ph) * 10 * u; x < 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y); }
            ctx.stroke();
          }
        });
        break;
      }
      case "code": {
        bg("#14204F", "#070B22");
        ctx.font = `${13 * u}px ui-monospace, Menlo, monospace`; ctx.fillStyle = info.tint || C.cyan;
        const cw = w / this.cols.length;
        this.cols.forEach((cl, i) => {
          cl.y = (cl.y + cl.v * dt) % 1.6;
          cl.chars.forEach((ch, j) => { const y = (cl.y - .3) * h + j * 15 * u; if (y < 0 || y > h) return; ctx.globalAlpha = base * (j === cl.chars.length - 1 ? .5 : .09 + j * .008); ctx.fillText(ch, i * cw + cw * .3, y); });
        });
        break;
      }
      case "thinking": {
        bg("#1E2766", "#090D2A");
        this.stars.forEach((s) => { const x = ((s.x - t * .004 * (1 + s.z * 3)) % 1 + 1) % 1; ctx.globalAlpha = base * (.25 + .35 * s.z); ctx.fillStyle = "#DDE3FF"; ctx.beginPath(); ctx.arc(x * w, s.y * h, s.r * u * (1 + s.z), 0, TAU); ctx.fill(); });
        for (let i = 0; i < 3; i++) {
          const a = t * .7 + i * TAU / 3;
          for (let k = 0; k < 10; k++) { const aa = a - k * .06; ctx.globalAlpha = base * (.5 - k * .045); ctx.fillStyle = C.violet; ctx.beginPath(); ctx.arc(w / 2 + Math.cos(aa) * w * .36, h * .42 + Math.sin(aa) * h * .12, (6 - k * .45) * u, 0, TAU); ctx.fill(); }
        }
        break;
      }
      case "music": {
        bg("#2A1E6E", "#0A0B2A");
        const bi = Math.floor(info.beat || 0);
        if (bi !== this.lastBeat) { this.lastBeat = bi; this.rings.push({ t0: t, c: [C.violet, C.pink, C.cyan, C.amber][bi % 4] }); }
        this.rings = this.rings.filter((r) => t - r.t0 < 2);
        this.rings.forEach((r) => { const a = (t - r.t0) / 2; ctx.globalAlpha = base * (1 - a) * .5; ctx.strokeStyle = r.c; ctx.lineWidth = 3 * u * (1 - a) + .5; ctx.beginPath(); ctx.arc(w / 2, h * .48, a * w * .65 + 40 * u, 0, TAU); ctx.stroke(); });
        const n = 28, bw = w / n, spec = info.spec;
        for (let i = 0; i < n; i++) {
          const v = spec ? spec[2 + Math.floor(Math.pow(i / n, 1.6) * 180)] / 255 : .2 + .2 * Math.sin(t * 6 + i);
          const bh = v * h * .28; const g = ctx.createLinearGradient(0, h, 0, h - bh); g.addColorStop(0, C.violet); g.addColorStop(1, C.pink);
          ctx.globalAlpha = base * .55; ctx.fillStyle = g; ctx.fillRect(i * bw + bw * .18, h - bh, bw * .64, bh);
        }
        break;
      }
      case "success": {
        bg("#1D3A6B", "#081530");
        this.confetti = this.confetti.filter((p) => (p.life -= dt) > 0);
        this.confetti.forEach((p) => { p.vy += .9 * dt; p.x += p.vx * dt * .5; p.y += p.vy * dt * .6; p.r += p.vr * dt; ctx.save(); ctx.globalAlpha = base * Math.min(1, p.life); ctx.translate(p.x * w, p.y * h); ctx.rotate(p.r); ctx.fillStyle = p.c; ctx.fillRect(-4 * u, -2 * u, 8 * u, 4 * u); ctx.restore(); });
        if (this.confetti.length < 20 && Math.random() < dt * 2) this.spawnConfettiSmall();
        this.stars.slice(0, 24).forEach((s) => { ctx.globalAlpha = base * (.3 + .3 * Math.sin(t * 3 + s.p)); ctx.fillStyle = C.amber; ctx.beginPath(); ctx.arc(s.x * w, s.y * h * .8, s.r * u * 1.5, 0, TAU); ctx.fill(); });
        break;
      }
      case "error": case "warning": {
        const c = name === "error" ? C.coral : C.amber;
        bg(name === "error" ? "#3A1A3E" : "#3A2E3A", "#0D0B22");
        const pz = .5 + .5 * Math.sin(t * (name === "error" ? 5 : 3));
        const g = ctx.createRadialGradient(w / 2, h * .45, 0, w / 2, h * .45, w * (.35 + .1 * pz));
        g.addColorStop(0, c); g.addColorStop(1, "rgba(0,0,0,0)"); ctx.globalAlpha = base * (.18 + .14 * pz); ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
        break;
      }
      case "guard": {
        bg("#0E2A4A", "#04101F");
        const r = 22 * u, hh = r * Math.sqrt(3), scan = ((t * .35) % 1.3 - .15) * h;
        ctx.lineWidth = 1.2 * u;
        for (let row = -1; row * hh * .5 < h + hh; row++) for (let colI = -1; colI * r * 1.5 < w + r; colI++) {
          const cx = colI * r * 1.5, cy = row * hh + (colI % 2 ? hh / 2 : 0), d = Math.abs(cy - scan);
          ctx.globalAlpha = base * (.07 + Math.max(0, 1 - d / (60 * u)) * .5); ctx.strokeStyle = d < 60 * u ? C.coral : C.cyan;
          ctx.beginPath(); for (let k = 0; k < 6; k++) { const a = k * Math.PI / 3; const x = cx + Math.cos(a) * r * .92, y = cy + Math.sin(a) * r * .92; k ? ctx.lineTo(x, y) : ctx.moveTo(x, y); } ctx.closePath(); ctx.stroke();
        }
        ctx.globalAlpha = base * .6; ctx.fillStyle = C.coral; ctx.fillRect(0, scan, w, 2 * u);
        break;
      }
      case "night": {
        bg("#141A4A", "#03051A");
        this.stars.forEach((s) => { ctx.globalAlpha = base * (.3 + .6 * (.5 + .5 * Math.sin(t * (1 + s.z * 2) + s.p))); ctx.fillStyle = "#F4F6FF"; ctx.beginPath(); ctx.arc(s.x * w, s.y * h * .75, s.r * u, 0, TAU); ctx.fill(); });
        ctx.globalAlpha = base * .9; ctx.fillStyle = "#F8F1D8"; ctx.beginPath(); ctx.arc(w * .18, h * .17, 26 * u, 0, TAU); ctx.fill();
        ctx.globalCompositeOperation = "destination-out"; ctx.beginPath(); ctx.arc(w * .18 + 11 * u, h * .17 - 7 * u, 23 * u, 0, TAU); ctx.fill(); ctx.globalCompositeOperation = "source-over";
        const sp = (t % 9) / 9; if (sp < .12) { const k = sp / .12; ctx.globalAlpha = base * (1 - k); ctx.strokeStyle = "#fff"; ctx.lineWidth = 2 * u; ctx.beginPath(); ctx.moveTo(w * (.9 - k * .5), h * (.08 + k * .2)); ctx.lineTo(w * (.95 - k * .5), h * (.05 + k * .2)); ctx.stroke(); }
        break;
      }
    }
    ctx.restore();
  }
  spawnConfettiSmall() { const cs = [C.mint, C.cyan, C.amber, C.pink, C.violet]; for (let i = 0; i < 6; i++) this.confetti.push({ x: Math.random(), y: -.05, vx: (Math.random() - .5) * .3, vy: .1, r: Math.random() * TAU, vr: (Math.random() - .5) * 8, c: cs[i % 5], life: 3.5 }); }
}

/* ---------- Live Nova ---------- */
const pointer = { x: 0, y: 0, at: -1e9 };
addEventListener("pointermove", (e) => { pointer.x = e.clientX; pointer.y = e.clientY; pointer.at = performance.now(); }, { passive: true });

class LiveNova {
  constructor(el, opts = {}) {
    this.el = el; this.o = Object.assign({ variant: "pearl", skin: "aurora", viewBox: "-30 -34 300 284", drag: false, sound: false }, opts);
    this.mood = "idle"; this.lastMood = "idle"; this.t = 0; this.speed = 1;
    this.layers = { springs: !reduce, idle: !reduce, fidget: !reduce, look: !reduce, react: !reduce, scene: true };
    const b = poseFor("idle"); this.s = {}; for (const j in SPR) this.s[j] = { x: b[j], v: 0 };
    this.reaction = null; this.fidget = null; this.nextFidget = 5; this.recent = []; this.nextBlink = 1.2; this.blinkT = -9; this.nextSacc = 1; this.sacc = [0, 0];
    this.ws = 0; this.nextWs = 8; this.pet = 0; this.drag = null; this.off = { x: 0, y: 0, vx: 0, vy: 0, dvx: 0 }; this.particles = []; this.taps = [];
    this.lastInteract = 0; this.sim = { typing: false, approval: null, guard: false, sessions: false, needy: false, act: .5, nextAct: 0, phase: 0, lastKnock: 0 };
    this.temp = null; this.msg = null; this.sparkPos = []; this.dancing = false; this.danceInfo = null; this.lastBar = -1; this.lastNoteBeat = -1;
    this.svg = null;
    this.bind();
  }
  setMood(m) { this.mood = m; this.temp = null; }
  tempMood(m, sec) { this.temp = { m, until: this.t + sec }; }
  say(text, sec = 2.5) { this.msg = { text, until: this.t + sec }; }
  touch() { this.lastInteract = this.t; }
  play(name, force) {
    if (!this.layers.react && !force) return;
    const def = R[name] || F[name]; if (!def) return;
    this.reaction = { name, def, t0: this.t, fired: new Set() };
  }
  effMood() {
    if (this.temp && this.t < this.temp.until) return this.temp.m;
    if (this.sim.guard) return "warning";
    if (this.sim.approval != null) return "notification";
    if (this.sim.typing) return "coding";
    if (this.dancing) return "happy";
    return this.mood;
  }
  toSvg(cx, cy) {
    const svg = this.el.querySelector("svg"); if (!svg) return { x: 0, y: 0 };
    const m = svg.getScreenCTM(); if (!m) return { x: 0, y: 0 };
    const p = new DOMPoint(cx, cy).matrixTransform(m.inverse()); return { x: p.x, y: p.y };
  }
  hitBody(p) { const dx = (p.x - 120 - this.off.x) / 90, dy = (p.y - 140 - this.off.y) / 100; return dx * dx + dy * dy < 1; }
  hitHead(p) { const dx = (p.x - 120 - this.off.x) / 72, dy = (p.y - 92 - this.off.y) / 62; return dx * dx + dy * dy < 1; }
  bind() {
    const el = this.el;
    el.addEventListener("pointerdown", (e) => {
      const p = this.toSvg(e.clientX, e.clientY);
      const hitSpark = this.sparkHit(p); if (hitSpark != null) { this.clickSpark(hitSpark); return; }
      if (!this.hitBody(p)) return;
      this.drag = { x0: p.x, y0: p.y, ox: this.off.x, oy: this.off.y, moved: false, last: p, lastT: performance.now(), revs: [], dir: 0 };
      try { el.setPointerCapture(e.pointerId); } catch (_) {}
      if (this.o.sound && Snd.ctx) Snd.context();
    });
    el.addEventListener("pointermove", (e) => {
      const p = this.toSvg(e.clientX, e.clientY), d = this.drag;
      if (d) {
        const mx = p.x - d.x0, my = p.y - d.y0;
        if (!d.moved && Math.hypot(mx, my) > 6) d.moved = true;
        if (d.moved && this.o.drag) {
          const now = performance.now(), dtm = Math.max(8, now - d.lastT);
          const nx = clamp(d.ox + mx, -80, 80), ny = clamp(d.oy + my, -50, 40);
          this.off.dvx = (nx - this.off.x) / dtm * 1000; this.off.x = nx; this.off.y = ny;
          const dir = Math.sign(this.off.dvx);
          if (Math.abs(this.off.dvx) > 260 && dir && dir !== d.dir) { d.revs.push(now); d.dir = dir; }
          d.revs = d.revs.filter((x) => now - x < 1300);
          if (d.revs.length >= 5) { this.dizzy(); d.revs = []; }
          d.last = p; d.lastT = now; this.touch();
        }
      } else if (this.hitHead(p)) {
        const mv = this.lastHover ? Math.hypot(p.x - this.lastHover.x, p.y - this.lastHover.y) : 0;
        this.pet = Math.min(1, this.pet + Math.min(mv, 20) * .012); this.touch();
      }
      this.lastHover = p;
    });
    const up = () => {
      const d = this.drag; this.drag = null;
      if (d && !d.moved) {
        const now = performance.now(); this.taps = this.taps.filter((x) => now - x < 900); this.taps.push(now);
        if (this.taps.length >= 3) { this.taps = []; this.dizzy(); } else this.play("boop", true);
        this.touch();
      }
    };
    el.addEventListener("pointerup", up); el.addEventListener("pointercancel", up);
    el.addEventListener("pointerleave", () => { this.lastHover = null; });
  }
  dizzy() { this.tempMood("dizzy", 2.6); this.play("headShake", true); }
  sparkHit(p) { for (let i = 0; i < this.sparkPos.length; i++) { const s = this.sparkPos[i]; if (Math.hypot(p.x - s.x, p.y - s.y) < 16) return i; } return null; }
  clickSpark(i) {
    const s = SPARKS[i]; if (!s) return;
    if (this.sim.needy && i === 1) { this.sim.needy = false;  }
    this.say(`Opening ${s.name} in its terminal`, 2.2); this.play("nod", true);
  }
  emit(name) {
    const P = this.particles, s = SKINS[this.o.skin];
    if (["pop", "chime", "knock", "boop", "stamp"].includes(name) && this.o.sound) Snd.play(name);
    if (name === "burst") for (let i = 0; i < 12; i++) { const a = Math.random() * TAU, v = 60 + Math.random() * 80; P.push({ k: "star", x: 120 + this.off.x, y: 70 + this.off.y + this.s.dy.x, vx: Math.cos(a) * v, vy: Math.sin(a) * v - 40, life: .9, max: .9, r: 4 + Math.random() * 4, c: i % 2 ? s.glow1 : C.amber }); }
    if (name === "drops") for (let i = 0; i < 10; i++) { const sd = i % 2 ? 1 : -1; P.push({ k: "drop", x: 120 + sd * 60 + this.off.x, y: 110 + this.off.y, vx: sd * (60 + Math.random() * 60), vy: -60 - Math.random() * 40, g: 300, life: .8, max: .8, r: 3, c: C.cyan }); }
    if (name === "knock") { const tip = this.pawTip(1); P.push({ k: "ring", x: tip.x, y: tip.y, life: .5, max: .5, r: 4, c: s.glow1 }); }
    if (name === "stamp") { P.push({ k: "ring", x: 120 + this.off.x, y: 168 + this.off.y + this.s.dy.x, life: .8, max: .8, r: 6, c: C.mint }); P.push({ k: "check", x: 152 + this.off.x, y: 150 + this.off.y, vx: 0, vy: -30, life: 1.2, max: 1.2, c: C.mint }); }
  }
  pawTip(side) {
    if (this.o.variant === "peek") return { x: 120 + side * 34 + this.off.x, y: 180 + this.off.y };
    const a = (side < 0 ? this.s.pawL.x : this.s.pawR.x) * Math.PI / 180, sx = 120 + side * 31;
    return { x: sx - 31 * Math.sin(a) + this.off.x + this.s.bx.x, y: 170 + 31 * Math.cos(a) + this.off.y + this.s.dy.x };
  }
  frame(dtReal, music) {
    const dt = Math.min(dtReal, .05) * this.speed; this.t += dt; const t = this.t, L = this.layers;
    // Dance state: music playing and nothing more important happening.
    const interrupt = this.sim.approval != null || this.sim.guard || (this.temp && t < this.temp.until && ["error", "dizzy"].includes(this.temp.m)) || this.sim.needy;
    this.dancing = !!(music && this.o.dance && !interrupt);
    this.danceInfo = music;
    const mood = this.effMood();
    if (mood !== this.lastMood) { const b = bridge(this.lastMood, mood); if (b) this.play(b); this.blinkT = t; this.lastMood = mood; }
    const T = poseFor(mood); const set = {}; let eyesOv = null;
    // 3. Idle life
    if (L.idle) {
      const br = Math.sin(t * TAU / 3.6); T.sy *= 1 + .012 * br; T.chest += .25 * br;
      if (t > this.nextWs) { const opts = [-1.6, 0, 1.6].filter((x) => x !== this.ws); this.ws = opts[Math.floor(Math.random() * opts.length)]; this.nextWs = t + 8 + Math.random() * 4; }
      T.lean += this.ws; T.tilt += this.ws * .6;
      const amp = T.tailMode === "fast" ? 14 : T.tailMode === "still" ? 2 : 8, fr = T.tailMode === "fast" ? 1.1 : .35; T.tail += amp * Math.sin(t * TAU * fr);
      if (T.pawState === "wave") T.pawR += 16 * Math.sin(t * TAU * 1.6);
      if (this.o.variant === "orbit") T.dy += 3 * Math.sin(t * 2);
      if (t > this.nextSacc) { this.sacc = [(Math.random() - .5) * .5, (Math.random() - .5) * .3]; this.nextSacc = t + 1.2 + Math.random() * 1.8; }
      T.gx += this.sacc[0]; T.gy += this.sacc[1];
    }
    // Agent typing: paw speed follows the agent's activity.
    if (this.sim.typing) {
      if (t > this.sim.nextAct) { this.sim.act = clamp(this.sim.act + (Math.random() - .45) * .5, .05, 1); this.sim.nextAct = t + .4; }
      this.sim.phase += dt * TAU * (2 + 7 * this.sim.act);
      T.pawL += 9 * Math.sin(this.sim.phase); T.pawR += 9 * Math.sin(this.sim.phase + Math.PI); set.gy = .45; set.gx = 0;
    }
    // Approval escalation: look → wave → knock.
    let dynMsg = null;
    if (this.sim.approval != null) {
      const e = t - this.sim.approval; set.gx = 0; set.gy = 0; T.turn = 0; T.earL += 4; T.earR += 4;
      if (e < 4) { T.pawR = -12; } else { dynMsg = "api needs your OK"; }
      if (e >= 4 && e < 9) T.pawR = -132 + 16 * Math.sin(t * TAU * 1.6);
      if (e >= 9) { T.pawR = -12; if (!this.reaction && t - this.sim.lastKnock > 3.2) { this.play("knock", true); this.sim.lastKnock = t; } }
    }
    let shield = null;
    if (this.sim.guard) {
      T.earL = T.earR = -14; T.sy *= .95; T.eyes = "focus"; T.eyeC = C.amber; T.chestC = C.coral; T.chest = 1 + .7 * Math.sin(t * TAU * 2.2); T.tilt = -2; T.turn = 0;
      shield = (t % 1.6) / 1.6; dynMsg = "Guarding your Mac"; set.gx = 0; set.gy = 0;
    }
    // Session sparks
    this.sparkPos = [];
    if (this.sim.sessions) {
      SPARKS.forEach((sp, i) => {
        const a = t * .7 + i * Math.PI;
        let x = 120 + Math.cos(a) * 112, y = 74 + Math.sin(a) * 26, z = Math.sin(a);
        if (this.sim.needy && i === 1) { x = 214; y = 30; z = 1; }
        const prev = this.sparkCache && this.sparkCache[i];
        if (prev) { x = prev.x + (x - prev.x) * Math.min(1, dt * 6); y = prev.y + (y - prev.y) * Math.min(1, dt * 6); }
        this.sparkPos.push({ x, y, z, c: sp.c, name: sp.name, needy: this.sim.needy && i === 1 });
      });
      this.sparkCache = this.sparkPos.map((p) => ({ x: p.x, y: p.y }));
      if (this.sim.needy) {
        const sp = this.sparkPos[1], sh = { x: 151 + this.off.x, y: 170 + this.off.y }, dx = sp.x - sh.x, dy = sp.y - sh.y;
        T.pawR = Math.atan2(-dx, dy) * 180 / Math.PI; T.turn = .35; set.gx = .8; set.gy = -.6; dynMsg = dynMsg || "web needs you";
        if (this.o.variant === "peek") T.pawR = -150;
      }
    } else this.sparkCache = null;
    // Dance
    if (this.dancing) {
      const m = music, b = m.beat, bi = Math.floor(b), ph = b - bi, amp = clamp(.35 + m.energy * 4, .35, 1);
      const bar = Math.floor(bi / 4), combo = COMBOS[Math.floor(bar / 8) % COMBOS.length];
      const hitE = Math.pow(1 - ph, 3), sway = Math.sin(Math.PI * ((bi % 2) + ph));
      T.eyes = "arc"; T.phones = true;
      if (reduce) { (bi % 2 ? T : T).earL += 8 * hitE; }
      else {
        if (combo.includes("bob")) { T.hy += 4 * amp * hitE; T.sy *= 1 - .045 * amp * Math.pow(1 - ph, 4); }
        if (combo.includes("sway")) { T.lean += 6 * amp * sway; T.tilt += 4 * amp * sway; }
        if (combo.includes("earBop")) { if (bi % 2) T.earL += 16 * amp * hitE; else T.earR += 16 * amp * hitE; }
        if (combo.includes("pawPump")) { const w = amp * Math.pow(1 - ph, 2); if (bi % 2) T.pawL += (120 - T.pawL) * w; else T.pawR += (-120 - T.pawR) * w; }
        if (combo.includes("tailWag")) T.tail += 22 * amp * sway;
        if (combo.includes("sideStep")) T.bx += 9 * amp * sway;
        if (m.drop && L.react) { this.play("spinHop", true); }
        if (bi !== this.lastNoteBeat && bi % 4 === 0) { this.lastNoteBeat = bi; this.particles.push({ k: "note", x: 180 + this.off.x, y: 70 + this.off.y, vx: 20, vy: -40, life: 1.4, max: 1.4, c: SKINS[this.o.skin].glow1 }); }
      }
    }
    // 7. Look at the cursor (eyes lead, head follows)
    if (L.look && performance.now() - pointer.at < 2500 && set.gx === undefined) {
      const p = this.toSvg(pointer.x, pointer.y), dx = p.x - 120 - this.off.x, dy = p.y - 96 - this.off.y;
      const gx = clamp(dx / 130, -1, 1), gy = clamp(dy / 130, -1, 1);
      set.gx = gx; set.gy = gy; T.turn += gx * .4; T.tilt += -gx * 2;
    }
    // Petting
    this.pet = Math.max(0, this.pet - dtReal * .5);
    if (this.pet > .1) {
      T.earL -= 12 * this.pet; T.earR -= 12 * this.pet; T.chest += this.pet * .6; T.tilt += 5 * this.pet;
      if (this.pet > .35) eyesOv = "arc";
      if (Math.random() < dtReal * 3 * this.pet) this.particles.push({ k: "heart", x: 120 + this.off.x + (Math.random() - .5) * 60, y: 40 + this.off.y, vx: (Math.random() - .5) * 20, vy: -35, life: 1.3, max: 1.3, c: C.pink });
    }
    if (this.o.sound) Snd.setPurr(this.pet > .15 ? this.pet : 0);
    // Dragging: dangle and swing
    if (this.drag && this.drag.moved && this.o.drag) {
      const w = .8; T.pawL += (4 - T.pawL) * w; T.pawR += (-4 - T.pawR) * w; T.sy *= 1.05; eyesOv = eyesOv || "tall";
      T.lean += clamp(-this.off.dvx * .035, -25, 25); this.off.dvx *= Math.pow(.02, dtReal);
    } else if (this.o.drag) {
      const k = 70, c = 2 * .45 * Math.sqrt(k);
      for (const ax of ["x", "y"]) { const v = ax === "x" ? "vx" : "vy"; const a = -k * this.off[ax] - c * this.off[v]; this.off[v] += a * dt; this.off[ax] += this.off[v] * dt; }
      T.lean += clamp(-this.off.vx * .03, -20, 20);
    }
    // 4. Fidgets (only when calm)
    const calm = ["idle", "happy", "listening", "sleepy"].includes(mood) && !this.dancing && !this.sim.typing && !this.sim.needy && !this.drag && this.pet < .1;
    if (L.fidget && calm && !this.reaction && !this.fidget && t > this.nextFidget) {
      const hour = new Date().getHours(), k = pickFidget(this.recent.slice(-2), t - this.lastInteract, hour);
      this.fidget = { name: k, def: F[k], t0: t }; this.recent.push(k); if (this.recent.length > 4) this.recent.shift();
    }
    const apply = (a) => {
      const u = clamp((t - a.t0) / a.def.dur, 0, 1), r = a.def.f(u);
      for (const k in r.add || {}) T[k] += r.add[k];
      for (const k in r.mul || {}) T[k] *= r.mul[k];
      for (const k in r.to || {}) { const [v, w] = r.to[k]; T[k] += (v - T[k]) * w; }
      for (const k in r.set || {}) set[k] = r.set[k];
      if (r.eyes) eyesOv = r.eyes;
      for (const [eu, name] of a.def.ev || []) if (u >= eu && !a.fired?.has(eu + name)) { a.fired?.add(eu + name); this.emit(name); }
      return u >= 1;
    };
    if (this.fidget) { if (!calm || apply(this.fidget)) { this.fidget = null; this.nextFidget = t + 6 + Math.random() * 8; } }
    if (this.reaction) { if (apply(this.reaction)) this.reaction = null; }
    if (set.gx !== undefined) T.gx = set.gx; if (set.gy !== undefined) T.gy = set.gy;
    // Follow-through: ears and tail are pushed by body motion.
    const ft = clamp(this.s.dy.v * .3 + this.s.hy.v * .4, -22, 22);
    T.earL += ft; T.earR += ft; T.tail += clamp(this.s.lean.v * .9 + this.s.bx.v * .3 + this.s.dy.v * .25, -35, 35);
    // 2. Springs
    for (const j in SPR) {
      const sp = this.s[j], [k, z] = SPR[j], target = T[j];
      if (!L.springs) { sp.x = target; sp.v = 0; continue; }
      let rem = dt; const c = 2 * z * Math.sqrt(k);
      while (rem > 1e-6) { const h = Math.min(rem, 1 / 240); sp.v += (k * (target - sp.x) - c * sp.v) * h; sp.x += sp.v * h; rem -= h; }
    }
    // Blink
    let blink = 1;
    if (L.idle && t > this.nextBlink) { this.blinkT = t; this.nextBlink = t + 2.5 + Math.random() * 3.5; if (Math.random() < .15) this.nextBlink = t + .3; }
    const bu = (t - this.blinkT) / .16; if (bu >= 0 && bu < 1) blink = bu < .5 ? 1 - bu * 1.84 : .08 + (bu - .5) * 1.84;
    // Particles
    this.particles = this.particles.filter((p) => (p.life -= dtReal) > 0);
    this.particles.forEach((p) => { p.vy += (p.g || 0) * dtReal; p.x += (p.vx || 0) * dtReal; p.y += (p.vy || 0) * dtReal; if (p.k === "ring") p.r += 60 * dtReal; });
    // Assemble pose and render
    const P = { ...T }; for (const j in SPR) P[j] = this.s[j].x;
    P.eyes = eyesOv || T.eyes; P.blink = blink; P.variant = this.o.variant; P.skin = this.o.skin; P.shield = shield; P.t = t; P.phones = T.phones;
    if (this.dancing || this.pet > .1) P.fx = null;
    const msg = dynMsg || (this.msg && t < this.msg.until ? this.msg.text : null);
    this.render(P, msg);
    this.state = { mood, P };
  }
  render(P, msg) {
    const s = SKINS[this.o.skin];
    let under = "", over = "";
    for (const sp of this.sparkPos) {
      const r = 6 + 2 * sp.z, op = .55 + .35 * sp.z;
      const pulse = sp.needy ? (this.t * 1.4) % 1 : 0;
      const g = `<circle cx="${sp.x.toFixed(1)}" cy="${sp.y.toFixed(1)}" r="${r * 2.2}" fill="${sp.c}" opacity="${(op * .25).toFixed(2)}"/><circle cx="${sp.x.toFixed(1)}" cy="${sp.y.toFixed(1)}" r="${r}" fill="${sp.c}" opacity="${op.toFixed(2)}"/>` +
        (sp.needy ? `<circle cx="${sp.x}" cy="${sp.y}" r="${8 + pulse * 16}" fill="none" stroke="${sp.c}" stroke-width="2" opacity="${(1 - pulse).toFixed(2)}"/><text x="${sp.x}" y="${sp.y + 24}" text-anchor="middle" font-family="Geist, system-ui, sans-serif" font-size="11" font-weight="600" fill="#fff">${sp.name}</text>` : "");
      if (sp.z < 0 && !sp.needy) under += g; else over += g;
    }
    for (const p of this.particles) {
      const a = clamp(p.life / p.max, 0, 1);
      if (p.k === "star") over += star(p.x, p.y, p.r, p.c, a);
      else if (p.k === "heart") over += heart(p.x, p.y, 6, p.c, a);
      else if (p.k === "drop") over += `<ellipse cx="${p.x}" cy="${p.y}" rx="2.5" ry="4" fill="${p.c}" opacity="${a}"/>`;
      else if (p.k === "ring") over += `<circle cx="${p.x}" cy="${p.y}" r="${p.r}" fill="none" stroke="${p.c}" stroke-width="3" opacity="${a}"/>`;
      else if (p.k === "check") over += `<path d="M${p.x - 7} ${p.y} l5 5 l9 -10" fill="none" stroke="${p.c}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" opacity="${a}"/>`;
      else if (p.k === "note") over += `<text x="${p.x}" y="${p.y}" font-size="22" fill="${p.c}" opacity="${a}">♪</text>`;
    }
    if (msg) {
      const w = msg.length * 6.4 + 22, x = clamp(150 + this.off.x, -26, 266 - w), y = -28;
      over += `<g><rect x="${x}" y="${y}" width="${w}" height="26" rx="13" fill="#fff" opacity=".95"/><path d="M${x + 22} ${y + 25} l6 8 l4 -8Z" fill="#fff" opacity=".95"/><text x="${x + w / 2}" y="${y + 17}" text-anchor="middle" font-family="Geist, system-ui, sans-serif" font-size="12" font-weight="600" fill="#121A45">${msg}</text></g>`;
    }
    this.el.innerHTML = draw(P, { css: false, viewBox: this.o.viewBox, offX: this.off.x, offY: this.off.y, under, extras: over });
  }
}
const SPARKS = [{ name: "api", c: C.mint }, { name: "web", c: C.pink }];

window.Nova2 = { LiveNova, Scenes, Snd, Music, nova, SKINS, MOODS, R, sceneFor };
})();
