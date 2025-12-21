import 'package:dispenserapp/services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String? displayName;
  final String? photoURL;
  final String? email;

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

    // 1. Önce Firebase Auth'ta zaten oturum açmış bir kullanıcı var mı bakalım.
    User? firebaseUser = _auth.currentUser;

    // 2. Eğer oturum yoksa Google Sign-In başlatalım
    if (firebaseUser == null) {
      try {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          return null; // Kullanıcı girişi iptal etti
        }

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential userCredential = await _auth.signInWithCredential(credential);
        firebaseUser = userCredential.user;
      } catch (e) {
        print('Google Sign-In Error: $e');
        return null;
      }
    }

    // 3. Kullanıcı (firebaseUser) elimizdeyse işlemleri yapalım
    if (firebaseUser != null) {
      final uid = firebaseUser.uid;
      final email = firebaseUser.email;
      final displayName = firebaseUser.displayName;
      final photoURL = firebaseUser.photoURL;

      // SharedPreferences'a UID'yi yedekleyelim (Session kontrolü için kullanıyorsanız)
      await prefs.setString('user_uid', uid);

      // --- KRİTİK GÜNCELLEME BURASI ---
      // Her açılışta, Firebase'den gelen en güncel İsim ve Fotoğrafı Firestore'a YAZIYORUZ.
      // Bu sayede "Yakınlarım" ekranında fotoğraflar her zaman güncel kalır.
      try {
        await _firestore.collection('users').doc(uid).set({
          'email': email,
          'displayName': displayName ?? '',
          'photoURL': photoURL ?? '',
          'lastLogin': FieldValue.serverTimestamp(), // Son görülme zamanı
          // 'createdAt': FieldValue.serverTimestamp(), // Bunu set ile her seferinde ezmemek için update kullanmak daha iyi olabilir veya merge ile createdAt varsa dokunma mantığı gerekebilir ama şimdilik set merge:true yeterli.
        }, SetOptions(merge: true)); // merge: true -> Mevcut cihaz listesi vb. verileri silme, sadece bunları güncelle.
      } catch (e) {
        print('Firestore update error: $e');
      }
      // ---------------------------------

      // Cihaz listelerini senkronize et (DatabaseService)
      if (email != null) {
        await _dbService.updateUserDeviceList(uid, email);
      }

      // Uygulamaya kullanıcı objesini döndür
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
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_uid');
    } catch (e) {
      print("Sign out error: $e");
    }
  }
}