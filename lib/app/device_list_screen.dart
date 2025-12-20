import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'home_screen.dart';

class DeviceListScreen extends StatefulWidget {
  final bool isDragMode;
  final Function(bool) onModeChanged;

  const DeviceListScreen({
    super.key,
    required this.isDragMode,
    required this.onModeChanged,
  });

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  late Future<AppUser?> _initAndPrecacheFuture;
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      _initAndPrecacheFuture = _initialize();
    }
  }

  Future<AppUser?> _initialize() async {
    final results = await Future.wait([
      _authService.getOrCreateUser(),
      precacheImage(const AssetImage('assets/dispenser_icon.png'), context),
    ]);
    return results[0] as AppUser?;
  }

  void _retryLogin() {
    setState(() {
      _initAndPrecacheFuture = _initialize();
    });
  }

  // --- Yardımcı Diyaloglar ---
  void _showAddDeviceDialog(String uid, String userEmail) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manuel Cihaz Ekle'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.visiblePassword,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-fA-F0-9]')),
            MacAddressInputFormatter(),
            LengthLimitingTextInputFormatter(17),
          ],
          decoration: const InputDecoration(
            labelText: 'MAC Adresi',
            hintText: 'AA:BB:CC:11:22:33',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () async {
              final mac = controller.text.trim();
              if (mac.length == 17) {
                if (userEmail.isEmpty) return;
                final result = await _dbService.addDeviceManually(uid, userEmail, mac);
                if (!mounted) return;
                Navigator.pop(context);
                if (result == 'success') {
                  await _dbService.updateUserDeviceList(uid, userEmail);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz başarıyla eklendi!')));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  void _showEditNameDialog(String macAddress, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cihaz Adını Düzenle"),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) _dbService.updateDeviceName(macAddress, controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text("Kaydet"),
          ),
        ],
      ),
    );
  }

  void _showRenameGroupDialog(String uid, String groupId, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Oda İsmini Düzenle"),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) _dbService.renameGroup(uid, groupId, controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text("Kaydet"),
          )
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(String uid, String groupId) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Odayı Sil"),
        content: const Text("Bu odayı silmek istediğinize emin misiniz? Cihazlar silinmez, ana listeye döner."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İptal")),
          TextButton(onPressed: () {
            _dbService.deleteGroup(uid, groupId);
            Navigator.pop(c);
          }, child: const Text("Sil", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // YENİ: Cihazı listeden gizleme onayı
  void _showHideDeviceDialog(String uid, String deviceId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cihazı Gizle"),
        content: const Text("Bu cihaz listenizden kaldırılacak ancak yetkileriniz saklı kalacaktır. Tekrar eklemek için '+' butonunu kullanabilirsiniz."),
        actions: [
          TextButton(child: const Text("İptal"), onPressed: () => Navigator.pop(ctx)),
          TextButton(
            child: const Text("Kaldır", style: TextStyle(color: Colors.red)),
            onPressed: () {
              _dbService.hideDevice(uid, deviceId);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _initAndPrecacheFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
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

        final userData = snapshot.data!;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: _buildDeviceList(userData.uid),
          floatingActionButton: !widget.isDragMode
              ? FloatingActionButton(
            onPressed: () => _showAddDeviceDialog(userData.uid, userData.email ?? ''),
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(Icons.add, color: Colors.white),
            tooltip: 'Manuel Cihaz Ekle',
          )
              : null,
        );
      },
    );
  }

  Widget _buildDeviceList(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData || !userSnapshot.data!.exists) return const CircularProgressIndicator();

        final userData = userSnapshot.data!.data() as Map<String, dynamic>;

        // GÖRÜNMEZ CİHAZLARI FİLTRELEME
        final List<dynamic> unvisibleList = userData['unvisible_devices'] ?? [];
        bool isVisible(dynamic mac) => !unvisibleList.contains(mac.toString());

        // Listeleri filtreleyerek alıyoruz
        final List<dynamic> owned = (userData['owned_dispensers'] ?? []).where(isVisible).toList();
        final List<dynamic> secondary = (userData['secondary_dispensers'] ?? []).where(isVisible).toList();
        final List<dynamic> readOnly = (userData['read_only_dispensers'] ?? []).where(isVisible).toList();
        final List<dynamic> deviceGroups = userData['device_groups'] ?? [];

        final List<Map<String, dynamic>> allDevices = [];
        for (var mac in owned) allDevices.add({'mac': mac, 'role': 'owner'});
        for (var mac in secondary) if (!allDevices.any((d) => d['mac'] == mac)) allDevices.add({'mac': mac, 'role': 'secondary'});
        for (var mac in readOnly) if (!allDevices.any((d) => d['mac'] == mac)) allDevices.add({'mac': mac, 'role': 'readOnly'});

        // Filtrelenmiş listeye göre boş durumu kontrolü
        if (allDevices.isEmpty && deviceGroups.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(24.0), child: Text("Henüz bir cihazınız yok.", textAlign: TextAlign.center)));
        }

        Set<String> groupedMacs = {};
        for (var group in deviceGroups) {
          List<dynamic> devices = group['devices'] ?? [];
          for (var d in devices) groupedMacs.add(d.toString());
        }

        List<Map<String, dynamic>> ungroupedDevices = allDevices
            .where((device) => !groupedMacs.contains(device['mac']))
            .toList();

        // ANA LİSTE DRAG TARGET (BOŞLUĞA BIRAKMA ALANI)
        return DragTarget<String>(
          onWillAccept: (data) => widget.isDragMode && data != null,
          onAccept: (macAddress) {
            _dbService.moveDeviceToGroup(uid, macAddress, ""); // Grubu temizle
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cihaz ana listeye alındı.")));
          },
          builder: (context, candidateData, rejectedData) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              color: candidateData.isNotEmpty
                  ? Colors.red.withOpacity(0.05)
                  : Colors.transparent,
              child: ListView(
                padding: const EdgeInsets.only(top: 20.0, bottom: 80, left: 16, right: 16),
                children: [
                  // Bilgi Kartı
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    crossFadeState: widget.isDragMode ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                    firstChild: Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.touch_app, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Düzenlemek için sürükleyin. Cihazı listeden kaldırmak için sağdaki çöp kutusuna basın.",
                              style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    secondChild: const SizedBox(width: double.infinity),
                  ),

                  // KLASÖRLER
                  ...deviceGroups.map((group) => _buildGroupCard(uid, group, allDevices)).toList(),

                  const SizedBox(height: 10),

                  // DİĞER CİHAZLAR BAŞLIĞI
                  if (deviceGroups.isNotEmpty && ungroupedDevices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
                      child: Text("Diğer Cihazlar", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600, fontSize: 16)),
                    ),

                  // CİHAZLAR
                  ...ungroupedDevices.map((device) {
                    return _buildDraggableOrNormalCard(uid, device['mac'], device['role'], isInsideGroup: false);
                  }).toList(),

                  const SizedBox(height: 150),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- KLASÖR KARTI ---
  Widget _buildGroupCard(String uid, Map<String, dynamic> group, List<Map<String, dynamic>> allDevices) {
    String groupId = group['id'] ?? "";
    String groupName = group['name'];
    List<dynamic> groupMacs = group['devices'] ?? [];

    // GÖRÜNMEZLERİ BURADA DA FİLTRELEMEK GEREKİR
    // Eğer bir cihaz gruba eklenmiş ama sonradan gizlenmişse, grupta da görünmemeli.
    // Ancak üstteki allDevices zaten filtrelenmiş olduğu için,
    // allDevices içinde olmayan mac'leri göstermeyeceğiz.
    List<dynamic> visibleGroupMacs = groupMacs.where((mac) => allDevices.any((d) => d['mac'] == mac)).toList();

    Widget cardContent = Card(
      elevation: 4,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: widget.isDragMode ? Colors.blue.shade300 : Colors.grey.shade200,
          width: widget.isDragMode ? 2 : 1,
        ),
      ),
      child: InkWell(
        onLongPress: () => widget.onModeChanged(true),
        borderRadius: BorderRadius.circular(22),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: widget.isDragMode,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
              child: Icon(Icons.meeting_room_rounded, color: Colors.orange.shade800, size: 28),
            ),
            title: Text(groupName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text("${visibleGroupMacs.length} Cihaz", style: TextStyle(color: Colors.grey.shade600)),
            trailing: widget.isDragMode
                ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showRenameGroupDialog(uid, groupId, groupName),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _showDeleteConfirmDialog(uid, groupId),
                ),
              ],
            )
                : null,
            children: visibleGroupMacs.map((mac) {
              var deviceEntry = allDevices.firstWhere((d) => d['mac'] == mac, orElse: () => {'mac': mac, 'role': 'unknown'});
              return _buildDraggableOrNormalCard(uid, mac.toString(), deviceEntry['role'], isInsideGroup: true);
            }).toList(),
          ),
        ),
      ),
    );

    if (widget.isDragMode) {
      return DragTarget<String>(
        onWillAccept: (data) => data != null,
        onAccept: (macAddress) {
          _dbService.moveDeviceToGroup(uid, macAddress, groupId);
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cihaz $groupName odasına taşındı"), duration: const Duration(milliseconds: 800)));
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            tween: Tween<double>(begin: 1.0, end: isHovering ? 1.05 : 1.0),
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.transparent,
                  child: cardContent,
                ),
              );
            },
          );
        },
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: cardContent,
    );
  }

  // --- CİHAZ KARTI ---
  Widget _buildDraggableOrNormalCard(String uid, String macAddress, String role, {required bool isInsideGroup}) {
    Widget card = _buildDeviceCardUI(
      uid, // UID EKLENDİ
      macAddress,
      role,
      isInsideGroup: isInsideGroup,
      interactive: !widget.isDragMode,
      onLongPress: () {},
    );

    return LongPressDraggable<String>(
      data: macAddress,
      delay: const Duration(milliseconds: 300),
      onDragStarted: () {
        if (!widget.isDragMode) {
          widget.onModeChanged(true);
        }
      },
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          child: Card(
            elevation: 10,
            color: Colors.white.withOpacity(0.95),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.drag_indicator, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Taşınıyor: $macAddress",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      child: card,
    );
  }

  // --- CİHAZ UI ---
  Widget _buildDeviceCardUI(String uid, String macAddress, String role, // uid parametresi eklendi
          {required bool isInsideGroup, required bool interactive, required VoidCallback onLongPress}) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('dispenser').doc(macAddress).snapshots(),
      builder: (context, deviceSnapshot) {
        String deviceName = "Yükleniyor...";
        bool exists = false;

        if (deviceSnapshot.hasData && deviceSnapshot.data!.exists) {
          final data = deviceSnapshot.data!.data() as Map<String, dynamic>;
          deviceName = data['device_name'] ?? "Akıllı İlaç Kutusu";
          exists = true;
        }

        Color roleColor;
        String roleText;
        IconData roleIcon;

        if (role == 'owner') {
          roleColor = Colors.green;
          roleText = "SAHİP";
          roleIcon = Icons.verified_user;
        } else if (role == 'secondary') {
          roleColor = Colors.blue;
          roleText = "YÖNETİCİ";
          roleIcon = Icons.security;
        } else {
          roleColor = Colors.orange;
          roleText = "İZLEYİCİ";
          roleIcon = Icons.visibility;
        }

        return SizedBox(
          height: isInsideGroup ? 160 : 195,
          width: double.infinity,
          child: Card(
            margin: EdgeInsets.symmetric(
              vertical: 8,
              horizontal: isInsideGroup ? 8 : 0,
            ),
            elevation: isInsideGroup ? 2 : 6,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: Colors.black, width: 1.0),
            ),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [Color(0xFFFFD9D9), Color(0xFFFFFFFF)],
                ),
                borderRadius: BorderRadius.all(Radius.circular(22)),
              ),
              child: InkWell(
                onTap: (exists && interactive)
                    ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => HomeScreen(macAddress: macAddress)),
                  );
                }
                    : null,
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12.0),
                        child: Image.asset(
                          'assets/dispenser_icon.png',
                          width: isInsideGroup ? 70 : 90,
                          height: isInsideGroup ? 80 : 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: roleColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: roleColor.withOpacity(0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(roleIcon, size: 12, color: roleColor),
                                  const SizedBox(width: 4),
                                  Text(roleText, style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            Text(
                              deviceName.toUpperCase(),
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: isInsideGroup ? 16 : 18,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'MAC: $macAddress',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade700,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      // DÜZENLEME MODU KONTROLLERİ
                      if (widget.isDragMode)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 1. ÇÖP KUTUSU (GİZLEME)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              tooltip: "Listeden Gizle",
                              onPressed: () => _showHideDeviceDialog(uid, macAddress),
                            ),
                            // 2. SÜRÜKLEME TUTAMACI
                            const Icon(Icons.drag_indicator, color: Colors.grey),
                          ],
                        )
                      else if (role != 'readOnly' && interactive)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.black87),
                          tooltip: 'Cihaz adını düzenle',
                          onPressed: () => _showEditNameDialog(macAddress, deviceName),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MacAddressInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    text = text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 2 == 0 && nonZeroIndex != text.length) {
        buffer.write(':');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}