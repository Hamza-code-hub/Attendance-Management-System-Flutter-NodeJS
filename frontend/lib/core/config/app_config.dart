// ─────────────────────────────────────────────────────────────────────────────
// CyberZeus Attendance — Server Configuration
//
// LOCAL DEV  (Chrome / Windows on same machine as backend):
//   Set kServerHost = '127.0.0.1'
//
// LAN / MOBILE (Android phones on the same WiFi):
//   Set kServerHost = '192.168.100.15'   ← your laptop's WiFi IP
// ─────────────────────────────────────────────────────────────────────────────

const String kServerHost = '192.168.100.15';   // office LAN — change to 127.0.0.1 for localhost dev only
const int    kServerPort = 5000;
const String kApiBase    = 'http://$kServerHost:$kServerPort/api';
