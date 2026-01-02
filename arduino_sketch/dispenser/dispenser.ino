#include <Arduino.h>
#include <WiFi.h>
#include <AccelStepper.h>
#include <Firebase_ESP_Client.h>
#include "time.h"
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

// ==========================================
// --- AYARLAR ---
// ==========================================
#define DEVICE_NAME "MEDTRACK_PROTOTYPE"
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define API_KEY "AIzaSyCiHSuyWiHG_6BvRKtJmwBu3SBLaIsKmfk"
// DİKKAT: Flutter tarafındaki databaseURL ile burası AYNI olmalı
#define DATABASE_URL "https://smartmedicinedispenser-default-rtdb.europe-west1.firebasedatabase.app"

// --- VERİ KONTROL SIKLIĞI (2.5 SANİYE) ---
#define FIREBASE_KONTROL_SURESI 2500

// --- NOTA FREKANSLARI ---
#define NOTE_C5  523
#define NOTE_D5  587
#define NOTE_E5  659
#define NOTE_F5  698
#define NOTE_G5  784
#define NOTE_A5  880
#define NOTE_B5  988
#define NOTE_C6  1047

// --- PINLER ---
#define M1_IN1 26
#define M1_IN2 25
#define M1_IN3 17
#define M1_IN4 16
#define M2_IN1 27
#define M2_IN2 14
#define M2_IN3 4
#define M2_IN4 13
#define M3_IN1 5
#define M3_IN2 23
#define M3_IN3 19
#define M3_IN4 18
#define SPEAKER_PIN 2
#define BUTTON_PIN 0 // BOOT Butonu (IO0)

// --- MOTOR ---
#define MOTOR_INTERFACE_TYPE AccelStepper::HALF4WIRE
#define ADIM_90_DERECE 1024
#define MAX_HIZ 1000.0
#define IVME 800.0

AccelStepper stepper1(MOTOR_INTERFACE_TYPE, M1_IN1, M1_IN3, M1_IN2, M1_IN4);
AccelStepper stepper2(MOTOR_INTERFACE_TYPE, M2_IN1, M2_IN3, M2_IN2, M2_IN4);
AccelStepper stepper3(MOTOR_INTERFACE_TYPE, M3_IN1, M3_IN3, M3_IN2, M3_IN4);

// --- FIREBASE & SİSTEM ---
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
String DEVICE_ID;

const char* ntpServer = "pool.ntp.org";
const long  gmtOffset_sec = 10800;
const int   daylightOffset_sec = 0;

#define MAX_ALARM 10
struct AlarmZamani { int saat = -1; int dakika = -1; bool verildi = false; };
struct Bolme { bool aktif = false; int alarmSayisi = 0; AlarmZamani alarmlar[MAX_ALARM]; };
Bolme bolmeler[3];

unsigned long sonVeriKontrol = 0;
bool bleMode = false;

// --- BAĞLANTI KONTROLÜ ---
unsigned long wifiKopmaZamani = 0;
unsigned long wifiBaglanmaZamani = 0;
bool internetVarMi = false;

// --- BLE ---
BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
String receivedSSID = "";
String receivedPassword = "";
bool credentialsReceived = false;

// --- SES EFEKTİ ---
unsigned long lastBleBeepTime = 0;
bool bleConnectEvent = false;

// --- BUTON KONTROL ---
volatile int pressCount = 0;
volatile unsigned long lastPressTime = 0;
volatile bool resetTriggered = false;

// --- PROTOTİPLER ---
void ayarlaMotor(AccelStepper &stepper);
void verileriGetir();
void buzzerKontrol();
void saatKontrolu();
void ilacVer(int motorNo);
void sesCikar(int sureMs);
void baslatBLE();
void durdurBLE();
void wifiBaglan(String ssid, String pass);
void firebaseBaslat();
void fabrikaAyarlarinaDon();
void playMelody(); 
void playTone(int frequency, int duration);

// ==========================================
// --- INTERRUPT (BUTON) ---
// ==========================================
void IRAM_ATTR buttonISR() {
  unsigned long now = millis();
  if (now - lastPressTime > 100) {
    if (now - lastPressTime > 1000) pressCount = 0;
    pressCount++;
    lastPressTime = now;
    if (pressCount >= 3) {
      resetTriggered = true;
      pressCount = 0;
    }
  }
}

