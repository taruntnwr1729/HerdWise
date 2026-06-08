// ═══════════════════════════════════════════════════════════════════════════
//  HERDWISE PRO — AI-Powered Livestock Health Platform
//  Version 2.0  |  Flutter + Google Gemini AI + BLE Hardware Support
// ═══════════════════════════════════════════════════════════════════════════
//
//  DEPENDENCIES (pubspec.yaml):
//  ─────────────────────────────
//  dependencies:
//    flutter:
//      sdk: flutter
//    fl_chart: ^0.68.0
//    geolocator: ^11.0.0
//    google_generative_ai: ^0.4.3        ← Google AI Studio (Gemini)
//    flutter_blue_plus: ^1.31.9          ← BLE Hardware collar support
//    shared_preferences: ^2.2.3          ← Persist login session
//    local_auth: ^2.1.8                  ← Biometric login (fingerprint/face)
//    intl: ^0.19.0                       ← Date formatting
//    lottie: ^3.1.0                      ← Animations (optional)
//    permission_handler: ^11.3.0         ← Runtime permissions
//    flutter_local_notifications: ^17.0.0 ← Push-style local alerts
//    uuid: ^4.4.0                        ← Unique IDs for animals/collars
//
//  SETUP:
//  ──────
//  1. Get your FREE Google AI Studio API key at https://aistudio.google.com
//  2. Replace "YOUR_GEMINI_API_KEY" below with your key
//  3. For hardware: Each BLE collar should advertise service UUID: "0x180D"
//     and expose characteristics for Temp (0x2A1C), HR (0x2A37), SpO2 (0x2A5F)
//     following standard Bluetooth GATT Health Thermometer / Heart Rate profiles
//  4. Run: flutter pub get && flutter run
//
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';

// ─────────────────────────────────────────
//  CONFIGURATION  ← EDIT THESE
// ─────────────────────────────────────────

const String kGeminiApiKey =
    "AIzaSyB58lTSCMwYB2YZ596E-sEnNyK-3uX5Y7Y"; // ← Replace with your key

// BLE Collar GATT UUIDs (standard Bluetooth Health profiles)
const String kCollarServiceUUID = "0000180d-0000-1000-8000-00805f9b34fb";
const String kTemperatureCharUUID = "00002a1c-0000-1000-8000-00805f9b34fb";
const String kHeartRateCharUUID = "00002a37-0000-1000-8000-00805f9b34fb";
const String kOxygenCharUUID = "00002a5f-0000-1000-8000-00805f9b34fb";
const String kActivityCharUUID = "00002a53-0000-1000-8000-00805f9b34fb";
const String kGpsCharUUID = "00002ab3-0000-1000-8000-00805f9b34fb";

// ─────────────────────────────────────────
//  ANIMAL TYPES & SPECIES DATA
// ─────────────────────────────────────────

const List<Map<String, dynamic>> kAnimalTypes = [
  {
    "type": "Cow",
    "icon": "🐄",
    "normalTempMin": 38.0,
    "normalTempMax": 39.5,
    "normalHRMin": 48,
    "normalHRMax": 84,
    "normalO2Min": 95,
    "gestationDays": 283,
  },
  {
    "type": "Horse",
    "icon": "🐴",
    "normalTempMin": 37.2,
    "normalTempMax": 38.3,
    "normalHRMin": 28,
    "normalHRMax": 44,
    "normalO2Min": 94,
    "gestationDays": 340,
  },
  {
    "type": "Sheep",
    "icon": "🐑",
    "normalTempMin": 38.5,
    "normalTempMax": 39.5,
    "normalHRMin": 60,
    "normalHRMax": 120,
    "normalO2Min": 95,
    "gestationDays": 147,
  },
  {
    "type": "Goat",
    "icon": "🐐",
    "normalTempMin": 38.5,
    "normalTempMax": 39.5,
    "normalHRMin": 70,
    "normalHRMax": 135,
    "normalO2Min": 95,
    "gestationDays": 150,
  },
  {
    "type": "Pig",
    "icon": "🐷",
    "normalTempMin": 38.0,
    "normalTempMax": 39.0,
    "normalHRMin": 58,
    "normalHRMax": 100,
    "normalO2Min": 96,
    "gestationDays": 114,
  },
  {
    "type": "Chicken",
    "icon": "🐔",
    "normalTempMin": 40.6,
    "normalTempMax": 41.7,
    "normalHRMin": 200,
    "normalHRMax": 400,
    "normalO2Min": 93,
    "gestationDays": 21,
  },
  {
    "type": "Dog",
    "icon": "🐕",
    "normalTempMin": 38.3,
    "normalTempMax": 39.2,
    "normalHRMin": 60,
    "normalHRMax": 140,
    "normalO2Min": 96,
    "gestationDays": 63,
  },
  {
    "type": "Cat",
    "icon": "🐱",
    "normalTempMin": 38.1,
    "normalTempMax": 39.2,
    "normalHRMin": 120,
    "normalHRMax": 140,
    "normalO2Min": 95,
    "gestationDays": 65,
  },
];

// ─────────────────────────────────────────
//  DATA MODELS
// ─────────────────────────────────────────

class UserProfile {
  final String name;
  final String email;
  final String farmName;
  final String role; // Owner / Vet / Worker
  UserProfile({
    required this.name,
    required this.email,
    required this.farmName,
    required this.role,
  });
}

class Animal {
  String id;
  String name;
  String animalType;
  String? tagNumber; // RFID / ear tag
  String? collarDeviceId; // BLE device ID
  bool isConnectedToHardware;
  double temp;
  int heartRate;
  int activity;
  double oxygenLevel;
  double lat, lng;
  String mood;
  bool isHungry;
  bool hasSkinIssue;
  bool inBreedingMode;
  String sleepState;
  double weight; // kg
  int ageMonths;
  String? lastVetNote;
  DateTime? lastVetVisit;
  List<double> tempHistory;
  List<int> hrHistory;
  List<double> o2History;
  List<int> activityHistory;
  List<AlertLog> alertLogs;
  List<VetRecord> vetRecords;
  DateTime lastUpdated;

  Animal({
    required this.id,
    required this.name,
    required this.animalType,
    this.tagNumber,
    this.collarDeviceId,
    this.isConnectedToHardware = false,
    required this.temp,
    required this.heartRate,
    required this.activity,
    required this.oxygenLevel,
    required this.lat,
    required this.lng,
    required this.mood,
    required this.isHungry,
    required this.hasSkinIssue,
    required this.inBreedingMode,
    required this.sleepState,
    required this.weight,
    required this.ageMonths,
    this.lastVetNote,
    this.lastVetVisit,
    required this.tempHistory,
    required this.hrHistory,
    required this.o2History,
    required this.activityHistory,
    required this.alertLogs,
    required this.vetRecords,
    required this.lastUpdated,
  });

  Map<String, dynamic> get typeInfo => kAnimalTypes.firstWhere(
        (t) => t["type"] == animalType,
        orElse: () => kAnimalTypes[0],
      );

  String get icon => typeInfo["icon"] as String;

  int get healthScore {
    int score = 100;
    final t = typeInfo;
    if (temp > (t["normalTempMax"] as double) + 1.0)
      score -= 30;
    else if (temp > (t["normalTempMax"] as double))
      score -= 15;
    else if (temp < (t["normalTempMin"] as double) - 0.5) score -= 20;
    if (heartRate > (t["normalHRMax"] as int) + 10)
      score -= 20;
    else if (heartRate > (t["normalHRMax"] as int))
      score -= 10;
    else if (heartRate < (t["normalHRMin"] as int) - 5) score -= 15;
    if (oxygenLevel < (t["normalO2Min"] as int) - 3)
      score -= 25;
    else if (oxygenLevel < (t["normalO2Min"] as int)) score -= 10;
    if (activity < 20) score -= 15;
    if (isHungry) score -= 10;
    if (hasSkinIssue) score -= 10;
    return score.clamp(0, 100);
  }

