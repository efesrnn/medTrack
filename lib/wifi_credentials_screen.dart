import 'dart:convert';

import 'package:dispenserapp/auth_service.dart';
import 'package:dispenserapp/ble_constants.dart';
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
  final AuthService _authService = AuthService();
  bool _isSending = false;

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCredentials() async {
    if (_ssidController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SSID ve şifre boş olamaz.')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final services = await widget.device.discoverServices();
      final service = services.firstWhere((s) => s.uuid == SERVICE_UUID);

      final ssidCharacteristic = service.characteristics
          .firstWhere((c) => c.uuid == WIFI_SSID_CHARACTERISTIC_UUID);
      final passwordCharacteristic = service.characteristics
          .firstWhere((c) => c.uuid == WIFI_PASSWORD_CHARACTERISTIC_UUID);
      final uidCharacteristic = service.characteristics
          .firstWhere((c) => c.uuid == USER_UID_CHARACTERISTIC_UUID);
      final statusCharacteristic = service.characteristics
          .firstWhere((c) => c.uuid == STATUS_CHARACTERISTIC_UUID);

      await ssidCharacteristic.write(utf8.encode(_ssidController.text));
      await passwordCharacteristic.write(utf8.encode(_passwordController.text));

      final uid = await _authService.getOrCreateUser();
      if (uid != null) {
        await uidCharacteristic.write(utf8.encode(uid));
      }

      // Listen for status updates
      await statusCharacteristic.setNotifyValue(true);
      statusCharacteristic.value.listen((value) {
        final status = utf8.decode(value);
        // TODO: Handle status updates (WIFI_OK, WIFI_FAIL, etc.)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Durum: $status')),
        );
        if (status == 'FIREBASE_OK') {
          Navigator.pop(context); // Go back to the previous screen
          Navigator.pop(context); // Go back to the home screen
        }
      });

      // Send the 'SAVE' command
      await statusCharacteristic.write(utf8.encode('SAVE'));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Veri gönderme hatası: $e')),
      );
    }

    setState(() {
      _isSending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Wi-Fi Bilgileri - ${widget.device.platformName}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(labelText: 'Wi-Fi Adı (SSID)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Wi-Fi Şifresi'),
              obscureText: true,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSending ? null : _sendCredentials,
              child: _isSending
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Cihaza Gönder'),
            ),
          ],
        ),
      ),
    );
  }
}
