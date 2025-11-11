import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dispenserapp/app/home_screen.dart';
import 'package:dispenserapp/features/ble_provisioning/sync_screen.dart';
import 'package:dispenserapp/app/relatives_screen.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:flutter/material.dart';

import 'device_list_screen.dart';

class MainHub extends StatefulWidget {
  const MainHub({super.key});

  @override
  State<MainHub> createState() => _MainHubState();
}

class _MainHubState extends State<MainHub> {
  final AuthService _authService = AuthService();
  int _selectedIndex = 0;
  Key _deviceListScreenKey = UniqueKey();

  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _widgetOptions = <Widget>[
      DeviceListScreen(key: _deviceListScreenKey),
      const SyncScreen(),
      const RelativesScreen(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _signOut() async {
    final bool? shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emin misiniz?'),
        content: const Text('Çıkış yapmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hayır'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      await _authService.signOut();
      final newUser = await _authService.getOrCreateUser();
      if (newUser != null) {
        setState(() {
          _deviceListScreenKey = UniqueKey();
          _widgetOptions[0] = DeviceListScreen(key: _deviceListScreenKey);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihazlarım'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
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
