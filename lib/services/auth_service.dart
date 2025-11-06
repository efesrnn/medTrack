import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String?> getOrCreateUser() async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = prefs.getString('user_uid');

    if (uid == null) {
      try {
        // Sign in anonymously
        final userCredential = await _auth.signInAnonymously();
        uid = userCredential.user?.uid;

        if (uid != null) {
          // Save UID to local storage
          await prefs.setString('user_uid', uid!);

          // Save user info to Firestore
          await _firestore.collection('users').doc(uid).set({
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        print('Error with anonymous sign-in: $e');
        return null; // Return null on error
      }
    } else {
      // Optional: Update last login time for existing users
      try {
        await _firestore.collection('users').doc(uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        print('Error updating last login: $e');
        // Non-critical error, so we can ignore it and still return the UID
      }
    }
    return uid;
  }
}
