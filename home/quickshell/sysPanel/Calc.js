.pragma library

// Calculator expression engine -- ported near-verbatim from `calcEval()` in
// "Quickshell Example/Quickshell Bar.dc.html" (around line 1060), the mock's
// own recursive-descent parser/evaluator. Only real change: the mock reads
// the running total as `this.state.menuAns`; here it's passed in explicitly
// as `ans` since there's no component state to close over.
//
// Handles: +-*/^, unary/implicit multiplication, parens, |abs|, √∛∜ prefix
// roots, sqrt/cbrt/root/exp/ln/log/log2/log10/trig(+inverse+hyperbolic)/abs/
// floor/ceil/round/trunc/sign/min/max/sum/mean/hypot/gcd/lcm/ncr/npr/
// fact/gamma/deg/rad conversions, `mod`, trailing `!` factorial, trailing
// `%` (plain and "+15%"/"-15%" percent-of), trailing `°`/`deg`, `log_2(x)`/
// `log2(x)`/`root(3)(27)` subscript-or-double-paren bases, hex (0x..) and
// binary (0b..) literals, named constants (pi/tau/e/phi/inf/ans), and
// superscript-digit exponents (x², x³, ...).
function evaluate(raw, ans) {
  if (!raw || raw.length > 240) return null;
  const SUPM = { "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-" };
  const src = raw.replace(/[×·∙]/g, "*").replace(/÷/g, "/").replace(/[−–]/g, "-").replace(/\*\*/g, "^")
    .replace(/[⁰¹²³⁴-⁹⁻]+/g, m => "^(" + [...m].map(c => SUPM[c]).join("") + ")");
  const M = Math;
  const gamma = z => {
    if (z < 0.5) return M.PI / (M.sin(M.PI * z) * gamma(1 - z));
    z -= 1;
    const c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7];
    let x = c[0];
    for (let i = 1; i < 9; i++) x += c[i] / (z + i);
    const t = z + 7.5;
    return M.sqrt(2 * M.PI) * M.pow(t, z + 0.5) * M.exp(-t) * x;
  };
  const fact = n => {
    if (Number.isInteger(n)) {
      if (n < 0) return NaN;
      if (n > 170) return Infinity;
      let r = 1;
      for (let i = 2; i <= n; i++) r *= i;
      return r;
    }
    return gamma(n + 1);
  };
  const g2 = (a, b) => { a = M.abs(M.round(a)); b = M.abs(M.round(b)); while (b) { const t = b; b = a % b; a = t; } return a; };
  const ncr = (n, k) => { if (k < 0 || k > n) return 0; k = M.min(k, n - k); let r = 1; for (let i = 1; i <= k; i++) r = r * (n - k + i) / i; return M.round(r); };
  const npr = (n, k) => { if (k < 0 || k > n) return 0; let r = 1; for (let i = 0; i < k; i++) r *= n - i; return r; };
  const one = fn => [1, 1, fn], many = fn => [1, 99, fn], avg = function () { const a = Array.prototype.slice.call(arguments); return a.reduce((x, y) => x + y, 0) / a.length; };
  const sumAll = function () { const a = Array.prototype.slice.call(arguments); return a.reduce((x, y) => x + y, 0); };
  const hypotAll = function () { return M.hypot.apply(M, arguments); };
  const minAll = function () { return M.min.apply(M, arguments); };
  const maxAll = function () { return M.max.apply(M, arguments); };
  const gcdAll = function () { const a = Array.prototype.slice.call(arguments); return a.reduce(g2); };
  const lcmAll = function () { const a = Array.prototype.slice.call(arguments); return a.reduce((x, y) => M.abs(M.round(x) * M.round(y)) / g2(x, y)); };
  const FN = {
    sqrt: one(M.sqrt), cbrt: one(M.cbrt), root: [2, 2, (n, x) => (x < 0 && M.abs(n % 2) === 1 ? -M.pow(-x, 1 / n) : M.pow(x, 1 / n))],
    exp: one(M.exp), ln: one(M.log), log: [1, 2, a => M.log10(a)], log2: one(M.log2), log10: one(M.log10), lg: one(M.log10), lb: one(M.log2),
    sin: one(M.sin), cos: one(M.cos), tan: one(M.tan), sec: one(x => 1 / M.cos(x)), csc: one(x => 1 / M.sin(x)), cot: one(x => 1 / M.tan(x)),
    asin: one(M.asin), acos: one(M.acos), atan: one(M.atan), arcsin: one(M.asin), arccos: one(M.acos), arctan: one(M.atan), atan2: [2, 2, M.atan2],
    sinh: one(M.sinh), cosh: one(M.cosh), tanh: one(M.tanh), asinh: one(M.asinh), acosh: one(M.acosh), atanh: one(M.atanh),
    abs: one(M.abs), floor: one(M.floor), ceil: one(M.ceil), round: [1, 2, (x, n) => M.round(x * 10 ** (n || 0)) / 10 ** (n || 0)], trunc: one(M.trunc), sign: one(M.sign), sgn: one(M.sign),
    min: many(minAll), max: many(maxAll), sum: many(sumAll), mean: many(avg), avg: many(avg),
    hypot: many(hypotAll), gcd: many(gcdAll), lcm: many(lcmAll),
    ncr: [2, 2, ncr], choose: [2, 2, ncr], npr: [2, 2, npr], perm: [2, 2, npr], fact: one(fact), factorial: one(fact), gamma: one(gamma),
    degrees: one(x => x * 180 / M.PI), radians: one(x => x * M.PI / 180), mod: [2, 2, (a, b) => ((a % b) + b) % b],
  };
  const PHI = (1 + M.sqrt(5)) / 2;
  const CONST = { pi: M.PI, "π": M.PI, tau: 2 * M.PI, "τ": 2 * M.PI, e: M.E, phi: PHI, "φ": PHI, inf: Infinity, infinity: Infinity, "∞": Infinity, ans: ans || 0 };
  const NAMES = [...Object.keys(FN), ...Object.keys(CONST).filter(k => /^[a-z]/.test(k)), "deg"].sort((a, b) => b.length - a.length);
  const toks = [];
  for (let i = 0; i < src.length;) {
    const ch = src[i], rest = src.slice(i);
    if (/\s/.test(ch)) { i++; continue; }
    let m = /^0x[0-9a-f]+|^0b[01]+/i.exec(rest);
    if (m) { const s = m[0].toLowerCase(); toks.push({ t: "num", v: s[1] === "b" ? parseInt(s.slice(2), 2) : parseInt(s, 16), s: m[0] }); i += m[0].length; continue; }
    m = /^(\d+(\.\d*)?|\.\d+)(e[+-]?\d+)?/i.exec(rest);
    if (m) { toks.push({ t: "num", v: parseFloat(m[0]), s: m[0] }); i += m[0].length; continue; }
    if ("+-*/^(),!%|_√∛∜°".includes(ch)) { toks.push({ t: "op", v: ch }); i++; continue; }
    if ("πτφ∞".includes(ch)) { toks.push({ t: "id", v: ch }); i++; continue; }
    if (/[a-z]/i.test(ch)) {
      const lr = rest.toLowerCase(), n = NAMES.find(nm => lr.startsWith(nm));
      if (!n) return null;
      toks.push({ t: "id", v: n }); i += n.length; continue;
    }
    return null;
  }
  if (!toks.length) return null;
  let p = 0, absD = 0, nontriv = false, autoClosed = 0;
  const isOp = (v, k) => { if (k === undefined) k = p; return !!toks[k] && toks[k].t === "op" && toks[k].v === v; };
  const isId = (v, k) => { if (k === undefined) k = p; return !!toks[k] && toks[k].t === "id" && toks[k].v === v; };
  const starts = (k) => {
    if (k === undefined) k = p;
    const t = toks[k];
    if (!t) return false;
    if (t.t === "num") return true;
    if (t.t === "id") return t.v === "deg" ? false : t.v === "mod" ? isOp("(", k + 1) : true;
    return t.v === "(" || t.v === "√" || t.v === "∛" || t.v === "∜" || (t.v === "|" && absD === 0);
  };
  const expect = v => { if (isOp(v)) { p++; return; } if (!toks[p] && v === ")") { autoClosed++; return; } throw 0; };
  let expr, term, unary, power, postfix, primary;
  expr = () => {
    let a = term();
    while (isOp("+") || isOp("-")) {
      const op = toks[p++].v; nontriv = true; const b = term();
      a = (b.t === "post" && b.op === "%") ? { t: "bin", op, a, b, pctOf: true } : { t: "bin", op, a, b };
    }
    return a;
  };
  term = () => {
    let a = unary();
    for (;;) {
      if (isOp("*") || isOp("/")) { const op = toks[p++].v; nontriv = true; a = { t: "bin", op, a, b: unary() }; }
      else if ((isId("mod") && !isOp("(", p + 1)) || (isOp("%") && starts(p + 1))) { p++; nontriv = true; a = { t: "bin", op: "mod", a, b: unary() }; }
      else if (starts()) { nontriv = true; a = { t: "bin", op: "*", imp: true, a, b: power() }; }
      else break;
    }
    return a;
  };
  unary = () => { if (isOp("-")) { p++; nontriv = true; return { t: "neg", a: unary() }; } if (isOp("+")) { p++; return unary(); } return power(); };
  power = () => { const a = postfix(); if (isOp("^")) { p++; nontriv = true; return { t: "bin", op: "^", a, b: unary() }; } return a; };
  postfix = () => {
    let a = primary();
    for (;;) {
      if (isOp("!")) { p++; nontriv = true; a = { t: "post", op: "!", a }; }
      else if (isOp("%") && !starts(p + 1)) { p++; nontriv = true; a = { t: "post", op: "%", a }; }
      else if (isOp("°") || isId("deg")) { p++; nontriv = true; a = { t: "post", op: "°", a }; }
      else break;
    }
    return a;
  };
  primary = () => {
    const t = toks[p]; if (!t) throw 0;
    if (t.t === "num") { p++; return { t: "num", v: t.v, s: t.s }; }
    if (t.t === "op") {
      if (t.v === "(") { p++; const e = expr(); expect(")"); return { t: "par", a: e }; }
      if (t.v === "|" && absD === 0) {
        p++; absD++; const e = expr(); absD--;
        if (isOp("|")) p++; else if (toks[p]) throw 0; else autoClosed++;
        nontriv = true; return { t: "fn", n: "abs", args: [e] };
      }
      if (t.v === "√" || t.v === "∛" || t.v === "∜") {
        p++; nontriv = true; const arg = isOp("-") ? unary() : power();
        return t.v === "∜" ? { t: "fn", n: "root", args: [{ t: "num", v: 4, s: "4" }, arg] } : { t: "fn", n: t.v === "√" ? "sqrt" : "cbrt", args: [arg] };
      }
      throw 0;
    }
    p++;
    if (t.v in CONST) { if (t.v !== "e" && t.v !== "ans") nontriv = true; return { t: "const", n: t.v, v: CONST[t.v] }; }
    const def = FN[t.v]; if (!def) throw 0;
    nontriv = true;
    let base = null, args;
    if (isOp("_")) { p++; base = primary(); }
    if (isOp("(")) {
      p++; args = [];
      if (!isOp(")")) { args.push(expr()); while (isOp(",")) { p++; args.push(expr()); } }
      expect(")");
      if ((t.v === "log" || t.v === "root") && args.length === 1 && !base && isOp("(")) { p++; const x = expr(); expect(")"); base = args[0]; args = [x]; }
    } else if (starts() || isOp("-")) args = [isOp("-") ? unary() : power()];
    else { const m = /^log(\d+)$/.exec(t.v); if (m && !base) return { t: "fn", n: "log", args: [{ t: "num", v: +m[1], s: m[1] }] }; throw 0; }
    if (base) {
      if (t.v === "log" && args.length === 1) return { t: "fn", n: "log", base, args };
      if (t.v === "root" && args.length === 1) return { t: "fn", n: "root", args: [base, args[0]] };
      throw 0;
    }
    if (args.length < def[0] || args.length > def[1]) throw 0;
    if (t.v === "log" && args.length === 2) return { t: "fn", n: "log", base: args[0], args: [args[1]] };
    return { t: "fn", n: t.v, args };
  };
  let ast;
  try { ast = expr(); if (p < toks.length) return null; } catch (e) { return null; }
  if (!nontriv) return null;
  const ev = n => {
    switch (n.t) {
      case "num": case "const": return n.v;
      case "par": return ev(n.a);
      case "neg": return -ev(n.a);
      case "post": { const a = ev(n.a); return n.op === "!" ? fact(a) : n.op === "%" ? a / 100 : a * M.PI / 180; }
      case "fn": return n.base ? M.log(ev(n.args[0])) / M.log(ev(n.base)) : FN[n.n][2].apply(null, n.args.map(ev));
      case "bin": {
        const a = ev(n.a);
        if (n.pctOf) { const pc = ev(n.b.a) / 100; return n.op === "+" ? a * (1 + pc) : a * (1 - pc); }
        const b = ev(n.b);
        if (n.op === "+") return a + b; if (n.op === "-") return a - b; if (n.op === "*") return a * b; if (n.op === "/") return a / b;
        if (n.op === "mod") return ((a % b) + b) % b;
        if (a < 0 && !Number.isInteger(b)) { const inv = 1 / b, ri = M.round(inv); if (M.abs(inv - ri) < 1e-9 && M.abs(ri % 2) === 1) return -M.pow(-a, b); }
        return M.pow(a, b);
      }
    }
    return NaN;
  };
  let v;
  try { v = ev(ast); } catch (e) { return null; }
  if (typeof v !== "number") return null;
  if (isFinite(v)) { const r = M.round(v); if (M.abs(v - r) < 1e-11 * M.max(1, M.abs(v))) v = r; }
  const SUPD = "⁰¹²³⁴⁵⁶⁷⁸⁹", SUBD = "₀₁₂₃₄₅₆₇₈₉";
  const sup = s => [...s].map(c => c === "-" ? "⁻" : SUPD[+c]).join(""), sub = s => [...s].map(c => SUBD[+c]).join("");
  const intS = n => !!n && n.t === "num" && /^\d+$/.test(n.s);
  const SYM = { pi: "π", tau: "τ", phi: "φ", inf: "∞", infinity: "∞" };
  const OPS = { "+": " + ", "-": " − ", "*": " × ", "/": " ÷ ", mod: " mod " }, PREC = { "+": 1, "-": 1, "*": 2, "/": 2, mod: 2 };
  const pp = (n, ctx) => {
    if (ctx === undefined) ctx = 0;
    const wrap = (s, pr) => pr < ctx ? "(" + s + ")" : s;
    switch (n.t) {
      case "num": return n.s;
      case "const": return SYM[n.n] || n.n;
      case "par": return pp(n.a, ctx);
      case "neg": return wrap("−" + pp(n.a, 3), 3);
      case "post": return pp(n.a, 5) + n.op;
      case "bin": {
        if (n.op === "^") { const bb = n.b.t === "par" ? n.b.a : n.b; return wrap(intS(bb) ? pp(n.a, 5) + sup(bb.s) : pp(n.a, 5) + "^" + pp(n.b, 4), 4); }
        if (n.pctOf) return wrap(pp(n.a, 1) + OPS[n.op] + pp(n.b.a, 5) + "%", 1);
        if (n.imp) { const sa = pp(n.a, 2), sb = pp(n.b, 3); return wrap(sa + (/[\d.]$/.test(sa) && /^[\d.√∛⁰-⁹]/.test(sb) ? "·" : "") + sb, 2); }
        const pr = PREC[n.op]; return wrap(pp(n.a, pr) + OPS[n.op] + pp(n.b, pr + 1), pr);
      }
      case "fn": {
        const A = n.args, atom = x => x.t === "num" || x.t === "const", arg = x => atom(x) ? pp(x) : "(" + pp(x) + ")";
        if (n.n === "sqrt") return "√" + arg(A[0]);
        if (n.n === "cbrt") return "∛" + arg(A[0]);
        if (n.n === "root") return intS(A[0]) ? sup(A[0].s) + "√" + arg(A[1]) : "root(" + pp(A[0]) + ", " + pp(A[1]) + ")";
        if (n.n === "abs") return "|" + pp(A[0]) + "|";
        if (n.n === "fact" || n.n === "factorial") return pp(A[0], 5) + "!";
        if (n.base) return intS(n.base) ? "log" + sub(n.base.s) + "(" + pp(A[0]) + ")" : "log_(" + pp(n.base) + ")(" + pp(A[0]) + ")";
        if (n.n === "log2" || n.n === "lb") return "log₂(" + pp(A[0]) + ")";
        if (n.n === "log10" || n.n === "lg") return "log₁₀(" + pp(A[0]) + ")";
        if (n.n === "ncr" || n.n === "choose") return "C(" + A.map(x => pp(x)).join(", ") + ")";
        if (n.n === "npr" || n.n === "perm") return "P(" + A.map(x => pp(x)).join(", ") + ")";
        return n.n + "(" + A.map(x => pp(x)).join(", ") + ")";
      }
    }
    return "?";
  };
  const pretty = pp(ast);
  if (Number.isNaN(v)) return { ok: false, display: "undefined", pretty, raw: "", reason: "not a real number", autoClosed };
  const trim = s => s.includes(".") ? s.replace(/\.?0+$/, "") : s;
  const sciOf = (x, d) => { const parts = x.toExponential(d).split("e"); return trim(parts[0]) + " × 10" + sup(String(+parts[1])); };
  const a = M.abs(v);
  let display, sci = "";
  if (!isFinite(v)) display = v > 0 ? "∞" : "−∞";
  else if (v !== 0 && (a >= 1e15 || a < 1e-7)) display = sciOf(v, 10);
  else {
    const s = String(+v.toPrecision(12)), parts = s.replace("-", "").split(".");
    display = (v < 0 ? "−" : "") + (a >= 10000 ? parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",") : parts[0]) + (parts[1] ? "." + parts[1] : "");
    if (a >= 1e6 || (a < 1e-3 && v !== 0)) sci = sciOf(v, 6);
  }
  const raw2 = isFinite(v) ? String(+v.toPrecision(15)) : (v > 0 ? "inf" : "-inf");
  const toFrac = (x, maxD) => {
    if (!isFinite(x) || Number.isInteger(x) || M.abs(x) > 1e6) return null;
    let h1 = 1, h0 = 0, k1 = 0, k0 = 1, b = x;
    for (let i = 0; i < 24; i++) {
      const ai = M.floor(b);
      const nh1 = ai * h1 + h0; h0 = h1; h1 = nh1;
      const nk1 = ai * k1 + k0; k0 = k1; k1 = nk1;
      if (k1 > maxD) return null;
      if (M.abs(x - h1 / k1) < 1e-10 * M.max(1, M.abs(x))) return [h1, k1];
      b = 1 / (b - ai); if (!isFinite(b)) break;
    }
    return null;
  };
  const neg = s => String(s).replace("-", "−");
  const fr = toFrac(v, 10000);
  let piFrac = "";
  if (!fr && isFinite(v) && v !== 0 && !Number.isInteger(v)) {
    const q = v / M.PI, qi = M.round(q);
    if (M.abs(q - qi) < 1e-10 && M.abs(qi) < 1000) piFrac = (qi === 1 ? "" : qi === -1 ? "−" : neg(qi)) + "π";
    else { const pf = toFrac(q, 24); if (pf) piFrac = (pf[0] === 1 ? "" : pf[0] === -1 ? "−" : neg(pf[0])) + "π/" + pf[1]; }
  }
  const isInt = Number.isInteger(v) && a < 2 ** 53;
  return {
    ok: true, value: v, display, pretty, raw: raw2, sci, autoClosed, piFrac,
    frac: fr ? neg(fr[0]) + "/" + fr[1] : "",
    hex: isInt ? (v < 0 ? "−0x" : "0x") + a.toString(16) : "",
    bin: isInt && a <= 65535 ? (v < 0 ? "−0b" : "0b") + a.toString(2) : "",
  };
}
