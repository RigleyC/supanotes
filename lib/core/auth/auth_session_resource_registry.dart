import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef AuthSessionResourceCloser = Future<void> Function();

/// Owns cleanup callbacks for resources that are active only during an
/// authenticated session.
///
/// The registry intentionally has no dependency on auth state. This allows
/// the auth controller to close already-created resources before publishing a
/// session transition without constructing an auth-dependent provider.
class AuthSessionResourceRegistry {
  final Map<Object, AuthSessionResourceCloser> _resources = {};

  /// Registers a resource and returns an idempotent unregister callback.
  void Function() register(AuthSessionResourceCloser close) {
    final key = Object();
    _resources[key] = close;
    var unregistered = false;
    return () {
      if (unregistered) return;
      unregistered = true;
      _resources.remove(key);
    };
  }

  /// Closes the resources currently registered for the active session.
  ///
  /// The snapshot is removed before cleanup starts so a concurrent session
  /// transition cannot close the same resource twice through this registry.
  Future<void> closeAll() async {
    final resources = List<AuthSessionResourceCloser>.of(_resources.values);
    _resources.clear();
    await Future.wait(resources.map((close) => close()));
  }
}

final authSessionResourceRegistryProvider =
    Provider<AuthSessionResourceRegistry>((ref) {
      return AuthSessionResourceRegistry();
    });
