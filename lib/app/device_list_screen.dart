import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'home_screen.dart';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  late Future<String?> _initFuture;
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  // 1. Durum değişkeni eklendi: Görselin yüklenip yüklenmediğini tutar
  bool _isImagePrecached = false;

  @override
  void initState() {
    super.initState();
    _initFuture = _authService.getOrCreateUser();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Yalnızca bir kere görsel önbelleğe alma işlemi yapılmasını sağlıyoruz
    if (!_isImagePrecached) {
      // 2. precacheImage'ın Future sonucunu bekliyoruz
      final image = const AssetImage('assets/dispenser_icon.png');
      precacheImage(image, context).then((_) {
        // Görsel başarılı bir şekilde önbelleğe alındığında durumu güncelliyoruz
        if (mounted) {
          setState(() {
            _isImagePrecached = true;
          });
        }
      }).catchError((error) {
        // Hata durumunda da devam etme kararı alabiliriz, burada sadece logladık
        debugPrint("Görsel yükleme hatası: $error");
        if (mounted) {
          setState(() {
            _isImagePrecached = true; // Hata olsa bile ilerlemek isteyebiliriz
          });
        }
      });
    }
  }

  void _retryLogin() {
    setState(() {
      _initFuture = _authService.getOrCreateUser();
      // Tekrar denemede görseli de tekrar yüklemeyi tetikleyebiliriz
      _isImagePrecached = false;
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
    // 3. Görsel yüklenmediyse önce CircularProgressIndicator gösteriyoruz
    if (!_isImagePrecached) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            // Estetik bir renk ekleyebilirsiniz
            color: Colors.deepPurple,
          ),
        ),
      );
    }

    // Görsel yüklendikten sonra mevcut FutureBuilder mantığı devam ediyor
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
          return CircularProgressIndicator(
            color: Colors.deepPurple,
          );
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
          padding: const EdgeInsets.only(top: 20.0),
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
                  margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  elevation: 9,
                  shadowColor: Colors.black38,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => HomeScreen(macAddress: macAddress)),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: Image.asset(
                              'assets/dispenser_icon.png',
                              width: 110,
                              height: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  deviceName,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'MAC Adresi: $macAddress',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 30, color: Colors.black),
                            tooltip: 'Cihaz adını düzenle',
                            onPressed: () => _showEditNameDialog(macAddress, deviceName),
                          ),
                        ],
                      ),
                    ),
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