import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

class ApiService {
  // Change this to your VM IP / domain in production
  static const String baseUrl = 'http://localhost:3000/api';
  //static const String baseUrl = 'http://72.60.137.97:3001/api';

  /// Called whenever the server returns 401. Set by AuthProvider.
  static VoidCallback? onUnauthorized;

  /// Checks the response status. Throws [UnauthorizedException] on 401,
  /// or a generic [Exception] with [fallbackMessage] for any other error status.
  static void _handleResponse(http.Response res, String fallbackMessage) {
    if (res.statusCode == 401) {
      onUnauthorized?.call();
      throw const UnauthorizedException();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {}
      throw Exception(body?['error'] ?? fallbackMessage);
    }
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('agent');
  }

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<void> forgotPassword(String email) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Request failed');
    }
  }

  static Future<void> resetPassword(String token, String newPassword) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'newPassword': newPassword}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'Reset failed');
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Login failed');
    return data;
  }

  static Future<Map<String, dynamic>> register(
    String email,
    String password,
    String name,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password, 'name': name}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 201) {
      throw Exception(data['error'] ?? 'Registration failed');
    }
    return data;
  }

  // ── Clients ────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getClients() async {
    final res = await http.get(
      Uri.parse('$baseUrl/clients'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to load clients');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getClient(String id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/clients/$id'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Client not found');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> createClient(
    Map<String, dynamic> data,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/clients'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    );
    _handleResponse(res, 'Failed to create client');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> updateClient(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/clients/$id'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    );
    _handleResponse(res, 'Failed to update client');
    return jsonDecode(res.body);
  }

  static Future<void> markClientReplied(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/clients/$id/replied'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to mark as replied');
  }

  static Future<void> deleteClient(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/clients/$id'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to delete client');
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getMessages(String clientId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/clients/$clientId/messages'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to load messages');
    return jsonDecode(res.body);
  }

  static Future<void> resetClientMessages(String clientId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/clients/$clientId/messages'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to reset messages');
  }

  static Future<List<dynamic>> upsertMessages(
    String clientId,
    List<Map<String, dynamic>> messages,
  ) async {
    final res = await http.put(
      Uri.parse('$baseUrl/clients/$clientId/messages'),
      headers: await _authHeaders(),
      body: jsonEncode({'messages': messages}),
    );
    _handleResponse(res, 'Failed to save messages');
    return jsonDecode(res.body);
  }

  // ── Templates ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getTemplates() async {
    final res = await http.get(
      Uri.parse('$baseUrl/templates'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to load templates');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> createTemplate(
    Map<String, dynamic> data,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/templates'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    );
    _handleResponse(res, 'Failed to create template');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> updateTemplate(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await http.put(
      Uri.parse('$baseUrl/templates/$id'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    );
    _handleResponse(res, 'Failed to update template');
    return jsonDecode(res.body);
  }

  static Future<void> deleteTemplate(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/templates/$id'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to delete template');
  }

  // ── Cold Clients ───────────────────────────────────────────────────────────

  static Future<List<dynamic>> getColdClients() async {
    final res = await http.get(
      Uri.parse('$baseUrl/cold-clients'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to load cold clients');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> createColdClient(
    Map<String, dynamic> data,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/cold-clients'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    );
    _handleResponse(res, 'Failed to create cold client');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> updateColdClient(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/cold-clients/$id'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    );
    _handleResponse(res, 'Failed to update cold client');
    return jsonDecode(res.body);
  }

  static Future<void> deleteColdClient(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/cold-clients/$id'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to delete cold client');
  }

  // ── Property Links ─────────────────────────────────────────────────────────

  static Future<List<dynamic>> getPropertyLinks() async {
    final res = await http.get(
      Uri.parse('$baseUrl/property-links'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to load property links');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> createPropertyLink(
    Map<String, dynamic> data,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/property-links'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    );
    _handleResponse(res, 'Failed to create property link');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> updatePropertyLink(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await http.put(
      Uri.parse('$baseUrl/property-links/$id'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    );
    _handleResponse(res, 'Failed to update property link');
    return jsonDecode(res.body);
  }

  static Future<void> deletePropertyLink(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/property-links/$id'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to delete property link');
  }

  // ── Dashboard ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getDashboardStats() async {
    final res = await http.get(
      Uri.parse('$baseUrl/dashboard/stats'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Failed to load stats');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> sendNow() async {
    final res = await http.post(
      Uri.parse('$baseUrl/dashboard/send-now'),
      headers: await _authHeaders(),
    );
    _handleResponse(res, 'Send now failed');
    return jsonDecode(res.body);
  }
}
