import 'package:dispenserapp/services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String? displayName;
  final String? photoURL;
  final String? email; // EKLENDİ: Email alanı eklendi

  AppUser({
    required this.uid,
    this.displayName,
    this.photoURL,
    this.email
  });
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseService _dbService = DatabaseService();

  Future<AppUser?> getOrCreateUser() async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = prefs.getString('user_uid');
    String? email;
    String? displayName;
    String? photoURL;

    if (uid == null) {
      try {
        // Yeni kullanıcı için Google Girişi
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          return null;
        }
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final UserCredential userCredential = await _auth.signInWithCredential(credential);

        uid = userCredential.user?.uid;
        email = userCredential.user?.email;
        displayName = userCredential.user?.displayName;
        photoURL = userCredential.user?.photoURL;

        if (uid != null) {
          await prefs.setString('user_uid', uid);
          // Firestore'a kaydet
          await _firestore.collection('users').doc(uid).set({
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
            'email': email,
            'displayName': displayName,
            'photoURL': photoURL,
          }, SetOptions(merge: true));
        }
      } catch (e) {
        print('Error with Google sign-in: $e');
        return null;
      }
    } else {
      // Mevcut kullanıcı, verileri Firestore'dan çek
      try {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          email = data['email'] as String?;
          displayName = data['displayName'] as String?;
          photoURL = data['photoURL'] as String?;
        }

        await _firestore.collection('users').doc(uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        print('Error fetching user email or updating login: $e');
      }
    }

    if (uid != null && email != null) {
      await _dbService.updateUserDeviceList(uid, email);
    }

    if (uid != null) {
      // EKLENDİ: email parametresi AppUser'a gönderiliyor
      return AppUser(
          uid: uid,
          displayName: displayName,
          photoURL: photoURL,
          email: email
      );
    }
    return null;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_uid');
  }
}