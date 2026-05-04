#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>
#include <SPIFFS.h>
#include "esp32-hal-ledc.h"

// ==== BLE Setup ====
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLEServer *pServer = NULL;
BLECharacteristic *pCharacteristic = NULL;
bool deviceConnected = false;

// ==== Configuration ====
const char* mqtt_client_id = "ESP32_DEV_001"; // Used for device ID only

// ==== Pin Definitions ====
#define PWM_CHARGE           18
#define PWM_DISCHARGE        19
#define ANALOG_PIN_COURANT   27

// ==== ADC Constants ====
const float Vref = 3.3;
const float ADC_MAX = 4095.0;
const int analogPinTemp = 39;
const int analogPinsTension[5] = {32, 33, 34, 35, 36};
const int nbMesuresADC = 20;
const int nbMesuresTemp = 50;

// ==== ACS758 ====
const float ACS758_OFFSET = 2.25;
const float ACS758_SENSIBILITE = 0.04;

// ==== Validation Limits ====
const float MIN_VOLTAGE = 0.0;
const float MAX_VOLTAGE_CELL = 4.2;
const float MAX_VOLTAGE_PACK = 16.8;
const float MIN_TEMP = -40.0;
const float MAX_TEMP = 100.0;
const float MIN_CURRENT = -100.0;
const float MAX_CURRENT = 100.0;

// ==== PWM Configuration ====
#define PWM_FREQ       20000
#define PWM_RESOLUTION 8
#define MAX_DUTY       255
#define CURRENT_CHARGE_LIMIT     12.0
#define CURRENT_DISCHARGE_LIMIT  20.0
#define TEMP_MIN_PWM             0.0
#define TEMP_MAX_PWM             45.0
#define VOLTAGE_CHARGE_CUTOFF    14.6
#define VOLTAGE_DISCHARGE_CUTOFF 12.0
#define PAUSE_TIME_MS            30000
#define FADE_INTERVAL_MS         50
#define CHARGE_CHANNEL           0
#define DISCHARGE_CHANNEL        1

float voltageChargeCutoff = 14.6;
float voltageDischargeCutoff = 12.0;
float currentChargeLimit = 12.0;
float currentDischargeLimit = 20.0;

// ==== Battery Parameters ====
const float batteryCapacityAh = 30.0;
const float batteryVoltageNominal = 12.8;
const float batteryEnergyWh = batteryCapacityAh * batteryVoltageNominal;

// ==== SoC Variables ====
float soc = 100.0;
float energyUsedWh = 0.0;
unsigned long lastSocTime = 0;
bool isResting = false;
unsigned long restStartTime = 0;
const unsigned long restDuration = 120000;
bool isCharging = false;
unsigned long chargeStartTime = 0;
const float I_charge = 12.0;

// ==== SoC ↔ Voltage Table ====
const int tableSize = 50;
float socTable[tableSize] = {  
  0.0, 2.0, 4.1, 6.1, 8.2, 10.2, 12.2, 14.3, 16.3, 18.4,  
  20.4, 22.4, 24.5, 26.5, 28.6, 30.6, 32.7, 34.7, 36.7, 38.8,  
  40.8, 42.9, 44.9, 46.9, 49.0, 51.0, 53.1, 55.1, 57.1, 59.2,  
  61.2, 63.3, 65.3, 67.3, 69.4, 71.4, 73.5, 75.5, 77.6, 79.6,  
  81.6, 83.7, 85.7, 87.8, 89.8, 91.8, 93.9, 95.9, 98.0, 100.0  
};

float voltageTable[tableSize] = {  
  12.052, 12.080, 12.108, 12.136, 12.164, 12.192, 12.220, 12.248, 12.276, 12.304,  
  12.332, 12.360, 12.388, 12.416, 12.444, 12.472, 12.500, 12.528, 12.556, 12.584,  
  12.612, 12.640, 12.668, 12.696, 12.724, 12.752, 12.780, 12.808, 12.836, 12.864,  
  12.892, 12.920, 12.948, 12.976, 13.004, 13.032, 13.060, 13.088, 13.116, 13.144,  
  13.172, 13.200, 13.228, 13.256, 13.288, 13.316, 13.344, 13.372, 13.400, 13.428  
};

