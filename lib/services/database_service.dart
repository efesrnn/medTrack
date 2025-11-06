import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveSections(String uid, List<Map<String, dynamic>> sections) async {
    if (uid.isEmpty) return; // Do not save if UID is not available

    try {
      final userDispenserDoc = _firestore.collection('users').doc(uid).collection('dispenser').doc('sections_config');
      await userDispenserDoc.set({'sections': sections});
    } catch (e) {
      print('Error saving sections to Firestore: $e');
    }
  }
}
