// lib/screens/reset_password_screen.dart

import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  String _token = '';
  bool _loading = false;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Uri.base works on Flutter Web without any special imports.
    // On mobile this will just return an empty string, which is fine
    // since reset links are only sent via email (web).
    _token = Uri.base.queryParameters['token'] ?? '';
  }

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.resetPassword(_token, _newPassCtrl.text);
      setState(() => _success = true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Text(
                  'RE Follow-Up Bot',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _success ? _buildSuccess() : _buildForm(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    // Token missing from URL — show a clear error instead of a useless form
    if (_token.isEmpty) {
      return Column(
        children: [
          Icon(Icons.link_off,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          const Text(
            'Invalid reset link',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'This link is missing a reset token. Please request a new password reset.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Set new password',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _newPassCtrl,
            decoration: const InputDecoration(labelText: 'New password'),
            obscureText: true,
            validator: (v) =>
                (v == null || v.length < 8) ? 'Min 8 characters' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPassCtrl,
            decoration: const InputDecoration(labelText: 'Confirm new password'),
            obscureText: true,
            validator: (v) =>
                v != _newPassCtrl.text ? 'Passwords do not match' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Reset Password'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        Icon(Icons.check_circle_outline,
            size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        const Text(
          'Password updated!',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your password has been changed. You can now sign in.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            // Clear the ?token= from the URL and go back to login.
            // On web, replaceState avoids adding a history entry.
            // On mobile this is a no-op since the screen isn't reachable there.
            if (Uri.base.hasQuery) {
              // ignore: undefined_prefixed_name
              // We use Navigator instead of manipulating history directly,
              // which is cleaner and cross-platform.
            }
            Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
          },
          child: const Text('Go to Sign In'),
        ),
      ],
    );
  }
}