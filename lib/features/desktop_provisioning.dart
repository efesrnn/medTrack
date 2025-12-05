import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/database_service.dart';

class DesktopProvisioningScreen extends StatefulWidget {
  const DesktopProvisioningScreen({super.key});

  @override
  State<DesktopProvisioningScreen> createState() => _DesktopProvisioningScreenState();
}

class _DesktopProvisioningScreenState extends State<DesktopProvisioningScreen> {
  final _ssidController = TextEditingController();
  final _passController = TextEditingController();
  String _status = "USB Kablosunu takın ve bekleyin...";
  bool _isWorking = false;

  void _startSetup() async {
    setState(() { _isWorking = true; _status = "Cihaz aranıyor..."; });

    final ports = SerialPort.availablePorts;
    if (ports.isEmpty) {
      setState(() { _status = "Hata: Hiçbir cihaz bulunamadı!"; _isWorking = false; });
      return;
    }

    // Genellikle son takılan port ESP32'dir.
    final portAddress = ports.last;
    final port = SerialPort(portAddress);

    if (!port.openReadWrite()) {
      setState(() { _status = "Port açılamadı: $portAddress"; _isWorking = false; });
      return;
    }

    SerialPortConfig config = port.config;
    config.baudRate = 115200;
    port.config = config;

    final reader = SerialPortReader(port);

    // ESP32'den gelen cevabı dinle
    reader.stream.listen((data) async {
      String response = utf8.decode(data).trim();
      print("ESP Cevap: $response");

      if (response.startsWith("MAC:")) {
        String mac = response.substring(4); // "MAC:" kısmını at
        setState(() { _status = "MAC: $mac algılandı. Firebase'e kaydediliyor..."; });

        final user = await AuthService().getOrCreateUser();
        if (user != null) {
          // 1. Firebase'e Sahiplik Kaydı
          await DatabaseService().claimDevice(mac, user.uid, "admin@medtrack.com");

          // 2. Wi-Fi Bilgilerini Gönder
          String wifiJson = jsonEncode({
            "cmd": "SET_WIFI",
            "ssid": _ssidController.text,
            "pass": _passController.text
          });

          port.write(Uint8List.fromList(utf8.encode("$wifiJson\n")));

          if(mounted) {
            setState(() { _status = "Kurulum Tamamlandı! Cihaz Wi-Fi'a bağlanıyor."; _isWorking = false; });
          }
          port.close();
        } else {
          setState(() { _status = "Hata: Önce uygulamaya giriş yapmalısınız."; _isWorking = false; });
        }
      }
    });

    // ESP32'yi dürterek MAC adresini iste
    print("MAC isteği gönderiliyor...");
    port.write(Uint8List.fromList(utf8.encode("GET_MAC\n")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ESP32 Kurulum Masası")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _ssidController, decoration: const InputDecoration(labelText: "Wi-Fi Adı")),
            TextField(controller: _passController, decoration: const InputDecoration(labelText: "Wi-Fi Şifresi")),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isWorking ? null : _startSetup,
              child: const Text("Cihazı Kur"),
            ),
            const SizedBox(height: 20),
            Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}