// --- BLE CALLBACKS ---
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      bleConnectEvent = true;
    };
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      if (bleMode) { delay(500); pServer->getAdvertising()->start(); }
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue().c_str();
      if (value.length() > 0) {
        FirebaseJson json; FirebaseJsonData d_ssid, d_pass;
        json.setJsonData(value);
        json.get(d_ssid, "s"); json.get(d_pass, "p");
        if (d_ssid.success && d_pass.success) {
           receivedSSID = d_ssid.stringValue; receivedPassword = d_pass.stringValue;
           credentialsReceived = true;
        }
      }
    }
};

void setup() {
  Serial.begin(115200);
  pinMode(SPEAKER_PIN, OUTPUT);
  digitalWrite(SPEAKER_PIN, LOW);
  
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(BUTTON_PIN), buttonISR, FALLING);

  ayarlaMotor(stepper1); ayarlaMotor(stepper2); ayarlaMotor(stepper3);

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.persistent(true); 
  
  delay(100);
  
  Serial.print("MAC Adresi Okunuyor");
  String geciciMAC = WiFi.macAddress();
  int deneme = 0;
  while ((geciciMAC == "00:00:00:00:00:00" || geciciMAC == "") && deneme < 5) {
      delay(500); Serial.print(".");
      WiFi.mode(WIFI_STA); geciciMAC = WiFi.macAddress();
      deneme++;
  }
  DEVICE_ID = geciciMAC;
  Serial.println("\nDevice ID: " + DEVICE_ID);

  WiFi.begin();
  Serial.println("WiFi baslatildi (Kayitli ag deneniyor)...");
  
  int waitTime = 0;
  while(WiFi.status() != WL_CONNECTED && waitTime < 10) {
    delay(500); Serial.print("."); waitTime++;
  }

  if (WiFi.status() == WL_CONNECTED) {
     Serial.println("\nBaslangic Baglantisi OK!");
     internetVarMi = true;
     sesCikar(1000);
     firebaseBaslat();
  } else {
    Serial.println("\nBaslangicta WiFi yok. BLE Moduna Geciliyor.");
    baslatBLE();
  }
}

void loop() {
  if (resetTriggered) {
    resetTriggered = false;
    fabrikaAyarlarinaDon();
  }

  if (bleConnectEvent) {
      Serial.println("Cihaz Baglandi! (Ses Caliniyor)");
      sesCikar(100); delay(50); sesCikar(100); delay(50); sesCikar(100);
      bleConnectEvent = false;
  }

  if (bleMode && !deviceConnected) {
      if (millis() - lastBleBeepTime > 2000) {
          sesCikar(100);
          lastBleBeepTime = millis();
      }
  }

  bool suankiDurum = (WiFi.status() == WL_CONNECTED);

  if (suankiDurum) {
      wifiKopmaZamani = 0;
      if (!internetVarMi) {
          if (wifiBaglanmaZamani == 0) wifiBaglanmaZamani = millis();
          if (millis() - wifiBaglanmaZamani > 3000) {
              Serial.println(">>> Internet Kararli Sekilde Geri Geldi!");
              internetVarMi = true;
              sesCikar(1000);
              
              if (bleMode) {
                  Serial.println("BLE Kapatiliyor...");
                  durdurBLE();
                  delay(500);
                  firebaseBaslat();
              }
          }
      }
  }
  else {
      wifiBaglanmaZamani = 0;
      if (internetVarMi) {
          if (wifiKopmaZamani == 0) wifiKopmaZamani = millis();
          if (millis() - wifiKopmaZamani > 5000) {
              Serial.println("!!! Internet Koptu !!!");
              internetVarMi = false;
              if (!bleMode) { baslatBLE(); }
          }
      } else {
         if (!bleMode && (millis() - wifiKopmaZamani > 5000)) { baslatBLE(); }
      }
  }

  if (internetVarMi) {
      unsigned long simdikiZaman = millis();
      if (simdikiZaman - sonVeriKontrol > FIREBASE_KONTROL_SURESI) {
        if (Firebase.ready()) {
           verileriGetir();
           buzzerKontrol();
        }
        sonVeriKontrol = simdikiZaman;
      }
      saatKontrolu();
  }
  else {
      if (credentialsReceived) {
         Serial.println("BLE'den yeni sifre geldi...");
         wifiBaglan(receivedSSID, receivedPassword);
         credentialsReceived = false;
      }
      delay(10);
  }
}

// ==========================================================
// --- FONKSİYONLAR ---
// ==========================================================

