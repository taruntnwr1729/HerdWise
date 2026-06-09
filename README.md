# 🐄 HerdWise

**AI-Powered Livestock Health Platform**

HerdWise is a cross-platform Flutter vibe coded application designed to help farmers, veterinarians, and livestock managers monitor and manage animal health intelligently — combining AI diagnostics, IoT sensor integration, geolocation, and offline-friendly design in one unified platform.

---
## UI

<img width="220" alt="app1" src="https://github.com/user-attachments/assets/2929f617-fdeb-4a36-9f99-a6f37757e453" />
<img width="220" alt="app2" src="https://github.com/user-attachments/assets/6a6de357-e6a3-46f4-9e53-15ee293f8ba5" />
<img width="220" alt="app3" src="https://github.com/user-attachments/assets/7f435983-30b9-4fd0-9438-2110e4e2bfa2" />
<img width="220" alt="app4" src="https://github.com/user-attachments/assets/7a744d24-5034-4dbd-9fef-36dadb018031" />

---


## ✨ Features

- **AI Health Diagnostics** — Powered by Google Gemini AI (`google_generative_ai`) to analyze symptoms and provide intelligent health insights for your herd.
- **IoT Sensor Integration** — Connects to Bluetooth-enabled wearables and sensors (`flutter_blue_plus`) for real-time vitals monitoring.
- **Health Analytics & Charts** — Visualize health trends, weight changes, and activity data with interactive charts (`fl_chart`).
- **Geolocation Tracking** — Track livestock locations and movement patterns using GPS (`geolocator`).
- **Secure Access** — Biometric and local authentication (`local_auth`) to protect sensitive farm data.
- **Smart Notifications** — Get timely alerts for health anomalies, feeding schedules, and vet reminders (`flutter_local_notifications`).
- **Offline Support** — Local data persistence using `shared_preferences` so the app works even without internet.
- **Cross-Platform** — Runs on Android, iOS, Web, Windows, macOS, and Linux.

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart ≥ 3.2.0) |
| AI / LLM | Google Generative AI (Gemini) |
| Bluetooth / IoT | flutter_blue_plus |
| Charts | fl_chart |
| Location | geolocator |
| Auth | local_auth |
| Notifications | flutter_local_notifications |
| Storage | shared_preferences |
| Internationalisation | intl |
| Permissions | permission_handler |
| Unique IDs | uuid |

---

## 📁 Project Structure

```
HerdWise/
├── lib/                  # Dart source code
├── android/              # Android platform files
├── ios/                  # iOS platform files
├── web/                  # Web platform files
├── windows/              # Windows platform files
├── macos/                # macOS platform files
├── linux/                # Linux platform files
├── test/                 # Unit & widget tests
├── pubspec.yaml          # Dependencies & project config
└── analysis_options.yaml # Lint rules
```

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.2.0
- Dart SDK ≥ 3.2.0
- A Google Gemini API key ([Get one here](https://aistudio.google.com/app/apikey))

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/taruntnwr1729/HerdWise.git
cd HerdWise

# 2. Install dependencies
flutter pub get

# 3. Configure your Gemini API key
#    Add your key to the appropriate config/env file before running

# 4. Run the app
flutter run
```

### Running on a specific platform

```bash
flutter run -d android      # Android device/emulator
flutter run -d ios          # iOS simulator/device
flutter run -d chrome       # Web (browser)
flutter run -d windows      # Windows desktop
```

---

## 🔑 Configuration

Before running the app, ensure the following are set up:

- **Gemini API Key** — Required for AI health diagnostics. Set the key in your environment or a config file (refer to `lib/` source).
- **Bluetooth Permissions** — On Android and iOS, location and Bluetooth permissions must be granted at runtime for sensor connectivity.
- **Location Permissions** — Required for geolocation features. The app uses `permission_handler` to request these at runtime.

---

## 🧪 Running Tests

```bash
flutter test
```

---

## 📱 Platform Support

| Platform | Status |
|---|---|
| Android | ✅ Supported |
| iOS | ✅ Supported |
| Web | ✅ Supported |
| Windows | ✅ Supported |
| macOS | ✅ Supported |
| Linux | ✅ Supported |

---

## 🤝 Contributing

Contributions are welcome! To get started:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m "Add your feature"`
4. Push to the branch: `git push origin feature/your-feature`
5. Open a Pull Request

---

## 📄 License

This project is currently unlicensed. Please contact the author before using it in production.

---

## 👤 Author

**Tarun** — [@taruntnwr1729](https://github.com/taruntnwr1729)

---

> *HerdWise — Smart health management for every animal in your herd.*
