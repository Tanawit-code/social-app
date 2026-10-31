import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;
  bool _listening = false;
  StreamSubscription<String>? _tokenSubscription;

  Future<void> initialize({
    required String uid,
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    if (_listening) return;
    _listening = true;
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? 'การแจ้งเตือนใหม่';
      final body = message.notification?.body ?? '';
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(body.isEmpty ? title : '$title: $body')),
        );
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((_) {
      navigatorKey.currentState?.pushNamed('/notifications');
    });
    final initial = await _messaging.getInitialMessage();
    if (initial != null) navigatorKey.currentState?.pushNamed('/notifications');
  }

  Future<bool> enableForUser(String uid) async {
    final permission = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus == AuthorizationStatus.denied)
      return false;
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return false;
    await _saveToken(uid, token);
    _watchTokenRefresh(uid);
    await _db
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('account')
        .set({'pushEnabled': true}, SetOptions(merge: true));
    return true;
  }

  Future<void> restoreForUser(String uid) async {
    final account = await _db
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('account')
        .get();
    if (account.data()?['pushEnabled'] != true) return;
    final settings = await _messaging.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _saveToken(uid, token);
      _watchTokenRefresh(uid);
    }
  }

  Future<void> unregisterCurrentDevice(String uid) async {
    final token = await _messaging.getToken();
    if (token != null) {
      await _db
          .collection('users')
          .doc(uid)
          .collection('deviceTokens')
          .doc(_tokenId(token))
          .delete();
    }
  }

  Future<void> stopListening() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
  }

  Future<void> disableForUser(String uid) async {
    await stopListening();
    final token = await _messaging.getToken();
    if (token != null)
      await _db
          .collection('users')
          .doc(uid)
          .collection('deviceTokens')
          .doc(_tokenId(token))
          .delete();
    await _db
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('account')
        .set({'pushEnabled': false}, SetOptions(merge: true));
  }

  Future<void> _saveToken(String uid, String token) => _db
      .collection('users')
      .doc(uid)
      .collection('deviceTokens')
      .doc(_tokenId(token))
      .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});

  void _watchTokenRefresh(String uid) {
    _tokenSubscription?.cancel();
    _tokenSubscription = _messaging.onTokenRefresh.listen(
      (newToken) => _saveToken(uid, newToken),
    );
  }

  String _tokenId(String token) => token.replaceAll('/', '_');
  static final navigatorKey = GlobalKey<NavigatorState>();
}
