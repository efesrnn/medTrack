import 'dart:io';

import 'package:dispenserapp/features/ble_provisioning/ble_constants.dart';
import 'package:dispenserapp/features/ble_provisioning/wifi_credentials_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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
    _connectedDevice?.disconnect();
    super.dispose();
  }

  Future<void> _requestPermissionsAndScan() async {
    // Request Bluetooth permissions
    if (Platform.isAndroid) {
      var bluetoothScanStatus = await Permission.bluetoothScan.request();
      var bluetoothConnectStatus = await Permission.bluetoothConnect.request();
      var locationStatus = await Permission.location.request();

      if (bluetoothScanStatus.isGranted &&
          bluetoothConnectStatus.isGranted &&
          locationStatus.isGranted) {
        _startScan();
      } else {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bluetooth ve konum izinleri cihaz taraması için gereklidir.')),
          );
        }
      }
    } else {
       // On iOS, permissions are handled by the system dialog when you start scanning.
      _startScan();
    }
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
       if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bluetooth taraması başlatılamadı: $e')),
        );
       }
    }

    FlutterBluePlus.scanResults.listen((results) {
      final filteredResults = results
          .where((r) => r.device.platformName.isNotEmpty)
          .toList();
      if (mounted) {
        setState(() {
          _scanResults = filteredResults;
        });
      }
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
    try {
      await device.connect();
      if (!mounted) return;
      setState(() {
        _connectedDevice = device;
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WifiCredentialsScreen(device: device),
        ),
      ).then((_) {
         // After returning from the credentials screen, disconnect
        device.disconnect();
        setState(() {
          _connectedDevice = null;
        });
      });
    } catch (e) {
       if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cihaza bağlanılamadı: $e')),
        );
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_isScanning)
            const LinearProgressIndicator(),
          Expanded(
            child: _scanResults.isEmpty && !_isScanning
                ? const Center(
                    child: Text('Yakında cihaz bulunamadı.\nİzinleri kontrol edin veya taramayı yeniden başlatın.', textAlign: TextAlign.center,),
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
        onPressed: _isScanning ? _stopScan : _requestPermissionsAndScan,
        child: Icon(_isScanning ? Icons.stop : Icons.search),
      ),
    );
  }
}
