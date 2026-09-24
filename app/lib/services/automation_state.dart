import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'abs_state.dart';
import 'app_state.dart';
import 'automation_client.dart';
import 'player_service.dart';

/// Avatar/accent palette (hex) assigned per account.
const accountPalette = <String>[
  '#9090FF',
  '#FF5A7A',
  '#40D0B0',
  '#E08040',
  '#B57BFF',
  '#5B9CFF',
  '#4FD07A',
  '#F5A623',
];

String _colorFor(String name) =>
    accountPalette[name.hashCode.abs() % accountPalette.length];

/// A saved backend account (one per server login).
class Account {
  final String url;
  String token;
  String username;
  String? email;
  String colorHex;

  /// Whether the server holds a profile picture for this account, and its
  /// version (the picture's last-write time). Both are cached locally so the
  /// avatar renders on launch without waiting for a round trip.
  bool hasAvatar;
  int avatarVersion;

  Account({
    required this.url,
    required this.token,
    required this.username,
    required this.colorHex,
    this.email,
    this.hasAvatar = false,
    this.avatarVersion = 0,
  });

  String get key => '$url|$username';

  Map<String, dynamic> toJson() => {
    'url': url,
    'token': token,
    'username': username,
    'email': email,
    'color': colorHex,
    'hasAvatar': hasAvatar,
    'avatarVersion': avatarVersion,
  };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    url: j['url'].toString(),
    token: j['token'].toString(),
    username: j['username'].toString(),
    email: j['email']?.toString(),
    colorHex: (j['color'] ?? '#9090FF').toString(),
    hasAvatar: j['hasAvatar'] == true,
    avatarVersion: (j['avatarVersion'] as num?)?.toInt() ?? 0,
  );
}

/// Holds all saved backend accounts, the active one, and its JWT client.
///
/// The account is the app's primary identity (required on first launch); the
/// active account's Navidrome credentials are pushed to the server so
/// recommendations run there.
class AutomationState extends ChangeNotifier {
  static const _kAccounts = 'accounts_v1';
  static const _kActive = 'accounts_active';

  final List<Account> _accounts = [];
  int _active = -1;
  AutomationClient? _client;

  List<Account> get accounts => List.unmodifiable(_accounts);
  Account? get active =>
      (_active >= 0 && _active < _accounts.length) ? _accounts[_active] : null;
  int get activeIndex => _active;
  bool get isConnected => active != null;
  AutomationClient? get client => _client;
  String? get username => active?.username;
  String? get email => active?.email;
  String? get colorHex => active?.colorHex;

  /// Profile-picture URL for any saved account, or null when it has none. Each
  /// account's own token identifies it to /auth/me/avatar, so this works for
  /// accounts that aren't currently active. The version is carried along so a
  /// replaced picture is never served from cache.
  String? avatarUrlFor(Account a) => a.hasAvatar
      ? AutomationClient.avatarUriFor(
          a.url,
          a.token,
          v: a.avatarVersion,
        ).toString()
      : null;

  /// The active account's profile-picture URL, or null when none is set.
  String? get avatarUrl {
    final a = active;
    return a == null ? null : avatarUrlFor(a);
  }

  /// Bumped every time the backing session changes (sign-in, switch, sign-out)
  /// — never on a profile edit. Screens key off this to drop data loaded for
  /// the previous account instead of showing it to the new one.
  int _session = 0;
  int get session => _session;

