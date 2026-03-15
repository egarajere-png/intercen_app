// lib/services/role_service.dart
// Place this file at: lib/services/role_service.dart
// Create the folder: lib/services/ if it doesn't exist

import 'package:supabase_flutter/supabase_flutter.dart';

const _adminIds = {
  '5fbc35df-ae08-4f8a-b0b3-dd6bb4610ebd',
  'e2925b0b-c730-484c-b4f1-1361380bccd3',
};

class RoleService {
  RoleService._();
  static final RoleService instance = RoleService._();

  String _role   = 'reader';
  String _userId = '';
  bool   _loaded = false;

  String get role    => _role;
  String get userId  => _userId;
  bool   get isAdmin => _role == 'admin';
  bool   get isAuthor => _role == 'author' || _role == 'publisher';
  bool   get isReader => !isAdmin && !isAuthor;
  bool   get loaded  => _loaded;

  /// Returns the named route for the current role's dashboard.
  static String dashboardForRole(String role) {
    switch (role) {
      case 'admin':
        return '/dashboard/admin';
      case 'author':
      case 'publisher':
        return '/dashboard/author';
      default:
        return '/dashboard/reader';
    }
  }

  /// Call once after sign-in. Returns the resolved role string.
  Future<String> load() async {
    final sb   = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) { _reset(); return _role; }

    _userId = user.id;

    // Protected admins always stay admin regardless of DB value
    if (_adminIds.contains(_userId)) {
      _role   = 'admin';
      _loaded = true;
      // Patch DB silently — fire and forget
      sb.from('profiles')
          .update({'role': 'admin', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', _userId)
          .then((_) {})
          .catchError((_) {});
      return _role;
    }

    try {
      final data = await sb
          .from('profiles')
          .select('role')
          .eq('id', _userId)
          .maybeSingle();

      _role = (data?['role'] as String?) ?? 'reader';
    } catch (_) {
      _role = 'reader';
    }

    _loaded = true;
    return _role;
  }

  /// Reload after a role change.
  Future<void> reload() => load();

  void _reset() {
    _role   = 'reader';
    _userId = '';
    _loaded = false;
  }

  void clear() => _reset();
}