import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Change this to your VM IP / domain in production
  static const String baseUrl = 'http://localhost:3000/api';
  //static const String baseUrl = 'http://72.60.137.97:3001/api';

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
    if (res.statusCode != 200)
      throw Exception(body['error'] ?? 'Request failed');
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
    if (res.statusCode != 201)
      throw Exception(data['error'] ?? 'Registration failed');
    return data;
  }

  // ── Clients ────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getClients() async {
    final res = await http.get(
      Uri.parse('$baseUrl/clients'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) throw Exception('Failed to load clients');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getClient(String id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/clients/$id'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) throw Exception('Client not found');
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
    final body = jsonDecode(res.body);
    if (res.statusCode != 201)
      throw Exception(body['error'] ?? 'Failed to create client');
    return body;
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
    final body = jsonDecode(res.body);
    if (res.statusCode != 200)
      throw Exception(body['error'] ?? 'Failed to update client');
    return body;
  }

  static Future<void> markClientReplied(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/clients/$id/replied'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) throw Exception('Failed to mark as replied');
  }

  static Future<void> deleteClient(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/clients/$id'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) throw Exception('Failed to delete client');
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getMessages(String clientId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/clients/$clientId/messages'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) throw Exception('Failed to load messages');
    return jsonDecode(res.body);
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
    final body = jsonDecode(res.body);
    if (res.statusCode != 200)
      throw Exception(body['error'] ?? 'Failed to save messages');
    return body;
  }

  // ── Templates ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getTemplates() async {
    final res = await http.get(
      Uri.parse('$baseUrl/templates'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) throw Exception('Failed to load templates');
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
    final body = jsonDecode(res.body);
    if (res.statusCode != 201)
      throw Exception(body['error'] ?? 'Failed to create template');
    return body;
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
    final body = jsonDecode(res.body);
    if (res.statusCode != 200)
      throw Exception(body['error'] ?? 'Failed to update template');
    return body;
  }

  static Future<void> deleteTemplate(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/templates/$id'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) throw Exception('Failed to delete template');
  }

  // ── Dashboard ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getDashboardStats() async {
    final res = await http.get(
      Uri.parse('$baseUrl/dashboard/stats'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) throw Exception('Failed to load stats');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> sendNow() async {
    final res = await http.post(
      Uri.parse('$baseUrl/dashboard/send-now'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) throw Exception('Send now failed');
    return jsonDecode(res.body);
  }
}
