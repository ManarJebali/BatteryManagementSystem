# 🔋 Battery Monitoring System (BMS)

A full-stack Battery Management System combining an **ESP32 firmware** with a **cross-platform Flutter mobile app**. The system monitors a 4-cell lithium battery pack in real time over Bluetooth Low Energy (BLE), tracking voltage, temperature, current, and State of Charge (SoC).

---

## 📌 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Hardware Requirements](#hardware-requirements)
- [Features](#features)
- [Project Structure](#project-structure)
- [Firmware (ESP32)](#firmware-esp32)
- [Mobile App (Flutter)](#mobile-app-flutter)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [Dependencies](#dependencies)
- [License](#license)

---

## Overview

This project implements a Battery Management System designed for a **4S LiFePO4 / Li-ion battery pack** (nominal ~12.8 V, 30 Ah). The ESP32 microcontroller continuously reads sensor data and streams it wirelessly to a Flutter mobile application via BLE, where it is displayed on an intuitive dashboard with gauges and indicators.

---

## Architecture

```
┌─────────────────────────────┐         BLE          ┌──────────────────────────┐
│         ESP32 Firmware      │  ◄──────────────────► │    Flutter Mobile App    │
│                             │                        │                          │
│  • ADC voltage sensing      │   JSON payloads        │  • Real-time dashboard   │
│  • Temperature (NTC)        │                        │  • Gauges & indicators   │
│  • Current (ACS758)         │                        │  • BLE device scanner    │
│  • SoC calculation          │                        │  • History charts        │
│  • PWM charge/discharge     │                        │  • Alerts & warnings     │
│  • SPIFFS history storage   │                        │                          │
└─────────────────────────────┘                        └──────────────────────────┘
```

---

## Hardware Requirements

| Component | Description |
|---|---|
| **ESP32** | Main microcontroller (DevKit or equivalent) |
| **4S Battery Pack** | LiFePO4 or Li-ion cells (up to 16.8 V) |
| **ACS758 Current Sensor** | Hall-effect sensor for current measurement |
| **NTC Thermistor** | Temperature sensing (analog, pin 39) |
| **Voltage Dividers** | For each cell tap (pins 32, 33, 34, 35) and pack (pin 36) |
| **MOSFETs / Gate Drivers** | For PWM charge/discharge control (pins 18, 19) |

---

## Features

### Firmware (ESP32)
- **Real-time multi-cell voltage measurement** — reads 4 individual cell voltages plus overall pack voltage
- **Temperature monitoring** — NTC thermistor with linear calibration (`-35.69 × V + 85.54`)
- **Current sensing** — ACS758 Hall-effect sensor with offset and sensitivity calibration
- **State of Charge (SoC) estimation** — hybrid coulomb counting + OCV lookup table (50-point SoC↔voltage map), with resting-state correction
- **PWM charge/discharge control** — progressive fade-in/fade-out on separate charge and discharge channels (20 kHz, 8-bit resolution)
- **Safety cutoffs** — configurable voltage, current, and temperature thresholds
- **Measurement history** — circular buffer of 24 hourly records persisted to SPIFFS (`/history.json`)
- **BLE communication** — broadcasts JSON-formatted sensor data every 10 seconds; supports read, write, and notify on a single characteristic

### Flutter Mobile App
- **BLE device scanner and connector** — discovers and pairs with the ESP32 BMS
- **Live dashboard** — displays cell voltages, pack voltage, temperature, current, and SoC
- **Visual gauges** — Syncfusion Flutter Gauges for SoC and key metrics
- **Percentage indicators** — `percent_indicator` widgets for battery level
- **State management** — Provider pattern for reactive UI updates
- **Cross-platform** — supports Android, iOS, Linux, macOS, Windows, and Web

---

## Project Structure

```
BatteryMonitoringSystem/
├── bms.ino                  # ESP32 Arduino firmware
├── pubspec.yaml             # Flutter dependencies and project config
├── lib/                     # Flutter Dart source code
│   └── ...
├── android/                 # Android platform files
├── ios/                     # iOS platform files
├── linux/                   # Linux desktop platform files
├── macos/                   # macOS platform files
├── windows/                 # Windows platform files
├── web/                     # Web platform files
├── assets/
│   └── images/              # App image assets
├── test/                    # Flutter unit/widget tests
├── analysis_options.yaml    # Dart linting rules
└── pubspec.lock             # Locked dependency versions
```

---

## Firmware (ESP32)

### Pin Mapping

| Pin | Function |
|-----|----------|
| `32` | Cell 1 voltage (ADC) |
| `33` | Cell 2 voltage (ADC) |
| `34` | Cell 3 voltage (ADC) |
| `35` | Cell 4 voltage (ADC) |
| `36` | Pack voltage (ADC) |
| `39` | Temperature (NTC, ADC) |
| `27` | Current sensor (ACS758, ADC) |
| `18` | PWM Charge output |
| `19` | PWM Discharge output |

### BLE Service

| Field | Value |
|-------|-------|
| Service UUID | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| Characteristic UUID | `beb5483e-36e1-4688-b7f5-ea07361b26a8` |
| Properties | Read, Write, Notify |
| Device name | `ESP32_BMS` |

### Data Payload (JSON)

```json
{
  "device": "ESP32_DEV_001",
  "C1": 3.32,
  "C2": 3.31,
  "C3": 3.30,
  "C4": 3.33,
  "PACK": 13.26,
  "TEMP": 28.5,
  "COURANT": 4.2,
  "SOC": 78.3
}
```

### Safety Thresholds (Defaults)

| Parameter | Limit |
|-----------|-------|
| Max cell voltage | 4.2 V |
| Max pack voltage | 16.8 V |
| Charge cutoff voltage | 14.6 V |
| Discharge cutoff voltage | 12.0 V |
| Max charge current | 12.0 A |
| Max discharge current | 20.0 A |
| Temperature range (PWM active) | 0 °C – 45 °C |

### Flashing the Firmware

1. Install the [Arduino IDE](https://www.arduino.cc/en/software) or [PlatformIO](https://platformio.org/).
2. Install the required libraries:
   - `BLEDevice` (ESP32 BLE Arduino)
   - `ArduinoJson`
   - `SPIFFS` (bundled with ESP32 core)
3. Select board: **ESP32 Dev Module**
4. Open `bms.ino` and flash to the device.

---

## Mobile App (Flutter)

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) ≥ 3.8.1
- Dart SDK ^3.8.1
- A physical device or emulator with BLE support (required for BLE functionality)

### Installation

```bash
# Clone the repository
git clone https://github.com/ManarJebali/BatteryMonitoringSystem.git
cd BatteryMonitoringSystem

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Android Permissions

The app requires the following permissions on Android (already handled via `permission_handler`):
- `BLUETOOTH`
- `BLUETOOTH_ADMIN`
- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `ACCESS_FINE_LOCATION`

### Building for Release

```bash
# Android APK
flutter build apk --release

# iOS (requires macOS + Xcode)
flutter build ios --release
```

---

## Configuration

Key firmware parameters can be adjusted at the top of `bms.ino`:

```cpp
// Battery capacity
const float batteryCapacityAh = 30.0;
const float batteryVoltageNominal = 12.8;

// Safety limits
float voltageChargeCutoff    = 14.6;
float voltageDischargeCutoff = 12.0;
float currentChargeLimit     = 12.0;
float currentDischargeLimit  = 20.0;

// Measurement interval
const long interval = 10000; // ms

// History depth
#define MAX_RECORDS 24        // hourly records stored in SPIFFS
```

---

## Dependencies

### Firmware Libraries

| Library | Purpose |
|---------|---------|
| `BLEDevice` | Bluetooth Low Energy server |
| `ArduinoJson` | JSON serialization/deserialization |
| `SPIFFS` | Flash file system for history persistence |
| `esp32-hal-ledc` | PWM output control |

### Flutter Packages

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_blue_plus` | ^1.35.3 | BLE scanning and communication |
| `syncfusion_flutter_gauges` | ^24.1.41 | Radial gauges and indicators |
| `percent_indicator` | ^4.2.5 | Battery percentage display |
| `provider` | ^6.1.2 | State management |
| `mqtt_client` | ^9.6.1 | MQTT support (optional/future use) |

---

## License

This project was developed as an end-of-studies project (PFE). All rights reserved by the author.

---

*Built with ❤️ using Flutter & ESP32*
