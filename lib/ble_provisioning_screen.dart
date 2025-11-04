import 'package:dispenserapp/ble_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleProvisioningScreen extends StatefulWidget {
  const BleProvisioningScreen({super.key});

  @override
  State<BleProvisioningScreen> createState() => _BleProvisioningScreenState();
}

class _BleProvisioningScreenState extends State<BleProvisioningScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _stopScan();
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
    }

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results;
      });
    });

    setState(() {
      _isScanning = false;
    });
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
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
            child: ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (context, index) {
                final result = _scanResults[index];
                return ListTile(
                  title: Text(result.device.platformName.isNotEmpty
                      ? result.device.platformName
                      : 'Bilinmeyen Cihaz'),
                  subtitle: Text(result.device.remoteId.toString()),
                  onTap: () {
                    // TODO: Connect to the selected device
                  },
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
