import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _loginFormKey    = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPassCtrl  = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().login(
        _emailCtrl.text.trim(),
        _passCtrl.text,
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (!_registerFormKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().register(
        _regEmailCtrl.text.trim(),
        _regPassCtrl.text,
        _nameCtrl.text.trim(),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  Future<void> _showForgotPasswordDialog() async {
  final l10n = AppLocalizations.of(context)!;
  final emailCtrl = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.resetPassword),
      content: TextField(
        controller: emailCtrl,
        decoration: InputDecoration(labelText: l10n.yourEmail),
        keyboardType: TextInputType.emailAddress,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () async {
            final email = emailCtrl.text.trim();
            if (email.isEmpty) return;
            Navigator.pop(ctx);
            setState(() => _loading = true);
            try {
              await ApiService.forgotPassword(email);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(l10n.resetLinkSent),
                ));
              }
            } catch (e) {
              if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          },
          child: Text(l10n.sendResetLink),
        ),
      ],
    ),
  );
}
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏡', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(l10n.appTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        TabBar(
                          controller: _tabs,
                          tabs: [Tab(text: l10n.signIn), Tab(text: l10n.register)],
                          onTap: (_) => setState(() => _error = null),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 280,
                          child: TabBarView(
                            controller: _tabs,
                            children: [_loginForm(l10n), _registerForm(l10n)],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading
                                ? null
                                : () => _tabs.index == 0 ? _login() : _register(),
                            child: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(_tabs.index == 0 ? l10n.signIn : l10n.createAccount),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginForm(AppLocalizations l10n) {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _emailCtrl,
            decoration: InputDecoration(labelText: l10n.email),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v?.isEmpty ?? true) ? l10n.required : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passCtrl,
            decoration: InputDecoration(labelText: l10n.password),
            obscureText: true,
            validator: (v) => (v?.isEmpty ?? true) ? l10n.required : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showForgotPasswordDialog,
              child: Text(l10n.forgotPassword),
            ),
          ),
        ],
      ),
    );
  }

  Widget _registerForm(AppLocalizations l10n) {
    return Form(
      key: _registerFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _nameCtrl,
            decoration: InputDecoration(labelText: l10n.fullName),
            validator: (v) => (v?.isEmpty ?? true) ? l10n.required : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _regEmailCtrl,
            decoration: InputDecoration(labelText: l10n.email),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v?.isEmpty ?? true) ? l10n.required : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _regPassCtrl,
            decoration: InputDecoration(labelText: l10n.passwordMinHint),
            obscureText: true,
            validator: (v) =>
                (v == null || v.length < 8) ? l10n.passwordMinChars : null,
          ),
        ],
      ),
    );
  }
}
