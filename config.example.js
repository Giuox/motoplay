// Copia questo file in config.js e inserisci i tuoi token
// NON committare config.js (contiene chiavi private)

window.MOTOPLAY = {
  MAPBOX_TOKEN:      '',   // https://account.mapbox.com
  SPOTIFY_CLIENT_ID: '',   // https://developer.spotify.com/dashboard
  OPENWEATHER_KEY:   '',   // https://openweathermap.org/api (gratuito)
  SOS_CONTACT:       '',   // es. '+39333123456'
  REDIRECT_URI:      'https://TUO-DOMINIO/callback.html',
  SPOTIFY_SCOPES: [
    'streaming','user-read-email','user-read-private',
    'user-read-playback-state','user-modify-playback-state',
    'user-read-currently-playing',
  ].join(' '),
};
