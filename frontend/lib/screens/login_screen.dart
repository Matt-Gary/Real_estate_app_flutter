import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  final emailCtrl = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Resetar Senha'),
      content: TextField(
        controller: emailCtrl,
        decoration: const InputDecoration(labelText: 'Seu email'),
        keyboardType: TextInputType.emailAddress,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Se esse email existir, um link de reset foi enviado.'),
                ));
              }
            } catch (e) {
              if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          },
          child: const Text('Enviar Link de Reset'),
        ),
      ],
    ),
  );
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
                Text('Follow-Up Bot',
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
                          tabs: const [Tab(text: 'Entrar'), Tab(text: 'Cadastrar')],
                          onTap: (_) => setState(() => _error = null),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 280,
                          child: TabBarView(
                            controller: _tabs,
                            children: [_loginForm(), _registerForm()],
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
                                : Text(_tabs.index == 0 ? 'Entrar' : 'Cadastrar'),
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

  Widget _loginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _emailCtrl,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v?.isEmpty ?? true) ? 'Obrigatório' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passCtrl,
            decoration: const InputDecoration(labelText: 'Senha'),
            obscureText: true,
            validator: (v) => (v?.isEmpty ?? true) ? 'Obrigatório' : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showForgotPasswordDialog,
              child: const Text('Esqueceu a senha?'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _registerForm() {
    return Form(
      key: _registerFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Nome completo'),
            validator: (v) => (v?.isEmpty ?? true) ? 'Obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _regEmailCtrl,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v?.isEmpty ?? true) ? 'Obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _regPassCtrl,
            decoration: const InputDecoration(labelText: 'Senha (min 8 caracteres)'),
            obscureText: true,
            validator: (v) =>
                (v == null || v.length < 8) ? 'Min 8 caracteres' : null,
          ),
        ],
      ),
    );
  }
}
