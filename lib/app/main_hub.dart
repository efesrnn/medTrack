import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dispenserapp/app/home_screen.dart';
import 'package:dispenserapp/features/ble_provisioning/sync_screen.dart';
import 'package:dispenserapp/app/relatives_screen.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:flutter/material.dart';

class MainHub extends StatefulWidget {
  const MainHub({super.key});

  @override
  State<MainHub> createState() => _MainHubState();
}

class _MainHubState extends State<MainHub> {
  int _selectedIndex = 0;

  // We define the screens here, but the primary screen will handle its own state.
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

/// A screen that handles user authentication and then lists their devices.
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  late Future<String?> _initFuture;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    // Start the user authentication process when the screen is first built.
    _initFuture = _authService.getOrCreateUser();
  }

  void _retryLogin() {
    setState(() {
      // Re-run the authentication process
      _initFuture = _authService.getOrCreateUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _initFuture,
      builder: (context, snapshot) {
        // Case 1: Waiting for authentication
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Case 2: Authentication failed or was cancelled
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Giriş başarısız oldu."),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _retryLogin,
                  child: const Text("Tekrar Dene"),
                ),
              ],
            ),
          );
        }

        // Case 3: Authentication successful, show the device list
        final uid = snapshot.data!;
        return _buildDeviceList(uid);
      },
    );
  }

  Widget _buildDeviceList(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text("Kullanıcı profili yüklenemedi."));
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final List<dynamic> ownedDispensers = userData['owned_dispensers'] ?? [];

        if (ownedDispensers.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                "Henüz bir cihazınız yok. Lütfen 'Senkronizasyon' sekmesinden yeni bir cihaz ekleyin.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: ownedDispensers.length,
          itemBuilder: (context, index) {
            final macAddress = ownedDispensers[index] as String;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: ListTile(
                leading: const Icon(Icons.memory_rounded, size: 28),
                title: const Text("Akıllı İlaç Kutusu"),
                subtitle: Text(macAddress),
                trailing: const Icon(Icons.arrow_forward_ios_rounded),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(macAddress: macAddress),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
