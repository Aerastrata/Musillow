import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/automation_client.dart';
import '../services/automation_state.dart';
import '../theme.dart';

/// Sign in / register a Musillow account. Shown full-screen as the first-launch
/// gate, and pushed from the account switcher to add another account.
class AccountAuthScreen extends StatefulWidget {
  const AccountAuthScreen({super.key});

  @override
  State<AccountAuthScreen> createState() => _AccountAuthScreenState();
}

class _AccountAuthScreenState extends State<AccountAuthScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prefill the server URL from an existing account, if any.
    final existing = automationState.accounts;
    if (existing.isNotEmpty) _url.text = existing.first.url;
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

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
    try {
      await automationState.connectAccount(
        url: url,
        username: _user.text.trim(),
        password: _pass.text,
        register: _register,
      );
      // Let the password manager offer to save/update these credentials.
      TextInput.finishAutofillContext();
      if (mounted) Navigator.of(context).maybePop();
    } on AutomationException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not reach server. Check the URL.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  Icon(
                    SolarIconsBold.headphonesRoundSound,
                    size: 52,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Musillow',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _register
                        ? 'Create your account to get started.'
                        : 'Sign in to your account.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 28),
                  _field(
                    _url,
                    'Server',
                    'https://your-server.example.com',
                    keyboard: TextInputType.url,
                    autofillHints: const [AutofillHints.url],
                  ),
                  const SizedBox(height: 14),
                  _field(
                    _user,
                    'Username',
                    'your username',
                    autofillHints: [
                      _register
                          ? AutofillHints.newUsername
                          : AutofillHints.username,
                    ],
                  ),
                  const SizedBox(height: 14),
                  _field(
                    _pass,
                    'Password',
                    '••••••••',
                    obscure: _obscure,
                    action: TextInputAction.done,
                    onSubmitted: (_) => _busy ? null : _submit(),
                    autofillHints: [
                      _register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
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
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
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
                        : Text(
                            _register ? 'Create account' : 'Sign in',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFE0605A)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _register = !_register),
                    child: Text(
                      _register
                          ? 'Have an account? Sign in'
                          : 'New here? Create an account',
                      style: TextStyle(color: AppColors.accent),
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