void baslatBLE() {
  if (bleMode) return;
  bleMode = true;
  BLEDevice::init(DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_WRITE  |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setCallbacks(new MyCallbacks());
  pService->start();
  
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("BLE Yayini Basladi");
}

// --- DÜZELTİLMİŞ WIFI BAĞLAN FONKSİYONU ---
void wifiBaglan(String ssid, String pass) {
  Serial.print("Yeni Ag Deneniyor: "); Serial.println(ssid);
  
  if (deviceConnected && pCharacteristic != NULL) {
      pCharacteristic->setValue("TRYING");
      pCharacteristic->notify();
  }

  // >>> HATA ÇÖZÜMÜ BURADA: <<<
  // Eski bağlantı denemesini veya mevcut bağlantıyı tamamen durduruyoruz.
  // Bu işlem "sta is connecting, cannot set config" hatasını engeller.
  WiFi.disconnect(true);  // Bağlantıyı kes ve eski config'i temizle
  delay(1000);            // Driver'ın kendine gelmesi için bekle
  WiFi.mode(WIFI_OFF);    // WiFi'ı kapat
  delay(100);
  WiFi.mode(WIFI_STA);    // WiFi'ı tekrar Station modunda aç
  delay(500);

  WiFi.begin(ssid.c_str(), pass.c_str());

  int count = 0;
  // Bekleme süresini biraz artırdık (40 * 500ms = 20 sn)
  while (WiFi.status() != WL_CONNECTED && count < 40) {
    delay(500); Serial.print("."); count++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nBaglandi!");
    sesCikar(1000);
    wifiBaglanmaZamani = millis();

    if (deviceConnected && pCharacteristic != NULL) {
       Serial.println("Telefona SUCCESS gonderiliyor...");
       pCharacteristic->setValue("SUCCESS");
       pCharacteristic->notify();
       // Mesajın gitmesi için biraz bekle
       delay(2000); 
    }
    
  } else {
    Serial.println("\nBaglanamadi.");
    if (deviceConnected && pCharacteristic != NULL) {
       Serial.println("Telefona FAIL gonderiliyor...");
       pCharacteristic->setValue("FAIL");
       pCharacteristic->notify();
    }
  }
}

void firebaseBaslat() {
     Serial.println("Firebase Baslatiliyor...");
     configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
     
     config.api_key = API_KEY;
     config.database_url = DATABASE_URL;

     fbdo.setBSSLBufferSize(4096, 1024);

     config.timeout.wifiReconnect = 10000;
     config.timeout.socketConnection = 10000;
     config.timeout.sslHandshake = 20000;
     config.timeout.serverResponse = 10000;

     if (!Firebase.ready()) {
        Firebase.signUp(&config, &auth, "", "");
        Firebase.begin(&config, &auth);
        Firebase.reconnectWiFi(true);
     }
}

void durdurBLE() {
  if (!bleMode) return;
  BLEDevice::deinit(true);
  bleMode = false;
  Serial.println("BLE Durduruldu.");
}

void fabrikaAyarlarinaDon() {
    Serial.println("\n!!! RESET ISLEMI BASLATILDI !!!");
    sesCikar(100); delay(100); sesCikar(100); delay(100); sesCikar(100);
    
    Serial.println("WiFi Hafizasi Siliniyor...");
    WiFi.disconnect(true, true); 
    
    delay(1000);
    
    Serial.println("Cihaz Yeniden Baslatiliyor...");
    sesCikar(1000);
    ESP.restart();
}

void verileriGetir() {
  String path = "/dispensers/" + DEVICE_ID + "/config";
  
  if (Firebase.RTDB.getJSON(&fbdo, path)) {
    FirebaseJson *json = fbdo.jsonObjectPtr();
    FirebaseJsonData result;
    for (int i = 0; i < 3; i++) {
      String sectionKey = "section_" + String(i);
      json->get(result, sectionKey);
      if (result.success) {
        FirebaseJson sectionJson; result.getJSON(sectionJson);
        FirebaseJsonData d_aktif; sectionJson.get(d_aktif, "isActive");
        if(d_aktif.success) bolmeler[i].aktif = d_aktif.boolValue;
        FirebaseJsonData d_schedule; sectionJson.get(d_schedule, "schedule");
        if (d_schedule.success && d_schedule.type == "array") {
          FirebaseJsonArray myArr; myArr.setJsonArrayData(d_schedule.to<String>());
          bolmeler[i].alarmSayisi = myArr.size();
          if(bolmeler[i].alarmSayisi > MAX_ALARM) bolmeler[i].alarmSayisi = MAX_ALARM;
          for (size_t k = 0; k < bolmeler[i].alarmSayisi; k++) {
            FirebaseJsonData timeData; myArr.get(timeData, k);
            FirebaseJson timeObj; timeData.getJSON(timeObj);
            FirebaseJsonData h, m; timeObj.get(h, "h"); timeObj.get(m, "m");
            if (h.success && m.success) {
               if(bolmeler[i].alarmlar[k].saat != h.intValue || bolmeler[i].alarmlar[k].dakika != m.intValue) {
                  Serial.printf("\n[GUNCELLEME] Bolme %d icin yeni alarm: %02d:%02d\n", i+1, h.intValue, m.intValue);
                  bolmeler[i].alarmlar[k].saat = h.intValue; bolmeler[i].alarmlar[k].dakika = m.intValue;
                  bolmeler[i].alarmlar[k].verildi = false;
               }
            }
          }
        } else { bolmeler[i].alarmSayisi = 0; }
      }
    }
  } else {
     if (String(fbdo.errorReason()).indexOf("timed out") == -1) {
         Serial.print("Hata: ");
         Serial.println(fbdo.errorReason());
     }
  }
}

void buzzerKontrol() {
  String path = "/dispensers/" + DEVICE_ID + "/buzzer";
  if (Firebase.RTDB.getBool(&fbdo, path)) {
    if (fbdo.boolData()) {
        Serial.println("\n>>> 🔔 MELODİ: Buzzer Tetiklendi! <<<");
        playMelody(); 
    }
  }
}

void saatKontrolu() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) return;
  int sa = timeinfo.tm_hour; int dk = timeinfo.tm_min; int sn = timeinfo.tm_sec;

  static int sonYazilanDakika = -1;
  if (dk != sonYazilanDakika) {
      Serial.printf("[Sistem Calisiyor] Saat: %02d:%02d\n", sa, dk);
      sonYazilanDakika = dk;
  }

  if (sa == 0 && dk == 0 && sn < 5) {
    for(int i=0; i<3; i++) for(int k=0; k < MAX_ALARM; k++) bolmeler[i].alarmlar[k].verildi = false;
  }
  
  for (int i = 0; i < 3; i++) {
    if (bolmeler[i].aktif) {
      for (int k = 0; k < bolmeler[i].alarmSayisi; k++) {
        if (!bolmeler[i].alarmlar[k].verildi) {
          if (bolmeler[i].alarmlar[k].saat == sa && bolmeler[i].alarmlar[k].dakika == dk && sn < 5) {
            Serial.println("\n***********************************");
            Serial.printf(">>> 💊 İLAÇ VAKTİ! BOLME %d MOTORU DONUYOR... <<<\n", i+1);
            Serial.println("***********************************\n");
            ilacVer(i + 1);
            bolmeler[i].alarmlar[k].verildi = true;
          }
        }
      }
    }
  }
}

