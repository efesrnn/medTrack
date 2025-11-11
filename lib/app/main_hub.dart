import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dispenserapp/app/home_screen.dart';
import 'package:dispenserapp/features/ble_provisioning/sync_screen.dart';
import 'package:dispenserapp/app/relatives_screen.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:flutter/material.dart';

class MainHub extends StatefulWidget {
  const MainHub({super.key});

  @override
  State<MainHub> createState() => _MainHubState();
}

class _MainHubState extends State<MainHub> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    DeviceListScreen(),
    SyncScreen(),
    RelativesScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihazlarım'),
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.devices_other_rounded),
            label: 'Cihazlarım',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sync_rounded),
            label: 'Senkronizasyon',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_alt_rounded),
            label: 'Yakınlarım',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        showUnselectedLabels: true,
      ),
    );
  }
}

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  late Future<String?> _initFuture;
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  @override
  void initState() {
    super.initState();
    _initFuture = _authService.getOrCreateUser();
  }

  void _retryLogin() {
    setState(() {
      _initFuture = _authService.getOrCreateUser();
    });
  }

  void _showEditNameDialog(String macAddress, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Cihaz Adını Düzenle"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "Yeni cihaz adı"),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("İptal"),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  _dbService.updateDeviceName(macAddress, newName);
                }
                Navigator.of(context).pop();
              },
              child: const Text("Kaydet"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Giriş başarısız oldu."),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _retryLogin, child: const Text("Tekrar Dene")),
              ],
            ),
          );
        }

        final uid = snapshot.data!;
        return _buildDeviceList(uid);
      },
    );
  }

  Widget _buildDeviceList(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
          return const Center(child: Text("Kullanıcı profili yüklenemedi."));
        }

        final userData = userSnapshot.data!.data() as Map<String, dynamic>;
        final List<dynamic> ownedDispensers = userData['owned_dispensers'] ?? [];

        if (ownedDispensers.isEmpty) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text("Henüz bir cihazınız yok.", textAlign: TextAlign.center)));
        }

        return ListView.builder(
          itemCount: ownedDispensers.length,
          itemBuilder: (context, index) {
            final macAddress = ownedDispensers[index] as String;
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('dispenser').doc(macAddress).snapshots(),
              builder: (context, deviceSnapshot) {
                if (!deviceSnapshot.hasData || !deviceSnapshot.data!.exists) {
                  return Card(margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: ListTile(title: Text(macAddress), subtitle: const Text("Cihaz bilgisi yükleniyor...")));
                }

                final deviceData = deviceSnapshot.data!.data() as Map<String, dynamic>;
                final deviceName = deviceData['device_name'] as String? ?? "Akıllı İlaç Kutusu";

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: ListTile(
                    leading: const Icon(Icons.memory_rounded, size: 28),
                    title: Text(deviceName),
                    subtitle: Text(macAddress),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showEditNameDialog(macAddress, deviceName),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => HomeScreen(macAddress: macAddress)),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
