import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

class SlotConflictException implements Exception {
  final int slot;
  final String conflictingTemplateId;
  final String conflictingTemplateName;
  const SlotConflictException({
    required this.slot,
    required this.conflictingTemplateId,
    required this.conflictingTemplateName,
  });
}

class ApiService {
  // Change this to your VM IP / domain in production
  static const String baseUrl = 'http://localhost:3000/api';
  //static const String baseUrl = 'http://72.60.137.97:3001/api';

  static const _timeout = Duration(seconds: 30);

  /// Called whenever the server returns 401. Set by AuthProvider.
  static VoidCallback? onUnauthorized;

  /// Safely decodes JSON, throwing a readable exception on malformed responses.
  static dynamic _decode(http.Response res) {
    try {
      return jsonDecode(res.body);
    } catch (_) {
      throw Exception('Invalid response from server');
    }
  }

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
    ).timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Request failed');
    }
  }

  static Future<void> resetPassword(String token, String newPassword) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'newPassword': newPassword}),
    ).timeout(_timeout);
    final body = _decode(res);
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
    ).timeout(_timeout);
    final data = _decode(res);
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
    ).timeout(_timeout);
    final data = _decode(res);
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
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to load clients');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> getClient(String id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/clients/$id'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Client not found');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> createClient(
    Map<String, dynamic> data,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/clients'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to create client');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> updateClient(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/clients/$id'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to update client');
    return _decode(res);
  }

  static Future<void> markClientReplied(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/clients/$id/replied'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to mark as replied');
  }

  static Future<void> archiveClient(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/clients/$id/archive'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to archive client');
  }

  static Future<void> unarchiveClient(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/clients/$id/unarchive'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to unarchive client');
  }

  static Future<void> deleteClient(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/clients/$id'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to delete client');
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getMessages(String clientId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/clients/$clientId/messages'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to load messages');
    return _decode(res);
  }

  static Future<void> resetClientMessages(String clientId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/clients/$clientId/messages'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
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
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to save messages');
    return _decode(res);
  }

  // ── Templates ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getTemplates() async {
    final res = await http.get(
      Uri.parse('$baseUrl/templates'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to load templates');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> createTemplate(
    Map<String, dynamic> data,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/templates'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to create template');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> updateTemplate(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await http.put(
      Uri.parse('$baseUrl/templates/$id'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to update template');
    return _decode(res);
  }

  static Future<void> deleteTemplate(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/templates/$id'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to delete template');
  }

  /// Assigns [slot] (1–5) or null to a template. When the slot is already
  /// owned by another template and [force] is false, throws
  /// [SlotConflictException] so the UI can confirm a swap. When [force] is
  /// true, the previous holder's slot is cleared first.
  static Future<Map<String, dynamic>> reassignTemplateSlot(
    String id,
    int? slot, {
    bool force = false,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/templates/$id/reassign-slot'),
      headers: await _authHeaders(),
      body: jsonEncode({'default_slot': slot, 'force': force}),
    ).timeout(_timeout);

    if (res.statusCode == 401) {
      onUnauthorized?.call();
      throw const UnauthorizedException();
    }
    if (res.statusCode == 409) {
      final body = _decode(res) as Map<String, dynamic>;
      if (body['error'] == 'slot_taken') {
        throw SlotConflictException(
          slot: slot!,
          conflictingTemplateId: body['conflicting_template_id'] as String,
          conflictingTemplateName: body['conflicting_template_name'] as String,
        );
      }
    }
    _handleResponse(res, 'Failed to assign slot');
    return _decode(res);
  }

  static Future<void> reorderTemplates(List<String> orderedIds) async {
    final res = await http.put(
      Uri.parse('$baseUrl/templates/reorder'),
      headers: await _authHeaders(),
      body: jsonEncode({'ordered_ids': orderedIds}),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to reorder templates');
  }

  // ── Cold Clients ───────────────────────────────────────────────────────────

  static Future<List<dynamic>> getColdClients() async {
    final res = await http.get(
      Uri.parse('$baseUrl/cold-clients'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to load cold clients');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> createColdClient(
    Map<String, dynamic> data,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/cold-clients'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to create cold client');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> updateColdClient(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/cold-clients/$id'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to update cold client');
    return _decode(res);
  }

  static Future<void> deleteColdClient(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/cold-clients/$id'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to delete cold client');
  }

  // ── Property Links ─────────────────────────────────────────────────────────

  static Future<List<dynamic>> getPropertyLinks() async {
    final res = await http.get(
      Uri.parse('$baseUrl/property-links'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to load property links');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> createPropertyLink(
    Map<String, dynamic> data,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/property-links'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to create property link');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> updatePropertyLink(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await http.put(
      Uri.parse('$baseUrl/property-links/$id'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to update property link');
    return _decode(res);
  }

  static Future<void> deletePropertyLink(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/property-links/$id'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to delete property link');
  }

  // ── Dashboard ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getDashboardStats() async {
    final res = await http.get(
      Uri.parse('$baseUrl/dashboard/stats'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Failed to load stats');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> sendNow() async {
    final res = await http.post(
      Uri.parse('$baseUrl/dashboard/send-now'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Send now failed');
    return _decode(res);
  }

  // ── WhatsApp ───────────────────────────────────────────────────────────────

  /// Creates (or reconnects) the agent's Evolution API instance.
  static Future<Map<String, dynamic>> whatsappConnect() async {
    final res = await http.post(
      Uri.parse('$baseUrl/whatsapp/connect'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao conectar WhatsApp');
    return _decode(res);
  }

  /// Returns the current WhatsApp connection state for the agent's instance.
  static Future<Map<String, dynamic>> getWhatsAppStatus() async {
    final res = await http.get(
      Uri.parse('$baseUrl/whatsapp/status'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao obter status do WhatsApp');
    return _decode(res);
  }

  /// Returns QR code data for the agent to scan. Poll every 3s until state == 'open'.
  static Future<Map<String, dynamic>> getWhatsAppQrCode() async {
    final res = await http.get(
      Uri.parse('$baseUrl/whatsapp/qrcode'),
      headers: await _authHeaders(),
    ).timeout(const Duration(seconds: 15));
    _handleResponse(res, 'Falha ao obter QR code');
    return _decode(res);
  }

  /// Logs out the WhatsApp session (disconnects the phone, keeps the instance slot).
  static Future<void> whatsappDisconnect() async {
    final res = await http.post(
      Uri.parse('$baseUrl/whatsapp/disconnect'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao desconectar WhatsApp');
  }

  // ── Anti-ban alerts / queue ────────────────────────────────────────────────

  static Future<void> dismissAlert(String id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/dashboard/alerts/$id/dismiss'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao dispensar alerta');
  }

  static Future<void> resumeQueue() async {
    final res = await http.post(
      Uri.parse('$baseUrl/dashboard/queue/resume'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao retomar fila');
  }

  // ── Labels ─────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getLabels() async {
    final res = await http.get(
      Uri.parse('$baseUrl/labels'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao carregar etiquetas');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> createLabel({
    required String name,
    String? color,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/labels'),
      headers: await _authHeaders(),
      body: jsonEncode({'name': name, if (color != null) 'color': color}),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao criar etiqueta');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> updateLabel(
    String id, {
    String? name,
    String? color,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (color != null) body['color'] = color;
    final res = await http.patch(
      Uri.parse('$baseUrl/labels/$id'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao atualizar etiqueta');
    return _decode(res);
  }

  static Future<void> deleteLabel(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/labels/$id'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao excluir etiqueta');
  }

  static Future<List<dynamic>> getClientsByLabel(String labelId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/labels/$labelId/clients'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao listar clientes da etiqueta');
    return _decode(res);
  }

  static Future<List<dynamic>> getClientLabels(String clientId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/clients/$clientId/labels'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao carregar etiquetas do cliente');
    return _decode(res);
  }

  static Future<void> setClientLabels(
    String clientId,
    List<String> labelIds,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/clients/$clientId/labels'),
      headers: await _authHeaders(),
      body: jsonEncode({'labelIds': labelIds}),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao salvar etiquetas');
  }

  // ── Campaigns ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getCampaigns() async {
    final res = await http.get(
      Uri.parse('$baseUrl/campaigns'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao carregar campanhas');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> getCampaign(String id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/campaigns/$id'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Campanha não encontrada');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> createCampaign({
    required String name,
    required String labelId,
    required String templateBody,
    required int dailyQuota,
    required String startAt,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/campaigns'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'name': name,
        'labelId': labelId,
        'templateBody': templateBody,
        'dailyQuota': dailyQuota,
        'startAt': startAt,
      }),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao criar campanha');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> updateCampaign(
    String id, {
    String? name,
    String? labelId,
    String? templateBody,
    int? dailyQuota,
    String? startAt,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (labelId != null) body['labelId'] = labelId;
    if (templateBody != null) body['templateBody'] = templateBody;
    if (dailyQuota != null) body['dailyQuota'] = dailyQuota;
    if (startAt != null) body['startAt'] = startAt;
    final res = await http.patch(
      Uri.parse('$baseUrl/campaigns/$id'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao atualizar campanha');
    return _decode(res);
  }

  static Future<void> deleteCampaign(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/campaigns/$id'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao excluir campanha');
  }

  static Future<Map<String, dynamic>> previewCampaign(String id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/campaigns/$id/preview'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao pré-visualizar campanha');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> launchCampaign(String id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/campaigns/$id/launch'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao lançar campanha');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> pauseCampaign(String id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/campaigns/$id/pause'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao pausar campanha');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> resumeCampaign(String id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/campaigns/$id/resume'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao retomar campanha');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> cancelCampaign(String id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/campaigns/$id/cancel'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao cancelar campanha');
    return _decode(res);
  }

  static Future<Map<String, dynamic>> getCampaignSchedule(String id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/campaigns/$id/schedule'),
      headers: await _authHeaders(),
    ).timeout(_timeout);
    _handleResponse(res, 'Falha ao carregar cronograma');
    return _decode(res);
  }
}