// ==== Measurement Variables ====
float temperature = 0.0;
float cellules[4] = {0.0};
float tensionPack = 0.0;
float courant = 0.0;

// ==== History ====
struct MeasurementRecord {
  float cellules[4];
  float tensionPack;
  float temperature;
  float courant;
  float soc;
  float energyUsed;
  unsigned long timestamp;
};

#define MAX_RECORDS 24
MeasurementRecord measurementHistory[MAX_RECORDS];
int recordIndex = 0;
float maxCellules[4] = {0.0, 0.0, 0.0, 0.0};
float maxTensionPack = 0.0;
float maxTemperature = 0.0;
float maxCourant = 0.0;
float maxSoc = 100.0;
unsigned long lastHourlyCheck = 0;
unsigned long lastDailyCheck = 0;
const long hourlyInterval = 3600000;
const long dailyInterval = 86400000;

// ==== Timer ====
unsigned long previousMillis = 0;
const long interval = 10000;

// ==== PWM Control ====
enum Mode {CHARGE, DISCHARGE, IDLE};
Mode mode = IDLE;
unsigned long lastActionTime = 0;
bool inPause = false;
int currentDutyCharge = 0;
int currentDutyDischarge = 0;
unsigned long lastFadeTime = 0;

// ==== BLE Callbacks ====
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("Client BLE connecté");
    BLEDevice::getAdvertising()->stop();
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("Client BLE déconnecté");
    BLEDevice::startAdvertising();
    Serial.println("Publicité BLE redémarrée");
  }
};

class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String rxValue = String(pCharacteristic->getValue().c_str());
    if (rxValue.length() > 0) {
      Serial.print("BLE reçu: ");
      Serial.println(rxValue);

      // Parse as JSON
      StaticJsonDocument<256> doc;
      DeserializationError error = deserializeJson(doc, rxValue);
      if (!error) {
        // Process commands here if needed
        Serial.println("JSON valide reçu");
      } else {
        Serial.println("JSON invalide");
      }
    }
  }
};

// ==== SPIFFS Functions ====
void saveHistoryToSPIFFS() {
  File file = SPIFFS.open("/history.json", FILE_WRITE);
  if (!file) {
    Serial.println("Erreur: Impossible d'ouvrir history.json");
    return;
  }

  StaticJsonDocument<2048> doc;
  JsonArray records = doc.to<JsonArray>();

  for (int i = 0; i < MAX_RECORDS; i++) {
    if (measurementHistory[i].timestamp > 0) {
      JsonObject record = records.createNestedObject();
      JsonArray cells = record.createNestedArray("cellules");
      for (int j = 0; j < 4; j++) {
        cells.add(measurementHistory[i].cellules[j]);
      }
      record["tensionPack"] = measurementHistory[i].tensionPack;
      record["temperature"] = measurementHistory[i].temperature;
      record["courant"] = measurementHistory[i].courant;
      record["soc"] = measurementHistory[i].soc;
      record["energyUsed"] = measurementHistory[i].energyUsed;
      record["timestamp"] = measurementHistory[i].timestamp;
    }
  }

  if (serializeJson(doc, file) == 0) {
    Serial.println("Erreur: Échec écriture JSON");
  } else {
    Serial.println("Historique sauvegardé");
  }
  file.close();
}

void loadHistoryFromSPIFFS() {
  File file = SPIFFS.open("/history.json", FILE_READ);
  if (!file) {
    Serial.println("Aucun historique trouvé");
    return;
  }

  StaticJsonDocument<2048> doc;
  DeserializationError error = deserializeJson(doc, file);
  if (error) {
    Serial.println("Erreur chargement JSON");
    file.close();
    return;
  }

  JsonArray records = doc.as<JsonArray>();
  int index = 0;
  for (JsonObject record : records) {
    if (index >= MAX_RECORDS) break;

    JsonArray cells = record["cellules"];
    for (int j = 0; j < 4 && j < cells.size(); j++) {
      measurementHistory[index].cellules[j] = cells[j];
    }

    measurementHistory[index].tensionPack = record["tensionPack"];
    measurementHistory[index].temperature = record["temperature"];
    measurementHistory[index].courant = record["courant"];
    measurementHistory[index].soc = record["soc"];
    measurementHistory[index].energyUsed = record["energyUsed"];
    measurementHistory[index].timestamp = record["timestamp"];
    index++;
  }

  recordIndex = index % MAX_RECORDS;
  if (index > 0) {
    soc = measurementHistory[index - 1].soc;
    energyUsedWh = measurementHistory[index - 1].energyUsed;
  }

  Serial.println("Historique chargé");
  file.close();
}

