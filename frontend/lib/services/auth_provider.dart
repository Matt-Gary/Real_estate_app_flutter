import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthProvider extends ChangeNotifier {
  Map<String, dynamic>? _agent;
  bool _loading = true;

  Map<String, dynamic>? get agent => _agent;
  bool get isLoggedIn => _agent != null;
  bool get loading => _loading;

  AuthProvider() {
    ApiService.onUnauthorized = () => logout();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('agent');
    final token = prefs.getString('jwt_token');
    if (raw != null && token != null) {
      _agent = jsonDecode(raw);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final data = await ApiService.login(email, password);
    await ApiService.saveToken(data['token']);
    _agent = data['agent'];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('agent', jsonEncode(_agent));
    notifyListeners();
  }

  Future<void> register(String email, String password, String name) async {
    final data = await ApiService.register(email, password, name);
    await ApiService.saveToken(data['token']);
    _agent = data['agent'];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('agent', jsonEncode(_agent));
    notifyListeners();
  }

  Future<void> logout() async {
    await ApiService.clearToken();
    _agent = null;
    notifyListeners();
  }
}