void ilacVer(int motorNo) {
  AccelStepper *motor;
  if (motorNo == 1) motor = &stepper1; else if (motorNo == 2) motor = &stepper2; else motor = &stepper3;
  motor->enableOutputs(); sesCikar(500);
  motor->move(ADIM_90_DERECE);
  while (motor->distanceToGo() != 0) motor->run();
  motor->disableOutputs(); sesCikar(1000);
}

void playTone(int frequency, int durationMs) {
  long period = 1000000 / frequency;
  long cycles = (durationMs * 1000) / period;
  for (long i = 0; i < cycles; i++) {
    digitalWrite(SPEAKER_PIN, HIGH); delayMicroseconds(period / 2);
    digitalWrite(SPEAKER_PIN, LOW); delayMicroseconds(period / 2);
  }
}

void playMelody() {
  int notes[] = {NOTE_C5, NOTE_E5, NOTE_G5, NOTE_C6, NOTE_G5, NOTE_C6};
  int durations[] = {150, 150, 150, 300, 150, 600};
  for (int i = 0; i < 6; i++) {
    playTone(notes[i], durations[i]);
    delay(50);
  }
}

void sesCikar(int sureMs) {
  unsigned long start = millis();
  while(millis() - start < sureMs) {
    digitalWrite(SPEAKER_PIN, HIGH); delayMicroseconds(500);
    digitalWrite(SPEAKER_PIN, LOW); delayMicroseconds(500);
  }
}

void ayarlaMotor(AccelStepper &stepper) { stepper.setMaxSpeed(MAX_HIZ); stepper.setAcceleration(IVME); }