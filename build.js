#!/usr/bin/env node
/**
 * Genera config.js dai variabili d'ambiente Vercel.
 * In locale: usa il config.js esistente (non sovrascrivere).
 * Su Vercel: crea config.js dalle env vars impostate nel dashboard.
 */
const fs = require('fs');
const path = require('path');

const configPath = path.join(__dirname, 'config.js');

// Se siamo in locale e config.js esiste già, non sovrascrivere
if (!process.env.VERCEL && fs.existsSync(configPath)) {
  console.log('build.js: config.js locale trovato, skip.');
  process.exit(0);
}

const {
  MAPBOX_TOKEN      = '',
  SPOTIFY_CLIENT_ID = '',
  OPENWEATHER_KEY   = '',
  SOS_CONTACT       = '',
  VERCEL_URL        = '',
  REDIRECT_URI      = '',
} = process.env;

// Su Vercel, REDIRECT_URI viene costruito automaticamente se non impostato
const redirectUri = REDIRECT_URI ||
  (VERCEL_URL ? `https://${VERCEL_URL}/callback.html` : 'http://localhost:8000/callback.html');

const content = `// Auto-generato da build.js — non modificare manualmente su Vercel
window.MOTOPLAY = {
  MAPBOX_TOKEN:      '${MAPBOX_TOKEN}',
  SPOTIFY_CLIENT_ID: '${SPOTIFY_CLIENT_ID}',
  OPENWEATHER_KEY:   '${OPENWEATHER_KEY}',
  SOS_CONTACT:       '${SOS_CONTACT}',
  REDIRECT_URI:      '${redirectUri}',
  SPOTIFY_SCOPES: [
    'streaming','user-read-email','user-read-private',
    'user-read-playback-state','user-modify-playback-state',
    'user-read-currently-playing',
  ].join(' '),
};
`;

fs.writeFileSync(configPath, content, 'utf8');
console.log(`build.js: config.js generato (redirect: ${redirectUri})`);