// ==== Measurement Functions ====
void mesurerTemperature() {
  float somme = 0.0;
  for (int i = 0; i < nbMesuresTemp; i++) {
    float sommeTemp = 0.0;
    for (int j = 0; j < nbMesuresADC; j++) {
      int raw = analogRead(analogPinTemp);
      sommeTemp += raw;
      delayMicroseconds(100);
    }
    float tension = ((sommeTemp / nbMesuresADC) * Vref) / ADC_MAX;
    somme += tension;
  }

  float moyenneTension = somme / nbMesuresTemp;
  temperature = (-35.69 * moyenneTension) + 85.54;
  
  if (temperature < MIN_TEMP || temperature > MAX_TEMP) {
    temperature = 0.0;
  }
  if (temperature > maxTemperature) {
    maxTemperature = temperature;
  }
}

void mesurerTensions() {
  for (int i = 0; i < 4; i++) {
    float somme = 0.0;
    for (int j = 0; j < nbMesuresADC; j++) {
      int raw = analogRead(analogPinsTension[i]);
      somme += raw;
      delayMicroseconds(100);
    }
    float adcValue = somme / nbMesuresADC;
    cellules[i] = ((adcValue / ADC_MAX) * Vref) * 2.0;
    
    if (cellules[i] < MIN_VOLTAGE || cellules[i] > MAX_VOLTAGE_CELL) {
      cellules[i] = 0.0;
    }
    if (cellules[i] > maxCellules[i]) {
      maxCellules[i] = cellules[i];
    }
  }

  float sommePack = 0.0;
  for (int j = 0; j < nbMesuresADC; j++) {
    int raw = analogRead(analogPinsTension[4]);
    sommePack += raw;
    delayMicroseconds(100);
  }
  float packValue = sommePack / nbMesuresADC;
  tensionPack = ((packValue / ADC_MAX) * Vref) * 6.8;
  
  if (tensionPack < MIN_VOLTAGE || tensionPack > MAX_VOLTAGE_PACK) {
    tensionPack = 0.0;
  }
  if (tensionPack > maxTensionPack) {
    maxTensionPack = tensionPack;
  }
}

void mesurerCourant() {
  float somme = 0.0;
  for (int j = 0; j < nbMesuresADC; j++) {
    int raw = analogRead(ANALOG_PIN_COURANT);
    somme += raw;
    delayMicroseconds(100);
  }
  float adcValue = somme / nbMesuresADC;
  float tension = (adcValue / ADC_MAX) * Vref;
  courant = (tension - ACS758_OFFSET) / ACS758_SENSIBILITE;
  
  if (courant < MIN_CURRENT || courant > MAX_CURRENT) {
    courant = 0.0;
  }
  if (courant > maxCourant) {
    maxCourant = courant;
  }
}

float estimateSoC(float voltage) {
  if (voltage <= voltageTable[0]) return socTable[0];
  if (voltage >= voltageTable[tableSize - 1]) return socTable[tableSize - 1];

  for (int i = 0; i < tableSize - 1; i++) {
    if (voltage >= voltageTable[i] && voltage <= voltageTable[i + 1]) {
      float soc_interp = socTable[i] + 
        (voltage - voltageTable[i]) * 
        (socTable[i + 1] - socTable[i]) / 
        (voltageTable[i + 1] - voltageTable[i]);
      return soc_interp;
    }
  }
  return 0.0;
}

