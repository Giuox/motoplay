#!/usr/bin/env node
// Copia i file web in www/ per il build Capacitor
const fs   = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const WWW  = path.join(ROOT, 'www');

if (fs.existsSync(WWW)) fs.rmSync(WWW, { recursive: true });
fs.mkdirSync(WWW);

const FILES = ['index.html', 'manifest.json', 'sw.js', 'callback.html', 'config.js', 'config.example.js'];
for (const f of FILES) {
  const src = path.join(ROOT, f);
  if (fs.existsSync(src)) {
    fs.copyFileSync(src, path.join(WWW, f));
    console.log(`  copied: ${f}`);
  }
}

function copyDir(src, dst) {
  if (!fs.existsSync(dst)) fs.mkdirSync(dst, { recursive: true });
  for (const entry of fs.readdirSync(src)) {
    const s = path.join(src, entry);
    const d = path.join(dst, entry);
    fs.statSync(s).isDirectory() ? copyDir(s, d) : fs.copyFileSync(s, d);
  }
}

copyDir(path.join(ROOT, 'assets'), path.join(WWW, 'assets'));
console.log('  copied: assets/');
console.log('www/ ready.');
