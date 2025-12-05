import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveSectionConfig(String macAddress, List<Map<String, dynamic>> sections) async {
    if (macAddress.isEmpty) return;

    try {
      final dispenserDoc = _firestore.collection('dispenser').doc(macAddress);
      await dispenserDoc.set({
        'section_config': sections,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving section_config to Firestore: $e');
    }
  }

  Future<void> updateDeviceName(String macAddress, String newName) async {
    if (macAddress.isEmpty || newName.isEmpty) return;

    try {
      await _firestore.collection('dispenser').doc(macAddress).update({
        'device_name': newName,
      });
    } catch (e) {
      print('Error updating device name: $e');
    }
  }

  Future<void> updateUserDeviceList(String uid, String email) async {
    if (uid.isEmpty || email.isEmpty) return;

    try {
      // Find all dispensers where owner_mail matches the user's email.
      final querySnapshot = await _firestore
          .collection('dispenser')
          .where('owner_mail', isEqualTo: email) // Corrected field name
          .get();

      // Get the MAC addresses (which are the document IDs)
      final macAddresses = querySnapshot.docs.map((doc) => doc.id).toList();

      // Save the list of MAC addresses to the user's document
      await _firestore.collection('users').doc(uid).update({
        'owned_dispensers': macAddresses,
      });

    } catch (e) {
      print('Error updating user device list: $e');
    }
  }
<<<<<<< Updated upstream
}
=======

  // Klasörü sil (İçindeki cihazlar ana listeye düşer)
  Future<void> deleteGroup(String uid, String groupId) async {
    try {
      final userDoc = _firestore.collection('users').doc(uid);
      final snapshot = await userDoc.get();

      List<dynamic> groups = List.from(snapshot.data()?['device_groups'] ?? []);
      groups.removeWhere((g) => g['id'] == groupId);

      await userDoc.update({'device_groups': groups});
    } catch (e) {
      print('Error deleting group: $e');
    }
  }

  // Klasör ismini değiştir
  Future<void> renameGroup(String uid, String groupId, String newName) async {
    try {
      final userDoc = _firestore.collection('users').doc(uid);
      final snapshot = await userDoc.get();

      List<dynamic> groups = List.from(snapshot.data()?['device_groups'] ?? []);
      var group = groups.firstWhere((g) => g['id'] == groupId, orElse: () => null);

      if (group != null) {
        group['name'] = newName;
        await userDoc.update({'device_groups': groups});
      }
    } catch (e) {
      print('Error renaming group: $e');
    }
  }

  // Cihazı bir klasöre taşı (Sürükle-Bırak işlemi için)
  Future<void> moveDeviceToGroup(String uid, String macAddress, String targetGroupId) async {
    try {
      final userDoc = _firestore.collection('users').doc(uid);
      final snapshot = await userDoc.get();

      List<dynamic> groups = List.from(snapshot.data()?['device_groups'] ?? []);

      // 1. Adım: Cihazı mevcut olduğu tüm gruplardan çıkar
      for (var group in groups) {
        List<dynamic> devices = List.from(group['devices'] ?? []);
        devices.remove(macAddress);
        group['devices'] = devices;
      }

      // 2. Adım: Eğer hedef bir grup ise (ana ekran değilse), o gruba ekle
      if (targetGroupId.isNotEmpty) {
        var targetGroup = groups.firstWhere((g) => g['id'] == targetGroupId, orElse: () => null);
        if (targetGroup != null) {
          List<dynamic> devices = List.from(targetGroup['devices'] ?? []);
          if (!devices.contains(macAddress)) {
            devices.add(macAddress);
          }
          targetGroup['devices'] = devices;
        }
      }

      await userDoc.update({'device_groups': groups});
    } catch (e) {
      print('Error moving device: $e');
    }
  }
  // Cihazı sahiplenmek için (PC Uygulaması kullanacak)
  Future<void> claimDevice(String macAddress, String ownerUid, String ownerEmail) async {
    if (macAddress.isEmpty) return;
    try {
      await _firestore.collection('dispenser').doc(macAddress).set({
        'owner_uid': ownerUid,
        'owner_mail': ownerEmail,
        'device_name': 'MedTrack Kutu',
        'last_setup': FieldValue.serverTimestamp(),
        'active_command': null, // Başlangıçta komut yok
      }, SetOptions(merge: true));

      // Kullanıcıya da ekle (Senin mevcut fonksiyonun)
      await updateUserDeviceList(ownerUid, ownerEmail);
    } catch (e) {
      print('Cihaz sahiplenme hatası: $e');
    }
  }

// Motoru uzaktan çalıştırmak için (Mobil Uygulama kullanacak)
  Future<void> sendMotorCommand(String macAddress, int sectionIndex) async {
    if (macAddress.isEmpty) return;
    try {
      await _firestore.collection('dispenser').doc(macAddress).update({
        'active_command': {
          'action': 'DISPENSE',
          'section': sectionIndex,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'PENDING' // ESP32 bunu okuyunca 'COMPLETED' yapacak
        }
      });
    } catch (e) {
      print('Komut hatası: $e');
    }
  }
  // lib/services/database_service.dart içine ekleyin

  Future<void> sendLedCommand(String macAddress, bool turnOn) async {
    if (macAddress.isEmpty) return;
    try {
      await _firestore.collection('dispenser').doc(macAddress).update({
        'active_command': {
          'action': turnOn ? 'LED_ON' : 'LED_OFF', // Eylem ismini değiştirdik
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'PENDING'
        }
      });
    } catch (e) {
      print('LED komutu hatası: $e');
    }
  }

  // YENİ 2: Komut Gönderme (Mobilden LED veya Motor Çalıştırmak İçin)
  Future<void> sendCommand(String macAddress, String action) async {
    if (macAddress.isEmpty) return;
    try {
      await _firestore.collection('dispenser').doc(macAddress).update({
        'active_command': {
          'action': action, // Örn: 'LED_ON', 'LED_OFF', 'DISPENSE'
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'PENDING'
        }
      });
    } catch (e) {
      print('Komut gönderme hatası: $e');
    }
  }

}
>>>>>>> Stashed changes
