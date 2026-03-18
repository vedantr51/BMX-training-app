# BMX Training App (Monorepo)

This repository contains two related Flutter applications for BMX training:

- `bmxmobile/` — The **BMX rider** mobile app (Android/iOS)
- `coach/coach_app/` — The **Coach** app that supports live tracking / analysis

---

## 📁 Repository Structure

```
/ (repo root)
  ├─ bmxmobile/          # BMX rider app (Flutter)
  ├─ coach/              # Coach app (Flutter workspace)
  │   └─ coach_app/      # Actual Flutter project for the coach app
  └─ README.md           # This file
```

---

## 🔧 Prerequisites

Make sure you have the following installed and configured on your machine:

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- Android SDK (via Android Studio)
- Xcode (macOS only)
- A device or emulator/simulator for Android/iOS

To verify your environment:

```bash
flutter doctor
```

---

## 🚀 Running the Apps

### Rider App (`bmxmobile`)

```bash
cd "bmxmobile"
flutter pub get
flutter run
```

### Coach App (`coach/coach_app`)

```bash
cd "coach/coach_app"
flutter pub get
flutter run
```

> Tip: Use `-d <device-id>` to target specific devices/emulators.

---

## 📦 Building APKs (Optional)

You can build release APKs for installation/testing.

### Rider App APK (bmxmobile)

```bash
cd "bmxmobile"
flutter pub get
flutter build apk --release
```

APK output location:

- `bmxmobile/build/app/outputs/flutter-apk/app-release.apk`

### Coach App APK (coach/coach_app)

```bash
cd "coach/coach_app"
flutter pub get
flutter build apk --release
```

APK output location:

- `coach/coach_app/build/app/outputs/flutter-apk/app-release.apk`

---

## 🧩 Notes

- Each app is a standalone Flutter project. Build/configuration is managed independently.
- Keep each project’s `pubspec.lock` and generated build artifacts inside its own folder.

---

## 🔍 Troubleshooting

If you run into issues, a good first step is:

```bash
flutter clean
flutter pub get
```

Then re-run the desired app.

---