  Color get healthColor {
    final s = healthScore;
    if (s >= 75) return const Color(0xFF4CAF50);
    if (s >= 50) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  String get healthLabel {
    final s = healthScore;
    if (s >= 75) return "Healthy";
    if (s >= 50) return "Fair";
    return "Critical";
  }

  /// Build a structured summary for Gemini AI
  String toAiSummary() => """
Animal: $name (${typeInfo['icon']} $animalType)
Tag: ${tagNumber ?? 'N/A'} | Age: ${ageMonths}mo | Weight: ${weight}kg
Vitals:
  - Temperature: ${temp.toStringAsFixed(1)}°C (Normal: ${typeInfo['normalTempMin']}–${typeInfo['normalTempMax']}°C)
  - Heart Rate: $heartRate bpm (Normal: ${typeInfo['normalHRMin']}–${typeInfo['normalHRMax']} bpm)
  - SpO₂: ${oxygenLevel.toStringAsFixed(1)}% (Normal: ≥${typeInfo['normalO2Min']}%)
  - Activity Level: $activity/100
Status Flags:
  - Mood: $mood | Sleep: $sleepState
  - Hungry: $isHungry | Skin Issue: $hasSkinIssue | Breeding Mode: $inBreedingMode
Health Score: $healthScore/100 ($healthLabel)
Recent Temp Trend: ${tempHistory.takeLast(5).map((t) => t.toStringAsFixed(1)).join(' → ')}°C
Last Vet Note: ${lastVetNote ?? 'None'}
""";
}

class AlertLog {
  final DateTime time;
  final String message;
  final String severity;
  AlertLog({required this.time, required this.message, required this.severity});
}

class VetRecord {
  final DateTime date;
  final String diagnosis;
  final String treatment;
  final String vetName;
  VetRecord({
    required this.date,
    required this.diagnosis,
    required this.treatment,
    required this.vetName,
  });
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  final bool isLoading;
  ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
    this.isLoading = false,
  });
}

// ─────────────────────────────────────────
//  SERVICES
// ─────────────────────────────────────────

class GeminiVetService {
  late final GenerativeModel _model;
  late final ChatSession _chat;

  GeminiVetService() {
    _model = GenerativeModel(
      model: 'gemini-3-flash-preview', // Updated to Gemini 3
      apiKey: kGeminiApiKey,
      systemInstruction: Content.system("""
You are **Dr. HerdWise**, an expert AI veterinary assistant integrated into the HerdWise Pro livestock monitoring platform.

Your role:
- Analyze real-time sensor data from smart IoT collars worn by farm animals
- Provide clear, actionable veterinary advice based on the animal's vitals, history, and flags
- Detect patterns that may indicate illness, stress, nutritional deficiency, or reproductive cycles
- Communicate in a warm, professional tone suitable for farmers, farm workers, and veterinarians
- Always mention when a real vet should be consulted for serious issues
- Consider species-specific normal ranges when interpreting vitals
- Suggest possible diagnoses ranked by likelihood
- Recommend concrete next steps (diet changes, medication, isolation, vet visit)
- Proactively identify if temperature trends suggest fever onset, if low SpO₂ suggests respiratory issues, etc.

Format responses with:
- 🔍 **Assessment**: Brief summary of what you see
- ⚠️ **Concerns**: Any red flags (if none, say so)
- ✅ **Recommendations**: Numbered action steps
- 💊 **Treatment Suggestions**: General guidance (always recommend confirming with a vet for medications)
- 🗓️ **Follow-up**: When to recheck

Always be concise. Use emojis for readability. Never give generic advice — always respond to the specific data provided.
"""),
    );
    _chat = _model.startChat();
  }

  Future<String> askAboutAnimal(Animal animal, String question) async {
    final prompt = """
${animal.toAiSummary()}

Farmer's question: $question

Please analyze this animal's current data and answer the question as Dr. HerdWise.
""";
    final response = await _chat.sendMessage(Content.text(prompt));
    return response.text ??
        "I could not generate a response. Please try again.";
  }

  Future<String> getProactiveInsight(Animal animal) async {
    final prompt = """
${animal.toAiSummary()}

Please proactively analyze this animal's vitals and provide a brief health insight. 
Focus on the most important observation. Keep it under 150 words.
""";
    final response = await _chat.sendMessage(Content.text(prompt));
    return response.text ?? "Unable to generate insight.";
  }

  Future<String> getHerdSummary(List<Animal> animals) async {
    final summaries = animals
        .map(
          (a) =>
              "${a.icon} ${a.name} (${a.animalType}): Score ${a.healthScore}% | Temp ${a.temp.toStringAsFixed(1)}°C | HR ${a.heartRate}bpm | SpO₂ ${a.oxygenLevel.toStringAsFixed(1)}%",
        )
        .join('\n');

    final prompt = """
Herd Summary (${animals.length} animals):
$summaries

Please provide a brief farm-level health summary. Highlight the most critical animals, 
overall herd trends, and 3 priority action items for the farmer today.
""";
    final response = await _chat.sendMessage(Content.text(prompt));
    return response.text ?? "Unable to generate herd summary.";
  }
}

// ─────────────────────────────────────────
//  HARDWARE BLE SERVICE
// ─────────────────────────────────────────

/// Manages BLE connections to physical smart collars.
/// Each collar is a BLE peripheral advertising GATT health profiles.
class CollarBleService {
  final Map<String, BluetoothDevice> _connectedDevices = {};
  final StreamController<Map<String, dynamic>> _dataStream =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get dataStream => _dataStream.stream;

  /// Start scanning for nearby collars
  Future<void> startScan() async {
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      withServices: [Guid(kCollarServiceUUID)],
    );
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  /// Connect to a specific collar and subscribe to its characteristics
  Future<void> connectCollar(BluetoothDevice device, String animalId) async {
    await device.connect(autoConnect: false);
    _connectedDevices[animalId] = device;

    final services = await device.discoverServices();
    for (final service in services) {
      if (service.serviceUuid == Guid(kCollarServiceUUID)) {
        for (final char in service.characteristics) {
          final uuid = char.characteristicUuid.toString();
          if ([
            kTemperatureCharUUID,
            kHeartRateCharUUID,
            kOxygenCharUUID,
            kActivityCharUUID,
            kGpsCharUUID,
          ].contains(uuid)) {
            await char.setNotifyValue(true);
            char.lastValueStream.listen((value) {
              _dataStream.add({
                "animalId": animalId,
                "charUuid": uuid,
                "value": value,
              });
            });
          }
        }
      }
    }
  }

  /// Parse raw BLE bytes into readable values per GATT standard
  static double parseTemperature(List<int> bytes) {
    // IEEE-11073 32-bit float, GATT Health Thermometer profile
    if (bytes.length < 5) return 0.0;
    final exponent = bytes[4].toSigned(8);
    final mantissa = (bytes[3] << 16) | (bytes[2] << 8) | bytes[1];
    return (mantissa * pow(10.0, exponent)).toDouble();
  }

  static int parseHeartRate(List<int> bytes) {
    if (bytes.isEmpty) return 0;
    final flag = bytes[0];
    return (flag & 0x01) == 0 ? bytes[1] : (bytes[2] << 8) + bytes[1];
  }

  static double parseSpO2(List<int> bytes) {
    if (bytes.length < 2) return 0.0;
    return (bytes[1] * 0.5) + (bytes[0] & 0x01 != 0 ? 0.5 : 0.0);
  }

  static int parseActivity(List<int> bytes) {
    if (bytes.length < 2) return 0;
    return ((bytes[1] << 8) | bytes[0]).clamp(0, 100);
  }

  static Map<String, double> parseGps(List<int> bytes) {
    if (bytes.length < 8) return {"lat": 0, "lng": 0};
    final lat = ByteData.sublistView(
      Uint8List.fromList(bytes.sublist(0, 4)),
    ).getFloat32(0, Endian.little);
    final lng = ByteData.sublistView(
      Uint8List.fromList(bytes.sublist(4, 8)),
    ).getFloat32(0, Endian.little);
    return {"lat": lat.toDouble(), "lng": lng.toDouble()};
  }

  Future<void> disconnectAll() async {
    for (final device in _connectedDevices.values) {
      await device.disconnect();
    }
    _connectedDevices.clear();
  }

  bool isConnected(String animalId) => _connectedDevices.containsKey(animalId);
}

