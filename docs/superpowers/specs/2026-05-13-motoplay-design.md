# MotoPlay — Design Spec
**Data:** 2026-05-13
**Versione:** 1.0 — Prototipo Web

---

## Contesto

Schermo dedicato da montare su Moto Guzzi per connettività Android/iOS. Obiettivo: sostituire il telefono sul manubrio con un'interfaccia ottimizzata per la guida. Connette telefono (BT/WiFi) e interfonico (BT). Prima fase: prototipo web single-file, poi evoluzione su hardware Raspberry Pi.

---

## Fase 1: Prototipo Web

**Stack:** HTML + CSS + JavaScript vanilla. Singolo file `index.html`. Nessuna dipendenza esterna, nessun build step. Apre direttamente nel browser.

---

## Splash Screen

- Sfondo `#0a0a0a`
- Logo Moto Guzzi: aquila SVG centrata, colore bianco
- Testo "MOTO GUZZI" — letterspaced, font sans-serif leggero
- Sottotitolo "MotoPlay" — colore rosso `#cc1100`, font size piccolo
- Animazione: fade-in 0.8s → pausa 1.5s → fade-out 0.6s → transizione main screen
- Transizione: opacity fade verso main screen

---

## Main Screen

### Layout

```
┌─────────────────────────────────┐
│  14:32     📱 iPhone  🎧 Sena   │  status bar (h: ~40px)
├─────────────────────────────────┤
│                                 │
│                                 │
│         APP ATTIVA              │  area principale (~70% altezza)
│                                 │
│                                 │
├─────────────────────────────────┤
│   🗺    🎵    📞    🎧    💬  ⚙️  │  dock (h: ~80px)
└─────────────────────────────────┘
```

### Palette colori

| Token | Valore | Uso |
|---|---|---|
| `--bg` | `#0a0a0a` | Sfondo principale |
| `--surface` | `#1a1a1a` | Card, dock, superfici |
| `--accent` | `#cc1100` | Rosso MG, icona attiva, highlights |
| `--text` | `#ffffff` | Testo primario |
| `--text-muted` | `#888888` | Testo secondario, labels |
| `--connected` | `#4CAF50` | Stato connesso |
| `--disconnected` | `#555555` | Stato disconnesso |

### Status Bar
- Ora corrente (aggiornata ogni minuto via JS)
- Badge telefono: verde "📱 iPhone" / grigio "📱 —" se disconnesso
- Badge interfonico: blu "🎧 Sena" / grigio "🎧 —" se disconnesso
- Logo "MG" rosso a destra

### Dock App
- 6 icone: Mappe, Musica, Telefono, Interfonico, Messaggi, Impostazioni
- Icona app attiva: sfondo `#cc1100`, bordo rosso
- Icone inattive: sfondo `#1a1a1a`
- Tap su icona → switch app con fade 200ms

---

## App Simulate

### Mappe
- Sfondo verde scuro `#0d1a0d`
- Freccia navigazione grande + testo "← Svolta a sinistra"
- Via e distanza
- Placeholder griglia mappa stilizzata CSS

### Musica
- Copertina album placeholder (gradiente colorato)
- Titolo brano + artista
- Controlli: ⏮ ⏸ ⏭ — grandi, touch-friendly
- Barra progresso

### Telefono
- Layout chiamata: nome contatto + numero
- Tasto verde "Chiama via interfonico"
- Tastierino numerico semplice

### Interfonico
- Stato connessione BT prominente
- Slider volume
- Info canale / device name
- Tasto "Connetti" se disconnesso

### Messaggi
- Lista messaggi read-only (sicurezza: no input durante guida)
- Mittente + anteprima testo
- Badge "Non rispondere durante la guida"

### Impostazioni
- Luminosità schermo (slider)
- Volume sistema (slider)
- Info connessioni (versione BT, device connessi)
- Versione app

---

## Interattività

- Switch app: fade opacity 200ms
- Splash → main: transizione automatica dopo ~3s
- Status bar: ora aggiornata ogni 60s via `setInterval`
- Stato connessioni: simulato (toggle via click per demo)
- Nessun framework, nessuna dipendenza

---

## File Structure (Fase 1)

```
motoplay/
├── index.html          ← tutto qui: HTML + CSS + JS inline
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-05-13-motoplay-design.md
```

---

## Roadmap futura (fuori scope Fase 1)

- Fase 2: Raspberry Pi + touchscreen 7" sunlight-readable
- Fase 3: Connettività reale BT (Web Bluetooth API o daemon Python)
- Fase 4: Integrazione interfonico (Sena/Cardo SDK o BT HFP profile)
- Fase 5: Enclosure IP67, montaggio manubrio, alimentazione 12V→5V
