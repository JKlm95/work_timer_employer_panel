// File generated / maintained for FlutterFire. Replace with output from:
//   dart pub global activate flutterfire_cli
//   flutterfire configure
//
// Until then, Web initialization uses the placeholders below — update them
// for your Firebase project before deploying.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for android - '
          'you can re-run flutterfire configure.',
        );
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can re-run flutterfire configure.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBPNgam5se3dHLQw8yhKrEb6W0FMhiHS1E',
    appId: '1:114088269593:web:614633d905dd810f175788',
    messagingSenderId: '114088269593',
    projectId: 'work-timer-2dab6',
    authDomain: 'work-timer-2dab6.firebaseapp.com',
    storageBucket: 'work-timer-2dab6.firebasestorage.app',
    measurementId: 'G-LBQC7K96VQ',
  );
}