// ─────────────────────────────────────────
//  NOTIFICATIONS SERVICE
// ─────────────────────────────────────────

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  static Future<void> showAlert({
    required String title,
    required String body,
    required String severity,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'herdwise_alerts',
      'HerdWise Alerts',
      channelDescription: 'Animal health alerts',
      importance: severity == "critical" ? Importance.max : Importance.high,
      priority: severity == "critical" ? Priority.max : Priority.high,
      color: severity == "critical" ? Colors.red : Colors.orange,
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  AUTH SERVICE
// ─────────────────────────────────────────

class AuthService {
  static const _keyLoggedIn = 'is_logged_in';
  static const _keyUserName = 'user_name';
  static const _keyFarmName = 'farm_name';
  static const _keyUserRole = 'user_role';
  static const _keyEmail = 'user_email';

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyLoggedIn) ?? false;
  }

  static Future<void> login({
    required String name,
    required String email,
    required String farmName,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLoggedIn, true);
    await prefs.setString(_keyUserName, name);
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyFarmName, farmName);
    await prefs.setString(_keyUserRole, role);
  }

  static Future<UserProfile?> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_keyLoggedIn) ?? false)) return null;
    return UserProfile(
      name: prefs.getString(_keyUserName) ?? '',
      email: prefs.getString(_keyEmail) ?? '',
      farmName: prefs.getString(_keyFarmName) ?? '',
      role: prefs.getString(_keyUserRole) ?? 'Owner',
    );
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static Future<bool> authenticateBiometric() async {
    final auth = LocalAuthentication();
    final canCheck = await auth.canCheckBiometrics;
    if (!canCheck) return true; // fallback allow if no biometrics
    return await auth.authenticate(
      localizedReason: 'Verify your identity to access HerdWise',
      options: const AuthenticationOptions(biometricOnly: false),
    );
  }
}

// ─────────────────────────────────────────
//  SAMPLE DATA FACTORY
// ─────────────────────────────────────────

Animal makeAnimal({
  required String name,
  required String type,
  required double temp,
  required int hr,
  required int activity,
  required double o2,
  required double lat,
  required double lng,
  String mood = "Calm",
  bool hungry = false,
  bool skinIssue = false,
  bool breeding = false,
  String sleep = "Active",
  double weight = 450,
  int ageMonths = 24,
  String? tagNumber,
  String? lastVetNote,
}) {
  return Animal(
    id: const Uuid().v4(),
    name: name,
    animalType: type,
    tagNumber: tagNumber ?? "TAG-${name.hashCode.abs() % 9999}",
    collarDeviceId: null,
    isConnectedToHardware: false,
    temp: temp,
    heartRate: hr,
    activity: activity,
    oxygenLevel: o2,
    lat: lat,
    lng: lng,
    mood: mood,
    isHungry: hungry,
    hasSkinIssue: skinIssue,
    inBreedingMode: breeding,
    sleepState: sleep,
    weight: weight,
    ageMonths: ageMonths,
    lastVetNote: lastVetNote,
    lastVetVisit: lastVetNote != null
        ? DateTime.now().subtract(const Duration(days: 7))
        : null,
    tempHistory: [temp - 0.3, temp - 0.1, temp],
    hrHistory: [hr - 2, hr - 1, hr],
    o2History: [o2 - 0.5, o2 - 0.2, o2],
    activityHistory: [activity - 5, activity - 2, activity],
    alertLogs: [],
    vetRecords: lastVetNote != null
        ? [
            VetRecord(
              date: DateTime.now().subtract(const Duration(days: 7)),
              diagnosis: "Routine checkup",
              treatment: "Vitamins administered",
              vetName: "Dr. Sharma",
            ),
          ]
        : [],
    lastUpdated: DateTime.now(),
  );
}

List<Animal> buildInitialAnimals() => [
      makeAnimal(
        name: "Bessie",
        type: "Cow",
        temp: 38.5,
        hr: 72,
        activity: 80,
        o2: 97.2,
        lat: 37.7749,
        lng: -122.4194,
        tagNumber: "TAG-1001",
        weight: 520,
        ageMonths: 36,
        lastVetNote: "Healthy. Continue current feed routine.",
      ),
      makeAnimal(
        name: "Daisy",
        type: "Cow",
        temp: 40.2,
        hr: 95,
        activity: 40,
        o2: 93.5,
        lat: 37.7758,
        lng: -122.4190,
        tagNumber: "TAG-1002",
        weight: 480,
        ageMonths: 28,
        mood: "Stressed",
        hungry: true,
        skinIssue: true,
      ),
      makeAnimal(
        name: "Thunder",
        type: "Horse",
        temp: 37.8,
        hr: 38,
        activity: 65,
        o2: 96.0,
        lat: 37.7742,
        lng: -122.4200,
        tagNumber: "TAG-2001",
        weight: 550,
        ageMonths: 60,
        breeding: true,
      ),
      makeAnimal(
        name: "Woolly",
        type: "Sheep",
        temp: 39.1,
        hr: 88,
        activity: 55,
        o2: 96.5,
        lat: 37.7755,
        lng: -122.4185,
        tagNumber: "TAG-3001",
        weight: 75,
        ageMonths: 18,
      ),
    ];

// ─────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const HerdWiseApp());
}

class HerdWiseApp extends StatelessWidget {
  const HerdWiseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HerdWise Pro',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF080F09),
        cardColor: const Color(0xFF111D12),
        fontFamily: 'SF Pro Display', // Falls back to system font
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF080F09),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF111D12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.green.shade900),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.green.shade900),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4CAF50)),
          ),
          labelStyle: const TextStyle(color: Colors.grey),
          hintStyle: TextStyle(color: Colors.grey.shade600),
        ),
      ),
      home: const SplashGate(),
    );
  }
}

// ─────────────────────────────────────────
//  SPLASH → AUTH GATE
// ─────────────────────────────────────────

