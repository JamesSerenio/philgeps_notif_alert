import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    return web;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDUdc3Sf1ySJFtHARU43lJQvrt6Moe8T_E',
    authDomain: 'philgeps-notif-alert.firebaseapp.com',
    projectId: 'philgeps-notif-alert',
    storageBucket: 'philgeps-notif-alert.firebasestorage.app',
    messagingSenderId: '124523489115',
    appId: '1:124523489115:web:93f7188df123b281545c7e',
    measurementId: 'G-RMEJ8R1SWN',
  );
}
