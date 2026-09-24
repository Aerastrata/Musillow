import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/abs_state.dart';
import '../services/app_state.dart';
import '../services/automation_client.dart';
import '../services/automation_state.dart';
import '../theme.dart';

/// The external services an account can link.
enum ConnectorKind {
  navidrome(
    key: 'navidrome',
    title: 'Navidrome',
    blurb: 'Your music library.',
    icon: SolarIconsBold.musicNote,
    urlHint: 'http://192.168.1.10:4533',
  ),
  audiobookshelf(
    key: 'abs',
    title: 'Audiobookshelf',
    blurb: 'Your audiobooks, authors and series.',
    icon: SolarIconsBold.headphonesRoundSound,
    brandColor: Color(0xFFB57BFF),
    urlHint: 'http://192.168.1.10:13378',
  );

  final String key;
  final String title;
  final String blurb;
  final IconData icon;
  final String urlHint;

  /// A fixed brand colour, where the service has one. Enum arguments must be
  /// const, so the accent can't be one of them — see [color].
  final Color? brandColor;

  /// Navidrome is the app's own music source, so it wears the user's accent
  /// rather than a colour of its own.
  Color get color => brandColor ?? AppColors.accent;

  const ConnectorKind({
    required this.key,
    required this.title,
    required this.blurb,
    required this.icon,
    required this.urlHint,
    this.brandColor,
  });
}

/// One form for linking any external service to the active account.
///
/// Both connectors work the same way: the credentials go to the Musillow
/// backend, which validates them against the service before storing them and
/// from then on proxies everything. Nothing is kept on the device, so the link
/// belongs to the account rather than the phone.
class ConnectorSetupScreen extends StatefulWidget {
  final ConnectorKind kind;
  const ConnectorSetupScreen({super.key, required this.kind});

  @override
  State<ConnectorSetupScreen> createState() => _ConnectorSetupScreenState();
}

class _ConnectorSetupScreenState extends State<ConnectorSetupScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  /// Fill in the server and username already stored for this account, so
  /// "Reconnect" only asks for the password again.
  Future<void> _prefill() async {
    try {
      final existing = await automationState.client?.connectors();
      final current = existing?[widget.kind.key];
      if (current == null || !mounted) return;
      if (_url.text.isEmpty) _url.text = current.baseUrl;
      if (_user.text.isEmpty) _user.text = current.username;
    } catch (_) {
      // Prefill is a convenience; a failure just leaves the fields blank.
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// Re-check the connector we just saved so the caller's UI updates.
  Future<void> _refreshState() => switch (widget.kind) {
    ConnectorKind.navidrome => appState.refreshConnector(),
    ConnectorKind.audiobookshelf => absState.refresh(),
  };

  Future<void> _submit() async {
    final url = _url.text.trim();
    if (url.isEmpty || _user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Fill in server, username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = automationState.client;
    if (client == null) {
      setState(() {
        _error = 'Sign in to your Musillow account first.';
        _busy = false;
      });
      return;
    }
    try {
      await client.putConnector(
        widget.kind.key,
        url,
        _user.text.trim(),
        _pass.text,
      );
      await _refreshState();
      // Let the password manager offer to save/update these credentials.
      TextInput.finishAutofillContext();
      if (mounted) Navigator.of(context).pop(true);
    } on AutomationException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the Musillow backend.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return Scaffold(
      appBar: AppBar(title: Text(kind.title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(kind.icon, size: 48, color: kind.color),
                    const SizedBox(height: 16),
                    Text(
                      'Connect to ${kind.title}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${kind.blurb} The login is stored on your Musillow '
                      'server, not on this device.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 28),
                    _field(
                      _url,
                      'Server URL',
                      kind.urlHint,
                      keyboard: TextInputType.url,
                      autofillHints: const [AutofillHints.url],
                    ),
                    const SizedBox(height: 14),
                    _field(
                      _user,
                      'Username',
                      'your username',
                      autofillHints: const [AutofillHints.username],
                    ),
                    const SizedBox(height: 14),
                    _field(
                      _pass,
                      'Password',
                      '••••••••',
                      obscure: _obscure,
                      action: TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _submit(),
                      autofillHints: const [AutofillHints.password],
                      trailing: IconButton(
                        icon: Icon(
                          _obscure
                              ? SolarIconsOutline.eye
                              : SolarIconsOutline.eyeClosed,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFE0605A)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: kind.color,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.all(16),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Connect',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String hint, {
    bool obscure = false,
    TextInputType? keyboard,
    Widget? trailing,
    List<String>? autofillHints,
    TextInputAction? action,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      autofillHints: autofillHints,
      textInputAction: action,
      onSubmitted: onSubmitted,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        hintStyle: const TextStyle(color: AppColors.textFaint),
        filled: true,
        fillColor: AppColors.surfaceAlt,
        suffixIcon: trailing,
        border: OutlineInputBorder(
          borderRadius: AppRadius.all(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.all(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.all(14),
          borderSide: BorderSide(color: AppColors.accent, width: 1.6),
        ),
      ),
    );
  }
}
