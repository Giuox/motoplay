#!/usr/bin/env python3
"""
MotoPlay Server — HTTP + WebSocket su porta singola
  - PC:  simula GPS/OBD (dati marcati sim:true, ignorati dalla mappa)
  - Pi:  legge hardware reale (gpsd, ESP32 serial, BlueZ)

Avvio locale:  python server.py
Avvio cloud:   PORT=8000 python server.py
"""

import asyncio, json, math, random, time, os, sys, logging, socket
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S',
)
log = logging.getLogger('motoplay')

try:
    from aiohttp import web, WSMsgType
except ImportError:
    log.error("Installa dipendenze: pip install -r requirements.txt")
    sys.exit(1)

# ─── Detect hardware ──────────────────────────────────────────
IS_PI  = os.path.exists('/sys/firmware/devicetree/base/model')
PORT   = int(os.environ.get('PORT', 8000))
ROOT   = Path(__file__).parent

if IS_PI:
    try:
        with open('/sys/firmware/devicetree/base/model') as f:
            log.info(f"Hardware: {f.read().strip()}")
    except Exception:
        pass
else:
    log.info("Hardware: PC (modalità simulazione)")

# ─── Stato globale ────────────────────────────────────────────
clients: set = set()

state = {
    'lat': 45.4642, 'lng': 9.1900,
    'speed': 0.0, 'heading': 0.0, 'accuracy': 4.5,
    'rpm': 800, 'temp': 22.0, 'fuel': 74.0,
    'gear': 0, 'voltage': 12.6, 'throttle': 0,
    'phone': False, 'phone_name': '',
    'intercom': False, 'intercom_name': '',
    '_t': 0.0,
}


# ─── Simulazione ─────────────────────────────────────────────
def sim_tick():
    s = state; s['_t'] += 0.5; t = s['_t']
    spd = max(0, 75 + 35 * math.sin(t * 0.04) + random.gauss(0, 3))
    s['speed']   = round(spd, 1)
    s['heading'] = round((t * 3.2) % 360, 1)
    s['lat']     = round(45.4642 + 0.036 * math.sin(t * 0.025), 6)
    s['lng']     = round(9.1900  + 0.036 * math.cos(t * 0.025), 6)
    s['accuracy']= round(random.uniform(3, 7), 1)
    s['rpm']     = max(800, int(spd * 55 + random.gauss(0, 80)))
    s['temp']    = round(min(90, 22 + t * 0.56) if t < 120 else
                         s['temp'] + random.gauss(0, 0.05), 1)
    s['fuel']    = round(max(0, s['fuel'] - 0.0008), 2)
    s['voltage'] = round((13.8 if spd > 10 else 12.6) + random.gauss(0, 0.05), 2)
    s['throttle']= round(max(0, min(100, spd / 130 * 100 + random.gauss(0, 3))), 1)
    s['gear']    = (0 if spd<5 else 1 if spd<20 else 2 if spd<38 else
                    3 if spd<58 else 4 if spd<82 else 5 if spd<108 else 6)
    if t > 3 and not s['phone']:
        s['phone'] = True; s['phone_name'] = 'iPhone 15 Pro'
        s['intercom'] = True; s['intercom_name'] = 'Sena 50S'


# ─── Raspberry Pi hardware ────────────────────────────────────
_esp32 = None

def init_pi_hardware():
    global _esp32
    for port in ['/dev/ttyUSB0', '/dev/ttyACM0']:
        if os.path.exists(port):
            try:
                import serial
                _esp32 = serial.Serial(port, 115200, timeout=1)
                log.info(f"ESP32 su {port}")
                return
            except Exception as e:
                log.warning(f"{port}: {e}")
    log.warning("ESP32 non trovato")
    try:
        import gpsd; gpsd.connect(); log.info("gpsd connesso")
    except Exception:
        log.warning("gpsd non disponibile")


async def pi_read():
    if not _esp32: return
    try:
        import serial
        line = await asyncio.get_event_loop().run_in_executor(
            None, _esp32.readline)
        data = json.loads(line.decode().strip())
        if 'gps' in data: state.update(data['gps'])
        if 'obd' in data: state.update(data['obd'])
        if 'btn' in data:
            await broadcast({'type': 'btn', 'button': data['btn']})
    except Exception:
        pass

async def pi_gps():
    try:
        import gpsd; p = gpsd.get_current()
        state.update({'lat': p.lat, 'lng': p.lon,
                      'speed': p.speed()*3.6, 'heading': p.track,
                      'accuracy': p.position_precision()[0]})
    except Exception:
        pass


# ─── Broadcast ───────────────────────────────────────────────
async def broadcast(msg: dict):
    if not clients: return
    dead = set()
    for ws in clients:
        try:
            await ws.send_json(msg)
        except Exception:
            dead.add(ws)
    clients.difference_update(dead)


