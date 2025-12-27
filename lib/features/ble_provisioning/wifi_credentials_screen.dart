import 'dart:async'; // Completer için gerekli
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WifiCredentialsScreen extends StatefulWidget {
  final BluetoothDevice device;

  const WifiCredentialsScreen({super.key, required this.device});

  @override
  State<WifiCredentialsScreen> createState() => _WifiCredentialsScreenState();
}

class _WifiCredentialsScreenState extends State<WifiCredentialsScreen> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isConnecting = false;
  String _statusMessage = "";

  // UUID'ler ESP32 ile AYNI olmalı
  final String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  Future<void> _sendCredentials() async {
    if (_ssidController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lütfen tüm alanları doldurun")));
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = "Cihaza bağlanılıyor...";
    });

    BluetoothCharacteristic? targetChar;
    StreamSubscription? notifySubscription;

    try {
      // 1. Cihaza Bağlan
      await widget.device.connect();

      setState(() { _statusMessage = "Servisler keşfediliyor..."; });

      // 2. Servisleri ve Karakteristiği Bul
      List<BluetoothService> services = await widget.device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == CHAR_UUID) {
              targetChar = characteristic;
              break;
            }
          }
        }
      }

      if (targetChar == null) {
        throw Exception("Hedef servis bulunamadı!");
      }

      // --- 3. DİNLEMEYİ BAŞLAT (KRİTİK KISIM) ---
      setState(() { _statusMessage = "Cihazdan yanıt bekleniyor..."; });

      // Notify özelliğini aç
      await targetChar.setNotifyValue(true);

      // Cevabı beklemek için bir Completer kullanıyoruz (Promise gibi)
      Completer<String> responseCompleter = Completer<String>();

      notifySubscription = targetChar.lastValueStream.listen((value) {
        String response = utf8.decode(value).trim(); // Gelen veri: "SUCCESS" veya "FAIL" veya "TRYING"
        debugPrint("ESP32 Cevabı: $response");

        if (response == "SUCCESS") {
          if (!responseCompleter.isCompleted) responseCompleter.complete("SUCCESS");
        } else if (response == "FAIL") {
          if (!responseCompleter.isCompleted) responseCompleter.complete("FAIL");
        }
      });

      // --- 4. VERİYİ GÖNDER ---
      Map<String, String> data = {
        "s": _ssidController.text.trim(),
        "p": _passwordController.text.trim()
      };
      String jsonString = jsonEncode(data);
      await targetChar.write(utf8.encode(jsonString));

      setState(() { _statusMessage = "Cihaz WiFi ağına bağlanmaya çalışıyor...\nBu işlem 15-20 saniye sürebilir."; });

      // --- 5. CEVABI BEKLE (TIMEOUT İLE) ---
      // 30 Saniye içinde cevap gelmezse hata ver
      String finalResult = await responseCompleter.future.timeout(
          const Duration(seconds: 40),
          onTimeout: () => "TIMEOUT"
      );

      // --- 6. SONUCA GÖRE İŞLEM YAP ---
      if (finalResult == "SUCCESS") {
        setState(() { _statusMessage = "BAŞARILI! Cihaz bağlandı."; });
        _showResultDialog(true);
      } else if (finalResult == "FAIL") {
        setState(() { _statusMessage = "HATA: Cihaz WiFi ağına bağlanamadı.\nŞifreyi kontrol edip tekrar deneyin."; });
        _showResultDialog(false, message: "WiFi şifresi yanlış olabilir veya sinyal zayıf.");
      } else {
        setState(() { _statusMessage = "Zaman aşımı! Cihazdan yanıt alınamadı."; });
        _showResultDialog(false, message: "Cihazdan yanıt gelmedi.");
      }

    } catch (e) {
      setState(() { _statusMessage = "Hata: $e"; });
    } finally {
      // Temizlik
      notifySubscription?.cancel();
      if (mounted) setState(() { _isConnecting = false; });
      // Başarılı olsa da olmasa da işimiz bitince BLE'yi kesiyoruz
      // (Başarılı ise zaten ESP32 kendini kapatacak)
      try { await widget.device.disconnect(); } catch (_) {}
    }
  }

  void _showResultDialog(bool success, {String? message}) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(success ? "Kurulum Tamamlandı" : "Bağlantı Başarısız"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? Colors.green : Colors.red,
              size: 50,
            ),
            const SizedBox(height: 10),
            Text(message ?? (success ? "Cihaz başarıyla WiFi ağına bağlandı." : "Hata oluştu.")),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Dialog kapa
              if (success) {
                Navigator.pop(context); // Ana ekrana dön
              }
            },
            child: const Text("Tamam"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.platformName)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView( // Klavye açılınca taşmayı önler
          child: Column(
            children: [
              const Text("WiFi bilgilerini girin ve bekleyin.", style: TextStyle(fontSize: 16)),
              const SizedBox(height: 20),
              TextField(
                controller: _ssidController,
                decoration: const InputDecoration(
                  labelText: "WiFi Adı (SSID)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: "WiFi Şifresi",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 30),
              if (_isConnecting)
                Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _sendCredentials,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    child: const Text("BAĞLAN", style: TextStyle(fontSize: 18)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}