  void _rebuildClient() {
    final a = active;
    _client?.dispose();
    _client = a != null ? AutomationClient(a.url, token: a.token) : null;
    // Music and audiobooks both stream through this same backend account, so
    // every data layer is rebound together — nothing from the previous account
    // survives a switch.
    appState.bind(a?.url, a?.token);
    absState.bind(a?.url, a?.token);
    // Hand playback over too: the outgoing queue is saved under its own
    // account, and this account's own saved queue is restored.
    unawaited(playerService.switchAccount(a?.key, appState.client));
    _session++;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kAccounts,
      jsonEncode(_accounts.map((a) => a.toJson()).toList()),
    );
    await prefs.setInt(_kActive, _active);
  }

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAccounts);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _accounts
        ..clear()
        ..addAll(list.map((e) => Account.fromJson(e as Map<String, dynamic>)));
    }
    _active = prefs.getInt(_kActive) ?? (_accounts.isEmpty ? -1 : 0);
    if (_active >= _accounts.length) _active = _accounts.isEmpty ? -1 : 0;
    _rebuildClient();
    notifyListeners();
  }

  /// Signs in (or registers), stores the account and activates it.
  Future<void> connectAccount({
    required String url,
    required String username,
    required String password,
    required bool register,
  }) async {
    final base = AutomationClient.normalize(url);
    final token = register
        ? await AutomationClient.register(base, username, password)
        : await AutomationClient.login(base, username, password);
    final client = AutomationClient(base, token: token);

    var uname = username;
    String? email;
    var hasAvatar = false;
    var avatarVersion = 0;
    try {
      final me = await client.me();
      uname = me['username']?.toString() ?? username;
      email = me['email']?.toString();
      hasAvatar = me['avatar'] == true;
      avatarVersion = (me['avatarVersion'] as num?)?.toInt() ?? 0;
    } catch (_) {}
    client.dispose();

    final account = Account(
      url: base,
      token: token,
      username: uname,
      email: email,
      colorHex: _colorFor(uname),
      hasAvatar: hasAvatar,
      avatarVersion: avatarVersion,
    );
    final idx = _accounts.indexWhere((a) => a.key == account.key);
    if (idx >= 0) {
      _accounts[idx] = account;
      _active = idx;
    } else {
      _accounts.add(account);
      _active = _accounts.length - 1;
    }
    _rebuildClient();
    await _persist();
    notifyListeners();
  }

  Future<void> switchTo(int index) async {
    if (index < 0 || index >= _accounts.length || index == _active) return;
    _active = index;
    _rebuildClient();
    await _persist();
    notifyListeners();
  }

  /// Signs out of (and removes) the active account.
  Future<void> logoutActive() async {
    if (_active < 0) return;
    _accounts.removeAt(_active);
    _active = _accounts.isEmpty ? -1 : 0;
    _rebuildClient();
    await _persist();
    notifyListeners();
  }

  /// Updates the active account's profile (name/email/password on the server,
  /// colour locally).
  Future<void> updateProfile({
    String? username,
    String? email,
    String? password,
    String? colorHex,
  }) async {
    final a = active;
    final client = _client;
    if (a == null || client == null) return;
    final changingServer =
        (username != null && username != a.username) ||
        email != null ||
        (password != null && password.isNotEmpty);
    if (changingServer) {
      final me = await client.updateMe(
        username: username,
        email: email,
        password: password,
      );
      a.username = me['username']?.toString() ?? a.username;
      a.email = me['email']?.toString();
    }
    if (colorHex != null) a.colorHex = colorHex;
    await _persist();
    notifyListeners();
  }

  /// Record the avatar state returned by any /auth/me response.
  Future<void> _adoptProfile(Map<String, dynamic> me) async {
    final a = active;
    if (a == null) return;
    a.hasAvatar = me['avatar'] == true;
    a.avatarVersion = (me['avatarVersion'] as num?)?.toInt() ?? 0;
    await _persist();
    notifyListeners();
  }

  /// Upload [filePath] as the active account's profile picture.
  Future<void> setAvatar(String filePath) async {
    final client = _client;
    if (client == null) return;
    await _adoptProfile(await client.uploadAvatar(filePath));
  }

  /// Remove the active account's profile picture.
  Future<void> removeAvatar() async {
    final client = _client;
    if (client == null) return;
    await _adoptProfile(await client.deleteAvatar());
  }

  /// Re-read the profile from the server (picks up a picture set on another
  /// device). Best-effort — a failure just leaves the cached values in place.
  Future<void> refreshProfile() async {
    final client = _client;
    if (client == null) return;
    try {
      final me = await client.me();
      final a = active;
      if (a != null) {
        a.username = me['username']?.toString() ?? a.username;
        a.email = me['email']?.toString();
      }
      await _adoptProfile(me);
    } catch (_) {}
  }
}

/// Single app-wide instance.
final automationState = AutomationState();
