import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';

sealed class AuthState {
  const AuthState();
}

/// Ilova ochilayotganda: saqlangan sessiya tekshirilmoqda
class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthGuest extends AuthState {
  const AuthGuest({this.sessionExpired = false});

  /// true bo'lsa, "Sessiya tugadi, qaytadan kiring" xabari ko'rsatiladi
  final bool sessionExpired;
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.me);
  final Me me;
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Kirgan foydalanuvchi (kirmagan bo'lsa null)
final currentUserProvider = Provider<Me?>((ref) {
  final state = ref.watch(authControllerProvider);
  return state is AuthSignedIn ? state.me : null;
});

class AuthController extends Notifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  AuthState build() {
    final sub = ref.read(sessionExpiredProvider).stream.listen((_) {
      state = const AuthGuest(sessionExpired: true);
    });
    ref.onDispose(sub.cancel);
    unawaited(_restore());
    return const AuthLoading();
  }

  Future<void> _restore() async {
    final storage = ref.read(tokenStorageProvider);
    await storage.load();
    if (!storage.hasSession) {
      state = const AuthGuest();
      return;
    }
    // Avval keshdagi profil bilan darhol ochamiz (splash uzoq turmasligi uchun),
    // keyin fonda serverdan yangilaymiz.
    final cached = await storage.cachedMe();
    if (cached != null) state = AuthSignedIn(Me.fromJson(cached));
    try {
      await refreshMe();
    } on ApiException catch (e) {
      if (e.isNetwork) {
        if (cached == null) state = const AuthGuest();
        return; // internet yo'q: keshdagi holat bilan ishlashda davom etamiz
      }
      if (e.status == 401) {
        await storage.clear();
        state = const AuthGuest(sessionExpired: true);
      }
    }
  }

  Future<Me> refreshMe() async {
    final me = await _repo.me();
    await ref.read(tokenStorageProvider).cacheMe(me.raw);
    state = AuthSignedIn(me);
    return me;
  }

  Future<void> signIn(Tokens tokens, Me me) async {
    final storage = ref.read(tokenStorageProvider);
    await storage.save(access: tokens.access, refresh: tokens.refresh);
    await storage.cacheMe(me.raw);
    state = AuthSignedIn(me);
  }

  /// Ekranlar profilni o'zgartirgandan keyin chaqiradi
  Future<void> updateMe(Me me) async {
    await ref.read(tokenStorageProvider).cacheMe(me.raw);
    state = AuthSignedIn(me);
  }

  Future<void> signOut() async {
    try {
      await _repo.logout();
    } catch (_) {
      // Server javob bermasa ham qurilmadan chiqamiz
    }
    await ref.read(tokenStorageProvider).clear();
    state = const AuthGuest();
  }
}
