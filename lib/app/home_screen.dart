import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:dispenserapp/widgets/circular_selector.dart';
import 'package:dispenserapp/services/database_service.dart'; // DeviceRole buradan geliyor
import 'package:firebase_auth/firebase_auth.dart';

class HomeScreen extends StatefulWidget {
  final String macAddress;

  const HomeScreen({super.key, required this.macAddress});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<CircularSelectorState> _circularSelectorKey = GlobalKey<CircularSelectorState>();
  final DatabaseService _databaseService = DatabaseService();
  final NotificationService _notificationService = NotificationService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _sections = [];
  bool _isLoading = true;
  bool _isRinging = false;

  // Varsayılan rol
  DeviceRole _currentRole = DeviceRole.readOnly;
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);

    final user = await _authService.getOrCreateUser();
    if (user != null) {
      _currentUserEmail = user.email;

      // Rolü veritabanından çek
      _currentRole = await _databaseService.getUserRole(widget.macAddress, user.email);
    }

    await _loadSections();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSections() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('dispenser').doc(widget.macAddress).get();
      if (!mounted) return;

      if (doc.exists && doc.data()!.containsKey('section_config')) {
        final List<dynamic> configData = doc.data()!['section_config'];
        _sections = configData.map((item) {
          final Map<String, dynamic> section = item as Map<String, dynamic>;
          final bool isActive = section['isActive'] ?? false;
          final TimeOfDay time = isActive
              ? TimeOfDay(hour: section['hour'], minute: section['minute'])
              : const TimeOfDay(hour: 8, minute: 0);

          return {
            'name': section['name'],
            'time': time,
            'isActive': isActive,
          };
        }).toList();
      } else {
        // Veri yoksa varsayılan olarak 3 bölme oluştur
        _sections = List.generate(3, (index) {
          return {
            'name': 'İlaç ${index + 1}', // "Bölme" yerine "İlaç" daha samimi olabilir
            'time': TimeOfDay(hour: (8 + 4 * index) % 24, minute: 0), // Saatleri biraz daha aralıklı yaydık
            'isActive': true,
          };
        });

        if (_canEdit()) {
          await _saveSectionConfig();
        }
      }

      // Local bildirimleri planla
      _notificationService.scheduleMedicationNotifications(_sections);

    } catch (e) {
      print("Error loading sections: $e");
    }
  }

  Future<void> _saveSectionConfig() async {
    if (!_canEdit()) return;

    final List<Map<String, dynamic>> serializableList = _sections.map((section) {
      final time = section['time'] as TimeOfDay;
      return {
        'name': section['name'],
        'hour': time.hour,
        'minute': time.minute,
        'isActive': section['isActive'] ?? false,
      };
    }).toList();

    await _databaseService.saveSectionConfig(widget.macAddress, serializableList);
    await _notificationService.scheduleMedicationNotifications(_sections);
  }

  void _updateSection(int index, Map<String, dynamic> data) {
    if (!_canEdit()) {
      _showReadOnlyWarning();
      return;
    }

    setState(() {
      _sections[index].addAll(data);
      _sections[index]['isActive'] = true;
    });
    _saveSectionConfig();
  }
  Future<void> _handleBuzzer() async {
    setState(() {
      _isRinging = !_isRinging;
    });

    // DatabaseService'e eklediğiniz fonksiyonu çağırıyoruz
    // Eğer 2. parametre true ise öttür, false ise sustur.
    await _databaseService.toggleBuzzer(widget.macAddress, _isRinging);

    // Eğer ötmeye başladıysa, 3 saniye sonra otomatik durdurma mantığı (Opsiyonel ama önerilir)
    if (_isRinging) {
      Future.delayed(const Duration(seconds: 3), () async {
        if (mounted && _isRinging) {
          setState(() {
            _isRinging = false;
          });
          await _databaseService.toggleBuzzer(widget.macAddress, false);
        }
      });
    }
  }

  bool _canEdit() {
    return _currentRole == DeviceRole.owner || _currentRole == DeviceRole.secondary;
  }

  void _showReadOnlyWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sadece İzleyici modundasınız. Değişiklik yapmak için cihaz sahibinden yetki isteyin.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }


  // --- KULLANICI YÖNETİMİ DİYALOGU (GÜNCELLENMİŞ) ---
  void _showUserManagementDialog() {
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('dispenser').doc(widget.macAddress).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final readOnlyUsers = List<String>.from(data['read_only_mails'] ?? []);
            final secondaryUsers = List<String>.from(data['secondary_mails'] ?? []);

            return AlertDialog(
              title: const Text('Erişim Yönetimi'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ekleme Kısmı
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: emailController,
                            decoration: const InputDecoration(
                              hintText: 'Kullanıcı maili...',
                              labelText: 'Yetki Ver',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          style: IconButton.styleFrom(backgroundColor: Colors.green.shade50),
                          icon: const Icon(Icons.person_add, color: Colors.green),
                          tooltip: 'Ekle',
                          onPressed: () {
                            final mail = emailController.text.trim();
                            if (mail.isNotEmpty) {
                              _databaseService.addReadOnlyUser(widget.macAddress, mail);
                              emailController.clear();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Kullanıcı Listesi", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                    ),

                    // Kullanıcı Listesi
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (readOnlyUsers.isEmpty && secondaryUsers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text("Henüz başka kullanıcı yok.", style: TextStyle(fontStyle: FontStyle.italic)),
                            ),

                          // 1. İzleyiciler (Yönetici Yap butonu var)
                          ...readOnlyUsers.map((email) => Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              leading: const Icon(Icons.remove_red_eye, color: Colors.grey),
                              title: Text(email, style: const TextStyle(fontSize: 13)),
                              subtitle: const Text("İzleyici"),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_upward_rounded, color: Colors.green),
                                    tooltip: 'Yönetici Yap',
                                    onPressed: () async {
                                      await _databaseService.promoteToSecondary(widget.macAddress, email);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    tooltip: 'Sil',
                                    onPressed: () async {
                                      await _databaseService.removeUser(widget.macAddress, email);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          )),

                          // 2. Yöneticiler (İzleyici Yap butonu EKLENDİ)
                          ...secondaryUsers.map((email) => Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: Colors.blue.shade50,
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              leading: const Icon(Icons.verified_user, color: Colors.blue),
                              title: Text(email, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              subtitle: const Text("Yönetici"),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // --- YENİ EKLENEN BUTON: AŞAĞI OK ---
                                  IconButton(
                                    icon: const Icon(Icons.arrow_downward_rounded, color: Colors.orange),
                                    tooltip: 'İzleyici Yap (Rütbe Düşür)',
                                    onPressed: () async {
                                      await _databaseService.demoteToReadOnly(widget.macAddress, email);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    tooltip: 'Sil',
                                    onPressed: () async {
                                      await _databaseService.removeUser(widget.macAddress, email);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Kapat'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- ALARM AYARLARI ---
  Future<void> _showNotificationSettingsDialog() async {
    final settings = await _notificationService.getNotificationSettings();
    bool notificationsEnabled = settings['enabled'];
    int offset = settings['offset'];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {
            return AlertDialog(
              title: const Text('Alarm Ayarları'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_canEdit())
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        "Not: Bu ayarlar sadece sizin telefonunuzu etkiler. Cihaz saatlerini değiştiremezsiniz.",
                        style: TextStyle(fontSize: 12, color: Colors.orange, fontStyle: FontStyle.italic),
                      ),
                    ),
                  SwitchListTile(
                    title: const Text('Alarmları Aktif Et'),
                    value: notificationsEnabled,
                    onChanged: (value) {
                      setStateInDialog(() {
                        notificationsEnabled = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('İlaç saatinden ne kadar önce haber verilsin?'),
                  DropdownButton<int>(
                    value: offset,
                    items: [0, 5, 10, 15, 30].map<DropdownMenuItem<int>>((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text(value == 0 ? 'Tam zamanında' : '$value dakika önce'),
                      );
                    }).toList(),
                    onChanged: notificationsEnabled
                        ? (int? newValue) {
                      setStateInDialog(() {
                        offset = newValue!;
                      });
                    }
                        : null,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _notificationService.saveNotificationSettings(
                      enabled: notificationsEnabled,
                      offset: offset,
                    );
                    await _notificationService.scheduleMedicationNotifications(_sections);
                    if (mounted) Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Alarm ayarları kaydedildi.')),
                    );
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isReadOnly = !_canEdit();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihaz Ayarları'),
        actions: [
          // Sadece Owner görebilir
          if (_currentRole == DeviceRole.owner)
            IconButton(
              icon: const Icon(Icons.manage_accounts_rounded),
              tooltip: 'Erişim Yönetimi',
              onPressed: _showUserManagementDialog,
            ),
          IconButton(
            icon: const Icon(Icons.alarm_add_rounded, size: 30),
            tooltip: 'Alarm Ayarları',
            onPressed: _showNotificationSettingsDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (isReadOnly)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "İzleyici Modu: İlaç saatlerini sadece cihaz sahibi değiştirebilir. Siz sadece bildirim alabilirsiniz.",
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.w600
                          ),
                        ),
                      ),
                    ],
                  ),
                )

              else
                Card(
                  color: colorScheme.primaryContainer.withOpacity(0.6),
                  margin: const EdgeInsets.only(bottom: 30),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        Icon(Icons.tips_and_updates_outlined, color: colorScheme.onPrimaryContainer, size: 28),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Text(
                            'İlaç saatlerinizi dairesel seçiciden veya listeden kolayca ayarlayın.',
                            style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              Center(
                child: Container(
                  height: MediaQuery.of(context).size.width * 0.85,
                  width: MediaQuery.of(context).size.width * 0.85,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.15),
                        spreadRadius: 5,
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: AbsorbPointer(
                    absorbing: isReadOnly,
                    child: CircularSelector(
                      key: _circularSelectorKey,
                      sections: _sections,
                      onUpdate: _updateSection,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),
              // Sadece yetkili kişiler (Owner/Secondary) buzzerı çaldırabilsin
              if (!isReadOnly)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Center(
                    child: SizedBox(
                      width: 200, // Buton genişliği
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _handleBuzzer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isRinging ? Colors.red : colorScheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        icon: Icon(_isRinging ? Icons.stop_circle_outlined : Icons.wifi_tethering),
                        label: Text(
                          _isRinging ? "Sesi Durdur" : "Cihazı Bul / Öttür",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  'Planlanmış İlaçlar',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 15),

              ..._sections.asMap().entries.map((entry) {
                int index = entry.key;
                Map<String, dynamic> section = entry.value;
                TimeOfDay time = section['time'] as TimeOfDay;
                bool isActive = section['isActive'] ?? false;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 7),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: isReadOnly ? Colors.grey.shade200 : colorScheme.primary.withOpacity(0.1),
                      child: Icon(
                          Icons.medication_liquid_rounded,
                          color: isReadOnly ? Colors.grey : colorScheme.primary,
                          size: 28
                      ),
                    ),
                    title: Text(
                      section['name'],
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 19),
                    ),
                    subtitle: Text(
                      isActive ? 'Saat: ${time.format(context)}' : 'Pasif',
                      style: theme.textTheme.bodyMedium?.copyWith(color: isActive ? colorScheme.onSurfaceVariant : Colors.grey),
                    ),
                    trailing: isReadOnly
                        ? const Tooltip(
                      message: "Değiştirme yetkiniz yok",
                      child: Icon(Icons.lock, color: Colors.grey),
                    )
                        : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: isActive,
                          onChanged: (bool value) {
                            setState(() {
                              _sections[index]['isActive'] = value;
                            });
                            _saveSectionConfig();
                          },
                          activeColor: colorScheme.primary,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Düzenle',
                          onPressed: () {
                            _circularSelectorKey.currentState?.showEditDialog(index);
                          },
                        ),
                      ],
                    ),
                    onTap: isReadOnly
                        ? () => _showReadOnlyWarning()
                        : () {
                      _circularSelectorKey.currentState?.showEditDialog(index);
                    },
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }
}