class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _ac.forward();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    final loggedIn = await AuthService.isLoggedIn();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => loggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080F09),
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    colors: [Color(0xFF4CAF50), Color(0xFF1B5E20)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4CAF50).withOpacity(0.4),
                      blurRadius: 40,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text("🐄", style: TextStyle(fontSize: 48)),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "HerdWise Pro",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "AI-Powered Livestock Health",
                style: TextStyle(
                  color: Colors.green.shade400,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 60),
              SizedBox(
                width: 40,
                child: LinearProgressIndicator(
                  color: const Color(0xFF4CAF50),
                  backgroundColor: Colors.green.shade900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  LOGIN SCREEN
// ─────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _farmCtrl = TextEditingController();
  String _role = "Owner";
  bool _loading = false;
  bool _isSignUp = false;
  String? _error;

  // In production: connect to Firebase / your backend
  // For demo: simple local auth
  static const _demoEmail = "farmer@herdwise.com";
  static const _demoPassword = "herdwise123";
  final _passCtrl = TextEditingController();

  Future<void> _handleLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await Future.delayed(const Duration(milliseconds: 800)); // simulate network

    if (_isSignUp) {
      if (_nameCtrl.text.isEmpty ||
          _farmCtrl.text.isEmpty ||
          _emailCtrl.text.isEmpty) {
        setState(() {
          _error = "Please fill in all fields.";
          _loading = false;
        });
        return;
      }
      await AuthService.login(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        farmName: _farmCtrl.text.trim(),
        role: _role,
      );
    } else {
      // Demo login check
      if (_emailCtrl.text.trim() != _demoEmail ||
          _passCtrl.text != _demoPassword) {
        setState(() {
          _error = "Invalid credentials.\nDemo: $_demoEmail / $_demoPassword";
          _loading = false;
        });
        return;
      }
      await AuthService.login(
        name: "Demo Farmer",
        email: _demoEmail,
        farmName: "Green Acres Farm",
        role: "Owner",
      );
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  Future<void> _biometricLogin() async {
    final ok = await AuthService.authenticateBiometric();
    if (ok) {
      await AuthService.login(
        name: "Demo Farmer",
        email: _demoEmail,
        farmName: "Green Acres Farm",
        role: "Owner",
      );
      if (mounted)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF66BB6A), Color(0xFF1B5E20)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4CAF50).withOpacity(0.3),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text("🐄", style: TextStyle(fontSize: 34)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "HerdWise Pro",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isSignUp
                          ? "Create your farm account"
                          : "Sign in to your farm",
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade800),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (_error != null) const SizedBox(height: 16),

              if (_isSignUp) ...[
                _Label("Full Name"),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Dr. Rajan Mehta",
                  ),
                ),
                const SizedBox(height: 14),
                _Label("Farm Name"),
                const SizedBox(height: 6),
                TextField(
                  controller: _farmCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Green Acres Farm",
                  ),
                ),
                const SizedBox(height: 14),
                _Label("Role"),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111D12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade900),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _role,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF111D12),
                      style: const TextStyle(color: Colors.white),
                      items: ["Owner", "Veterinarian", "Farm Worker"]
                          .map(
                            (r) => DropdownMenuItem(value: r, child: Text(r)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _role = v!),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              _Label("Email Address"), const SizedBox(height: 6),
              TextField(
                controller: _emailCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: "farmer@herdwise.com",
                ),
              ),
              const SizedBox(height: 14),

              if (!_isSignUp) ...[
                _Label("Password"),
                const SizedBox(height: 6),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(hintText: "••••••••"),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "Demo: farmer@herdwise.com / herdwise123",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // Main CTA
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isSignUp ? "Create Account" : "Sign In",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),

              if (!_isSignUp) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade800)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        "or",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade800)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _biometricLogin,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.green.shade800),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(
                      Icons.fingerprint,
                      color: Color(0xFF4CAF50),
                    ),
                    label: const Text("Sign in with Biometrics"),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _isSignUp = !_isSignUp;
                    _error = null;
                  }),
                  child: RichText(
                    text: TextSpan(
                      text: _isSignUp
                          ? "Already have an account? "
                          : "New to HerdWise? ",
                      style: TextStyle(color: Colors.grey.shade500),
                      children: [
                        TextSpan(
                          text: _isSignUp ? "Sign In" : "Create Account",
                          style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _Label(String text) => Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );

// ─────────────────────────────────────────
//  HOME SCREEN (Shell with Bottom Nav)
// ─────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  List<Animal> animals = buildInitialAnimals();
  bool alertsEnabled = true;
  DateTime? lastAlertTime;
  final double barnLat = 37.7749, barnLng = -122.4194;
  final Random _rng = Random();
  UserProfile? _profile;

  late final GeminiVetService _gemini;
  late final CollarBleService _ble;

  @override
  void initState() {
    super.initState();
    _gemini = GeminiVetService();
    _ble = CollarBleService();
    _loadProfile();
    _startSimulation();
    _listenToBle();
  }

  Future<void> _loadProfile() async {
    final p = await AuthService.getProfile();
    setState(() => _profile = p);
  }

  void _startSimulation() {
    Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      setState(() {
        for (var a in animals) {
          if (!a.isConnectedToHardware) _simulateAnimal(a);
          if (alertsEnabled) _checkAlerts(a);
        }
      });
    });
  }

  /// When a real collar sends BLE data, apply it to the matching animal
  void _listenToBle() {
    _ble.dataStream.listen((data) {
      final animalId = data["animalId"] as String;
      final charUuid = data["charUuid"] as String;
      final bytes = data["value"] as List<int>;
      setState(() {
        final animal = animals.firstWhere(
          (a) => a.id == animalId,
          orElse: () => animals.first,
        );
        animal.isConnectedToHardware = true;
        if (charUuid == kTemperatureCharUUID)
          animal.temp = CollarBleService.parseTemperature(bytes);
        if (charUuid == kHeartRateCharUUID)
          animal.heartRate = CollarBleService.parseHeartRate(bytes);
        if (charUuid == kOxygenCharUUID)
          animal.oxygenLevel = CollarBleService.parseSpO2(bytes);
        if (charUuid == kActivityCharUUID)
          animal.activity = CollarBleService.parseActivity(bytes);
        if (charUuid == kGpsCharUUID) {
          final gps = CollarBleService.parseGps(bytes);
          animal.lat = gps["lat"]!;
          animal.lng = gps["lng"]!;
        }
        _appendHistory(animal);
      });
    });
  }

  void _simulateAnimal(Animal a) {
    final t = a.typeInfo;
    a.temp = (a.temp + (_rng.nextDouble() * 0.4 - 0.2)).clamp(
      (t["normalTempMin"] as double) - 1.0,
      (t["normalTempMax"] as double) + 2.0,
    );
    a.heartRate = (a.heartRate + _rng.nextInt(5) - 2).clamp(
      (t["normalHRMin"] as int) - 10,
      (t["normalHRMax"] as int) + 20,
    );
    a.oxygenLevel = (a.oxygenLevel + (_rng.nextDouble() * 0.6 - 0.3)).clamp(
      88.0,
      100.0,
    );
    a.activity = (a.activity + _rng.nextInt(11) - 5).clamp(0, 100);
    a.lat += 0.00003;
    a.lng += 0.00002;
    final score = a.healthScore;
    a.mood = score >= 80
        ? "Calm"
        : score >= 60
            ? "Stressed"
            : score >= 40
                ? "Agitated"
                : "Lethargic";
    a.sleepState = a.activity < 15
        ? "Sleeping"
        : a.activity < 40
            ? "Resting"
            : "Active";
    if (_rng.nextInt(60) == 0) a.isHungry = !a.isHungry;
    _appendHistory(a);
    a.lastUpdated = DateTime.now();
  }

  void _appendHistory(Animal a) {
    a.tempHistory.add(a.temp);
    a.hrHistory.add(a.heartRate);
    a.o2History.add(a.oxygenLevel);
    a.activityHistory.add(a.activity);
    for (final list in [a.tempHistory, a.o2History, a.activityHistory]) {
      if (list.length > 20) list.removeAt(0);
    }
    if (a.hrHistory.length > 20) a.hrHistory.removeAt(0);
  }

  Future<void> _checkAlerts(Animal a) async {
    if (lastAlertTime != null &&
        DateTime.now().difference(lastAlertTime!).inSeconds < 20) return;
    final score = a.healthScore;
    double distance = Geolocator.distanceBetween(
      a.lat,
      a.lng,
      barnLat,
      barnLng,
    );
    String? msg;
    String sev = "info";
    if (score < 40) {
      msg = "${a.icon} ${a.name}: Critical health ($score%)!";
      sev = "critical";
    } else if (score < 60) {
      msg = "${a.icon} ${a.name}: Needs attention ($score%)";
      sev = "warning";
    } else if (a.oxygenLevel < 92) {
      msg =
          "${a.icon} ${a.name}: Low SpO₂ (${a.oxygenLevel.toStringAsFixed(1)}%)!";
      sev = "critical";
    } else if (distance > 200) {
      msg = "${a.icon} ${a.name} is far from barn";
      sev = "warning";
    } else if (a.isHungry) {
      msg = "${a.icon} ${a.name} is hungry";
      sev = "info";
    }
    if (msg != null) {
      lastAlertTime = DateTime.now();
      a.alertLogs.insert(
        0,
        AlertLog(time: DateTime.now(), message: msg, severity: sev),
      );
      if (a.alertLogs.length > 100) a.alertLogs.removeLast();
      await NotificationService.showAlert(
        title: "HerdWise Alert",
        body: msg,
        severity: sev,
      );
      if (mounted) _showSnackBar(msg, sev);
    }
  }

  void _showSnackBar(String msg, String sev) {
    final color = sev == "critical"
        ? Colors.red[800]
        : sev == "warning"
            ? Colors.orange[800]
            : Colors.blueGrey[800];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: "MUTE",
          textColor: Colors.yellow,
          onPressed: () => setState(() => alertsEnabled = false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      AnimalListScreen(
        animals: animals,
        alertsEnabled: alertsEnabled,
        onAlertToggle: (v) => setState(() => alertsEnabled = v),
        onAdd: (a) => setState(() => animals.add(a)),
        onRemove: (id) =>
            setState(() => animals.removeWhere((a) => a.id == id)),
        gemini: _gemini,
        ble: _ble,
      ),
      AlertsScreen(animals: animals),
      DashboardScreen(animals: animals, gemini: _gemini),
      AiVetScreen(animals: animals, gemini: _gemini),
      ProfileScreen(
        profile: _profile,
        onLogout: () async {
          await AuthService.logout();
          if (mounted)
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
        },
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF080F09),
        indicatorColor: const Color(0xFF2E7D32),
        selectedIndex: _selectedIndex,
        height: 64,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.pets_outlined),
            selectedIcon: Icon(Icons.pets),
            label: "Animals",
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: "Alerts",
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: "Dashboard",
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: "AI Vet",
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  ANIMAL LIST SCREEN
// ─────────────────────────────────────────

class AnimalListScreen extends StatelessWidget {
  final List<Animal> animals;
  final bool alertsEnabled;
  final ValueChanged<bool> onAlertToggle;
  final ValueChanged<Animal> onAdd;
  final ValueChanged<String> onRemove;
  final GeminiVetService gemini;
  final CollarBleService ble;

  const AnimalListScreen({
    super.key,
    required this.animals,
    required this.alertsEnabled,
    required this.onAlertToggle,
    required this.onAdd,
    required this.onRemove,
    required this.gemini,
    required this.ble,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("My Animals"),
            Text(
              "${animals.length} monitored",
              style: TextStyle(
                fontSize: 12,
                color: Colors.green.shade400,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: alertsEnabled ? "Alerts ON" : "Alerts OFF",
            child: IconButton(
              icon: Icon(
                alertsEnabled
                    ? Icons.notifications_active
                    : Icons.notifications_off,
                color: alertsEnabled ? const Color(0xFF4CAF50) : Colors.grey,
              ),
              onPressed: () => onAlertToggle(!alertsEnabled),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.bluetooth_searching,
              color: Color(0xFF4CAF50),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BleScreen(ble: ble, animals: animals),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => AddAnimalDialog(onAdd: onAdd),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        icon: const Icon(Icons.add),
        label: const Text("Add Animal"),
      ),
      body: animals.isEmpty
          ? _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: animals.length,
              itemBuilder: (ctx, i) => _AnimalCard(
                animal: animals[i],
                onRemove: () => onRemove(animals[i].id),
                onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        AnimalDetailScreen(animal: animals[i], gemini: gemini),
                  ),
                ),
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("🐄",
                style: TextStyle(fontSize: 60, color: Colors.grey.shade700)),
            const SizedBox(height: 16),
            Text(
              "No animals yet",
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Tap + to add your first animal",
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
          ],
        ),
      );
}

class _AnimalCard extends StatelessWidget {
  final Animal animal;
  final VoidCallback onTap, onRemove;
  const _AnimalCard({
    required this.animal,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final a = animal;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111D12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: a.healthColor.withOpacity(0.25), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2E1B),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            a.icon,
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      ),
                      if (a.isConnectedToHardware)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF111D12),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              a.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            if (a.isConnectedToHardware) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  "BLE",
                                  style: TextStyle(
                                    color: Colors.lightBlueAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          "${a.animalType} • ${a.tagNumber ?? ''}",
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _HealthRing(score: a.healthScore, color: a.healthColor),
                  IconButton(
                    icon: const Icon(
                      Icons.more_vert,
                      color: Colors.grey,
                      size: 20,
                    ),
                    onPressed: () => _showOptions(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _Stat(
                    icon: Icons.thermostat,
                    value: "${a.temp.toStringAsFixed(1)}°C",
                    color: Colors.orangeAccent,
                  ),
                  _Stat(
                    icon: Icons.favorite,
                    value: "${a.heartRate} bpm",
                    color: Colors.redAccent,
                  ),
                  _Stat(
                    icon: Icons.air,
                    value: "${a.oxygenLevel.toStringAsFixed(1)}%",
                    color: Colors.lightBlueAccent,
                  ),
                  _Stat(
                    icon: Icons.directions_run,
                    value: "${a.activity}%",
                    color: Colors.greenAccent,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _Chip(_moodIcon(a.mood) + " " + a.mood, _moodColor(a.mood)),
                  _Chip(
                    _sleepIcon(a.sleepState) + " " + a.sleepState,
                    Colors.indigo,
                  ),
                  if (a.isHungry) _Chip("🍽️ Hungry", Colors.amber[700]!),
                  if (a.hasSkinIssue) _Chip("⚠️ Skin Issue", Colors.deepOrange),
                  if (a.inBreedingMode) _Chip("💕 Breeding", Colors.pink),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111D12),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text(
              "Remove Animal",
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: () {
              Navigator.pop(context);
              onRemove();
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _HealthRing extends StatelessWidget {
  final int score;
  final Color color;
  const _HealthRing({required this.score, required this.color});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 4,
              color: color,
              backgroundColor: color.withOpacity(0.2),
            ),
            Text(
              "$score",
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
}

Widget _Stat({
  required IconData icon,
  required String value,
  required Color color,
}) =>
    Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: color, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

Widget _Chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );

// ─────────────────────────────────────────
//  BLE COLLAR PAIRING SCREEN
// ─────────────────────────────────────────

class BleScreen extends StatefulWidget {
  final CollarBleService ble;
  final List<Animal> animals;
  const BleScreen({super.key, required this.ble, required this.animals});
  @override
  State<BleScreen> createState() => _BleScreenState();
}

class _BleScreenState extends State<BleScreen> {
  bool _scanning = false;
  List<ScanResult> _results = [];

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _results = [];
    });
    await widget.ble.startScan();
    widget.ble.scanResults.listen((results) {
      if (mounted) setState(() => _results = results);
    });
    await Future.delayed(const Duration(seconds: 10));
    await widget.ble.stopScan();
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("🔵 Pair Collar Hardware")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1F2D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.blue.shade900),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "🔵 BLE Collar Requirements",
                    style: TextStyle(
                      color: Colors.lightBlueAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _BleReq(
                    "Advertise Service UUID: 0x180D (Health Thermometer)",
                  ),
                  _BleReq(
                    "Expose Temperature (0x2A1C), HR (0x2A37), SpO₂ (0x2A5F)",
                  ),
                  _BleReq("Optional: Activity (0x2A53), GPS (0x2AB3)"),
                  _BleReq(
                    "Compatible chipsets: Nordic nRF52, ESP32, TI CC2640",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _scanning ? null : _startScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D2137),
                ),
                icon: _scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.lightBlueAccent,
                        ),
                      )
                    : const Icon(
                        Icons.bluetooth_searching,
                        color: Colors.lightBlueAccent,
                      ),
                label: Text(
                  _scanning ? "Scanning for collars..." : "Scan for Collars",
                  style: const TextStyle(color: Colors.lightBlueAccent),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Nearby Devices",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _scanning ? "Searching..." : "No devices found",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1F2D),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade900),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.bluetooth,
                                color: Colors.lightBlueAccent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.device.platformName.isEmpty
                                          ? "Unknown Device"
                                          : r.device.platformName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      r.device.remoteId.toString(),
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                "${r.rssi} dBm",
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _PairButton(
                                device: r.device,
                                animals: widget.animals,
                                ble: widget.ble,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _BleReq(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.check, color: Colors.lightBlueAccent, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );

class _PairButton extends StatefulWidget {
  final BluetoothDevice device;
  final List<Animal> animals;
  final CollarBleService ble;
  const _PairButton({
    required this.device,
    required this.animals,
    required this.ble,
  });
  @override
  State<_PairButton> createState() => _PairButtonState();
}

class _PairButtonState extends State<_PairButton> {
  bool _connecting = false;

  Future<void> _pair() async {
    String? selectedId;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111D12),
        title: const Text(
          "Assign to Animal",
          style: TextStyle(color: Colors.white),
        ),
        content: DropdownButton<String>(
          dropdownColor: const Color(0xFF111D12),
          isExpanded: true,
          items: widget.animals
              .map(
                (a) => DropdownMenuItem(
                  value: a.id,
                  child: Text(
                    "${a.icon} ${a.name}",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            selectedId = v;
            Navigator.pop(context);
          },
          hint: const Text(
            "Select animal",
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ),
    );
    if (selectedId == null) return;
    setState(() => _connecting = true);
    try {
      await widget.ble.connectCollar(widget.device, selectedId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Collar paired successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Pairing failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
    }
    if (mounted) setState(() => _connecting = false);
  }

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: _connecting ? null : _pair,
        child: _connecting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text(
                "Pair",
                style: TextStyle(
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.bold,
                ),
              ),
      );
}

// ─────────────────────────────────────────
//  ANIMAL DETAIL SCREEN (4 tabs)
// ─────────────────────────────────────────

class AnimalDetailScreen extends StatefulWidget {
  final Animal animal;
  final GeminiVetService gemini;
  const AnimalDetailScreen({
    super.key,
    required this.animal,
    required this.gemini,
  });
  @override
  State<AnimalDetailScreen> createState() => _AnimalDetailScreenState();
}

class _AnimalDetailScreenState extends State<AnimalDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.animal;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text("${a.icon} ${a.name}"),
            if (a.isConnectedToHardware) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      "Live Hardware",
                      style: TextStyle(
                        color: Colors.lightBlueAccent,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.greenAccent,
          labelColor: Colors.greenAccent,
          unselectedLabelColor: Colors.grey,
          isScrollable: true,
          tabs: const [
            Tab(text: "Vitals"),
            Tab(text: "Charts"),
            Tab(text: "Status"),
            Tab(text: "Records"),
            Tab(text: "Alerts"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _VitalsTab(animal: a),
          _ChartsTab(animal: a),
          _StatusTab(
            animal: a,
            onToggle: (f, v) => setState(() {
              if (f == "hungry") a.isHungry = v;
              if (f == "skin") a.hasSkinIssue = v;
              if (f == "breeding") a.inBreedingMode = v;
            }),
          ),
          _RecordsTab(animal: a),
          _AlertsTab(animal: a),
        ],
      ),
    );
  }
}

// ── Vitals Tab ──

class _VitalsTab extends StatelessWidget {
  final Animal animal;
  const _VitalsTab({required this.animal});
  @override
  Widget build(BuildContext context) {
    final a = animal;
    final t = a.typeInfo;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: CircularProgressIndicator(
                    value: a.healthScore / 100,
                    strokeWidth: 10,
                    color: a.healthColor,
                    backgroundColor: Colors.grey.shade900,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${a.healthScore}%",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: a.healthColor,
                      ),
                    ),
                    Text(
                      a.healthLabel,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Last updated ${_timeAgo(a.lastUpdated)}",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _VitalCard(
                icon: Icons.thermostat,
                title: "Temperature",
                value: "${a.temp.toStringAsFixed(1)}°C",
                normal: "${t['normalTempMin']}–${t['normalTempMax']}°C",
                color: Colors.orangeAccent,
                isNormal: a.temp >= (t["normalTempMin"] as double) &&
                    a.temp <= (t["normalTempMax"] as double),
              ),
              _VitalCard(
                icon: Icons.favorite,
                title: "Heart Rate",
                value: "${a.heartRate} bpm",
                normal: "${t['normalHRMin']}–${t['normalHRMax']} bpm",
                color: Colors.redAccent,
                isNormal: a.heartRate >= (t["normalHRMin"] as int) &&
                    a.heartRate <= (t["normalHRMax"] as int),
              ),
              _VitalCard(
                icon: Icons.air,
                title: "SpO₂ Oxygen",
                value: "${a.oxygenLevel.toStringAsFixed(1)}%",
                normal: "≥${t['normalO2Min']}%",
                color: Colors.lightBlueAccent,
                isNormal: a.oxygenLevel >= (t["normalO2Min"] as int),
              ),
              _VitalCard(
                icon: Icons.directions_run,
                title: "Activity",
                value: "${a.activity}%",
                normal: "30–100%",
                color: Colors.greenAccent,
                isNormal: a.activity >= 30,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111D12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Animal Profile",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _ProfileRow("Tag Number", a.tagNumber ?? "N/A"),
                _ProfileRow("Age", "${a.ageMonths} months"),
                _ProfileRow("Weight", "${a.weight} kg"),
                _ProfileRow(
                  "GPS",
                  "Lat ${a.lat.toStringAsFixed(4)}, Lng ${a.lng.toStringAsFixed(4)}",
                ),
                _ProfileRow(
                  "Hardware",
                  a.isConnectedToHardware
                      ? "🔵 BLE Collar Connected"
                      : "📱 Simulated",
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _ProfileRow(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(k, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          Text(
            v,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

class _VitalCard extends StatelessWidget {
  final IconData icon;
  final String title, value, normal;
  final Color color;
  final bool isNormal;
  const _VitalCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.normal,
    required this.color,
    required this.isNormal,
  });
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF111D12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isNormal ? Colors.green.shade900 : Colors.red.shade900,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  isNormal ? Icons.check_circle : Icons.warning_amber,
                  color: isNormal ? Colors.green : Colors.red,
                  size: 14,
                ),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              "Normal: $normal",
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ],
        ),
      );
}

// ── Charts Tab ──

class _ChartsTab extends StatelessWidget {
  final Animal animal;
  const _ChartsTab({required this.animal});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _LineChartCard(
              "Temperature (°C)",
              animal.tempHistory,
              Colors.orangeAccent,
              36,
              42,
            ),
            const SizedBox(height: 14),
            _LineChartCard(
              "Heart Rate (bpm)",
              animal.hrHistory.map((e) => e.toDouble()).toList(),
              Colors.redAccent,
              40,
              160,
            ),
            const SizedBox(height: 14),
            _LineChartCard(
              "Oxygen SpO₂ (%)",
              animal.o2History,
              Colors.lightBlueAccent,
              85,
              100,
            ),
            const SizedBox(height: 14),
            _LineChartCard(
              "Activity Level (%)",
              animal.activityHistory.map((e) => e.toDouble()).toList(),
              Colors.greenAccent,
              0,
              100,
            ),
          ],
        ),
      );
}

Widget _LineChartCard(
  String title,
  List<double> data,
  Color color,
  double minY,
  double maxY,
) =>
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111D12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (data.isNotEmpty)
                Text(
                  data.last.toStringAsFixed(1),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) =>
                      // Using shade900 which is the darkest standard green
                      FlLine(color: Colors.green.shade900, strokeWidth: 1),
                  // OR use a custom hex color: Color(0xFF001A00)
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(0),
                        style: const TextStyle(color: Colors.grey, fontSize: 9),
                      ),
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: data
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(), e.value))
                        .toList(),
                    isCurved: true,
                    color: color,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.07),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

