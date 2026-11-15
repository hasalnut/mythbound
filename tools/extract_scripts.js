// Pulls every Script, LocalScript and ModuleScript out of a binary .rbxl place file.
// Usage: node tools/extract_scripts.js Mythbound.rbxl out/   (needs Node 22.15+ for zstd)
const fs = require('fs'), zlib = require('zlib');
const d = fs.readFileSync(process.argv[2]);
const out = process.argv[3];
let pos = 32;
const classes = {}; // classID -> {name, refs}
const props = {};   // ref -> {Name, Source}
const parent = {};
function readStr(b, o) { const n = b.readUInt32LE(o); return [b.slice(o + 4, o + 4 + n).toString('utf8'), o + 4 + n]; }
function readInts(b, o, n) {
  const r = [];
  for (let i = 0; i < n; i++) {
    let v = ((b[o + i] << 24) | (b[o + n + i] << 16) | (b[o + 2 * n + i] << 8) | b[o + 3 * n + i]) >>> 0;
    r.push((v >>> 1) ^ -(v & 1));
  }
  return [r, o + 4 * n];
}
function refs(b, o, n) { const [r, e] = readInts(b, o, n); let acc = 0; return [r.map(x => (acc += x)), e]; }
while (pos < d.length) {
  const name = d.slice(pos, pos + 4).toString('latin1').replace(/\0/g, '');
  const clen = d.readUInt32LE(pos + 4), ulen = d.readUInt32LE(pos + 8);
  const raw = d.slice(pos + 16, pos + 16 + (clen || ulen));
  pos += 16 + (clen || ulen);
  if (name === 'END') break;
  let b = raw;
  if (clen) {
    if (raw[0] === 0x28 && raw[1] === 0xb5) b = zlib.zstdDecompressSync(raw);
    else throw new Error('LZ4 chunk not supported');
  }
  if (name === 'INST') {
    const id = b.readUInt32LE(0); let [cn, o] = readStr(b, 4); o += 1;
    const n = b.readUInt32LE(o); o += 4;
    const [r] = refs(b, o, n);
    classes[id] = { name: cn, refs: r };
  } else if (name === 'PROP') {
    const id = b.readUInt32LE(0); let [pn, o] = readStr(b, 4); const type = b[o]; o += 1;
    if ((pn === 'Name' || pn === 'Source') && type === 0x01) {
      for (const ref of classes[id].refs) {
        const [s, e] = readStr(b, o); o = e;
        (props[ref] ||= {})[pn] = s;
      }
    }
  } else if (name === 'PRNT') {
    const n = b.readUInt32LE(1);
    const [c, o2] = refs(b, 5, n); const [p] = refs(b, o2, n);
    c.forEach((x, i) => (parent[x] = p[i]));
  }
}
const cls = {};
for (const k in classes) for (const r of classes[k].refs) cls[r] = classes[k].name;
function path(r) { const p = []; while (r !== undefined && r !== -1 && cls[r]) { p.unshift((props[r] || {}).Name || cls[r]); r = parent[r]; } return p; }
const list = [];
for (const r in cls) {
  if (['Script', 'LocalScript', 'ModuleScript'].includes(cls[r])) {
    const p = path(+r); const src = (props[r] || {}).Source || '';
    list.push({ cls: cls[r], path: p.join('/'), bytes: src.length });
    fs.mkdirSync(out + '/' + p.slice(0, -1).join('/'), { recursive: true });
    fs.writeFileSync(out + '/' + p.join('/') + '.' + cls[r] + '.luau', src);
  }
}
list.sort((a, b) => a.path.localeCompare(b.path)).forEach(x => console.log(x.cls.padEnd(13), String(x.bytes).padStart(6), x.path));