void calculateSoC() {
  unsigned long currentTime = millis();
  float dt = (currentTime - lastSocTime) / 3600000.0;
  lastSocTime = currentTime;

  float power = tensionPack * courant;
  energyUsedWh += power * dt;
  soc = 100.0 - (energyUsedWh / batteryEnergyWh * 100.0);
  soc = constrain(soc, 0.0f, 100.0f);

  if (abs(courant) < 0.2f) {
    if (!isResting) {
      restStartTime = currentTime;
      isResting = true;
    }
    else if (currentTime - restStartTime >= restDuration) {
      float socFromVoltage = estimateSoC(tensionPack);
      soc = 0.9f * soc + 0.1f * socFromVoltage;
    }
  } else {
    isResting = false;
  }

  if (courant < -0.2f) {
    if (!isCharging) {
      chargeStartTime = currentTime;
      isCharging = true;
    }
    float t_hours = (currentTime - chargeStartTime) / 3600000.0f;
    soc += (I_charge * t_hours / batteryCapacityAh) * 100.0f;
    soc = constrain(soc, 0.0f, 100.0f);
  } else {
    isCharging = false;
  }

  if (soc > maxSoc) {
    maxSoc = soc;
  }
}

void updateMeasurementHistory() {
  unsigned long currentMillis = millis();

  if (currentMillis - lastHourlyCheck >= hourlyInterval) {
    if (maxTemperature > 0 || maxTensionPack > 0) {
      for (int i = 0; i < 4; i++) {
        measurementHistory[recordIndex].cellules[i] = maxCellules[i];
      }
      measurementHistory[recordIndex].tensionPack = maxTensionPack;
      measurementHistory[recordIndex].temperature = maxTemperature;
      measurementHistory[recordIndex].courant = maxCourant;
      measurementHistory[recordIndex].soc = maxSoc;
      measurementHistory[recordIndex].energyUsed = energyUsedWh;
      measurementHistory[recordIndex].timestamp = currentMillis;

      saveHistoryToSPIFFS();

      for (int i = 0; i < 4; i++) {
        maxCellules[i] = 0.0;
      }
      maxTensionPack = 0.0;
      maxTemperature = 0.0;
      maxCourant = 0.0;
      maxSoc = 0.0;
      recordIndex = (recordIndex + 1) % MAX_RECORDS;
    }
    lastHourlyCheck = currentMillis;
  }
}

void progressiveStart(int channel, int* duty) {
  unsigned long currentMillis = millis();
  if (currentMillis - lastFadeTime >= FADE_INTERVAL_MS) {
    if (*duty < MAX_DUTY) {
      *duty += 25;
      if (*duty > MAX_DUTY) *duty = MAX_DUTY;
      ledcWrite(channel, *duty);
      lastFadeTime = currentMillis;
    }
  }
}

void progressiveStop(int channel, int& duty) {
  unsigned long currentMillis = millis();
  if (currentMillis - lastFadeTime >= FADE_INTERVAL_MS) {
    if (duty > 0) {
      duty -= 25;
      if (duty < 0) duty = 0;
      ledcWrite(channel, duty);
      lastFadeTime = currentMillis;
    }
  }
}

/*void setupPWM() {
  ledcSetup(CHARGE_CHANNEL, PWM_FREQ, PWM_RESOLUTION);
  ledcAttachPin(PWM_CHARGE, CHARGE_CHANNEL);
  ledcWrite(CHARGE_CHANNEL, 0);

  ledcSetup(DISCHARGE_CHANNEL, PWM_FREQ, PWM_RESOLUTION);
  ledcAttachPin(PWM_DISCHARGE, DISCHARGE_CHANNEL);
  ledcWrite(DISCHARGE_CHANNEL, 0);
  
  Serial.println("PWM initialisé");
}*/
void setupPWM() {
  ledcAttach(PWM_CHARGE, PWM_FREQ, PWM_RESOLUTION);
  ledcAttach(PWM_DISCHARGE, PWM_FREQ, PWM_RESOLUTION);

  ledcWrite(PWM_CHARGE, 0);
  ledcWrite(PWM_DISCHARGE, 0);

  Serial.println("PWM initialisé");
}