// ── Status Tab ──

class _StatusTab extends StatelessWidget {
  final Animal animal;
  final Function(String, bool) onToggle;
  const _StatusTab({required this.animal, required this.onToggle});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SecLabel("Behavioral Analysis"),
            const SizedBox(height: 12),
            _BigTile(
              _moodIcon(animal.mood),
              "Mood",
              animal.mood,
              _moodColor(animal.mood),
              _moodDesc(animal.mood),
            ),
            const SizedBox(height: 10),
            _BigTile(
              _sleepIcon(animal.sleepState),
              "Sleep State",
              animal.sleepState,
              Colors.indigoAccent,
              _sleepDesc(animal.sleepState),
            ),
            const SizedBox(height: 24),
            _SecLabel("Health Flags"),
            const SizedBox(height: 12),
            _Toggle(
              "🍽️",
              "Hunger Signal",
              "Shows signs of seeking food/water",
              animal.isHungry,
              Colors.amber,
              (v) => onToggle("hungry", v),
            ),
            _Toggle(
              "⚠️",
              "Skin Issue",
              "Irritation, rash, wound or parasite detected",
              animal.hasSkinIssue,
              Colors.deepOrange,
              (v) => onToggle("skin", v),
            ),
            _Toggle(
              "💕",
              "Breeding Readiness",
              "Estrus/heat cycle or breeding behavior detected",
              animal.inBreedingMode,
              Colors.pinkAccent,
              (v) => onToggle("breeding", v),
            ),
          ],
        ),
      );
}

