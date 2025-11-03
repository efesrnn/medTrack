import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final CollectionReference _dispenserCollection = FirebaseFirestore.instance.collection('dispenser');

  Future<void> saveSections(List<Map<String, dynamic>> sections) async {
    try {
      // Using a specific document to hold the configuration of the 6 sections.
      await _dispenserCollection.doc('sections_config').set({'sections': sections});
    } catch (e) {
      // Handle potential errors, e.g., by logging them
      print('Error saving sections to Firestore: $e');
    }
  }
}