void publishMeasurements() {
  StaticJsonDocument<512> doc;
  doc["device"] = mqtt_client_id;
  doc["C1"] = cellules[0];
  doc["C2"] = cellules[1];
  doc["C3"] = cellules[2];
  doc["C4"] = cellules[3];
  doc["PACK"] = tensionPack;
  doc["TEMP"] = temperature;
  doc["COURANT"] = courant;
  doc["SOC"] = soc;

  char buffer[512];
  serializeJson(doc, buffer);

  if (deviceConnected) {
    pCharacteristic->setValue(buffer);
    pCharacteristic->notify();
    Serial.println("Données envoyées via BLE");
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("===== ESP32 BMS Starting =====");

  // Initialize SPIFFS
  if (!SPIFFS.begin(true)) {
    Serial.println("Erreur SPIFFS");
    return;
  }
  Serial.println("SPIFFS OK");

  // Clear history
  for (int i = 0; i < MAX_RECORDS; i++) {
    for (int j = 0; j < 4; j++) {
      measurementHistory[i].cellules[j] = 0.0;
    }
    measurementHistory[i].tensionPack = 0.0;
    measurementHistory[i].temperature = 0.0;
    measurementHistory[i].courant = 0.0;
    measurementHistory[i].soc = 0.0f;
    measurementHistory[i].energyUsed = 0.0f;
    measurementHistory[i].timestamp = 0;
  }
  
  loadHistoryFromSPIFFS();
  lastSocTime = millis();

  // Initialize BLE
  Serial.println(">>> Starting BLE...");
  BLEDevice::init("ESP32_BMS");
  Serial.println(">>> BLEDevice::init OK");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());

  pService->start();
  BLEAdvertising* pAdvertising = pServer->getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();
  
  Serial.println(" BLE démarré - En attente de connexions...");
  Serial.print("Nom du device: ESP32_BMS");
  Serial.println();

  analogSetAttenuation(ADC_11db);
  setupPWM();
  
  Serial.println("===== Setup Complete =====");
}

void loop() {
  unsigned long currentMillis = millis();

  // Periodic measurements
  if (currentMillis - previousMillis >= interval) {
    previousMillis = currentMillis;

    Serial.println("--- Mesures ---");
    mesurerTemperature();
    mesurerTensions();
    mesurerCourant();
    calculateSoC();
    updateMeasurementHistory();
    publishMeasurements();
    
    Serial.print("Temp: "); Serial.print(temperature); Serial.println("°C");
    Serial.print("Pack: "); Serial.print(tensionPack); Serial.println("V");
    Serial.print("Courant: "); Serial.print(courant); Serial.println("A");
    Serial.print("SoC: "); Serial.print(soc); Serial.println("%");
  }

  // PWM Control (disabled for now - uncomment when ready to test)
  /*
  if (!inPause) {
    if (tensionPack < VOLTAGE_DISCHARGE_CUTOFF) mode = CHARGE;
    else if (tensionPack >= VOLTAGE_CHARGE_CUTOFF) mode = DISCHARGE;

    if (mode == CHARGE) {
      if (courant > CURRENT_CHARGE_LIMIT || temperature < TEMP_MIN_PWM || temperature > TEMP_MAX_PWM) {
        progressiveStop(CHARGE_CHANNEL, currentDutyCharge);
        inPause = true;
        lastActionTime = currentMillis;
      } else {
        progressiveStart(CHARGE_CHANNEL, &currentDutyCharge);
        progressiveStop(DISCHARGE_CHANNEL, currentDutyDischarge);
      }
    }
    else if (mode == DISCHARGE) {
      if (courant > CURRENT_DISCHARGE_LIMIT || temperature < TEMP_MIN_PWM || temperature > TEMP_MAX_PWM) {
        progressiveStop(DISCHARGE_CHANNEL, currentDutyDischarge);
        inPause = true;
        lastActionTime = currentMillis;
      } else {
        progressiveStart(DISCHARGE_CHANNEL, &currentDutyDischarge);
        progressiveStop(CHARGE_CHANNEL, currentDutyCharge);
      }
    }
  } else {
    if (currentMillis - lastActionTime > PAUSE_TIME_MS) {
      if ((mode == CHARGE && courant <= CURRENT_CHARGE_LIMIT && temperature >= TEMP_MIN_PWM && temperature <= TEMP_MAX_PWM) ||
          (mode == DISCHARGE && courant <= CURRENT_DISCHARGE_LIMIT && temperature >= TEMP_MIN_PWM && temperature <= TEMP_MAX_PWM)) {
        inPause = false;
      }
    }
  }
  */

  delay(100);
}