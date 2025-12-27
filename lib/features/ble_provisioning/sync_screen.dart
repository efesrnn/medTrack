import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'wifi_credentials_screen.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  BluetoothDevice? _connectedDevice;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndScan();
  }

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }

  Future<void> _requestPermissionsAndScan() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      if (statuses[Permission.bluetoothScan]!.isGranted &&
          statuses[Permission.bluetoothConnect]!.isGranted) {
        _startScan();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bluetooth izinleri gerekli.')),
          );
        }
      }
    } else {
      _startScan();
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _scanResults = [];
      _isScanning = true;
    });

    try {
      // --- DEĞİŞİKLİK BURADA ---
      // 'withServices' filtresini kaldırdık. Artık etraftaki HER ŞEYİ tarayacak.
      // Bu sayede UUID uyuşmazlığı olsa bile cihazı görebileceğiz.
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint("Tarama hatası: $e");
    }

    // Sonuçları Dinle
    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          // --- İSİM FİLTRESİ ---
          // Sadece isminde "MEDTRACK" geçen cihazları listeye alıyoruz.
          // Büyük/Küçük harf duyarlılığını kaldırmak için .toUpperCase() kullandık.
          _scanResults = results
              .where((r) => r.device.platformName.toUpperCase().contains("MEDTRACK"))
              .toList();
        });
      }
    });

    await Future.delayed(const Duration(seconds: 15));
    _stopScan();
  }

  void _stopScan() {
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
    FlutterBluePlus.stopScan();
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _stopScan();
    try {
      await device.connect();
      if (!mounted) return;

      setState(() {
        _connectedDevice = device;
      });

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WifiCredentialsScreen(device: device),
        ),
      );

      await device.disconnect();
      setState(() {
        _connectedDevice = null;
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bağlantı hatası: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Cihaz Ara")),
      body: Column(
        children: [
          if (_isScanning) const LinearProgressIndicator(),
          Expanded(
            child: _scanResults.isEmpty
                ? Center(
              child: Text(
                _isScanning
                    ? 'MedTrack cihazları aranıyor...'
                    : 'Cihaz bulunamadı.\nLütfen cihazın fişe takılı olduğundan emin olun.',
                textAlign: TextAlign.center,
              ),
            )
                : ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (context, index) {
                final result = _scanResults[index];
                // Sinyal gücünü (RSSI) de gösterelim
                final rssi = result.rssi;

                return ListTile(
                  leading: const Icon(Icons.bluetooth_audio, size: 30, color: Colors.blue),
                  title: Text(
                      result.device.platformName,
                      style: const TextStyle(fontWeight: FontWeight.bold)
                  ),
                  subtitle: Text("ID: ${result.device.remoteId}\nSinyal: $rssi dBm"),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white
                    ),
                    child: const Text("Kur"),
                    onPressed: () => _connectToDevice(result.device),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? _stopScan : _startScan,
        child: Icon(_isScanning ? Icons.stop : Icons.search),
      ),
    );
  }
}