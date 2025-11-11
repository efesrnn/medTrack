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
}
