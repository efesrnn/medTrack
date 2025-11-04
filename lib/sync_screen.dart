import 'package:dispenserapp/ble_constants.dart';
import 'package:dispenserapp/wifi_credentials_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
    _startScan();
  }

  @override
  void dispose() {
    _stopScan();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [SERVICE_UUID],
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      // Handle scan error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bluetooth taraması başlatılamadı: $e')),
      );
    }

    FlutterBluePlus.scanResults.listen((results) {
      final filteredResults = results
          .where((r) => r.device.platformName.isNotEmpty)
          .toList();
      setState(() {
        _scanResults = filteredResults;
      });
    });

    await Future.delayed(const Duration(seconds: 15));
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _stopScan();
    await device.connect();
    setState(() {
      _connectedDevice = device;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WifiCredentialsScreen(device: device),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihaz Kurulumu'),
      ),
      body: Column(
        children: [
          if (_isScanning)
            const LinearProgressIndicator(),
          Expanded(
            child: _scanResults.isEmpty && !_isScanning
                ? const Center(
                    child: Text('Yakında cihaz bulunamadı.'),
                  )
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final result = _scanResults[index];
                      return ListTile(
                        title: Text(result.device.platformName),
                        subtitle: Text(result.device.remoteId.toString()),
                        onTap: () => _connectToDevice(result.device),
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
