import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/notifications/data/notifications_repository.dart';

/// Shows messages from outside a screen (a push that arrives while the app
/// is open). Given to MaterialApp in main.dart.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Push notifications on this phone (Firebase Cloud Messaging).
///
/// - After login: asks permission (Android 13+), registers this phone so the
///   send-push Edge Function can reach it.
/// - Before logout: unregisters it (the next person on this phone doesn't get
///   someone else's notifications).
/// - App open: a small banner with "Open"; the bell list refreshes.
/// - Tapping a notification: opens the screen it's about.
///
/// Everything is skipped when Firebase isn't set up (tests).
class PushService {
  PushService(this._ref);

  final Ref _ref;
  bool _started = false;

  bool get _available => Firebase.apps.isNotEmpty;

  /// Called once at startup.
  Future<void> start() async {
    if (_started || !_available) return;
    _started = true;
    final messaging = FirebaseMessaging.instance;

    FirebaseMessaging.onMessage.listen(_onMessageWhileOpen);
    FirebaseMessaging.onMessageOpenedApp.listen((message) => _open(message.data['route'] as String?));
    messaging.onTokenRefresh.listen((token) => _register(token));

    // Opened by tapping a notification while the app was closed.
    final initial = await messaging.getInitialMessage();
    final route = initial?.data['route'] as String?;
    if (route != null) {
      // Give the router a moment to finish logging in.
      Future.delayed(const Duration(milliseconds: 800), () => _open(route));
    }
  }

  /// After login: permission, then register this phone.
  Future<void> registerThisPhone() async {
    if (!_available) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    } catch (e) {
      debugPrint('Push: could not register this phone: $e');
    }
  }

  /// Before logout.
  Future<void> unregisterThisPhone() async {
    if (!_available) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _ref.read(notificationsRepositoryProvider).unregisterDevice(token);
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('Push: could not unregister this phone: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      await _ref.read(notificationsRepositoryProvider).registerDevice(token);
    } catch (e) {
      debugPrint('Push: register failed: $e');
    }
  }

  void _onMessageWhileOpen(RemoteMessage message) {
    _ref.invalidate(myNotificationsProvider);
    final notification = message.notification;
    if (notification == null) return;
    final route = message.data['route'] as String?;
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text([notification.title, notification.body].nonNulls.join('\n')),
        duration: const Duration(seconds: 6),
        action: route == null ? null : SnackBarAction(label: 'Open', onPressed: () => _open(route)),
      ),
    );
  }

  void _open(String? route) {
    if (route == null || route.isEmpty) return;
    _ref.invalidate(myNotificationsProvider);
    _ref.read(appRouterProvider).push(route);
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));
