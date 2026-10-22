.pragma library

// Launcher search: the original substring search (is the query inside
// label + subtitle + category?, ranked prefix 3 > word-start 2 > contains 1),
// with a little extra grace over the plain `hay.includes(q)` it replaced:
//   - case and accents are ignored ("cafe" finds "Café")
//   - the query's words may appear in any order ("key ssh" finds "New SSH key")
//   - separators are ignored for words of 3+ chars ("sshkey", "ssh-key")
// No typo/subsequence guessing.
//
// compile(raw) once per search, then score(cq, label, sub, cat) per item ->
// -1 for no match, else 0..3 (0 = matched only via subtitle/category, as before).

var cache = {};
var cacheSize = 0;
var ascii = /^[\x00-\x7f]*$/;

function norm(s) {
  if (!s) return "";
  let r = cache[s];
  if (r === undefined) {
    r = ascii.test(s) ? s.toLowerCase() : s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    if (cacheSize++ > 50000) { cache = {}; cacheSize = 0; }  // clipboard text is unbounded
    cache[s] = r;
  }
  return r;
}

function compile(raw) {
  const q = norm(raw.trim());
  return { q, toks: q.split(/\s+/).filter(t => t.length > 0) };
}

function rank(q, l) {
  return l.startsWith(q) ? 3 : l.split(/[\s-]+/).some(w => w.startsWith(q)) ? 2 : l.includes(q) ? 1 : 0;
}

// l = normalized label, hay = normalized label + subtitle/category text
function scoreN(cq, l, hay) {
  const toks = cq.toks;
  if (toks.length === 0) return -1;
  let flat = null;
  for (let i = 0; i < toks.length; i++) {
    if (hay.indexOf(toks[i]) >= 0) continue;
    if (toks[i].length < 3 || hay.length > 200) return -1;
    if (flat === null) flat = hay.replace(/[^a-z0-9]+/g, "");
    if (flat.indexOf(toks[i].replace(/[^a-z0-9]+/g, "")) < 0) return -1;
  }
  let s = rank(cq.q, l);
  if (toks.length > 1) {
    let m = 3;
    for (let i = 0; i < toks.length; i++) m = Math.min(m, rank(toks[i], l));
    if (m > s) s = m;
  }
  return s;
}

function score(cq, label, sub, cat) {
  const l = norm(label);
  return scoreN(cq, l, l + " " + norm(sub) + (cat ? " " + norm(cat) : ""));
}
