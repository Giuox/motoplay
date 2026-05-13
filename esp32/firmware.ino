/*
 * MotoPlay ESP32 — Bridge Hardware
 *
 * Legge GPS + OBD-II + pulsanti, invia JSON via USB Serial al Raspberry Pi.
 *
 * Librerie necessarie (Arduino IDE):
 *   - TinyGPSPlus  by Mikal Hart
 *   - ArduinoJson  by Benoit Blanchon (v7)
 *
 * Pinout:
 *   GPS  NEO-M9N:  RX=GPIO16, TX=GPIO17  (Serial1, 9600 baud)
 *   ELM327 OBD-II: RX=GPIO4,  TX=GPIO5   (Serial2, 38400 baud)
 *   Btn PREV:      GPIO34 (input-only)
 *   Btn NEXT:      GPIO35 (input-only)
 *   Btn CALL:      GPIO36 (input-only)
 *   LED status:    GPIO2 (onboard)
 */

#include <TinyGPSPlus.h>
#include <ArduinoJson.h>
#include <HardwareSerial.h>

// ── Pin ───────────────────────────────────────────────────────
#define GPS_RX   16
#define GPS_TX   17
#define OBD_RX    4
#define OBD_TX    5
#define BTN_PREV 34
#define BTN_NEXT 35
#define BTN_CALL 36
#define LED       2

// ── Serial ────────────────────────────────────────────────────
HardwareSerial gpsSerial(1);   // Serial1 → GPS
HardwareSerial obdSerial(2);   // Serial2 → ELM327

TinyGPSPlus gps;

// ── Stato ─────────────────────────────────────────────────────
struct OBD {
  int     rpm      = 0;
  int     speed    = 0;
  float   temp     = 0;
  float   fuel     = 0;
  float   voltage  = 0;
  int     throttle = 0;
  bool    ready    = false;
} obd;

struct GPS_State {
  double  lat      = 0;
  double  lng      = 0;
  float   speed    = 0;  // km/h
  float   heading  = 0;
  float   accuracy = 9;
  bool    valid    = false;
} gpsState;

// ── Debounce pulsanti ──────────────────────────────────────────
unsigned long lastBtn[3] = {0, 0, 0};
const unsigned long DEBOUNCE = 250;
const char* BTN_NAMES[] = {"prev", "next", "call"};
const int   BTN_PINS[]  = {BTN_PREV, BTN_NEXT, BTN_CALL};

// ── Timing ────────────────────────────────────────────────────
unsigned long lastOBD    = 0;
unsigned long lastOutput = 0;
int obdPid = 0;

// ── Setup ─────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);   // USB → Raspberry Pi
  gpsSerial.begin(9600,  SERIAL_8N1, GPS_RX, GPS_TX);
  obdSerial.begin(38400, SERIAL_8N1, OBD_RX, OBD_TX);

  pinMode(BTN_PREV, INPUT_PULLUP);
  pinMode(BTN_NEXT, INPUT_PULLUP);
  pinMode(BTN_CALL, INPUT_PULLUP);
  pinMode(LED, OUTPUT);

  delay(500);
  obdInit();

  digitalWrite(LED, HIGH);
  Serial.println("{\"type\":\"ready\",\"fw\":\"1.0\"}");
}

// ── OBD init ──────────────────────────────────────────────────
void obdInit() {
  sendOBD("ATZ");   delay(1000);
  sendOBD("ATE0");  delay(200);   // echo off
  sendOBD("ATL0");  delay(200);   // linefeed off
  sendOBD("ATH0");  delay(200);   // headers off
  sendOBD("ATSP0"); delay(200);   // auto protocol
  obd.ready = true;
}

String sendOBD(const char* cmd) {
  obdSerial.println(cmd);
  delay(100);
  String res = "";
  unsigned long t = millis();
  while (millis() - t < 500) {
    if (obdSerial.available())
      res += (char)obdSerial.read();
  }
  res.trim();
  return res;
}

int parseOBD(const String& resp) {
  // risposta ELM327: "41 0C 0F A0" → hex bytes
  int idx = resp.lastIndexOf(' ');
  if (idx < 0) return -1;
  String hex = resp.substring(idx + 1);
  return strtol(hex.c_str(), nullptr, 16);
}

