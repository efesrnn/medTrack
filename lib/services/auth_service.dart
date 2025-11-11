import 'package:dispenserapp/services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseService _dbService = DatabaseService(); // Database service instance

  Future<String?> getOrCreateUser() async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = prefs.getString('user_uid');
    String? email;

    if (uid == null) {
      try {
        // Sign in with Google for new user
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          return null; // User canceled sign-in
        }
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final UserCredential userCredential = await _auth.signInWithCredential(credential);
        uid = userCredential.user?.uid;
        email = userCredential.user?.email;

        if (uid != null) {
          await prefs.setString('user_uid', uid);
          // Save new user info to Firestore
          await _firestore.collection('users').doc(uid).set({
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
            'email': email,
            'displayName': userCredential.user?.displayName,
            'photoURL': userCredential.user?.photoURL,
          }, SetOptions(merge: true));
        }
      } catch (e) {
        print('Error with Google sign-in: $e');
        return null;
      }
    } else {
      // For existing user, get email from Firestore
      try {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (userDoc.exists) {
          email = userDoc.data()!['email'] as String?;
        }
        // Update last login time
        await _firestore.collection('users').doc(uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        print('Error fetching user email or updating login: $e');
      }
    }

    // After login/creation, update the user's list of owned devices
    if (uid != null && email != null) {
      await _dbService.updateUserDeviceList(uid, email);
    }

    return uid;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_uid');
  }
}