# ─── Loop dati ────────────────────────────────────────────────
async def data_loop():
    while True:
        if IS_PI:
            await pi_read(); await pi_gps()
        else:
            sim_tick()
        s = state
        await broadcast({
            'type': 'gps', 'sim': not IS_PI,
            'lat': s['lat'], 'lng': s['lng'],
            'speed': s['speed'], 'heading': s['heading'],
            'accuracy': s['accuracy'],
        })
        await broadcast({
            'type': 'obd',
            'rpm': s['rpm'], 'speed': int(s['speed']),
            'temp': s['temp'], 'fuel': round(s['fuel'], 1),
            'gear': s['gear'], 'voltage': s['voltage'],
            'throttle': s['throttle'],
        })
        await asyncio.sleep(0.5)


async def bt_loop():
    while True:
        if IS_PI:
            # Solo su Pi: legge stato BT reale e lo invia
            s = state
            if s['phone'] or s['intercom']:
                await broadcast({
                    'type': 'bt',
                    'phone': s['phone'], 'phone_name': s['phone_name'],
                    'intercom': s['intercom'], 'intercom_name': s['intercom_name'],
                })
        # Su PC: non inviare mai dati BT simulati
        await asyncio.sleep(4)


# ─── Comandi client ───────────────────────────────────────────
async def handle_command(cmd: dict):
    c = cmd.get('cmd')
    if c == 'vol' and IS_PI:
        os.system(f'amixer set Master {cmd.get("value",70)}%')
    elif c == 'call_answer' and IS_PI:
        os.system('bluetoothctl -- telephony answer')
    elif c == 'call_reject' and IS_PI:
        os.system('bluetoothctl -- telephony reject')
    elif c == 'nav_voice' and IS_PI:
        t = cmd.get('text','').replace('"','')
        os.system(f'espeak-ng -v it "{t}" &')
    elif c == 'bt_connect' and not IS_PI:
        state.update({'phone': True, 'phone_name': 'iPhone 15 Pro',
                      'intercom': True, 'intercom_name': 'Sena 50S'})
    elif c == 'sim_call' and not IS_PI:
        await broadcast({'type':'call','state':'incoming',
                         'number':'+39 333 456 7890','name':'Marco R.'})
        await asyncio.sleep(8)
        await broadcast({'type':'call','state':'ended'})


# ─── WebSocket handler ────────────────────────────────────────
async def ws_handler(request):
    ws = web.WebSocketResponse(heartbeat=30)
    await ws.prepare(request)
    clients.add(ws)
    ip = request.remote
    log.info(f"WS connesso: {ip} (tot: {len(clients)})")

    await ws.send_json({
        'type': 'status',
        'hardware': 'pi' if IS_PI else 'sim',
        'version': '1.0',
    })

    async for msg in ws:
        if msg.type == WSMsgType.TEXT:
            try: await handle_command(json.loads(msg.data))
            except Exception: pass
        elif msg.type in (WSMsgType.ERROR, WSMsgType.CLOSE):
            break

    clients.discard(ws)
    log.info(f"WS disconnesso: {ip}")
    return ws


# ─── HTTP static files ────────────────────────────────────────
async def index_handler(request):
    return web.FileResponse(ROOT / 'index.html')

async def static_handler(request):
    path = ROOT / request.match_info['path']
    if path.is_file():
        return web.FileResponse(path)
    return web.FileResponse(ROOT / 'index.html')  # SPA fallback


# ─── iPhone Shortcuts endpoint ───────────────────────────────
async def iphone_handler(request):
    try:
        data = await request.json()
    except Exception:
        return web.Response(status=400, text='bad json')
    event = data.get('event', '?')
    log.info(f"iPhone: {event}")
    await broadcast({'type': 'iphone', **data})
    return web.json_response({'ok': True})


# ─── App setup ────────────────────────────────────────────────
app = web.Application()
app.router.add_get('/ws',              ws_handler)
app.router.add_post('/api/iphone',     iphone_handler)
app.router.add_get('/',                index_handler)
app.router.add_get('/{path:.+}',       static_handler)


async def on_startup(a):
    if IS_PI: init_pi_hardware()
    asyncio.create_task(data_loop())
    asyncio.create_task(bt_loop())

    # Mostra IP locale per accesso da iPhone/tablet
    try:
        local_ip = socket.gethostbyname(socket.gethostname())
    except Exception:
        local_ip = 'localhost'

    log.info("─" * 44)
    log.info(f"Locale  →  http://localhost:{PORT}")
    log.info(f"iPhone  →  http://{local_ip}:{PORT}")
    log.info("─" * 44)

app.on_startup.append(on_startup)


if __name__ == '__main__':
    web.run_app(app, host='0.0.0.0', port=PORT, access_log=None)
