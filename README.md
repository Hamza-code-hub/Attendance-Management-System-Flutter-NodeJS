# CyberZeus AMS — Attendance Management System

A production-ready, full-stack attendance management system for office deployment.
Built with a Node.js/TypeScript REST API and a Flutter Android + Web client.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend API | Node.js 20 + Express + TypeScript |
| Database | SQLite (auto-created on first run) |
| Auth | JWT (access 12 h + refresh 7 d) |
| Frontend | Flutter 3.x (Android APK + Web) |
| State | Riverpod 2.x |
| Routing | GoRouter 12.x |
| UI | Material 3, custom dark/light theme |

---

## Project Structure

```
Attendance_System/
├── backend/               # Node.js + TypeScript REST API
│   ├── src/
│   │   ├── config/        # DB, logger, settings
│   │   ├── controllers/   # Route handlers
│   │   ├── middleware/     # Auth, rate-limiter, error handler
│   │   ├── repositories/  # Data access layer
│   │   ├── routes/        # Express routers
│   │   ├── services/      # Business logic
│   │   └── server.ts      # Entry point
│   ├── .env.example
│   └── package.json
│
├── frontend/              # Flutter Android + Web client
│   ├── lib/
│   │   ├── core/          # Theme, router, server config
│   │   └── features/      # Feature modules
│   ├── assets/
│   ├── android/
│   └── pubspec.yaml
│
└── README.md
```

---

## New Device Setup (Complete)

### Prerequisites

| Tool | Version | Install |
|---|---|---|
| Node.js | 20.x LTS | https://nodejs.org |
| npm | 10.x | bundled with Node |
| Flutter SDK | 3.10+ | https://docs.flutter.dev/get-started/install |
| Android Studio | latest | https://developer.android.com/studio |
| Java JDK | 17 | via Android Studio or https://adoptium.net |
| Git | any | https://git-scm.com |

### 1 — Clone the repository

```bash
git clone https://github.com/Hamza-code-hub/Cyberzeus_AMS.git
cd Cyberzeus_AMS
```

### 2 — Backend setup

```bash
cd backend

# Install all Node.js dependencies (from package.json)
npm install

# Create environment file
cp .env.example .env
# Open .env and change JWT_SECRET to a strong random string

# Start development server (auto-restarts on file change)
npm run dev
```

The API starts on **http://localhost:5000**.
The SQLite database (`attendance.db`) is created automatically on first run.

**Production:**
```bash
npm run build   # TypeScript → dist/
npm start       # runs dist/server.js
```

### 3 — Flutter dependencies

```bash
cd frontend
flutter pub get
```

### 4 — Run on Web (development)

```bash
cd frontend
flutter run -d chrome
```

### 5 — Build Android APK (release)

> **Signing key required.** The keystore (`cyberzeus-release.jks`) and
> `key.properties` are NOT in the repository for security.
> Get them from the project owner and place them at:
> - `frontend/android/app/cyberzeus-release.jks`
> - `frontend/android/key.properties`

```bash
cd frontend
flutter clean
flutter pub get
flutter build apk --release
```

Output: `frontend/build/app/outputs/flutter-apk/app-release.apk`

---

## Server URL Configuration

The Android app lets you set the server address at runtime — **no rebuild needed**.

On the login screen, tap the **"Server: ..."** row to expand it, enter the new URL, and tap **Save**.

| Use case | URL format |
|---|---|
| Office LAN (same WiFi) | `http://192.168.100.15:5000` |
| Internet / public IP | `http://YOUR_PUBLIC_IP:5000` |
| Local dev (emulator) | `http://10.0.2.2:5000` |
| Local dev (localhost) | `http://127.0.0.1:5000` |

> For internet access over HTTP, make sure your router forwards port 5000 to the server machine.
> HTTPS is recommended for production internet use.

---

## Default Login

On a fresh database the seeder creates an Admin account:

| Field | Value |
|---|---|
| Username | `admin` |
| Password | `admin123` |

**Change the admin password immediately after first login.**

---

## Features

### Employee
- Clock in / clock out with server-enforced timestamps
- Break start / end logging
- View own attendance history
- Submit correction, overtime, and time adjustment requests

### Manager
- Team attendance dashboard
- Approve / reject employee requests

### HR
- Live attendance monitor and shift monitor
- Employee directory
- Reports with Excel / CSV export
- Approve requests (second-level)

### Admin
- User account management
- Department and shift configuration
- System settings (subnet, grace period, org name)
- Audit logs
- Health check (`GET /api/health`)

---

## Environment Variables

See [`backend/.env.example`](backend/.env.example) for the full list.

| Variable | Default | Description |
|---|---|---|
| `PORT` | `5000` | API server port |
| `NODE_ENV` | `development` | `development` or `production` |
| `JWT_SECRET` | **(required)** | Signing key — must change before deploying |
| `JWT_EXPIRE_HOURS` | `12` | Access token lifetime |
| `ENFORCE_SUBNET` | `false` | Restrict to office LAN only |

---

## Android Signing (for new builds)

The release keystore is kept outside the repo. To regenerate one:

```bash
keytool -genkeypair -v \
  -keystore android/app/cyberzeus-release.jks \
  -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 \
  -alias cyberzeus \
  -storepass "YOUR_PASS" -keypass "YOUR_PASS" \
  -dname "CN=CyberZeus AMS, O=CyberZeus, C=PK"
```

Then create `frontend/android/key.properties`:
```
storePassword=YOUR_PASS
keyPassword=YOUR_PASS
keyAlias=cyberzeus
storeFile=../app/cyberzeus-release.jks
```

> If you regenerate the keystore, Android will treat it as a different app and
> existing installs must be uninstalled before installing the new APK.

---

## License

Private / proprietary — internal use only.
© 2026 CyberZeus Software Systems. All rights reserved.