// OBD PIDs ciclici
void pollOBD() {
  if (!obd.ready || millis() - lastOBD < 120) return;
  lastOBD = millis();

  switch (obdPid % 5) {
    case 0: {  // RPM (PID 0x0C)
      String r = sendOBD("010C");
      // Formula: (A*256 + B) / 4
      int p = r.indexOf(' ');
      if (p > 0) {
        int A = strtol(r.substring(0, p).c_str(), nullptr, 16);
        int B = strtol(r.substring(p+1).c_str(), nullptr, 16);
        obd.rpm = (A * 256 + B) / 4;
      }
      break;
    }
    case 1: {  // Velocità (PID 0x0D)
      String r = sendOBD("010D");
      int v = parseOBD(r);
      if (v >= 0) obd.speed = v;
      break;
    }
    case 2: {  // Temp motore (PID 0x05)
      String r = sendOBD("0105");
      int v = parseOBD(r);
      if (v >= 0) obd.temp = v - 40.0f;
      break;
    }
    case 3: {  // Carburante % (PID 0x2F)
      String r = sendOBD("012F");
      int v = parseOBD(r);
      if (v >= 0) obd.fuel = (v / 255.0f) * 100.0f;
      break;
    }
    case 4: {  // Throttle (PID 0x11)
      String r = sendOBD("0111");
      int v = parseOBD(r);
      if (v >= 0) obd.throttle = (v / 255) * 100;
      break;
    }
  }
  obdPid++;

  // Tensione batteria (ATRVn, non standard PID)
  if (obdPid % 20 == 0) {
    String r = sendOBD("ATRV");
    r.replace("V", "");
    obd.voltage = r.toFloat();
  }
}

int calcGear(int spd, int rpm) {
  if (spd < 5)  return 0;
  if (rpm <= 0) return -1;
  float ratio = (float)rpm / max(spd, 1);
  if (ratio > 150) return 1;
  if (ratio > 100) return 2;
  if (ratio > 70)  return 3;
  if (ratio > 50)  return 4;
  if (ratio > 38)  return 5;
  return 6;
}

// ── GPS read ──────────────────────────────────────────────────
void readGPS() {
  while (gpsSerial.available())
    gps.encode(gpsSerial.read());

  if (gps.location.isUpdated()) {
    gpsState.lat      = gps.location.lat();
    gpsState.lng      = gps.location.lng();
    gpsState.valid    = gps.location.isValid();
    gpsState.accuracy = gps.hdop.isValid() ? gps.hdop.value() / 100.0f : 9.9f;
  }
  if (gps.speed.isUpdated())
    gpsState.speed = gps.speed.kmph();
  if (gps.course.isUpdated())
    gpsState.heading = gps.course.deg();
}

// ── Pulsanti ──────────────────────────────────────────────────
void checkButtons() {
  unsigned long now = millis();
  for (int i = 0; i < 3; i++) {
    if (digitalRead(BTN_PINS[i]) == LOW && now - lastBtn[i] > DEBOUNCE) {
      lastBtn[i] = now;
      StaticJsonDocument<64> doc;
      doc["type"] = "btn";
      doc["btn"]  = BTN_NAMES[i];
      serializeJson(doc, Serial);
      Serial.println();
    }
  }
}

// ── Output JSON ───────────────────────────────────────────────
void sendJSON() {
  if (millis() - lastOutput < 500) return;
  lastOutput = millis();

  StaticJsonDocument<256> doc;
  JsonObject g = doc.createNestedObject("gps");
  g["lat"]      = gpsState.lat;
  g["lng"]      = gpsState.lng;
  g["speed"]    = round(gpsState.speed * 10) / 10.0;
  g["heading"]  = round(gpsState.heading);
  g["accuracy"] = gpsState.accuracy;
  g["valid"]    = gpsState.valid;

  JsonObject o = doc.createNestedObject("obd");
  o["rpm"]      = obd.rpm;
  o["speed"]    = obd.speed;
  o["temp"]     = round(obd.temp * 10) / 10.0;
  o["fuel"]     = round(obd.fuel);
  o["gear"]     = calcGear(obd.speed, obd.rpm);
  o["voltage"]  = round(obd.voltage * 10) / 10.0;
  o["throttle"] = obd.throttle;

  serializeJson(doc, Serial);
  Serial.println();

  // LED blink
  digitalWrite(LED, !digitalRead(LED));
}

// ── Loop ─────────────────────────────────────────────────────
void loop() {
  readGPS();
  pollOBD();
  checkButtons();
  sendJSON();
}