Widget _BigTile(
  String icon,
  String title,
  String value,
  Color color,
  String desc,
) =>
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111D12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  desc,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );

Widget _Toggle(
  String icon,
  String title,
  String sub,
  bool value,
  Color color,
  ValueChanged<bool> onChange,
) =>
    Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111D12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? color.withOpacity(0.4) : Colors.grey.shade900,
        ),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(sub,
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChange, activeThumbColor: color),
        ],
      ),
    );

// ── Records Tab ──

class _RecordsTab extends StatefulWidget {
  final Animal animal;
  const _RecordsTab({required this.animal});
  @override
  State<_RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<_RecordsTab> {
  void _addRecord() {
    final diagCtrl = TextEditingController();
    final treatCtrl = TextEditingController();
    final vetCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111D12),
        title: const Text(
          "Add Vet Record",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: diagCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Diagnosis"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: treatCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Treatment"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: vetCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Vet Name"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
            ),
            onPressed: () {
              setState(
                () => widget.animal.vetRecords.insert(
                  0,
                  VetRecord(
                    date: DateTime.now(),
                    diagnosis: diagCtrl.text,
                    treatment: treatCtrl.text,
                    vetName: vetCtrl.text,
                  ),
                ),
              );
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.animal.vetRecords;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.small(
        onPressed: _addRecord,
        backgroundColor: const Color(0xFF2E7D32),
        child: const Icon(Icons.add),
      ),
      body: records.isEmpty
          ? const Center(
              child: Text(
                "No vet records yet",
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              itemBuilder: (_, i) {
                final r = records[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111D12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade900),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.medical_services,
                            color: Color(0xFF4CAF50),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat("dd MMM yyyy").format(r.date),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            r.vetName,
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Diagnosis: ${r.diagnosis}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        "Treatment: ${r.treatment}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ── Alerts Tab ──

class _AlertsTab extends StatelessWidget {
  final Animal animal;
  const _AlertsTab({required this.animal});
  @override
  Widget build(BuildContext context) {
    if (animal.alertLogs.isEmpty)
      return const Center(
        child: Text("No alerts ✅", style: TextStyle(color: Colors.grey)),
      );
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: animal.alertLogs.length,
      itemBuilder: (_, i) => _AlertTile(log: animal.alertLogs[i]),
    );
  }
}

Widget _AlertTile({required AlertLog log}) {
  final color = log.severity == "critical"
      ? Colors.red
      : log.severity == "warning"
          ? Colors.orange
          : Colors.blueGrey;
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Row(
      children: [
        Icon(
          log.severity == "critical" ? Icons.error : Icons.warning_amber,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(log.message, style: TextStyle(color: color, fontSize: 13)),
              Text(
                _timeAgo(log.time),
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            log.severity.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────
//  AI VET SCREEN — Gemini Chat
// ─────────────────────────────────────────

class AiVetScreen extends StatefulWidget {
  final List<Animal> animals;
  final GeminiVetService gemini;
  const AiVetScreen({super.key, required this.animals, required this.gemini});
  @override
  State<AiVetScreen> createState() => _AiVetScreenState();
}

class _AiVetScreenState extends State<AiVetScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  Animal? _selectedAnimal;
  List<ChatMessage> _messages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.animals.isNotEmpty) {
      _selectedAnimal = widget.animals.first;
      _addWelcome();
    }
  }

  void _addWelcome() {
    _messages = [
      ChatMessage(
        text:
            "👋 Hello! I'm **Dr. HerdWise**, your AI veterinary assistant.\n\n"
            "I have access to live sensor data from all your animals. Select an animal above and ask me anything — "
            "symptoms, vitals interpretation, treatment suggestions, breeding advice, and more.\n\n"
            "I'm powered by Google Gemini AI and trained on veterinary knowledge for livestock and farm animals.",
        isUser: false,
        time: DateTime.now(),
      ),
    ];
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _selectedAnimal == null) return;
    _ctrl.clear();
    setState(() {
      _messages.add(
        ChatMessage(text: text, isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(
          text: "",
          isUser: false,
          time: DateTime.now(),
          isLoading: true,
        ),
      );
      _loading = true;
    });
    _scrollDown();

    try {
      final response = await widget.gemini.askAboutAnimal(
        _selectedAnimal!,
        text,
      );
      setState(() {
        _messages.removeLast();
        _messages.add(
          ChatMessage(text: response, isUser: false, time: DateTime.now()),
        );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add(
          ChatMessage(
            text:
                "⚠️ I couldn't connect to the AI service. Please check your API key and internet connection.\n\nError: $e",
            isUser: false,
            time: DateTime.now(),
          ),
        );
        _loading = false;
      });
    }
    _scrollDown();
  }

  Future<void> _getQuickInsight() async {
    if (_selectedAnimal == null) return;
    await _sendMessage(
      "Give me a quick health insight for ${_selectedAnimal!.name} based on their current vitals.",
    );
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients)
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF66BB6A), Color(0xFF1B5E20)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text("🩺", style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Dr. HerdWise",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                Text(
                  "AI Veterinary Assistant",
                  style: TextStyle(fontSize: 11, color: Color(0xFF4CAF50)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_selectedAnimal != null)
            TextButton.icon(
              onPressed: _loading ? null : _getQuickInsight,
              icon: const Icon(
                Icons.auto_awesome,
                size: 16,
                color: Color(0xFF4CAF50),
              ),
              label: const Text(
                "Insight",
                style: TextStyle(color: Color(0xFF4CAF50), fontSize: 13),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Animal Selector
          Container(
            height: 56,
            color: const Color(0xFF0C160D),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: widget.animals.length,
              itemBuilder: (_, i) {
                final a = widget.animals[i];
                final selected = _selectedAnimal?.id == a.id;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedAnimal = a;
                    _addWelcome();
                  }),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF111D12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? Colors.greenAccent
                            : Colors.grey.shade800,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(a.icon, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(
                          a.name,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.grey,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: a.healthColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Chat
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _ChatBubble(msg: _messages[i]),
            ),
          ),

          // Quick Questions
          if (!_loading)
            Container(
              height: 44,
              color: const Color(0xFF0C160D),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                children: [
                  "What's wrong?",
                  "Check temperature",
                  "Breeding advice",
                  "Skin issue help",
                  "Feeding recommendations",
                ]
                    .map(
                      (q) => GestureDetector(
                        onTap: () => _sendMessage(q),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 0,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2E1B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.green.shade900,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              q,
                              style: TextStyle(
                                color: Colors.green.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          // Input
          Container(
            color: const Color(0xFF0C160D),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: _sendMessage,
                    decoration: InputDecoration(
                      hintText: "Ask Dr. HerdWise anything...",
                      hintStyle: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF111D12),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.green.shade900),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _loading ? null : () => _sendMessage(_ctrl.text),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4CAF50), Color(0xFF1B5E20)],
                      ),
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: _loading
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  const _ChatBubble({required this.msg});
  @override
  Widget build(BuildContext context) {
    if (msg.isLoading) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111D12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.green.shade400,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Dr. HerdWise is analyzing...",
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: msg.isUser ? const Color(0xFF2E7D32) : const Color(0xFF111D12),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(msg.isUser ? 18 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!msg.isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  "🩺 Dr. HerdWise",
                  style: TextStyle(
                    color: Colors.green.shade400,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Text(
              msg.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _timeAgo(msg.time),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  ALERTS SCREEN
// ─────────────────────────────────────────

class AlertsScreen extends StatelessWidget {
  final List<Animal> animals;
  const AlertsScreen({super.key, required this.animals});
  @override
  Widget build(BuildContext context) {
    final all = <Map>[];
    for (final a in animals)
      for (final l in a.alertLogs) all.add({"log": l, "animal": a});
    all.sort(
      (x, y) =>
          (y["log"] as AlertLog).time.compareTo((x["log"] as AlertLog).time),
    );
    final critical =
        all.where((e) => (e["log"] as AlertLog).severity == "critical").length;
    return Scaffold(
      appBar: AppBar(
        title: const Text("🔔 Alert History"),
        actions: [
          if (critical > 0)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade800),
              ),
              child: Text(
                "$critical critical",
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: all.isEmpty
          ? const Center(
              child: Text(
                "No alerts yet ✅",
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: all.length,
              itemBuilder: (_, i) {
                final log = all[i]["log"] as AlertLog;
                final animal = all[i]["animal"] as Animal;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _sevColor(log.severity).withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _sevColor(log.severity).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(animal.icon, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log.message,
                              style: TextStyle(
                                color: _sevColor(log.severity),
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _timeAgo(log.time),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _sevColor(log.severity).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          log.severity.toUpperCase(),
                          style: TextStyle(
                            color: _sevColor(log.severity),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

Color _sevColor(String s) => s == "critical"
    ? Colors.red
    : s == "warning"
        ? Colors.orange
        : Colors.blueGrey;

// ─────────────────────────────────────────
//  DASHBOARD SCREEN
// ─────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  final List<Animal> animals;
  final GeminiVetService gemini;
  const DashboardScreen({
    super.key,
    required this.animals,
    required this.gemini,
  });
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _herdSummary;
  bool _summaryLoading = false;

  Future<void> _loadSummary() async {
    setState(() => _summaryLoading = true);
    final s = await widget.gemini.getHerdSummary(widget.animals);
    setState(() {
      _herdSummary = s;
      _summaryLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final animals = widget.animals;
    final healthy = animals.where((a) => a.healthScore >= 75).length;
    final fair =
        animals.where((a) => a.healthScore >= 50 && a.healthScore < 75).length;
    final critical = animals.where((a) => a.healthScore < 50).length;
    final avgTemp = animals.isEmpty
        ? 0.0
        : animals.map((a) => a.temp).reduce((a, b) => a + b) / animals.length;
    final avgHR = animals.isEmpty
        ? 0
        : (animals.map((a) => a.heartRate).reduce((a, b) => a + b) /
                animals.length)
            .round();
    final avgO2 = animals.isEmpty
        ? 0.0
        : animals.map((a) => a.oxygenLevel).reduce((a, b) => a + b) /
            animals.length;
    final hungry = animals.where((a) => a.isHungry).length;
    final skin = animals.where((a) => a.hasSkinIssue).length;
    final breed = animals.where((a) => a.inBreedingMode).length;
    final bleConn = animals.where((a) => a.isConnectedToHardware).length;

    return Scaffold(
      appBar: AppBar(title: const Text("📊 Farm Dashboard")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI Summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF1B3A1C), const Color(0xFF0F1A10)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade800),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text("🩺", style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      const Text(
                        "AI Herd Summary",
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _summaryLoading ? null : _loadSummary,
                        child: Text(
                          _summaryLoading
                              ? "Loading..."
                              : _herdSummary == null
                                  ? "Generate"
                                  : "Refresh",
                          style: TextStyle(
                            color: Colors.green.shade400,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_herdSummary != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _herdSummary!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ] else if (!_summaryLoading)
                    Text(
                      "Tap Generate for an AI-powered herd health summary by Dr. HerdWise",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  if (_summaryLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(color: Color(0xFF4CAF50)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _SecLabel("Herd Health (${animals.length} animals)"),
            const SizedBox(height: 12),
            Row(
              children: [
                _DashTile(
                  "Healthy",
                  "$healthy",
                  Colors.green,
                  Icons.check_circle,
                ),
                const SizedBox(width: 10),
                _DashTile("Fair", "$fair", Colors.orange, Icons.info),
                const SizedBox(width: 10),
                _DashTile("Critical", "$critical", Colors.red, Icons.error),
              ],
            ),
            const SizedBox(height: 20),

            _SecLabel("Live Averages"),
            const SizedBox(height: 12),
            Row(
              children: [
                _DashTile(
                  "Avg Temp",
                  "${avgTemp.toStringAsFixed(1)}°C",
                  Colors.orangeAccent,
                  Icons.thermostat,
                ),
                const SizedBox(width: 10),
                _DashTile(
                  "Avg HR",
                  "$avgHR bpm",
                  Colors.redAccent,
                  Icons.favorite,
                ),
                const SizedBox(width: 10),
                _DashTile(
                  "Avg SpO₂",
                  "${avgO2.toStringAsFixed(1)}%",
                  Colors.lightBlueAccent,
                  Icons.air,
                ),
              ],
            ),
            const SizedBox(height: 20),

            _SecLabel("Flags & Connectivity"),
            const SizedBox(height: 12),
            Row(
              children: [
                _DashTile("Hungry", "$hungry", Colors.amber, Icons.restaurant),
                const SizedBox(width: 10),
                _DashTile(
                  "Skin Issues",
                  "$skin",
                  Colors.deepOrange,
                  Icons.healing,
                ),
                const SizedBox(width: 10),
                _DashTile(
                  "BLE Collars",
                  "$bleConn",
                  Colors.lightBlueAccent,
                  Icons.bluetooth,
                ),
              ],
            ),
            const SizedBox(height: 20),

            _SecLabel("Individual Health"),
            const SizedBox(height: 12),
            ...animals.map(
              (a) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF111D12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(a.icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            "${a.animalType} • ${a.mood}",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: a.healthScore / 100,
                          color: a.healthColor,
                          backgroundColor: Colors.grey.shade900,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${a.healthScore}%",
                      style: TextStyle(
                        color: a.healthColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _DashTile(String label, String value, Color color, IconData icon) =>
    Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF111D12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ),
    );

// ─────────────────────────────────────────
//  PROFILE SCREEN
// ─────────────────────────────────────────

class ProfileScreen extends StatelessWidget {
  final UserProfile? profile;
  final VoidCallback onLogout;
  const ProfileScreen({
    super.key,
    required this.profile,
    required this.onLogout,
  });
  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Avatar
            Center(
              child: Column(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4CAF50), Color(0xFF1B5E20)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4CAF50).withOpacity(0.3),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        (p?.name ?? "?")[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    p?.name ?? "—",
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2E1B),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      p?.role ?? "—",
                      style: TextStyle(
                        color: Colors.green.shade400,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Info
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111D12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _PRow(Icons.home, "Farm Name", p?.farmName ?? "—"),
                  const Divider(color: Color(0xFF1A2E1B), height: 20),
                  _PRow(Icons.email, "Email", p?.email ?? "—"),
                  const Divider(color: Color(0xFF1A2E1B), height: 20),
                  _PRow(Icons.badge, "Role", p?.role ?? "—"),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // App info
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111D12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _PRow(
                    Icons.smart_toy,
                    "AI Vet Engine",
                    "Google Gemini 1.5 Flash",
                  ),
                  const Divider(color: Color(0xFF1A2E1B), height: 20),
                  _PRow(
                    Icons.bluetooth,
                    "Collar Protocol",
                    "BLE GATT Health Profiles",
                  ),
                  const Divider(color: Color(0xFF1A2E1B), height: 20),
                  _PRow(Icons.info, "App Version", "HerdWise Pro v2.0"),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: onLogout,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade800),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                label: const Text(
                  "Sign Out",
                  style: TextStyle(color: Colors.redAccent, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _PRow(IconData icon, String label, String value) => Row(
      children: [
        Icon(icon, color: const Color(0xFF4CAF50), size: 18),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

// ─────────────────────────────────────────
//  ADD ANIMAL DIALOG
// ─────────────────────────────────────────

class AddAnimalDialog extends StatefulWidget {
  final ValueChanged<Animal> onAdd;
  const AddAnimalDialog({super.key, required this.onAdd});
  @override
  State<AddAnimalDialog> createState() => _AddAnimalDialogState();
}

class _AddAnimalDialogState extends State<AddAnimalDialog> {
  final _nameCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _weightCtrl = TextEditingController(text: "100");
  final _ageCtrl = TextEditingController(text: "12");
  String _type = "Cow";
  final _rng = Random();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111D12),
      title: const Text(
        "Add New Animal",
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Name",
                hintText: "e.g. Bessie",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Tag / RFID Number",
                hintText: "Optional",
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Weight (kg)"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ageCtrl,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Age (months)",
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Species",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kAnimalTypes.map((t) {
                final sel = _type == t["type"];
                return GestureDetector(
                  onTap: () => setState(() => _type = t["type"] as String),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF2E7D32) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? Colors.greenAccent : Colors.grey.shade700,
                      ),
                    ),
                    child: Text(
                      "${t['icon']} ${t['type']}",
                      style: TextStyle(
                        color: sel ? Colors.white : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
          ),
          onPressed: () {
            final t = kAnimalTypes.firstWhere((t) => t["type"] == _type);
            final hr =
                ((t["normalHRMin"] as int) + (t["normalHRMax"] as int)) ~/ 2;
            final temp = ((t["normalTempMin"] as double) +
                    (t["normalTempMax"] as double)) /
                2;
            final o2 = (t["normalO2Min"] as int).toDouble() + 1.0;
            widget.onAdd(
              makeAnimal(
                name: _nameCtrl.text.trim().isEmpty
                    ? _type
                    : _nameCtrl.text.trim(),
                type: _type,
                temp: temp,
                hr: hr,
                activity: 60,
                o2: o2,
                lat: 37.7749 + _rng.nextDouble() * 0.002,
                lng: -122.4194 + _rng.nextDouble() * 0.002,
                tagNumber:
                    _tagCtrl.text.trim().isEmpty ? null : _tagCtrl.text.trim(),
                weight: double.tryParse(_weightCtrl.text) ?? 100,
                ageMonths: int.tryParse(_ageCtrl.text) ?? 12,
              ),
            );
            Navigator.pop(context);
          },
          child: const Text("Add Animal"),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────

Widget _SecLabel(String text) => Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );

String _timeAgo(DateTime dt) {
  final d = DateTime.now().difference(dt);
  if (d.inSeconds < 10) return "just now";
  if (d.inSeconds < 60) return "${d.inSeconds}s ago";
  if (d.inMinutes < 60) return "${d.inMinutes}m ago";
  return "${d.inHours}h ago";
}

String _moodIcon(String m) =>
    {"Calm": "😌", "Stressed": "😰", "Agitated": "😤"}[m] ?? "😴";
Color _moodColor(String m) =>
    {
      "Calm": Colors.green,
      "Stressed": Colors.orange,
      "Agitated": Colors.red,
    }[m] ??
    Colors.blueGrey;
String _sleepIcon(String s) => {"Sleeping": "💤", "Resting": "🌙"}[s] ?? "🏃";
String _moodDesc(String m) =>
    {
      "Calm": "Animal is relaxed and comfortable",
      "Stressed": "Elevated vitals — monitor closely",
      "Agitated": "May need immediate attention",
    }[m] ??
    "Low energy detected";
String _sleepDesc(String s) =>
    {
      "Sleeping": "Deep rest, minimal movement",
      "Resting": "Light rest, low movement",
    }[s] ??
    "Normal activity";

extension TakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
