import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class RelativesScreen extends StatefulWidget {
  const RelativesScreen({super.key});

  @override
  State<RelativesScreen> createState() => _RelativesScreenState();
}

class _RelativesScreenState extends State<RelativesScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  String? _currentUid;
  String? _currentEmail;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  Future<void> _initUser() async {
    final user = await _authService.getOrCreateUser();
    if (user != null) {
      setState(() {
        _currentUid = user.uid;
        _currentEmail = user.email;
        _isLoading = false;
      });
    }
  }

  // Takma İsim Düzenleme Diyalogu
  void _showEditNicknameDialog(String email, String currentNickname) {
    final controller = TextEditingController(text: currentNickname);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("edit_nickname".tr()), // "Takma İsim Düzenle"
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("nickname_hint".tr(), style: const TextStyle(fontSize: 12, color: Colors.grey)), // "Bu kişiyi nasıl görmek istersiniz?"
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "father_mom_etc".tr(), // "Örn: Babam, Bakıcı Ayşe..."
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("cancel".tr()),
          ),
          ElevatedButton(
            onPressed: () {
              if (_currentUid != null) {
                _dbService.updateRelativeNickname(_currentUid!, email, controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: Text("save".tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_currentUid == null) return const Center(child: Text("Giriş hatası"));

    return Scaffold(
      backgroundColor: Colors.transparent, // MainHub'dan gelen arka plan
      body: StreamBuilder<DocumentSnapshot>(
        // 1. Kendi kullanıcı verimizi dinliyoruz (Nicknameleri almak için)
        stream: FirebaseFirestore.instance.collection('users').doc(_currentUid).snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());

          // Nickname haritasını al
          Map<String, dynamic> nicknamesMap = {};
          try {
            nicknamesMap = userSnapshot.data!.get('relatives_nicknames') as Map<String, dynamic>;
          } catch (e) {
            // Alan yoksa boş kalır
          }

          // 2. Yakınların listesini çekiyoruz (FutureBuilder)
          // Not: Bunu Stream yapmak çok maliyetli olur, o yüzden Future + RefreshIndicator kullanıyoruz.
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _dbService.getRelativesInfo(_currentUid!, _currentEmail!),
            builder: (context, relativesSnapshot) {
              if (relativesSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final relatives = relativesSnapshot.data ?? [];

              if (relatives.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.people_outline_rounded, size: 60, color: Colors.blue.shade200),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "no_relatives_found".tr(), // "Henüz yakınınız yok"
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          "no_relatives_desc".tr(), // "Cihaz paylaştığınız kişiler burada görünür."
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.blueGrey.shade400),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {}); // Sayfayı yenile
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: relatives.length,
                  itemBuilder: (context, index) {
                    final person = relatives[index];
                    final String email = person['email'];
                    final String rawName = person['displayName'];
                    final String photoUrl = person['photoURL'];

                    // Nickname var mı kontrol et (Key'deki noktayı _dot_ yapmıştık)
                    String safeKey = email.replaceAll('.', '_dot_');
                    String? nickname = nicknamesMap[safeKey];

                    // Görünen İsim Mantığı: Nickname > Gerçek İsim > Email
                    String displayName = (nickname != null && nickname.isNotEmpty)
                        ? nickname
                        : (rawName.isNotEmpty ? rawName : email.split('@')[0]);

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            // --- Profil Resmi ---
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF1D8AD6).withOpacity(0.3), width: 2),
                              ),
                              child: CircleAvatar(
                                radius: 26,
                                backgroundColor: const Color(0xFF1D8AD6),
                                backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                                child: (photoUrl.isEmpty)
                                    ? Text(
                                  displayName.isNotEmpty ? displayName[0].toUpperCase() : "?",
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                                )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),

                            // --- İsim ve Email ---
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: Color(0xFF0F5191), // Derin Mavi
                                    ),
                                  ),
                                  if (nickname != null && nickname.isNotEmpty && rawName.isNotEmpty)
                                    Text(
                                      "($rawName)", // Nickname varsa parantez içinde gerçek adı
                                      style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade400),
                                    ),
                                  Text(
                                    email,
                                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade300),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),

                            // --- Düzenle Butonu ---
                            IconButton(
                              onPressed: () => _showEditNicknameDialog(email, nickname ?? ""),
                              icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF36C0A6)), // Turkuaz
                              tooltip: "edit_nickname".tr(),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF36C0A6).withOpacity(0.1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}