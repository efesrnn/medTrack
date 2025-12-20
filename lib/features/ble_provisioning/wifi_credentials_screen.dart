import 'dart:convert';
import 'package:dispenserapp/features/ble_provisioning/ble_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WifiCredentialsScreen extends StatefulWidget {
  final BluetoothDevice device;

  const WifiCredentialsScreen({super.key, required this.device});

  @override
  State<WifiCredentialsScreen> createState() => _WifiCredentialsScreenState();
}

class _WifiCredentialsScreenState extends State<WifiCredentialsScreen> {
  String _status = 'Bağlı, komut bekleniyor...';
  BluetoothCharacteristic? _statusCharacteristic;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _discoverServices();
  }

  // Cihazdaki servisleri ve karakteristiği bulur
  Future<void> _discoverServices() async {
    try {
      // Servisleri keşfet
      final services = await widget.device.discoverServices();

      // ble_constants.dart dosyasındaki SERVICE_UUID'yi bul
      final service = services.firstWhere((s) => s.uuid == SERVICE_UUID);

      // STATUS karakteristiğini bul
      final characteristic = service.characteristics
          .firstWhere((c) => c.uuid == STATUS_CHARACTERISTIC_UUID);

      setState(() {
        _statusCharacteristic = characteristic;
        _isReady = true;
      });
    } catch (e) {
      setState(() {
        _status = 'Hata: Servis veya Karakteristik bulunamadı.\nUUID\'leri kontrol edin.';
      });
    }
  }

  // LED komutunu gönderir
  Future<void> _sendLedCommand(bool turnOn) async {
    if (_statusCharacteristic == null) return;

    // "1" = AÇ, "0" = KAPAT
    String command = turnOn ? "1" : "0";

    try {
      await _statusCharacteristic!.write(utf8.encode(command));
      setState(() {
        _status = turnOn ? 'LED Açık komutu gönderildi (1)' : 'LED Kapalı komutu gönderildi (0)';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(turnOn ? 'Işık Açılıyor...' : 'Işık Kapanıyor...')),
      );
    } catch (e) {
      setState(() {
        _status = 'Gönderme Hatası: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Test Modu - ${widget.device.platformName}'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 40),
              // Eğer bağlantı hazır değilse yükleniyor göster
              if (!_isReady) const CircularProgressIndicator(),

              if (_isReady) ...[
                // AÇ BUTONU
                SizedBox(
                  width: 200,
                  height: 60,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _sendLedCommand(true),
                    icon: const Icon(Icons.flash_on),
                    label: const Text('LED AÇ', style: TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(height: 20),
                // KAPAT BUTONU
                SizedBox(
                  width: 200,
                  height: 60,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _sendLedCommand(false),
                    icon: const Icon(Icons.flash_off),
                    label: const Text('LED KAPAT', style: TextStyle(fontSize: 20)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}