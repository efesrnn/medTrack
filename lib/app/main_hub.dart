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
  final DatabaseService _dbService = DatabaseService();
  int _selectedIndex = 0;

  // Sürükle Bırak Modu Aktif mi?
  bool _isDragMode = false;

  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _authService.getOrCreateUser().then((user) {
      if (user != null) {
        setState(() {
          _currentUser = user;
        });
      }
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _isDragMode = false; // Sayfa değişince modu kapat
    });
  }

  // Modu değiştiren fonksiyon
  void _toggleDragMode(bool value) {
    setState(() {
      _isDragMode = value;
    });
    if (value) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Düzenleme modu açıldı. Cihazları sürükleyebilirsiniz."),
            duration: Duration(seconds: 1),
          )
      );
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    final newUser = await _authService.getOrCreateUser();
    setState(() {
      _currentUser = newUser;
    });
    Navigator.of(context).pop();
  }

  void _showProfileMenu() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  backgroundImage: _currentUser?.photoURL != null
                      ? NetworkImage(_currentUser!.photoURL!)
                      : null,
                  child: _currentUser?.photoURL == null
                      ? Text(
                    _currentUser?.displayName != null
                        ? _currentUser!.displayName![0].toUpperCase()
                        : "U",
                    style: const TextStyle(fontSize: 30, color: Colors.white),
                  )
                      : null,
                ),
                const SizedBox(height: 16),
                const Text("Logged as", style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text(
                  _currentUser?.displayName ?? "Kullanıcı",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text("Çıkış Yap"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.errorContainer,
                      foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateFolderDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Yeni Oda Oluştur"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Örn: 102 Nolu Oda"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty && _currentUser != null) {
                _dbService.createGroup(_currentUser!.uid, controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text("Oluştur"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget currentScreen;
    if (_selectedIndex == 0) {
      currentScreen = DeviceListScreen(
        isDragMode: _isDragMode,
        onModeChanged: _toggleDragMode,
      );
    } else if (_selectedIndex == 1) {
      currentScreen = const SyncScreen();
    } else {
      currentScreen = const RelativesScreen();
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: colorScheme.onSurface,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.settings, size: 28),
          onPressed: _showProfileMenu,
        ),
        title: Text(
          _selectedIndex == 0
              ? (_isDragMode ? 'Düzenleme Modu' : 'Cihazlarım')
              : (_selectedIndex == 1 ? 'Senkronizasyon' : 'Yakınlarım'),
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              // --- DEĞİŞİKLİK BURADA YAPILDI ---
              icon: Icon(
                _isDragMode ? Icons.close : Icons.menu, // Drag modu açıksa Çarpı (Close), kapalıysa Menü (3 çizgi)
                size: 30,
                color: _isDragMode ? colorScheme.error : colorScheme.onSurface, // Açıkken kırmızımsı, kapalıyken normal renk
              ),
              tooltip: _isDragMode ? 'Düzenlemeyi Bitir' : 'Düzenle / Taşı',
              onPressed: () => _toggleDragMode(!_isDragMode),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: currentScreen,
      floatingActionButton: (_selectedIndex == 0 && _isDragMode)
          ? FloatingActionButton.extended(
        onPressed: _showCreateFolderDialog,
        icon: const Icon(Icons.create_new_folder),
        label: const Text("Oda Ekle"),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.devices_other_rounded), label: 'Cihazlarım'),
          BottomNavigationBarItem(icon: Icon(Icons.sync_rounded), label: 'Senkronizasyon'),
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'Yakınlarım'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: colorScheme.primary,
        onTap: _onItemTapped,
      ),
    );
  }
}