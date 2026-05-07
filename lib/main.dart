import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'file_download.dart';
import 'platform_machine_id.dart';

import 'package:http/http.dart' as http;

void main() {
  Intl.defaultLocale = 'pt_BR';
  runApp(const CobrejaApp());
}

double _readDouble(dynamic value) {
  if (value is num) return value.toDouble();
  final raw = (value?.toString() ?? '').trim();
  if (raw.isEmpty) return 0;

  // Aceita formatos pt-BR (ex: "1.234,56") e tambem o formato com ponto
  // (ex: "1234.56"). Remove quaisquer simbolos como "R$".
  var cleaned = raw.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (cleaned.contains(',')) {
    cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
  }

  return double.tryParse(cleaned) ?? 0;
}

String _currency(double value) {
  return NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$ ',
    decimalDigits: 2,
  ).format(value);
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  static const String baseUrl = 'https://cobreja-backend-production.up.railway.app';

  static String _errorMessageFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) return message;
      }
    } catch (_) {}
    return 'Erro na comunicacao com o servidor.';
  }

  static Map<String, String> _jsonHeaders({String? token}) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Map<String, dynamic> _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static Map<String, dynamic> _extractPayloadMap(String body) {
    final decoded = _decodeJsonMap(body);
    final payload = decoded['data'];
    if (payload is Map<String, dynamic>) return payload;
    return decoded;
  }

  static List<Map<String, dynamic>> _extractPayloadList(String body) {
  final decoded = jsonDecode(body);

  // Se vier como { data: [...] }
  if (decoded is Map<String, dynamic> && decoded['data'] is List) {
    return List<Map<String, dynamic>>.from(decoded['data']);
  }

  // Se vier direto como lista
  if (decoded is List) {
    return List<Map<String, dynamic>>.from(decoded);
  }

  return [];
}

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? cpf,
    String? phone,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        if (cpf != null && cpf.trim().isNotEmpty) 'cpf': cpf.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> registerClient({
    required String name,
    required String email,
    required String password,
    String? cpf,
    String? phone,
    String? address,
    String? inviteCode,
    int? accountId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/client-register'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        if (cpf != null && cpf.trim().isNotEmpty) 'cpf': cpf.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
        if (inviteCode != null && inviteCode.trim().isNotEmpty)
          'inviteCode': inviteCode.trim(),
        if (accountId != null) 'accountId': accountId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'identifier': identifier,
        'password': password,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> fetchMe({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/me'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> getPremiumSettings({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/settings'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> updatePremiumSettings({
    required String token,
    required Map<String, dynamic> settings,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/settings'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode(settings),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<List<dynamic>> listSupportConversations({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/support/conversations'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadList(response.body);
  }

  static Future<Map<String, dynamic>> createSupportConversation({
    required String token,
    required String subject,
    required String body,
    int? clientId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/support/conversations'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'subject': subject,
        'body': body,
        if (clientId != null) 'clientId': clientId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> addSupportMessage({
    required String token,
    required int conversationId,
    required String body,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/support/conversations/$conversationId/messages'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'body': body}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> updateSupportStatus({
    required String token,
    required int conversationId,
    required String status,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/support/conversations/$conversationId/status'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'status': status}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<List<dynamic>> listAuditLogs({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/audit'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadList(response.body);
  }

  static Future<Map<String, dynamic>> fetchMercadoPagoSummary({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/payments/mercadopago/admin/summary'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> fetchCollectionAutomation({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/collections/automation-summary'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> registerCollectionGenerated({
    required String token,
    required int installmentId,
    String channel = 'WHATSAPP_MANUAL',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/collections/installments/$installmentId/generated'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'channel': channel}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> fetchSaasStatus({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/saas/status'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> selectSaasPlan({
    required String token,
    required String planCode,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/saas/select-plan'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'planCode': planCode}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> fetchInvite({
    required String inviteCode,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/invite/${Uri.encodeComponent(inviteCode.trim())}'),
      headers: _jsonHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<List<Map<String, dynamic>>> fetchMyDebts({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/my-debts'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadList(response.body);
  }

  static Future<List<Map<String, dynamic>>> fetchMyPayments({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/my-payments'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadList(response.body);
  }

  static Future<Map<String, dynamic>> createInstallmentPix({
    required String token,
    required int installmentId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/payments/mercadopago/installments/$installmentId/pix'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = response.body.trim();
      final missingPixRoute = response.statusCode == 404 &&
          (body.isEmpty || body.contains('Cannot POST') || body.contains('Cannot GET'));
      throw ApiException(
        statusCode: response.statusCode,
        message: missingPixRoute
            ? 'Modulo Pix ainda nao publicado no servidor. Aguarde o redeploy do backend e tente novamente.'
            : _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> fetchPixIntentStatus({
    required String token,
    required int intentId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/payments/mercadopago/intents/$intentId/status'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<List<Map<String, dynamic>>> fetchMyRequests({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/client/my-requests'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadList(response.body);
  }

  static Future<Map<String, dynamic>> createCreditRequest({
    required String token,
    required double amount,
    String? description,
    int? desiredTermDays,
    int? requestedInstallments,
    String type = 'EMPRESTIMO',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/request/credit-request'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'amount': amount,
        'type': type,
        if (desiredTermDays != null && desiredTermDays > 0)
          'desiredTermDays': desiredTermDays,
        if (requestedInstallments != null && requestedInstallments > 0)
          'requestedInstallments': requestedInstallments,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }

    return _extractPayloadMap(response.body);
  }

  static Future<List<Map<String, dynamic>>> fetchCreditRequests({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/request/credit-requests'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadList(response.body);
  }

  static Future<Map<String, dynamic>> approveCreditRequest({
    required String token,
    required int requestId,
    required DateTime dueDate,
    double? interestValue,
    double? dailyFee,
    int? installmentCount,
    String? decisionNote,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/request/approve-request'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'requestId': requestId,
        'dueDate': dueDate.toIso8601String(),
        if (interestValue != null) 'interestValue': interestValue,
        if (dailyFee != null) 'dailyFee': dailyFee,
        if (installmentCount != null && installmentCount > 0)
          'installmentCount': installmentCount,
        if (decisionNote != null && decisionNote.trim().isNotEmpty)
          'decisionNote': decisionNote.trim(),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }

    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> rejectCreditRequest({
    required String token,
    required int requestId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/request/reject-request'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'requestId': requestId,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }

    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> fetchClientsSummary({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/client/clients/summary'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> createClient({
    required String token,
    required String name,
    required String phone,
    String? cpf,
    String? address,
    String? email,
    String? avatarUrl,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/client/clients'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'name': name,
        'phone': phone,
        if (cpf != null && cpf.trim().isNotEmpty) 'cpf': cpf.trim(),
        if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (avatarUrl != null && avatarUrl.trim().isNotEmpty)
          'avatarUrl': avatarUrl.trim(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<List<Map<String, dynamic>>> fetchClients({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/client/clients'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadList(response.body);
  }

  static Future<Map<String, dynamic>> fetchClientById({
    required String token,
    required int clientId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/client/clients/$clientId'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> updateClient({
    required String token,
    required int clientId,
    required String name,
    required String phone,
    String? cpf,
    String? address,
    String? email,
    String? avatarUrl,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'phone': phone,
      if (cpf != null) 'cpf': cpf.trim(),
      if (address != null) 'address': address.trim(),
      if (email != null) 'email': email.trim(),
      if (avatarUrl != null) 'avatarUrl': avatarUrl.trim(),
    };
    final response = await http.put(
      Uri.parse('$baseUrl/api/client/clients/$clientId'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> createClientLogin({
    required String token,
    required int clientId,
    required String password,
    String? email,
    String? cpf,
    bool mergeByName = false,
  }) async {
    final body = <String, dynamic>{'password': password};
    final normalizedEmail = email?.trim() ?? '';
    if (normalizedEmail.isNotEmpty) body['email'] = normalizedEmail;
    final normalizedCpf = cpf?.trim() ?? '';
    if (normalizedCpf.isNotEmpty) body['cpf'] = normalizedCpf;
    if (mergeByName) body['mergeByName'] = true;

    final response = await http.post(
      Uri.parse('$baseUrl/api/client/clients/$clientId/create-login'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }

    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> mergeClientDuplicates({
    required String token,
    required int clientId,
    bool mergeByName = true,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/client/clients/$clientId/merge-duplicates'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'mergeByName': mergeByName,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }

    return _extractPayloadMap(response.body);
  }

  static Future<void> deleteClient({
    required String token,
    required int clientId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/client/clients/$clientId'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
  }

  static Future<void> restoreClient({
    required String token,
    required int clientId,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/client/clients/$clientId/restore'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
  }

  static Future<void> permanentlyDeleteClient({
    required String token,
    required int clientId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/client/clients/$clientId/permanent'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
  }

  static Future<Map<String, dynamic>> createDebt({
    required String token,
    required int clientId,
    required double principalAmount,
    required DateTime borrowedAt,
    required DateTime dueDate,
    String? title,
    String? monthlyInterestMode,
    double? monthlyInterestValue,
    String? dailyInterestMode,
    double? dailyInterestValue,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/debt'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'clientId': clientId,
        'principalAmount': principalAmount,
        'borrowedAt': borrowedAt.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        if (monthlyInterestMode != null && monthlyInterestMode.trim().isNotEmpty)
          'monthlyInterestMode': monthlyInterestMode.trim(),
        if (monthlyInterestValue != null && monthlyInterestValue > 0)
          'monthlyInterestValue': monthlyInterestValue,
        if (dailyInterestMode != null && dailyInterestMode.trim().isNotEmpty)
          'dailyInterestMode': dailyInterestMode.trim(),
        if (dailyInterestValue != null && dailyInterestValue > 0)
          'dailyInterestValue': dailyInterestValue,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> updateDebt({
    required String token,
    required int debtId,
    required double principalAmount,
    required DateTime borrowedAt,
    required DateTime dueDate,
    String? title,
    String? monthlyInterestMode,
    double? monthlyInterestValue,
    String? dailyInterestMode,
    double? dailyInterestValue,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/debt/$debtId'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'principalAmount': principalAmount,
        'borrowedAt': borrowedAt.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        if (monthlyInterestMode != null && monthlyInterestMode.trim().isNotEmpty)
          'monthlyInterestMode': monthlyInterestMode.trim(),
        if (monthlyInterestValue != null && monthlyInterestValue > 0)
          'monthlyInterestValue': monthlyInterestValue,
        if (dailyInterestMode != null && dailyInterestMode.trim().isNotEmpty)
          'dailyInterestMode': dailyInterestMode.trim(),
        if (dailyInterestValue != null && dailyInterestValue > 0)
          'dailyInterestValue': dailyInterestValue,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<Map<String, dynamic>> createPayment({
    required String token,
    required int clientId,
    required double amount,
    required String type,
    required DateTime date,
    int? debtId,
    int? installmentId,
    String? note,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/payment'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'clientId': clientId,
        if (debtId != null) 'debtId': debtId,
        if (installmentId != null) 'installmentId': installmentId,
        'amount': amount,
        'type': type,
        'paidAt': date.toIso8601String(),
        'date': date.toIso8601String(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<void> deletePayment({
    required String token,
    required int paymentId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/payment/$paymentId'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
  }

  static Future<Map<String, dynamic>> updatePayment({
    required String token,
    required int paymentId,
    required double amount,
    required DateTime paidAt,
    String? type,
    String? note,
  }) async {
    final payload = <String, dynamic>{
      'amount': amount,
      'paidAt': paidAt.toIso8601String(),
      'date': paidAt.toIso8601String(),
    };

    if (type != null && type.trim().isNotEmpty) {
      payload['type'] = type.trim();
    }
    if (note != null) {
      payload['note'] = note.trim();
    }

    final response = await http.put(
      Uri.parse('$baseUrl/api/payment/$paymentId'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadMap(response.body);
  }

  static Future<List<Map<String, dynamic>>> fetchPaymentHistory({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/payment/history'),
      headers: _jsonHeaders(token: token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
    return _extractPayloadList(response.body);
  }

  static Future<void> createRenegotiation({
    required String token,
    required int clientId,
    required double newTotal,
    required DateTime newDueDate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/renegotiation'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'clientId': clientId,
        'negotiatedTotal': newTotal,
        'newTotal': newTotal,
        'firstDueDate': newDueDate.toIso8601String(),
        'newDueDate': newDueDate.toIso8601String(),
        'installmentCount': 1,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessageFromBody(response.body),
      );
    }
  }
}

InterestValueType _interestValueTypeFromString(String? raw) {
  return raw == InterestValueType.fixedAmount.name
      ? InterestValueType.fixedAmount
      : InterestValueType.percentage;
}

double _resolveMonthlyInterestAmount(Client client, double principalBase) {
  if (client.monthlyInterestType == InterestValueType.fixedAmount) {
    return math.max(0, client.monthlyInterestAmount);
  }
  return math.max(0, principalBase * (client.monthlyInterestRate / 100));
}

double _resolveDailyInterestAmount(Client client, double lateBase) {
  if (client.dailyInterestType == InterestValueType.fixedAmount) {
    return math.max(0, client.dailyInterestAmount);
  }
  return math.max(0, lateBase * (client.dailyInterestRate / 100));
}

double _resolveDailyInterestAmountForOutstanding({
  required Client client,
  required double fullCycleInterest,
  required double outstandingInterest,
}) {
  final safeOutstanding = math.max(0, outstandingInterest);
  if (safeOutstanding <= 0.009) {
    return 0;
  }

  if (client.dailyInterestType == InterestValueType.fixedAmount) {
    final fullDaily = math.max(0, client.dailyInterestAmount).toDouble();
    if (fullCycleInterest <= 0.009) {
      return fullDaily;
    }
    final ratio = (safeOutstanding / fullCycleInterest).clamp(0.0, 1.0).toDouble();
    return fullDaily * ratio;
  }

  return math.max(0, safeOutstanding * (client.dailyInterestRate / 100));
}

String _formatInterestRule({
  required InterestValueType type,
  required double percentageValue,
  required double amountValue,
  required String suffix,
}) {
  if (type == InterestValueType.fixedAmount) {
    return '${_currency(amountValue)} $suffix';
  }
  return '${percentageValue.toStringAsFixed(2)}% $suffix';
}

const String _privacyPolicyUpdatedAt = '09 de abril de 2026';
const String _privacyPolicyContact = '(21) 96568-0720';
const String _accountDeletionPolicyUpdatedAt = '09 de abril de 2026';
const List<String> _windowsLicenseSecretParts = [
  'COBREJA',
  '_WIN',
  '_LIC',
  '_2026',
  '_FMB',
  '_0720',
];

String get _windowsLicenseSecret => _windowsLicenseSecretParts.join();

enum WindowsLicenseType { lifetime, singleUse, subscription }

class WindowsLicenseInfo {
  final WindowsLicenseType type;
  final String machineCode;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final String customerName;
  final String licenseId;

  const WindowsLicenseInfo({
    required this.type,
    required this.machineCode,
    required this.issuedAt,
    required this.expiresAt,
    required this.customerName,
    required this.licenseId,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isValid => !isExpired;

  String get typeLabel {
    switch (type) {
      case WindowsLicenseType.lifetime:
        return 'Vitalícia';
      case WindowsLicenseType.singleUse:
        return 'Uso único';
      case WindowsLicenseType.subscription:
        return 'Assinatura';
    }
  }
}

WindowsLicenseType? _licenseTypeFromRaw(String raw) {
  for (final type in WindowsLicenseType.values) {
    if (type.name == raw) return type;
  }
  return null;
}

String _createLicenseSignature(String payloadBase64) {
  final hmac = Hmac(sha256, utf8.encode(_windowsLicenseSecret));
  return hmac.convert(utf8.encode(payloadBase64)).toString().toUpperCase();
}

WindowsLicenseInfo? _parseWindowsLicense(
  String licenseKey,
  String machineCode,
) {
  try {
    final parts = licenseKey.trim().split('.');
    if (parts.length != 2) return null;

    final payloadBase64 = parts.first.trim();
    final providedSignature = parts.last.trim().toUpperCase();
    final expectedSignature = _createLicenseSignature(payloadBase64);
    if (providedSignature != expectedSignature) return null;

    final payloadJson = utf8.decode(base64Url.decode(base64Url.normalize(payloadBase64)));
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

    if (payload['product']?.toString() != 'COBREJA_WINDOWS') return null;
    if (payload['machineCode']?.toString() != machineCode) return null;

    final type = _licenseTypeFromRaw(payload['type']?.toString() ?? '');
    final issuedAt = DateTime.tryParse(payload['issuedAt']?.toString() ?? '');
    if (type == null || issuedAt == null) return null;

    final expiresRaw = payload['expiresAt']?.toString();
    final expiresAt = expiresRaw == null || expiresRaw.isEmpty
        ? null
        : DateTime.tryParse(expiresRaw);

    final info = WindowsLicenseInfo(
      type: type,
      machineCode: payload['machineCode']?.toString() ?? '',
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      customerName: payload['customerName']?.toString() ?? 'Cliente',
      licenseId: payload['licenseId']?.toString() ?? 'LIC',
    );

    return info.isValid ? info : null;
  } catch (_) {
    return null;
  }
}

class _PrivacyPolicySectionData {
  final String title;
  final List<String> paragraphs;

  const _PrivacyPolicySectionData({
    required this.title,
    required this.paragraphs,
  });
}

const List<_PrivacyPolicySectionData> _privacyPolicySections = [
  _PrivacyPolicySectionData(
    title: '1. Sobre esta política',
    paragraphs: [
      'A COBREJÁ é um aplicativo de gestão local de cobranças, clientes, juros, renegociações, lembretes e recebimentos.',
      'Esta política explica quais dados podem ser armazenados pelo app, para quais finalidades eles são usados e quais ações dependem diretamente do usuário.',
    ],
  ),
  _PrivacyPolicySectionData(
    title: '2. Dados tratados pelo aplicativo',
    paragraphs: [
      'O aplicativo pode armazenar no aparelho dados informados pelo próprio usuário, como nome, email, hash da senha, telefone, cadastro de clientes, valores emprestados, juros, vencimentos, pagamentos, renegociações, relatórios e lembretes personalizados.',
      'Também podem ser gerados dados derivados para funcionamento do app, como total em aberto, lucro gerado, prejuízo estimado, histórico financeiro e QR Code PIX para cobrança.',
    ],
  ),
  _PrivacyPolicySectionData(
    title: '3. Como esses dados são usados',
    paragraphs: [
      'Os dados são usados para autenticação local, organização da carteira, cálculo de juros, controle de pagamentos, renegociação de dívidas, backup, exportação de relatórios e geração de mensagens de cobrança iniciadas pelo usuário.',
      'A COBREJÁ não usa esses dados para publicidade comportamental nem para venda de informações.',
    ],
  ),
  _PrivacyPolicySectionData(
    title: '4. Armazenamento e compartilhamento',
    paragraphs: [
      'Pela implementação atual, os dados são armazenados localmente no dispositivo do usuário.',
      'O aplicativo não envia os dados para servidor próprio. As informações só saem do aparelho quando o usuário escolhe exportar backup/relatórios, copiar conteúdo ou abrir uma cobrança em aplicativos externos, como o WhatsApp.',
    ],
  ),
  _PrivacyPolicySectionData(
    title: '5. Exclusão e retenção',
    paragraphs: [
      'Clientes marcados como excluídos permanecem temporariamente na área de excluídos e são removidos automaticamente após 24 horas, salvo se forem eliminados definitivamente antes disso.',
      'Backups, PDFs, CSVs e comprovantes exportados passam a ficar sob responsabilidade do usuário no local onde forem salvos.',
    ],
  ),
  _PrivacyPolicySectionData(
    title: '6. Segurança',
    paragraphs: [
      'As senhas cadastradas no app são protegidas com hash forte e salt individual por conta.',
      'Mesmo assim, por se tratar de um aplicativo local, o usuário deve manter o aparelho protegido por senha, biometria e boas práticas de segurança.',
    ],
  ),
  _PrivacyPolicySectionData(
    title: '7. Contato',
    paragraphs: [
      'Para dúvidas sobre privacidade e uso do aplicativo, o contato atualmente informado para a COBREJÁ é $_privacyPolicyContact.',
      'Antes da publicação definitiva na Play Store, este contato pode ser substituído por um email oficial da marca, se desejado.',
    ],
  ),
];

Future<void> showPrivacyPolicyDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary.withOpacity(0.12),
            child: const Icon(
              Icons.privacy_tip_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Política de privacidade'),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Última atualização: $_privacyPolicyUpdatedAt',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'A COBREJÁ foi pensada para operar de forma local no aparelho, mantendo a carteira e os registros financeiros sob controle do próprio usuário.',
                style: TextStyle(
                  color: AppColors.textBody,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              for (final section in _privacyPolicySections)
                _PrivacyPolicySection(section: section),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

Future<void> showAccountDeletionInfoDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.danger.withOpacity(0.12),
            child: const Icon(
              Icons.person_remove_alt_1_rounded,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Exclusão de conta'),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Última atualização: $_accountDeletionPolicyUpdatedAt',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'A COBREJÁ permite excluir a conta local diretamente dentro do aplicativo.',
                style: TextStyle(color: AppColors.textBody, height: 1.5),
              ),
              const SizedBox(height: 14),
              const Text(
                'Ao excluir a conta, o app remove desta instalação os dados locais vinculados ao uso atual, incluindo sessão, clientes, pagamentos, renegociações e lembretes salvos no aparelho.',
                style: TextStyle(color: AppColors.textBody, height: 1.5),
              ),
              const SizedBox(height: 14),
              const Text(
                'Para excluir a conta dentro do app: abra o painel principal, toque no ícone de backup e escolha "Excluir conta local".',
                style: TextStyle(color: AppColors.textBody, height: 1.5),
              ),
              const SizedBox(height: 14),
              const Text(
                'Se você exportou backups, PDFs, CSVs ou comprovantes para fora do app, esses arquivos permanecem onde foram salvos e precisam ser apagados manualmente pelo usuário.',
                style: TextStyle(color: AppColors.textBody, height: 1.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}


class AppColors {
  static const primary = Color(0xFF082B54);
  static const secondary = Color(0xFF16A34A);
  static const accent = Color(0xFF7C3AED);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
  static const textStrong = Color(0xFF061C3D);
  static const textBody = Color(0xFF253A57);
  static const textMuted = Color(0xFF64748B);
  static const border = Color(0xFFC8D3E2);
  static const borderSoft = Color(0xFFD7E0EC);
  static const surface = Colors.white;
  static const surfaceSoft = Color(0xFFF3F7FB);
  static const surfaceTint = Color(0xFFEAF1F8);
  static const background = Color(0xFFF3F7FB);
  static const backgroundTop = Color(0xFFEAF2FA);
  static const backgroundMid = Color(0xFFF8FAFC);
  static const backgroundBottom = Color(0xFFECFDF5);
}

class AppRadii {
  static const double sm = 14;
  static const double md = 18;
  static const double lg = 22;
  static const double xl = 28;
  static const double xxl = 36;
}

class AppSpacing {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;
  static const double page = 28;
}

class AppTypography {
  static const textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 42,
      fontWeight: FontWeight.w800,
      color: AppColors.textStrong,
      height: 1.05,
      letterSpacing: -0.6,
    ),
    headlineLarge: TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      color: AppColors.textStrong,
      height: 1.08,
      letterSpacing: -0.4,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      color: AppColors.textStrong,
      height: 1.1,
      letterSpacing: -0.3,
    ),
    titleLarge: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      color: AppColors.textStrong,
      height: 1.16,
    ),
    titleMedium: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: AppColors.textStrong,
      height: 1.2,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: AppColors.textBody,
      height: 1.55,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppColors.textMuted,
      height: 1.5,
    ),
    labelLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: 0.1,
      height: 1.1,
    ),
  );
}


bool _isValidEmail(String value) {
  final email = value.trim();
  final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  return emailRegex.hasMatch(email);
}

bool _isValidCpf(String value) {
  final digits = value.replaceAll(RegExp(r'\D+'), '');
  return digits.length == 11;
}

bool _isStrongPassword(String value) {
  final hasMinLength = value.length >= 8;
  final hasUppercase = RegExp(r'[A-Z]').hasMatch(value);
  final hasLowercase = RegExp(r'[a-z]').hasMatch(value);
  final hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(value);
  return hasMinLength && hasUppercase && hasLowercase && hasSpecial;
}

String _normalizeEmail(String value) => value.trim().toLowerCase();

String _normalizeClientName(String value) => value.trim().toLowerCase();

const String _currentPasswordHashVersion = 'pbkdf2_sha256_v1';
const int _currentPasswordIterations = 60000;
const int _currentPasswordKeyLength = 32;
const Duration _splashAnimationDuration = Duration(milliseconds: 650);
const String _pixPrimaryKey = '12704258708';
const String _pixFallbackPhoneKey = '21965680720';
const String _pixMerchantName = 'COBREJA';
const String _pixMerchantCity = 'RIO DE JANEIRO';

String _generateSalt() {
  final random = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64UrlEncode(bytes);
}

String _protectPasswordLegacy(String password, String salt) {
  final source = '$salt::$password::cobreja';
  int hash = 146959810;
  for (final codeUnit in source.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 16777619) & 0x7fffffff;
    hash = ((hash << 5) - hash + codeUnit) & 0x7fffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _protectPassword(
  String password,
  String salt, {
  int iterations = _currentPasswordIterations,
  int keyLength = _currentPasswordKeyLength,
}) {
  final passwordBytes = utf8.encode(password);
  final saltBytes = utf8.encode(salt);
  final hmac = Hmac(sha256, passwordBytes);
  final blockCount = (keyLength / 32).ceil();
  final derived = <int>[];

  for (var block = 1; block <= blockCount; block++) {
    final initialInput = <int>[
      ...saltBytes,
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ];

    var u = hmac.convert(initialInput).bytes;
    final t = Uint8List.fromList(u);

    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }

    derived.addAll(t);
  }

  return base64UrlEncode(derived.take(keyLength).toList());
}

bool _secureEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

class UserAccount {
  final String name;
  final String email;
  final String password;
  final String passwordSalt;
  final String passwordHash;
  final String passwordHashVersion;
  final int passwordIterations;

  const UserAccount({
    required this.name,
    required this.email,
    this.password = '',
    this.passwordSalt = '',
    this.passwordHash = '',
    this.passwordHashVersion = '',
    this.passwordIterations = 0,
  });

  factory UserAccount.create({
    required String name,
    required String email,
    required String password,
  }) {
    final salt = _generateSalt();
    return UserAccount(
      name: name,
      email: email,
      password: '',
      passwordSalt: salt,
      passwordHash: _protectPassword(
        password,
        salt,
        iterations: _currentPasswordIterations,
      ),
      passwordHashVersion: _currentPasswordHashVersion,
      passwordIterations: _currentPasswordIterations,
    );
  }

  bool get needsSecurityUpgrade {
    if (password.isNotEmpty) return true;
    if (passwordHash.isEmpty || passwordSalt.isEmpty) return true;
    return passwordHashVersion != _currentPasswordHashVersion ||
        passwordIterations < _currentPasswordIterations;
  }

  UserAccount upgradeWithPassword(String plainPassword) {
    final salt = _generateSalt();
    return UserAccount(
      name: name,
      email: email,
      password: '',
      passwordSalt: salt,
      passwordHash: _protectPassword(
        plainPassword,
        salt,
        iterations: _currentPasswordIterations,
      ),
      passwordHashVersion: _currentPasswordHashVersion,
      passwordIterations: _currentPasswordIterations,
    );
  }

  bool verifyPassword(String plainPassword) {
    if (passwordHash.isNotEmpty && passwordSalt.isNotEmpty) {
      if (passwordHashVersion == _currentPasswordHashVersion) {
        final candidate = _protectPassword(
          plainPassword,
          passwordSalt,
          iterations: passwordIterations > 0
              ? passwordIterations
              : _currentPasswordIterations,
        );
        return _secureEquals(candidate, passwordHash);
      }

      final legacyCandidate = _protectPasswordLegacy(plainPassword, passwordSalt);
      return _secureEquals(legacyCandidate, passwordHash);
    }
    return password == plainPassword;
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'password': password,
      'passwordSalt': passwordSalt,
      'passwordHash': passwordHash,
      'passwordHashVersion': passwordHashVersion,
      'passwordIterations': passwordIterations,
    };
  }

  factory UserAccount.fromMap(Map<String, dynamic> map) {
    return UserAccount(
      name: map['name']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      password: map['password']?.toString() ?? '',
      passwordSalt: map['passwordSalt']?.toString() ?? '',
      passwordHash: map['passwordHash']?.toString() ?? '',
      passwordHashVersion: map['passwordHashVersion']?.toString() ?? '',
      passwordIterations: map['passwordIterations'] is int
          ? map['passwordIterations'] as int
          : int.tryParse(map['passwordIterations']?.toString() ?? '') ?? 0,
    );
  }
}

class PaymentRecord {
  final String id;
  final DateTime date;
  final double amount;
  final double interestPaid;
  final double dailyPaid;
  final double principalPaid;
  final String type;
  final String note;

  const PaymentRecord({
    required this.id,
    required this.date,
    required this.amount,
    required this.interestPaid,
    this.dailyPaid = 0,
    required this.principalPaid,
    required this.type,
    required this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'amount': amount,
      'interestPaid': interestPaid,
      'dailyPaid': dailyPaid,
      'principalPaid': principalPaid,
      'type': type,
      'note': note,
    };
  }

  factory PaymentRecord.fromMap(Map<String, dynamic> map) {
    return PaymentRecord(
      id: map['id']?.toString() ?? '',
      date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
      amount: _readDouble(map['amount']),
      interestPaid: _readDouble(map['interestPaid']),
      dailyPaid: _readDouble(map['dailyPaid']),
      principalPaid: _readDouble(map['principalPaid']),
      type: map['type']?.toString() ?? 'custom',
      note: map['note']?.toString() ?? '',
    );
  }
}

class Client {
  String id;
  int? backendUserId;
  String? cpf;
  String? address;
  String? email;
  String? avatarUrl;
  int? backendPrimaryDebtId;
  String name;
  String phone;
  double borrowedAmount;
  double activePrincipalCollected;
  double monthlyInterestRate;
  double monthlyInterestAmount;
  InterestValueType monthlyInterestType;
  double dailyInterestRate;
  double dailyInterestAmount;
  InterestValueType dailyInterestType;
  DateTime borrowedDate;
  DateTime dueDate;
  int originalTermDays;
  DateTime cycleStartDate;
  DateTime? deletedAt;
  String? statusBeforeDeletion;
  String status;
  bool pagouJuros;
  bool isNegotiated;
  bool? isMarkedAsLost;
  int installmentCount;
  int installmentsPaid;
  double installmentAmount;
  DateTime? renegotiatedAt;
  DateTime? installmentStartDate;
  DateTime? lastInterestPaidAt;
  double interestPaidCurrentCycle;
  double totalInterestCollected;
  double totalPrincipalCollected;
  List<PaymentRecord> paymentHistory;
  // Snapshot do backend (nao persiste em toMap/fromMap) para telas que precisam
  // listar todas as dividas do cliente, inclusive quando houver mais de uma.
  List<Map<String, dynamic>> backendDebts;

  Client({
    required this.id,
    this.backendUserId,
    this.cpf,
    this.address,
    this.email,
    this.avatarUrl,
    this.backendPrimaryDebtId,
    required this.name,
    required this.phone,
    required this.borrowedAmount,
    this.activePrincipalCollected = 0,
    required this.monthlyInterestRate,
    this.monthlyInterestAmount = 0,
    this.monthlyInterestType = InterestValueType.percentage,
    required this.dailyInterestRate,
    this.dailyInterestAmount = 0,
    this.dailyInterestType = InterestValueType.percentage,
    required this.borrowedDate,
    required this.dueDate,
      required this.originalTermDays,
      required this.cycleStartDate,
      this.deletedAt,
      this.statusBeforeDeletion,
      this.status = 'devendo',
    this.pagouJuros = false,
    this.isNegotiated = false,
    this.isMarkedAsLost = false,
    this.installmentCount = 0,
    this.installmentsPaid = 0,
    this.installmentAmount = 0,
    this.renegotiatedAt,
    this.installmentStartDate,
    this.lastInterestPaidAt,
    this.interestPaidCurrentCycle = 0,
    this.totalInterestCollected = 0,
    this.totalPrincipalCollected = 0,
    this.paymentHistory = const [],
    this.backendDebts = const [],
  });

  double get remainingPrincipal =>
      math.max(0, borrowedAmount - activePrincipalCollected);

  bool get isMarkedAsLostSafe => isMarkedAsLost == true;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'backendUserId': backendUserId,
      'cpf': cpf,
      'address': address,
      'email': email,
      'avatarUrl': avatarUrl,
      'backendPrimaryDebtId': backendPrimaryDebtId,
      'name': name,
      'phone': phone,
      'borrowedAmount': borrowedAmount,
      'activePrincipalCollected': activePrincipalCollected,
      'monthlyInterestRate': monthlyInterestRate,
      'monthlyInterestAmount': monthlyInterestAmount,
      'monthlyInterestType': monthlyInterestType.name,
      'dailyInterestRate': dailyInterestRate,
      'dailyInterestAmount': dailyInterestAmount,
      'dailyInterestType': dailyInterestType.name,
      'borrowedDate': borrowedDate.toIso8601String(),
      'dueDate': dueDate.toIso8601String(),
      'originalTermDays': originalTermDays,
      'cycleStartDate': cycleStartDate.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'statusBeforeDeletion': statusBeforeDeletion,
      'status': status,
      'pagouJuros': pagouJuros,
      'isNegotiated': isNegotiated,
      'isMarkedAsLost': isMarkedAsLostSafe,
      'installmentCount': installmentCount,
      'installmentsPaid': installmentsPaid,
      'installmentAmount': installmentAmount,
      'renegotiatedAt': renegotiatedAt?.toIso8601String(),
      'installmentStartDate': installmentStartDate?.toIso8601String(),
      'lastInterestPaidAt': lastInterestPaidAt?.toIso8601String(),
      'interestPaidCurrentCycle': interestPaidCurrentCycle,
      'totalInterestCollected': totalInterestCollected,
      'totalPrincipalCollected': totalPrincipalCollected,
      'paymentHistory': paymentHistory.map((item) => item.toMap()).toList(),
    };
  }

  factory Client.fromMap(Map<String, dynamic> map) {
    final borrowedDate =
        DateTime.tryParse(map['borrowedDate']?.toString() ?? '') ??
            DateTime.now();
    final dueDate =
        DateTime.tryParse(map['dueDate']?.toString() ?? '') ??
            borrowedDate.add(const Duration(days: 30));
    final originalTermDays = map['originalTermDays'] is int
        ? map['originalTermDays'] as int
        : math.max(1, dueDate.difference(borrowedDate).inDays);

    int? backendPrimaryDebtId;
    final rawDebtId = map['backendPrimaryDebtId'];
    if (rawDebtId is num) {
      backendPrimaryDebtId = rawDebtId.toInt();
    } else if (rawDebtId != null) {
      backendPrimaryDebtId = int.tryParse(rawDebtId.toString());
    }

    int? backendUserId;
    final rawUserId = map['backendUserId'] ?? map['userId'];
    if (rawUserId is num) {
      backendUserId = rawUserId.toInt();
    } else if (rawUserId != null) {
      backendUserId = int.tryParse(rawUserId.toString());
    }

    return Client(
      id: map['id']?.toString() ?? '',
      backendUserId: backendUserId,
      cpf: map['cpf']?.toString(),
      address: map['address']?.toString(),
      email: map['email']?.toString(),
      avatarUrl: map['avatarUrl']?.toString(),
      backendPrimaryDebtId: backendPrimaryDebtId,
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      borrowedAmount: _readDouble(map['borrowedAmount']),
      activePrincipalCollected: map['activePrincipalCollected'] == null
          ? _readDouble(map['totalPrincipalCollected'])
          : _readDouble(map['activePrincipalCollected']),
      monthlyInterestRate: _readDouble(map['monthlyInterestRate']),
      monthlyInterestAmount: _readDouble(map['monthlyInterestAmount']),
      monthlyInterestType: _interestValueTypeFromString(
        map['monthlyInterestType']?.toString(),
      ),
      dailyInterestRate: _readDouble(map['dailyInterestRate']),
      dailyInterestAmount: _readDouble(map['dailyInterestAmount']),
      dailyInterestType: _interestValueTypeFromString(
        map['dailyInterestType']?.toString(),
      ),
      borrowedDate: borrowedDate,
      dueDate: dueDate,
      originalTermDays: originalTermDays <= 0 ? 30 : originalTermDays,
      cycleStartDate:
          DateTime.tryParse(map['cycleStartDate']?.toString() ?? '') ??
              borrowedDate,
      deletedAt: DateTime.tryParse(map['deletedAt']?.toString() ?? ''),
      statusBeforeDeletion: map['statusBeforeDeletion']?.toString(),
      status: map['status']?.toString() ?? 'devendo',
      pagouJuros: map['pagouJuros'] == true,
      isNegotiated: map['isNegotiated'] == true,
      isMarkedAsLost: map['isMarkedAsLost'] == true,
      installmentCount: (map['installmentCount'] as num?)?.toInt() ?? 0,
      installmentsPaid: (map['installmentsPaid'] as num?)?.toInt() ?? 0,
      installmentAmount: _readDouble(map['installmentAmount']),
      renegotiatedAt:
          DateTime.tryParse(map['renegotiatedAt']?.toString() ?? ''),
      installmentStartDate:
          DateTime.tryParse(map['installmentStartDate']?.toString() ?? ''),
      lastInterestPaidAt:
          DateTime.tryParse(map['lastInterestPaidAt']?.toString() ?? ''),
      interestPaidCurrentCycle: _readDouble(map['interestPaidCurrentCycle']),
      totalInterestCollected: _readDouble(map['totalInterestCollected']),
      totalPrincipalCollected: _readDouble(map['totalPrincipalCollected']),
      paymentHistory: (map['paymentHistory'] as List<dynamic>? ?? [])
          .map((item) => PaymentRecord.fromMap(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

enum PaymentMode { interestOnly, principalOnly, automatic, settlement }

enum InterestValueType { percentage, fixedAmount }

enum _FeedbackTone { success, warning, error, info }

enum _ClientQuickFilter { todos, atrasados, venceHoje, renegociados }

enum _MainSection {
  inicio,
  devendo,
  juros,
  parcelasPagas,
  quitados,
  excluidos,
  emAtraso,
  venceHoje,
  renegociados,
  solicitacoes,
  metricas,
  configuracoes,
}

enum _ChargeCollectionMode {
  total,
  interestOnly,
  currentCycle,
  dailyOnly,
  installment,
}

enum AppAccentPreset { cobreja, esmeralda, oceano, sunset }

enum AppThemePreference { claro, escuro }

extension AppThemePreferenceExtension on AppThemePreference {
  String get label => switch (this) {
    AppThemePreference.claro => 'Claro',
    AppThemePreference.escuro => 'Escuro',
  };

  IconData get icon => switch (this) {
    AppThemePreference.claro => Icons.light_mode_rounded,
    AppThemePreference.escuro => Icons.dark_mode_rounded,
  };
}

extension AppAccentPresetExtension on AppAccentPreset {
  String get label => switch (this) {
    AppAccentPreset.cobreja => 'COBREJÁ',
    AppAccentPreset.esmeralda => 'Esmeralda',
    AppAccentPreset.oceano => 'Oceano',
    AppAccentPreset.sunset => 'Sunset',
  };

  Color get primaryColor => switch (this) {
    AppAccentPreset.cobreja => AppColors.primary,
    AppAccentPreset.esmeralda => const Color(0xFF059669),
    AppAccentPreset.oceano => const Color(0xFF0284C7),
    AppAccentPreset.sunset => const Color(0xFFEA580C),
  };

  Color get secondaryColor => switch (this) {
    AppAccentPreset.cobreja => AppColors.secondary,
    AppAccentPreset.esmeralda => const Color(0xFF10B981),
    AppAccentPreset.oceano => const Color(0xFF06B6D4),
    AppAccentPreset.sunset => const Color(0xFFF59E0B),
  };
}

enum AppPlan { basic, professional, premium }

extension AppPlanExtension on AppPlan {
  String get label => switch (this) {
    AppPlan.basic => 'Básico',
    AppPlan.professional => 'Profissional',
    AppPlan.premium => 'Premium',
  };

  String get subtitle => switch (this) {
    AppPlan.basic => 'Operação essencial da carteira',
    AppPlan.professional => 'Mais controle, cobrança e produtividade',
    AppPlan.premium => 'Visão avançada e recursos completos',
  };

  String get priceLabel => switch (this) {
    AppPlan.basic => 'Entrada',
    AppPlan.professional => 'Mais vendido',
    AppPlan.premium => 'Completo',
  };

  Color get color => switch (this) {
    AppPlan.basic => const Color(0xFF061C3D),
    AppPlan.professional => const Color(0xFF22C55E),
    AppPlan.premium => const Color(0xFF7C3AED),
  };

  List<String> get highlights => switch (this) {
    AppPlan.basic => const [
      'Clientes e dívidas',
      'Pagamentos e histórico',
      'Cobrança simples no WhatsApp',
    ],
    AppPlan.professional => const [
      'Tudo do Básico',
      'Lembretes personalizados',
      'Backup e exportações',
      'Renegociação e PIX',
    ],
    AppPlan.premium => const [
      'Tudo do Profissional',
      'Relatórios completos',
      'Visão mensal de recebimentos',
      'Comprovante em PDF',
    ],
  };
}

enum _MetricCardKind {
  totalToReceive,
  totalReceived,
  totalOverdue,
  monthlyInterestReceivable,
  totalProfit,
  totalLent,
  estimatedLoss,
}

enum _PaymentHistoryQuickFilter {
  todos,
  hoje,
  ultimos7Dias,
  ultimos30Dias,
  juros,
  principal,
  quitacao,
}

const Duration _excludedRetention = Duration(hours: 24);

const int _estimatedLossOverdueDays = 90;

enum _ReportPeriodPreset {
  todoPeriodo,
  hoje,
  ultimos7Dias,
  ultimos30Dias,
  esteMes,
  personalizado,
}

class _ResolvedReportPeriod {
  final DateTime? startDate;
  final DateTime? endDate;
  final String label;

  const _ResolvedReportPeriod({
    required this.startDate,
    required this.endDate,
    required this.label,
  });
}

class _MonthlyReceiptPoint {
  final DateTime month;
  final double total;
  final double interest;
  final double principal;

  const _MonthlyReceiptPoint({
    required this.month,
    required this.total,
    required this.interest,
    required this.principal,
  });
}

class DebtSummary {
  final double remainingPrincipal;
  final double cycleInterest;
  final double lateInterest;
  final double totalInterestDue;
  final double totalDebt;
  final int monthlyCyclesDue;
  final int overdueDays;
  final bool isOverdue;
  final bool isDueToday;
  final bool isNegotiated;
  final int installmentCount;
  final int installmentsPaid;
  final double installmentAmount;

  const DebtSummary({
    required this.remainingPrincipal,
    required this.cycleInterest,
    required this.lateInterest,
    required this.totalInterestDue,
    required this.totalDebt,
    this.monthlyCyclesDue = 0,
    required this.overdueDays,
    required this.isOverdue,
    required this.isDueToday,
    this.isNegotiated = false,
    this.installmentCount = 0,
    this.installmentsPaid = 0,
    this.installmentAmount = 0,
  });
}

class DashboardMetrics {
  final double totalToReceive;
  final double totalReceived;
  final double totalOverdue;
  final double totalProfit;
  final double totalLent;
  final double monthlyInterestReceivable;
  final double estimatedLoss;

  const DashboardMetrics({
    required this.totalToReceive,
    required this.totalReceived,
    required this.totalOverdue,
    required this.totalProfit,
    required this.totalLent,
    required this.monthlyInterestReceivable,
    required this.estimatedLoss,
  });
}

class ReminderItem {
  final String title;
  final String subtitle;
  final Client client;
  final Color color;

  const ReminderItem({
    required this.title,
    required this.subtitle,
    required this.client,
    required this.color,
  });
}

class CustomReminder {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;

  const CustomReminder({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CustomReminder.fromMap(Map<String, dynamic> map) {
    return CustomReminder(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class FinanceService {
  static DebtSummary calculateDebt(Client client, {DateTime? now}) {
    final reference = _dateOnly(now ?? DateTime.now());
    final dueDate = _dateOnly(client.dueDate);
    final remainingPrincipal = client.remainingPrincipal;

    if (client.status != 'devendo' || remainingPrincipal <= 0.009) {
      return const DebtSummary(
        remainingPrincipal: 0,
        cycleInterest: 0,
        lateInterest: 0,
        totalInterestDue: 0,
        totalDebt: 0,
        monthlyCyclesDue: 0,
        overdueDays: 0,
        isOverdue: false,
        isDueToday: false,
      );
    }

    if (client.isNegotiated) {
      final overdueDays =
          reference.isAfter(dueDate) ? reference.difference(dueDate).inDays : 0;
      final installmentBase = client.installmentAmount > 0
          ? math.min(client.installmentAmount, remainingPrincipal)
          : remainingPrincipal;
      final lateInterest = overdueDays <= 0
          ? 0.0
          : _resolveDailyInterestAmount(client, installmentBase) * overdueDays;
        return DebtSummary(
          remainingPrincipal: remainingPrincipal,
          cycleInterest: 0,
          lateInterest: lateInterest,
          totalInterestDue: lateInterest,
          totalDebt: remainingPrincipal + lateInterest,
          monthlyCyclesDue: 0,
          overdueDays: overdueDays,
          isOverdue: overdueDays > 0,
          isDueToday: reference == dueDate,
          isNegotiated: true,
          installmentCount: client.installmentCount,
        installmentsPaid: client.installmentsPaid,
        installmentAmount: client.installmentAmount,
      );
    }

    final overdueDays =
        reference.isAfter(dueDate) ? reference.difference(dueDate).inDays : 0;

    // Juros mensal representa apenas o ciclo atual.
    // Se houver atraso, a diária deve incidir sobre o total em aberto do ciclo
    // (principal + juros do ciclo), para não subestimar a mora.
    final monthlyInterestAmount =
        _resolveMonthlyInterestAmount(client, remainingPrincipal);
    final cycleInterest = math.max(
      0.0,
      monthlyInterestAmount - client.interestPaidCurrentCycle,
    ).toDouble();
    final dailyBase = (remainingPrincipal + cycleInterest).toDouble();
    final lateInterestPerDay = _resolveDailyInterestAmount(client, dailyBase);
    final lateInterest = overdueDays <= 0 ? 0.0 : lateInterestPerDay * overdueDays;
    final totalInterest = math.max(0.0, cycleInterest + lateInterest).toDouble();

    return DebtSummary(
      remainingPrincipal: remainingPrincipal,
      cycleInterest: cycleInterest,
      lateInterest: lateInterest,
      totalInterestDue: totalInterest,
      totalDebt: remainingPrincipal + totalInterest,
      monthlyCyclesDue: 1,
      overdueDays: overdueDays,
      isOverdue: overdueDays > 0,
      isDueToday: reference == dueDate,
      isNegotiated: client.isNegotiated,
      installmentCount: client.installmentCount,
      installmentsPaid: client.installmentsPaid,
      installmentAmount: client.installmentAmount,
    );
  }

  static bool isEstimatedLoss(Client client, {DateTime? now}) {
    final debt = calculateDebt(client, now: now);
    if (client.status != 'devendo' || debt.totalDebt <= 0.009) {
      return false;
    }
    return client.isMarkedAsLostSafe || debt.overdueDays >= _estimatedLossOverdueDays;
  }

  static DashboardMetrics calculateDashboard(List<Client> clients) {
    double totalToReceive = 0;
    double totalReceived = 0;
    double totalOverdue = 0;
    double totalProfit = 0;
    double totalLent = 0;
    double monthlyInterestReceivable = 0;
    double estimatedLoss = 0;

    for (final client in clients) {
      final debt = calculateDebt(client);
      if (client.status != 'excluido') {
        totalLent += client.borrowedAmount;
      }
      if (client.status == 'devendo') {
        totalToReceive += debt.totalDebt;
        monthlyInterestReceivable += debt.cycleInterest + debt.lateInterest;
        if (debt.isOverdue) {
          totalOverdue += debt.totalDebt;
        }
        if (isEstimatedLoss(client)) {
          estimatedLoss += debt.totalDebt;
        }
      }
      totalReceived +=
          client.totalInterestCollected + client.totalPrincipalCollected;
      totalProfit += client.totalInterestCollected;
    }

    return DashboardMetrics(
      totalToReceive: totalToReceive,
      totalReceived: totalReceived,
      totalOverdue: totalOverdue,
      totalProfit: totalProfit,
      totalLent: totalLent,
      monthlyInterestReceivable: monthlyInterestReceivable,
      estimatedLoss: estimatedLoss,
    );
  }

  static List<ReminderItem> generateReminders(List<Client> clients) {
    final items = <ReminderItem>[];
    for (final client in clients.where((item) => item.status == 'devendo')) {
      final debt = calculateDebt(client);
      if (debt.isOverdue) {
        items.add(
          ReminderItem(
            title: '${client.name} esta em atraso',
            subtitle:
                '${debt.overdueDays} dia(s) • total ${_currency(debt.totalDebt)}',
            client: client,
            color: const Color(0xFFDC2626),
          ),
        );
      } else if (debt.isDueToday) {
        items.add(
          ReminderItem(
            title: '${client.name} vence hoje',
            subtitle: 'Cobrar ${_currency(debt.totalDebt)} ainda hoje',
            client: client,
            color: const Color(0xFFF59E0B),
          ),
        );
      } else if (client.dueDate.difference(DateTime.now()).inDays == 1) {
        items.add(
          ReminderItem(
            title: '${client.name} vence amanhã',
            subtitle: 'Prepare a cobrança de ${_currency(debt.totalDebt)}',
            client: client,
            color: const Color(0xFF061C3D),
          ),
        );
      }
    }
    items.sort((a, b) => a.client.dueDate.compareTo(b.client.dueDate));
    return items;
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

class CobrejaApp extends StatefulWidget {
  const CobrejaApp({super.key});

  @override
  State<CobrejaApp> createState() => _CobrejaAppState();
}

class _CobrejaAppState extends State<CobrejaApp> {
  UserAccount? _account;
  List<UserAccount> _accounts = [];
  bool _isLoading = true;
  bool _sessionAuthenticated = false;
  String? _sessionRole;
  String? _windowsMachineCode;
  WindowsLicenseInfo? _windowsLicense;
  AppAccentPreset _accentPreset = AppAccentPreset.cobreja;
  AppThemePreference _themePreference = AppThemePreference.claro;
  double _fontScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('account');
    final accountsRaw = prefs.getString('accounts');
    final sessionEmail = prefs.getString('session_email');
    final token = prefs.getString('token');
    final savedRole = prefs.getString('session_role');
    final rawAccentPreset = prefs.getString('app_accent_preset');
    final rawThemePreference = prefs.getString('app_theme_preference');
    final rawFontScale = prefs.getDouble('app_font_scale');

    List<UserAccount> loadedAccounts = [];
    if (accountsRaw != null && accountsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(accountsRaw) as List<dynamic>;
        loadedAccounts = decoded
            .map((item) => UserAccount.fromMap(item as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    if (loadedAccounts.isEmpty && raw != null && raw.isNotEmpty) {
      try {
        loadedAccounts = [UserAccount.fromMap(jsonDecode(raw))];
      } catch (_) {}
    }

    final deduplicatedAccounts = <String, UserAccount>{};
    for (final account in loadedAccounts) {
      deduplicatedAccounts[_normalizeEmail(account.email)] = account;
    }
    loadedAccounts = deduplicatedAccounts.values.toList();

    UserAccount? sessionAccount;
    if (sessionEmail != null && loadedAccounts.isNotEmpty) {
      for (final account in loadedAccounts) {
        if (_normalizeEmail(account.email) == _normalizeEmail(sessionEmail)) {
          sessionAccount = account;
          break;
        }
      }
    }

    var sessionAuthenticated =
        sessionAccount != null && token != null && token.isNotEmpty;
    var sessionRole = savedRole;

    // Confirma o token no backend para evitar "sessÃ£o zera no F5" quando o token
    // expira/Ã© invÃ¡lido ou quando mudou a estrutura do JWT.
    if (sessionAuthenticated) {
      try {
        final me = await ApiService.fetchMe(token: token!);
        final user = me['user'] as Map<String, dynamic>?;
        final role = user?['role']?.toString();
        if (role != null && role.isNotEmpty) {
          sessionRole = role;
          await prefs.setString('session_role', role);
        }
      } catch (e) {
        if (e is ApiException && e.statusCode == 401) {
          sessionAuthenticated = false;
          sessionAccount = null;
          sessionRole = null;
          await prefs.remove('session_email');
          await prefs.remove('token');
          await prefs.remove('session_role');
        }
      }
    }

    String? machineCode;
    WindowsLicenseInfo? windowsLicense;
    var accentPreset = AppAccentPreset.cobreja;
    var themePreference = AppThemePreference.claro;
    var fontScale = 1.0;
    if (rawAccentPreset != null && rawAccentPreset.isNotEmpty) {
      try {
        accentPreset = AppAccentPreset.values.firstWhere(
          (item) => item.name == rawAccentPreset,
        );
      } catch (_) {}
    }
    if (rawFontScale != null && rawFontScale >= 0.85 && rawFontScale <= 1.3) {
      fontScale = rawFontScale;
    }
    if (rawThemePreference != null && rawThemePreference.isNotEmpty) {
      try {
        themePreference = AppThemePreference.values.firstWhere(
          (item) => item.name == rawThemePreference,
        );
      } catch (_) {}
    }
    if (isWindowsDesktopPlatform) {
      machineCode = await getPlatformMachineCode();
      final savedLicense = prefs.getString('windows_license_key');
      if (machineCode != null &&
          savedLicense != null &&
          savedLicense.trim().isNotEmpty) {
        windowsLicense = _parseWindowsLicense(savedLicense, machineCode);
        if (windowsLicense == null) {
          await prefs.remove('windows_license_key');
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _accounts = loadedAccounts;
      _account = sessionAccount;
      _sessionAuthenticated = sessionAuthenticated;
      _sessionRole = sessionRole;
      _windowsMachineCode = machineCode;
      _windowsLicense = windowsLicense;
      _accentPreset = accentPreset;
      _themePreference = themePreference;
      _fontScale = fontScale;
      _isLoading = false;
    });
  }

  Future<void> _updateThemePreference(AppThemePreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme_preference', preference.name);
    if (!mounted) return;
    setState(() {
      _themePreference = preference;
    });
  }

  Future<void> _updateAccentPreset(AppAccentPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_accent_preset', preset.name);
    if (!mounted) return;
    setState(() {
      _accentPreset = preset;
    });
  }

  Future<void> _updateFontScale(double scale) async {
    final normalized = scale.clamp(0.85, 1.30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('app_font_scale', normalized);
    if (!mounted) return;
    setState(() {
      _fontScale = normalized;
    });
  }

  Future<void> _resetVisualPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('app_accent_preset');
    await prefs.remove('app_theme_preference');
    await prefs.remove('app_font_scale');
    if (!mounted) return;
    setState(() {
      _accentPreset = AppAccentPreset.cobreja;
      _themePreference = AppThemePreference.claro;
      _fontScale = 1.0;
    });
  }

  Future<bool> _activateWindowsLicense(String licenseKey) async {
    final machineCode = _windowsMachineCode ?? await getPlatformMachineCode();
    if (machineCode == null) return false;

    final license = _parseWindowsLicense(licenseKey, machineCode);
    if (license == null) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('windows_license_key', licenseKey.trim());

    if (!mounted) return true;

    setState(() {
      _windowsMachineCode = machineCode;
      _windowsLicense = license;
    });
    return true;
  }

  Future<void> _saveAccount(UserAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    final nextAccounts = [..._accounts];
    final index = nextAccounts.indexWhere(
      (item) => _normalizeEmail(item.email) == _normalizeEmail(account.email),
    );
    if (index == -1) {
      nextAccounts.add(account);
    } else {
      nextAccounts[index] = account;
    }

    await prefs.setString(
      'accounts',
      jsonEncode(nextAccounts.map((item) => item.toMap()).toList()),
    );
    await prefs.setString('account', jsonEncode(account.toMap()));
    await prefs.setString('session_email', _normalizeEmail(account.email));
    if (!mounted) return;
    setState(() {
      _accounts = nextAccounts;
      _account = account;
      _sessionAuthenticated = true;
      _sessionRole = prefs.getString('session_role');
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_email');
    await prefs.remove('token');
    await prefs.remove('session_role');
    if (!mounted) return;
    setState(() {
      _account = null;
      _sessionAuthenticated = false;
      _sessionRole = null;
    });
  }

  Future<void> _deleteAccount(UserAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    final remainingAccounts = _accounts
        .where(
          (item) =>
              _normalizeEmail(item.email) != _normalizeEmail(account.email),
        )
        .toList();

    if (remainingAccounts.isEmpty) {
      await prefs.remove('accounts');
      await prefs.remove('account');
    } else {
      await prefs.setString(
        'accounts',
        jsonEncode(remainingAccounts.map((item) => item.toMap()).toList()),
      );
      await prefs.remove('account');
    }

    await prefs.remove('session_email');
    await prefs.remove('token');
    await prefs.remove('session_role');
    await prefs.remove('clients');
    await prefs.remove('custom_reminders');

    if (!mounted) return;
    setState(() {
      _accounts = remainingAccounts;
      _account = null;
      _sessionAuthenticated = false;
      _sessionRole = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accentPrimary = _accentPreset.primaryColor;
    final accentSecondary = _accentPreset.secondaryColor;

    return MaterialApp(
      title: 'COBREJA',

       // routes: {
        //'/home': (context) => HomePage(),
      //},

      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(_fontScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [
        Locale('pt', 'BR'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentPrimary,
          primary: accentPrimary,
          secondary: accentSecondary,
          surface: AppColors.surface,
          error: AppColors.danger,
        ),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: AppTypography.textTheme,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.textStrong,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: AppColors.textStrong,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.16,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            side: const BorderSide(color: AppColors.borderSoft),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 15,
          ),
          labelStyle: const TextStyle(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
          hintStyle: const TextStyle(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: BorderSide(color: accentPrimary, width: 1.6),
          ),
        ),
          filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accentPrimary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFBFD4FF),
            disabledForegroundColor: Colors.white,
            // Height 54 without forcing infinite width (prevents vertical-wrapped text in Rows).
            minimumSize: const Size(0, 54),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        ),
          textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: accentPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textStrong,
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.borderSoft),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: accentPrimary,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
          ),
        ),
        tabBarTheme: TabBarThemeData(
          indicatorColor: accentPrimary,
          labelColor: accentPrimary,
          unselectedLabelColor: AppColors.textMuted,
          dividerColor: AppColors.borderSoft,
          labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentSecondary,
          brightness: Brightness.dark,
          primary: accentSecondary,
          secondary: accentSecondary,
          surface: const Color(0xFF0F2238),
          error: AppColors.danger,
        ),
        scaffoldBackgroundColor: const Color(0xFF071827),
        textTheme: AppTypography.textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF0F2238),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            side: const BorderSide(color: Color(0xFF1E3A5F)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF0F2238),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF10263F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: const BorderSide(color: Color(0xFF25476E)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: const BorderSide(color: Color(0xFF25476E)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: BorderSide(color: accentSecondary, width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accentSecondary,
            foregroundColor: const Color(0xFF061C3D),
            minimumSize: const Size(0, 54),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        ),
      ),
      themeMode: _themePreference == AppThemePreference.escuro
          ? ThemeMode.dark
          : ThemeMode.light,
      home: _isLoading
          ? const SplashPage()
          : AuthGatePage(
              savedAccount: _account,
              registeredAccounts: _accounts,
              initiallyAuthenticated: _sessionAuthenticated,
              onAuthenticated: _saveAccount,
              onDeleteAccount: _deleteAccount,
              windowsMachineCode: _windowsMachineCode,
              windowsLicense: null,
              onActivateWindowsLicense: null,
              authenticatedBuilder: (account) => _sessionRole == 'CLIENT'
                  ? ClientPortalPage(
                      account: account,
                      onLogout: _logout,
                    )
                  : MainNavigationPage(
                      account: account,
                      onLogout: _logout,
                      onDeleteAccount: () => _deleteAccount(account),
                      windowsLicense: _windowsLicense,
                      accentPreset: _accentPreset,
                      themePreference: _themePreference,
                      fontScale: _fontScale,
                      onUpdateAccentPreset: _updateAccentPreset,
                      onUpdateThemePreference: _updateThemePreference,
                      onUpdateFontScale: _updateFontScale,
                      onResetVisualPreferences: _resetVisualPreferences,
                    ),
            ),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _splashAnimationDuration,
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.88,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.60, curve: Curves.easeOutBack),
      ),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.18, 0.72, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 520;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.backgroundTop,
              AppColors.backgroundMid,
              AppColors.backgroundBottom,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.10),
                ),
              ),
            ),
            Positioned(
              bottom: -120,
              left: -30,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.secondary.withOpacity(0.12),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 24 : 34,
                      vertical: isCompact ? 28 : 34,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.86),
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(color: const Color(0xFFDCE9FF)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x140F172A),
                          blurRadius: 36,
                          offset: Offset(0, 24),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              width: isCompact ? 78 : 92,
                              height: isCompact ? 78 : 92,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [AppColors.primary, AppColors.secondary],
                                ),
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.22),
                                    blurRadius: 24,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: SvgPicture.asset(
                                'assets/branding/cobreja_mark.svg',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: isCompact ? 18 : 22),
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: SvgPicture.asset(
                              'assets/branding/cobreja_logo.svg',
                              height: isCompact ? 42 : 52,
                              fit: BoxFit.fitHeight,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: Text(
                              'Cobrança inteligente, recebimento garantido.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: const Color(0xFF4B5563),
                                fontSize: isCompact ? 15 : 16,
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: isCompact ? 22 : 26),
                        SizedBox(
                          width: isCompact ? 170 : 220,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: AnimatedBuilder(
                              animation: _controller,
                              builder: (context, _) => LinearProgressIndicator(
                                value: _controller.value.clamp(0.08, 1.0),
                                minHeight: 8,
                                backgroundColor: const Color(0xFFD9E7FF),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Text(
                            'Preparando seu painel financeiro...',
                            style: TextStyle(
                              color: const Color(0xFF5B6474),
                              fontSize: isCompact ? 13 : 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CobrejaLoading extends StatelessWidget {
  final String label;

  const _CobrejaLoading({
    this.label = 'Carregando COBREJÁ',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 180,
            child: SvgPicture.asset(
              'assets/branding/cobreja_logo.svg',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 18),
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class WindowsLicensePage extends StatefulWidget {
  final String? machineCode;
  final Future<bool> Function(String licenseKey) onActivate;

  const WindowsLicensePage({
    super.key,
    required this.machineCode,
    required this.onActivate,
  });

  @override
  State<WindowsLicensePage> createState() => _WindowsLicensePageState();
}

class _WindowsLicensePageState extends State<WindowsLicensePage> {
  final _licenseController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final key = _licenseController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _error = 'Digite a licença para liberar o sistema neste computador.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final success = await widget.onActivate(key);
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      if (!success) {
        _error =
            'Licença inválida para este computador. Confira o código da máquina e tente novamente.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final machineCode = widget.machineCode;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.backgroundTop,
              AppColors.backgroundMid,
              AppColors.backgroundBottom,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: const Color(0xFFDCE9FF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 28,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 64,
                          width: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.secondary],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SvgPicture.asset(
                              'assets/branding/cobreja_mark.svg',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ativação do COBREJÁ',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontSize: 30),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Digite a licença do Windows para liberar o sistema neste computador.',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAFF),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFDCE9FF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Código da máquina',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textStrong,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            machineCode ?? 'Não foi possível gerar o código da máquina.',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton.icon(
                                onPressed: machineCode == null
                                    ? null
                                    : () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: machineCode),
                                        );
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Código da máquina copiado.',
                                            ),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.copy_rounded),
                                label: const Text('Copiar código'),
                              ),
                              const Chip(
                                label: Text('Licenças: Vitalícia e Uso único'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _licenseController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Licença do sistema',
                        hintText:
                            'Cole aqui a licença gerada para este computador.',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: machineCode == null || _isSubmitting
                            ? null
                            : _activate,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.verified_rounded),
                        label: Text(
                          _isSubmitting ? 'Validando licença...' : 'Ativar sistema',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBFF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDCE9FF)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Como funciona',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '1. Copie o código da máquina.\n2. Gere a licença no seu gerador privado.\n3. Cole a licença aqui para liberar o uso no Windows.',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              height: 1.5,
                            ),
                          ),
                        ],
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
}

class AuthGatePage extends StatefulWidget {
  final UserAccount? savedAccount;
  final List<UserAccount> registeredAccounts;
  final bool initiallyAuthenticated;
  final ValueChanged<UserAccount> onAuthenticated;
  final Future<void> Function(UserAccount account) onDeleteAccount;
  final String? windowsMachineCode;
  final WindowsLicenseInfo? windowsLicense;
  final Future<bool> Function(String licenseKey)? onActivateWindowsLicense;
  final Widget Function(UserAccount account) authenticatedBuilder;

  const AuthGatePage({
    super.key,
    required this.savedAccount,
    required this.registeredAccounts,
    required this.initiallyAuthenticated,
    required this.onAuthenticated,
    required this.onDeleteAccount,
    this.windowsMachineCode,
    this.windowsLicense,
    this.onActivateWindowsLicense,
    required this.authenticatedBuilder,
  });

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends State<AuthGatePage> {
  bool _authenticated = false;
  bool _isRegisterMode = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isActivatingWindowsLicense = false;
  bool _registerAsClient = true;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  UserAccount? _sessionAccount;
  String? _windowsLicenseError;
  String? _lastAuthError;
  int? _inviteAccountId;
  bool _clientInviteMode = false;
  final _nameController = TextEditingController();
  final _cpfController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _windowsLicenseController = TextEditingController();

  Map<String, dynamic>? dashboardData;

void _showError(String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg)),
  );
}

  @override
  void initState() {
    super.initState();
    _isRegisterMode = false;
    _authenticated = widget.initiallyAuthenticated;
    _sessionAccount = widget.savedAccount;
    final inviteFromUrl = Uri.base.queryParameters['convite'] ??
        Uri.base.queryParameters['invite'];
    _inviteAccountId = int.tryParse(
      Uri.base.queryParameters['conta'] ??
          Uri.base.queryParameters['accountId'] ??
          '',
    );
    if (inviteFromUrl != null && inviteFromUrl.trim().isNotEmpty) {
      _inviteCodeController.text = inviteFromUrl.trim().toUpperCase();
      _isRegisterMode = true;
      _registerAsClient = true;
      _clientInviteMode = true;
    }
    if (_inviteAccountId != null) {
      _isRegisterMode = true;
      _registerAsClient = true;
      _clientInviteMode = true;
    }
    if (widget.savedAccount != null) {
      _emailController.text = widget.savedAccount!.email;
    }
  }

// 👇 AGORA SIM FORA DO LOGIN
Future<bool> register(String name, String email, String password) async {
  try {
    await ApiService.register(name: name, email: email, password: password);
    _lastAuthError = null;
    return true;
  } catch (e) {
    final message = e is ApiException ? e.message : 'Erro geral no cadastro.';
    _lastAuthError = message;
    _showError(message);
    debugPrint('Erro geral cadastro: $e');
    return false;
  }
}

Future<bool> registerClient(
  String name,
  String email,
  String password, {
  String? cpf,
  String? phone,
  String? address,
  String? inviteCode,
  int? accountId,
}) async {
  try {
    final data = await ApiService.registerClient(
      name: name,
      email: email,
      password: password,
      cpf: cpf,
      phone: phone,
      address: address,
      inviteCode: inviteCode,
      accountId: accountId,
    );
    final token = (data['token'] ?? data['data']?['token'] ?? '').toString();
    final payload = data['data'] is Map<String, dynamic>
        ? data['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    final userData = data['user'] is Map<String, dynamic>
        ? data['user'] as Map<String, dynamic>
        : payload['user'] is Map<String, dynamic>
            ? payload['user'] as Map<String, dynamic>
            : data;
    final resolvedEmail = userData['email']?.toString() ?? email;
    final resolvedName = userData['name']?.toString() ?? name;
    if (token.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
      await prefs.setString('session_role', 'CLIENT');
    }
    widget.onAuthenticated(UserAccount(name: resolvedName, email: resolvedEmail));
    _lastAuthError = null;
    return true;
  } catch (e) {
    final message = e is ApiException ? e.message : 'Erro geral no cadastro do cliente.';
    _lastAuthError = message;
    _showError(message);
    debugPrint('Erro geral cadastro cliente: $e');
    return false;
  }
}

Future<bool> login(String identifier, String password) async {
  try {
    final data = await ApiService.login(identifier: identifier, password: password);
    print('RESPOSTA LOGIN: $data');
    final token = (data['token'] ?? data['data']?['token'] ?? '').toString();
    print('TOKEN SALVO: $token');
    if (token.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);

      // Guarda a role do usuario para escolher a experiÃªncia (ADMIN x CLIENT)
      // mesmo apÃ³s recarregar a pÃ¡gina (F5) ou reiniciar o app.
      try {
        final me = await ApiService.fetchMe(token: token);
        final user = me['user'] as Map<String, dynamic>?;
        final role = user?['role']?.toString();
        if (role != null && role.isNotEmpty) {
          await prefs.setString('session_role', role);
        } else {
          await prefs.remove('session_role');
        }
      } catch (_) {
        // Se falhar, mantÃ©m a sessÃ£o e usa a role salva anteriormente (se houver).
      }
    }

    final userData = data['user'] as Map<String, dynamic>? ?? data;
    final resolvedEmail = userData['email']?.toString() ?? identifier;
    final resolvedName = userData['name']?.toString() ?? resolvedEmail;
    final account = UserAccount(
      name: resolvedName,
      email: resolvedEmail,
    );

    widget.onAuthenticated(account);

    setState(() {
      _sessionAccount = account;
      _authenticated = true;
    });

    _lastAuthError = null;
    return true;
  } catch (e) {
    final message = e is ApiException ? e.message : 'Erro geral no login.';
    _lastAuthError = message;
    _showError(message);
    debugPrint('Erro geral login: $e');
    return false;
  }
}

  @override
  void didUpdateWidget(covariant AuthGatePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyAuthenticated != oldWidget.initiallyAuthenticated ||
        widget.savedAccount?.email != oldWidget.savedAccount?.email) {
      _authenticated = widget.initiallyAuthenticated;
      _sessionAccount = widget.savedAccount;
      if (widget.savedAccount != null) {
        _emailController.text = widget.savedAccount!.email;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cpfController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _inviteCodeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _windowsLicenseController.dispose();
    super.dispose();
  }

  bool get _requiresWindowsLicense =>
      isWindowsDesktopPlatform && widget.onActivateWindowsLicense != null;

  bool get _hasWindowsLicense =>
      !_requiresWindowsLicense || widget.windowsLicense != null;

  Future<void> _activateWindowsLicense() async {
    final licenseKey = _windowsLicenseController.text.trim();
    if (licenseKey.isEmpty) {
      setState(() {
        _windowsLicenseError =
            'Cole a licença enviada pelo distribuidor para liberar o sistema.';
      });
      return;
    }

    setState(() {
      _isActivatingWindowsLicense = true;
      _windowsLicenseError = null;
    });

    final success = await widget.onActivateWindowsLicense!(licenseKey);
    if (!mounted) return;

    setState(() {
      _isActivatingWindowsLicense = false;
      if (!success) {
        _windowsLicenseError =
            'Licença inválida para este computador. Confira o código da máquina e tente novamente.';
      }
    });

    if (success) {
      _showAuthMessage(
        'Licença ativada',
        'O sistema foi liberado com sucesso neste computador.',
        success: true,
      );
    }
  }

 Future<void> _submit() async {
  if (_isSubmitting) return;

  if (!_hasWindowsLicense) {
    _showAuthMessage(
      'Licença necessária',
      'Peça ao distribuidor do seu sistema para enviar a licença antes de continuar.',
    );
    return;
  }

  final rawIdentifier = _emailController.text.trim();
  final email = _normalizeEmail(rawIdentifier);
  final password = _passwordController.text;
  if (rawIdentifier.isEmpty || password.trim().isEmpty) {
    _showAuthMessage(
      'Campos obrigatorios',
      'Preencha email ou CPF e senha para continuar.',
    );
    return;
  }

  if (_isRegisterMode && !_isValidEmail(email)) {
    _showAuthMessage(
      'Email inválido',
      'Informe um email válido, por exemplo: nome@dominio.com.',
    );
    return;
  }

  if (!_isRegisterMode &&
      !_isValidEmail(rawIdentifier) &&
      !_isValidCpf(rawIdentifier)) {
    _showAuthMessage(
      'Acesso inválido',
      'Use um email válido ou um CPF com 11 dígitos para entrar.',
    );
    return;
  }

  if (_isRegisterMode) {
    if (_nameController.text.trim().isEmpty) {
      _showAuthMessage('Campo obrigatório', 'Informe um nome para cadastro.');
      return;
    }
    if (_registerAsClient) {
      if (!_isValidCpf(_cpfController.text)) {
        _showAuthMessage(
          'CPF obrigatorio',
          'Informe um CPF valido para criar sua conta de cliente.',
        );
        return;
      }
      if (_phoneController.text.trim().isEmpty ||
          _addressController.text.trim().isEmpty) {
        _showAuthMessage(
          'Dados obrigatorios',
          'Informe telefone e endereco para criar sua conta de cliente.',
        );
        return;
      }
    }
    if (!_isStrongPassword(password)) {
      _showAuthMessage(
        'Senha fraca',
        'A senha precisa ter no minimo 8 caracteres, com letra maiuscula, letra minuscula e caractere especial.',
      );
      return;
    }
    if (_confirmPasswordController.text != password) {
      _showAuthMessage(
        'Senhas diferentes',
        'A confirmacao de senha precisa ser igual a senha digitada.',
      );
      return;
    }
  }

  setState(() => _isSubmitting = true);
  final success = _isRegisterMode
      ? (_registerAsClient
          ? await registerClient(
              _nameController.text.trim(),
              email,
              password,
              cpf: _cpfController.text.trim(),
              phone: _phoneController.text.trim(),
              address: _addressController.text.trim(),
              inviteCode: _inviteCodeController.text.trim(),
              accountId: _inviteAccountId,
            )
          : (await register(_nameController.text.trim(), email, password) &&
              await login(email, password)))
      : await login(rawIdentifier, password);
  if (mounted) {
    setState(() => _isSubmitting = false);
  }

  if (success) {
    debugPrint('LOGIN OK - ENTRANDO NO SISTEMA');
    setState(() {
      _authenticated = true;
    });
    return;
  }

  _showAuthMessage(
    _isRegisterMode ? 'Cadastro não concluído' : 'Acesso negado',
    _isRegisterMode
        ? 'Nao foi possível concluir o cadastro no servidor. Verifique os dados e tente novamente.'
        : 'Email ou senha inválidos. Verifique seus dados e tente novamente.',
  );
  return;
 }

  void _showAuthMessage(String title, String message, {bool success = false}) {
    final isGenericAuthFailure =
        message.startsWith('Nao foi') || message.startsWith('Email ou senha');
    final visibleMessage = !success && isGenericAuthFailure
        ? (_lastAuthError ?? message)
        : message;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: (success
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626))
                  .withOpacity(0.12),
              child: Icon(
                success ? Icons.check_rounded : Icons.info_outline_rounded,
                color:
                    success ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(visibleMessage),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  void _showForgotPasswordDialog() {
    final email = _emailController.text.trim();
    final exists = widget.registeredAccounts.any(
      (item) => _normalizeEmail(item.email) == _normalizeEmail(email),
    );

    _showAuthMessage(
      exists ? 'Recuperacao local' : 'Email nao encontrado',
      exists
          ? 'Este app usa recuperacao local. Use sua senha salva no aparelho ou cadastre uma nova conta local se necessario.'
          : 'Digite primeiro o email cadastrado para usar esse lembrete local.',
    );
  }

  void _showBrandInfoDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.all(0),
        content: Container(
          width: 420,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF061C3D), Color(0xFF22C55E)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 54,
                      width: 54,
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: SvgPicture.asset(
                        'assets/branding/cobreja_mark.svg',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SvgPicture.asset(
                        'assets/branding/cobreja_logo_white.svg',
                        height: 34,
                        fit: BoxFit.fitHeight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Cobrança inteligente, recebimento garantido.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _isRegisterMode
                      ? 'Crie sua conta local para começar a organizar clientes, juros, renegociações e recebimentos com a identidade da COBREJA.'
                      : 'Entre para continuar gerenciando sua carteira, lembretes, cobranças e acordos em um so lugar.',
                  style: const TextStyle(
                    color: Color(0xFFE8FFFB),
                    fontSize: 15,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _AuthFeatureChip(icon: Icons.bolt_rounded, label: 'Cobrança rápida'),
                    _AuthFeatureChip(icon: Icons.receipt_long_rounded, label: 'Histórico seguro'),
                    _AuthFeatureChip(icon: Icons.calendar_month_rounded, label: 'Lembretes úteis'),
                  ],
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF061C3D),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fechar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved = _sessionAccount ?? widget.savedAccount;
    if (_authenticated && saved != null && _hasWindowsLicense) {
      return widget.authenticatedBuilder(saved);
    }

    final isWide = MediaQuery.of(context).size.width >= 860;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFDDE6F0), Color(0xFFEFF4F8), Color(0xFFE3F4EC)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(36),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140F172A),
                        blurRadius: 36,
                        offset: Offset(0, 22),
                      ),
                    ],
                  ),
                  child: isWide
                      ? Row(
                          children: [
                            Expanded(child: _buildAuthBrandPanel()),
                            SizedBox(
                              width: 420,
                              child: _buildAuthFormCard(),
                            ),
                          ],
                        )
                      : _buildAuthFormCard(showTopBrand: true, showBrandInfoButton: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthBrandPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 44),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF061C3D), Color(0xFF22C55E)],
        ),
        borderRadius: BorderRadius.horizontal(left: Radius.circular(36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 64,
                    width: 64,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: SvgPicture.asset(
                      'assets/branding/cobreja_mark.svg',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: SvgPicture.asset(
                      'assets/branding/cobreja_logo_white.svg',
                      height: 40,
                      fit: BoxFit.fitHeight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Text(
                'Cobrança inteligente, recebimento garantido.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isRegisterMode
                    ? 'Crie sua conta local para começar a organizar clientes, juros, renegociações e recebimentos com a identidade da COBREJA.'
                    : 'Entre para continuar gerenciando sua carteira, lembretes, cobranças e acordos em um so lugar.',
                style: const TextStyle(
                  color: Color(0xFFE8FFFB),
                  fontSize: 16,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _AuthFeatureChip(
                icon: Icons.bolt_rounded,
                label: 'Cobrança rápida',
              ),
              _AuthFeatureChip(
                icon: Icons.receipt_long_rounded,
                label: 'Histórico seguro',
              ),
              _AuthFeatureChip(
                icon: Icons.calendar_month_rounded,
                label: 'Lembretes úteis',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuthFormCard({
    bool showTopBrand = false,
    bool showBrandInfoButton = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTopBrand) ...[
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: double.infinity,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: SvgPicture.asset(
                        'assets/branding/cobreja_logo.svg',
                        height: 46,
                        fit: BoxFit.fitHeight,
                      ),
                    ),
                    if (showBrandInfoButton)
                      Positioned(
                        right: 0,
                        bottom: -6,
                        child: Material(
                          color: const Color(0xFFEAF1F8),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _showBrandInfoDialog,
                            child: const Padding(
                              padding: EdgeInsets.all(9),
                              child: Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFF061C3D),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEAF1F8), Color(0xFFF2FFFC)],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFD9E7FF)),
            ),
            child: Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF061C3D), Color(0xFF22C55E)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SvgPicture.asset(
                    'assets/branding/cobreja_mark.svg',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isRegisterMode ? 'Criar acesso' : 'Entrar',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isRegisterMode
                            ? 'Abra sua conta local da COBREJA e comece a organizar suas cobranças.'
                            : 'Acesse sua conta para continuar no painel da COBREJÁ.',
                        style: const TextStyle(
                          color: Color(0xFF5B6474),
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_requiresWindowsLicense && !_hasWindowsLicense) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFF),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFDCE9FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Licença do sistema',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Peça ao distribuidor do seu sistema para enviar a licença.',
                    style: TextStyle(
                      color: Color(0xFF5B6474),
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFDCE9FF)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Código da máquina',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          widget.windowsMachineCode ??
                              'Não foi possível gerar o código da máquina.',
                          style: const TextStyle(
                            color: Color(0xFF061C3D),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: widget.windowsMachineCode == null
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text: widget.windowsMachineCode!,
                                    ),
                                  );
                                  if (!mounted) return;
                                  _showAuthMessage(
                                    'Código copiado',
                                    'O código da máquina foi copiado para você enviar ao distribuidor.',
                                    success: true,
                                  );
                                },
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Copiar código'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _windowsLicenseController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Licença',
                      hintText: 'Cole aqui a licença recebida para este computador.',
                    ),
                  ),
                  if (_windowsLicenseError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _windowsLicenseError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isActivatingWindowsLicense
                          ? null
                          : _activateWindowsLicense,
                      icon: _isActivatingWindowsLicense
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.verified_rounded),
                      label: Text(
                        _isActivatingWindowsLicense
                            ? 'Validando licença...'
                            : 'Ativar licença',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (_requiresWindowsLicense && _hasWindowsLicense) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFFCF6),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFB6F0CF)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: Color(0xFF15803D),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Licença ${widget.windowsLicense!.typeLabel.toLowerCase()} ativa neste computador.',
                      style: const TextStyle(
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (_isRegisterMode) ...[
            if (_clientInviteMode)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFFCF6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFB6F0CF)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.person_rounded, color: Color(0xFF15803D)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Cadastro de cliente por convite',
                        style: TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Cliente'),
                    icon: Icon(Icons.person_rounded),
                  ),
                ],
                selected: {_registerAsClient},
                onSelectionChanged: (values) {
                  setState(() {
                    _registerAsClient = true;
                  });
                },
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 12),
            if (_registerAsClient) ...[
              TextField(
                controller: _cpfController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'CPF'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Endereco'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _inviteCodeController,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Codigo de convite',
                  hintText: 'Enviado pelo administrador',
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: _isRegisterMode ? 'Email' : null,
              hintText: _isRegisterMode ? null : 'Email ou CPF',
              floatingLabelBehavior: _isRegisterMode
                  ? FloatingLabelBehavior.auto
                  : FloatingLabelBehavior.never,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.password],
            textInputAction: _isRegisterMode
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: (_) {
              if (!_isRegisterMode) {
                _submit();
              }
            },
            decoration: InputDecoration(
              labelText: 'Senha',
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
              ),
            ),
          ),
          if (_isRegisterMode) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Confirmar senha',
                suffixIcon: IconButton(
                  tooltip: _obscureConfirmPassword
                      ? 'Mostrar confirmacao da senha'
                      : 'Ocultar confirmacao da senha',
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showForgotPasswordDialog,
              child: const Text('Esqueci minha senha'),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showPrivacyPolicyDialog(context),
              icon: const Icon(Icons.privacy_tip_rounded, size: 18),
              label: const Text('Política de privacidade'),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
            onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isRegisterMode ? 'Cadastrar' : 'Entrar'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              setState(() {
                _isRegisterMode = !_isRegisterMode;
              });
            },
            child: Text(
              _isRegisterMode ? 'Já tenho cadastro' : 'Não tenho cadastro',
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthFeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AuthFeatureChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPolicySection extends StatelessWidget {
  final _PrivacyPolicySectionData section;

  const _PrivacyPolicySection({
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              color: AppColors.textStrong,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final paragraph in section.paragraphs) ...[
            Text(
              paragraph,
              style: const TextStyle(
                color: AppColors.textBody,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class ClientPortalPage extends StatefulWidget {
  final UserAccount account;
  final VoidCallback onLogout;

  const ClientPortalPage({
    super.key,
    required this.account,
    required this.onLogout,
  });

  @override
  State<ClientPortalPage> createState() => _ClientPortalPageState();
}

class _ClientPortalPageState extends State<ClientPortalPage> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _debts = const [];
  List<Map<String, dynamic>> _payments = const [];
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _supportConversations = const [];
  bool _isSubmittingRequest = false;

  @override
  void initState() {
    super.initState();
    _loadClientPortal();
  }

  Future<void> _loadClientPortal() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      widget.onLogout();
      return;
    }

    try {
      final me = await ApiService.fetchMe(token: token);
      final debts = await ApiService.fetchMyDebts(token: token);
      final payments = await ApiService.fetchMyPayments(token: token);
      final requests = await ApiService.fetchMyRequests(token: token);
      final supportConversations =
          await ApiService.listSupportConversations(token: token);

      if (!mounted) return;
      setState(() {
        _me = me;
        _debts = debts;
        _payments = payments;
        _requests = requests;
        _supportConversations = supportConversations
            .whereType<Map<String, dynamic>>()
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Falha ao carregar seus dados.';
        _isLoading = false;
      });
    }
  }

  void _showPortalSnack(
    String message, {
    bool isError = false,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFB91C1C) : const Color(0xFF0F766E),
      ),
    );
  }

  Future<void> _requestCredit() async {
    if (_isSubmittingRequest) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      widget.onLogout();
      return;
    }

    final amountController = TextEditingController();
    final termController = TextEditingController(text: '30');
    final installmentsController = TextEditingController(text: '1');
    final descriptionController = TextEditingController();
    try {
      final draft = await showDialog<_CreditRequestDraft>(
        context: context,
        builder: (dialogContext) => _CreditRequestDialog(
          amountController: amountController,
          termController: termController,
          installmentsController: installmentsController,
          descriptionController: descriptionController,
        ),
      );
      if (draft == null) return;

      setState(() => _isSubmittingRequest = true);
      await ApiService.createCreditRequest(
        token: token,
        amount: draft.amount,
        description: draft.description,
        desiredTermDays: draft.desiredTermDays,
        requestedInstallments: draft.requestedInstallments,
        type: 'EMPRESTIMO',
      );

      if (!mounted) return;
      _showPortalSnack(
        'Solicitação enviada. Assim que for analisada, você verá o status aqui.',
      );
      await _loadClientPortal();
    } catch (e) {
      if (!mounted) return;
      _showPortalSnack(
        e is ApiException ? e.message : 'Não foi possível enviar sua solicitação agora.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmittingRequest = false);
      amountController.dispose();
      termController.dispose();
      installmentsController.dispose();
      descriptionController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _me?['user'] as Map<String, dynamic>?;
    final client = _me?['client'] as Map<String, dynamic>?;
    final clientName = client?['name']?.toString().trim() ?? '';
    final displayName = user?['name']?.toString().trim().isNotEmpty == true
        ? user!['name'].toString()
        : (clientName.isNotEmpty ? clientName : widget.account.email);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text('COBREJÁ • $displayName'),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _isLoading ? null : _loadClientPortal,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Sair',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Perfil'),
              Tab(text: 'Dívidas'),
              Tab(text: 'Pagamentos'),
              Tab(text: 'Suporte'),
            ],
          ),
        ),
        body: _isLoading
            ? const _CobrejaLoading(label: 'Carregando portal do cliente')
            : (_error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : TabBarView(
                    children: [
                      _ClientProfileTab(
                        me: _me,
                        debts: _debts,
                        payments: _payments,
                        requests: _requests,
                        isSubmittingRequest: _isSubmittingRequest,
                        onRequestCredit: _requestCredit,
                      ),
                      _ClientDebtsList(
                        debts: _debts,
                        onRefresh: _loadClientPortal,
                      ),
                      _ClientPaymentsList(payments: _payments),
                      _SupportCenterTab(
                        conversations: _supportConversations,
                        onRefresh: _loadClientPortal,
                        showPortalSnack: _showPortalSnack,
                      ),
                    ],
                  )),
      ),
    );
  }
}

class _CreditRequestDraft {
  final double amount;
  final int desiredTermDays;
  final int requestedInstallments;
  final String? description;

  const _CreditRequestDraft({
    required this.amount,
    required this.desiredTermDays,
    required this.requestedInstallments,
    this.description,
  });
}

class _CreditRequestDialog extends StatefulWidget {
  final TextEditingController amountController;
  final TextEditingController termController;
  final TextEditingController installmentsController;
  final TextEditingController descriptionController;

  const _CreditRequestDialog({
    required this.amountController,
    required this.termController,
    required this.installmentsController,
    required this.descriptionController,
  });

  @override
  State<_CreditRequestDialog> createState() => _CreditRequestDialogState();
}

class _CreditRequestDialogState extends State<_CreditRequestDialog> {
  String? _error;

  double? _parseAmount(String raw) {
    final cleaned = raw
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    return double.tryParse(cleaned.trim());
  }

  void _submit() {
    final amount = _parseAmount(widget.amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Informe um valor válido para a solicitação.');
      return;
    }

    final termDays = int.tryParse(widget.termController.text.trim()) ?? 0;
    final installments = int.tryParse(widget.installmentsController.text.trim()) ?? 0;
    if (termDays <= 0) {
      setState(() => _error = 'Informe um prazo valido em dias.');
      return;
    }
    if (installments <= 0) {
      setState(() => _error = 'Informe a quantidade de parcelas desejada.');
      return;
    }

    Navigator.of(context).pop(
      _CreditRequestDraft(
        amount: amount,
        desiredTermDays: termDays,
        requestedInstallments: installments,
        description: widget.descriptionController.text.trim().isEmpty
            ? null
            : widget.descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Solicitar empréstimo'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Envie o valor desejado e uma observação opcional. A solicitação ficará pendente até aprovação do administrador.',
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: widget.amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor solicitado (R\$)',
                prefixIcon: Icon(Icons.payments_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.termController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Prazo desejado (dias)',
                      prefixIcon: Icon(Icons.calendar_month_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: widget.installmentsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Parcelas',
                      prefixIcon: Icon(Icons.view_week_rounded),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: widget.descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo da solicitação',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_rounded),
          label: const Text('Enviar'),
        ),
      ],
    );
  }
}

class _ClientProfileTab extends StatelessWidget {
  final Map<String, dynamic>? me;
  final List<Map<String, dynamic>> debts;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> requests;
  final bool isSubmittingRequest;
  final Future<void> Function() onRequestCredit;

  const _ClientProfileTab({
    required this.me,
    required this.debts,
    required this.payments,
    required this.requests,
    required this.isSubmittingRequest,
    required this.onRequestCredit,
  });

  @override
  Widget build(BuildContext context) {
    final client = me?['client'] as Map<String, dynamic>?;
    final user = me?['user'] as Map<String, dynamic>?;

    String _valueOrDash(String? value) {
      final text = value?.trim() ?? '';
      return text.isEmpty ? '—' : text;
    }

    final name = (client?['name']?.toString() ?? user?['name']?.toString() ?? '')
        .trim();
    final email =
        (client?['email']?.toString() ?? user?['email']?.toString() ?? '').trim();
    final phone =
        (client?['phone']?.toString() ?? user?['phone']?.toString() ?? '').trim();
    final cpf =
        (client?['cpf']?.toString() ?? user?['cpf']?.toString() ?? '').trim();
    final address = (client?['address']?.toString() ?? '').trim();
    final avatarUrl = (client?['avatarUrl']?.toString() ??
            user?['avatarUrl']?.toString() ??
            '')
        .trim();

    int overdueCount = 0;
    int activeCount = 0;
    int settledCount = 0;
    double totalDue = 0;
    double totalPaid = 0;
    double activePrincipal = 0;
    DateTime? nextDueDate;
    double nextDueAmount = 0;

    for (final debt in debts) {
      final status = debt['status']?.toString().toUpperCase() ?? 'ACTIVE';
      if (status == 'EXCLUDED') continue;
      final snapshot = debt['snapshot'] as Map<String, dynamic>?;
      final overdueDays = (snapshot?['overdueDays'] as num?)?.toInt() ?? 0;
      final isSettled = status == 'SETTLED' || (snapshot?['isSettled'] == true);
      final debtTotal = _readDouble(snapshot?['totalDue']);
      final debtPrincipal =
          _readDouble(snapshot?['principalOutstanding'] ?? debt['principalOutstanding']);
      if (isSettled) {
        settledCount += 1;
      } else if (overdueDays > 0) {
        overdueCount += 1;
        totalDue += debtTotal;
        activePrincipal += debtPrincipal;
      } else {
        activeCount += 1;
        totalDue += debtTotal;
        activePrincipal += debtPrincipal;
      }

      final installments = (debt['installments'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      for (final installment in installments) {
        final installmentStatus =
            installment['status']?.toString().toUpperCase() ?? 'PENDING';
        if (installmentStatus == 'PAID') continue;
        final dueDate =
            DateTime.tryParse(installment['dueDate']?.toString() ?? '');
        if (dueDate == null) continue;
        if (nextDueDate == null || dueDate.isBefore(nextDueDate!)) {
          nextDueDate = dueDate;
          nextDueAmount = _readDouble(installment['amount']) -
              _readDouble(installment['paidAmount']);
        }
      }
    }

    for (final payment in payments) {
      totalPaid += _readDouble(payment['amount']);
    }

    final approvedCredit = requests
        .where((request) =>
            request['status']?.toString().toUpperCase() == 'APPROVED')
        .fold<double>(
          0,
          (sum, request) => sum + _readDouble(request['amount']),
        );
    final virtualBalance = math.max(0, totalPaid - totalDue).toDouble();
    final availableLimit = math.max(0, approvedCredit - activePrincipal).toDouble();

    Widget _infoRow(IconData icon, String label, String value) {
      return Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textStrong,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    Color _statusColor(String status) {
      switch (status.toUpperCase()) {
        case 'APPROVED':
          return const Color(0xFF16A34A);
        case 'REJECTED':
          return const Color(0xFFDC2626);
        default:
          return const Color(0xFFF59E0B);
      }
    }

    String _statusLabel(String status) {
      switch (status.toUpperCase()) {
        case 'APPROVED':
          return 'Aprovado';
        case 'REJECTED':
          return 'Recusado';
        default:
          return 'Pendente';
      }
    }

    final initials = name.isNotEmpty ? name.characters.first.toUpperCase() : 'C';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        110,
      ),
      children: [
        _ClientBankDashboardCard(
          displayName: name.isNotEmpty ? name : 'Cliente',
          virtualBalance: virtualBalance,
          availableLimit: availableLimit,
          totalPaid: totalPaid,
          totalDue: totalDue,
          nextDueDate: nextDueDate,
          nextDueAmount: nextDueAmount,
          activeDebts: activeCount + overdueCount,
          overdueDebts: overdueCount,
          onRequestCredit: isSubmittingRequest ? null : onRequestCredit,
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.borderSoft,
                  foregroundColor: AppColors.textStrong,
                  backgroundImage:
                      avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl.isNotEmpty
                      ? null
                      : Text(
                          initials,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : 'Meu perfil',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textStrong,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email.isNotEmpty ? email : 'Conta do cliente',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: isSubmittingRequest ? null : () => onRequestCredit(),
                  icon: const Icon(Icons.request_quote_rounded),
                  label: const Text('Solicitar'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seus dados',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textStrong,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _infoRow(Icons.badge_rounded, 'CPF', _valueOrDash(cpf)),
                const SizedBox(height: AppSpacing.sm),
                _infoRow(Icons.phone_rounded, 'Telefone', _valueOrDash(phone)),
                const SizedBox(height: AppSpacing.sm),
                _infoRow(Icons.home_rounded, 'Endereço', _valueOrDash(address)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _ClientProfileMetricChip(
              title: 'Dívidas ativas',
              value: '$activeCount',
              color: const Color(0xFF061C3D),
              icon: Icons.account_balance_wallet_rounded,
            ),
            _ClientProfileMetricChip(
              title: 'Em atraso',
              value: '$overdueCount',
              color: const Color(0xFFEF4444),
              icon: Icons.warning_amber_rounded,
            ),
            _ClientProfileMetricChip(
              title: 'Quitadas',
              value: '$settledCount',
              color: const Color(0xFF16A34A),
              icon: Icons.check_circle_rounded,
            ),
            _ClientProfileMetricChip(
              title: 'Pagamentos',
              value: '${payments.length}',
              color: const Color(0xFF8B5CF6),
              icon: Icons.receipt_long_rounded,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          'Minhas solicitações',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.textStrong,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (requests.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Você ainda não fez nenhuma solicitação. Quando precisar de crédito, toque em “Solicitar”.',
                style: TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
            ),
          )
        else
          ...requests.map((request) {
            final amount = _readDouble(request['amount']);
            final status = request['status']?.toString() ?? 'PENDING';
            final createdAt =
                DateTime.tryParse(request['createdAt']?.toString() ?? '');
            final description = request['description']?.toString().trim() ?? '';
            final type = request['type']?.toString().trim() ?? '';
            final desiredTermDays =
                (request['desiredTermDays'] as num?)?.toInt();
            final requestedInstallments =
                (request['requestedInstallments'] as num?)?.toInt();
            final decisionNote = request['decisionNote']?.toString().trim() ?? '';

            return Card(
              child: ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _statusColor(status).withOpacity(0.14),
                  ),
                  child: Icon(
                    status.toUpperCase() == 'APPROVED'
                        ? Icons.check_circle_rounded
                        : (status.toUpperCase() == 'REJECTED'
                            ? Icons.cancel_rounded
                            : Icons.schedule_rounded),
                    color: _statusColor(status),
                  ),
                ),
                title: Text(
                  '${_currency(amount)} • ${_statusLabel(status)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (type.isNotEmpty)
                      Text(
                        'Tipo: $type',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    if (createdAt != null)
                      Text(
                        'Enviado em ${DateFormat('dd/MM/yyyy HH:mm').format(createdAt)}',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    if (desiredTermDays != null || requestedInstallments != null)
                      Text(
                        [
                          if (desiredTermDays != null)
                            'Prazo: $desiredTermDays dias',
                          if (requestedInstallments != null)
                            'Parcelas: $requestedInstallments',
                        ].join(' • '),
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    if (description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(description),
                      ),
                    if (decisionNote.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Resposta: $decisionNote'),
                      ),
                  ],
                ),
                isThreeLine: true,
              ),
            );
          }),
      ],
    );
  }
}

class _ClientBankDashboardCard extends StatelessWidget {
  final String displayName;
  final double virtualBalance;
  final double availableLimit;
  final double totalPaid;
  final double totalDue;
  final DateTime? nextDueDate;
  final double nextDueAmount;
  final int activeDebts;
  final int overdueDebts;
  final VoidCallback? onRequestCredit;

  const _ClientBankDashboardCard({
    required this.displayName,
    required this.virtualBalance,
    required this.availableLimit,
    required this.totalPaid,
    required this.totalDue,
    required this.nextDueDate,
    required this.nextDueAmount,
    required this.activeDebts,
    required this.overdueDebts,
    required this.onRequestCredit,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 620;
    final nextDueLabel = nextDueDate == null
        ? 'Sem parcelas pendentes'
        : '${DateFormat('dd/MM/yyyy').format(nextDueDate!)} • ${_currency(math.max(0, nextDueAmount))}';

    return Container(
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF061C3D), Color(0xFF0F766E), Color(0xFF16A34A)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22061C3D),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Olá, $displayName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Saldo operacional interno. Não representa saldo bancário real.',
                      style: TextStyle(
                        color: Color(0xFFD8FFF0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Saldo virtual',
            style: TextStyle(
              color: Color(0xFFD8FFF0),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _currency(virtualBalance),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 30 : 38,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ClientBankMetricTile(
                title: 'Limite disponível',
                value: _currency(availableLimit),
                icon: Icons.credit_score_rounded,
              ),
              _ClientBankMetricTile(
                title: 'Total devido',
                value: _currency(totalDue),
                icon: Icons.trending_down_rounded,
              ),
              _ClientBankMetricTile(
                title: 'Total pago',
                value: _currency(totalPaid),
                icon: Icons.payments_rounded,
              ),
              _ClientBankMetricTile(
                title: 'Próxima parcela',
                value: nextDueLabel,
                icon: Icons.event_available_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$activeDebts dívida(s) ativa(s) • $overdueDebts em atraso',
                  style: const TextStyle(
                    color: Color(0xFFE8FFF7),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: onRequestCredit,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.add_card_rounded),
                label: const Text('Pedir crédito'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClientBankMetricTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _ClientBankMetricTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 260),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD8FFF0),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientProfileMetricChip extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _ClientProfileMetricChip({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSoft),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textStrong,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _ClientDebtFilter { all, active, overdue, settled }

extension _ClientDebtFilterExtension on _ClientDebtFilter {
  String get label => switch (this) {
        _ClientDebtFilter.all => 'Todas',
        _ClientDebtFilter.active => 'Ativas',
        _ClientDebtFilter.overdue => 'Em atraso',
        _ClientDebtFilter.settled => 'Quitadas',
      };
}

class _ClientDebtsList extends StatefulWidget {
  final List<Map<String, dynamic>> debts;
  final Future<void> Function() onRefresh;

  const _ClientDebtsList({
    required this.debts,
    required this.onRefresh,
  });

  @override
  State<_ClientDebtsList> createState() => _ClientDebtsListState();
}

class _ClientDebtsListState extends State<_ClientDebtsList> {
  _ClientDebtFilter _filter = _ClientDebtFilter.all;
  bool _isCreatingPix = false;

  Future<void> _payInstallmentWithPix(Map<String, dynamic> installment) async {
    final installmentId = (installment['id'] as num?)?.toInt();
    if (installmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parcela invalida para pagamento Pix.')),
      );
      return;
    }

    setState(() => _isCreatingPix = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null || token.isEmpty) {
        throw const ApiException(
          statusCode: 401,
          message: 'Sessao expirada. Entre novamente.',
        );
      }

      final intent = await ApiService.createInstallmentPix(
        token: token,
        installmentId: installmentId,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PixPaymentDialog(
          initialIntent: intent,
          onRefresh: widget.onRefresh,
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err is ApiException ? err.message : 'Erro ao gerar Pix.')),
      );
    } finally {
      if (mounted) setState(() => _isCreatingPix = false);
    }
  }

  bool _matchesFilter(Map<String, dynamic> debt) {
    final status = debt['status']?.toString().toUpperCase() ?? 'ACTIVE';
    if (status == 'EXCLUDED') return false;

    final snapshot = debt['snapshot'] as Map<String, dynamic>?;
    final overdueDays = (snapshot?['overdueDays'] as num?)?.toInt() ?? 0;
    final isSettled = status == 'SETTLED' || (snapshot?['isSettled'] == true);
    final isOverdue = status == 'ACTIVE' && overdueDays > 0 && !isSettled;

    switch (_filter) {
      case _ClientDebtFilter.all:
        return true;
      case _ClientDebtFilter.active:
        return !isSettled && !isOverdue;
      case _ClientDebtFilter.overdue:
        return isOverdue;
      case _ClientDebtFilter.settled:
        return isSettled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allDebts = widget.debts.where((debt) {
      final status = debt['status']?.toString().toUpperCase() ?? 'ACTIVE';
      return status != 'EXCLUDED';
    }).toList();
    final visibleDebts = allDebts.where(_matchesFilter).toList();

    final itemCount = 1 + (visibleDebts.isEmpty ? 1 : visibleDebts.length);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 110),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _ClientDebtFilter.values.map((filter) {
                    final selected = _filter == filter;
                    return ChoiceChip(
                      selected: selected,
                      label: Text(filter.label),
                      onSelected: (_) => setState(() => _filter = filter),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Mostrando ${visibleDebts.length} de ${allDebts.length} dívidas.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        if (visibleDebts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xl),
            child: Center(
              child: Text(
                'Nenhuma dívida encontrada neste filtro.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          );
        }

        final debt = visibleDebts[index - 1];
        final snapshot = debt['snapshot'] as Map<String, dynamic>?;
        final dueDate = DateTime.tryParse(debt['dueDate']?.toString() ?? '');
        final borrowedAt = DateTime.tryParse(debt['borrowedAt']?.toString() ?? '');
        final principalOutstanding = _readDouble(snapshot?['principalOutstanding'] ?? debt['principalOutstanding']);
        final interestOutstanding = _readDouble(snapshot?['interestOutstanding']);
        final dailyAccrued = _readDouble(snapshot?['dailyAccruedAmount']);
        final totalDue = _readDouble(snapshot?['totalDue']);
        final overdueDays = (snapshot?['overdueDays'] as num?)?.toInt() ?? 0;
        final status = debt['status']?.toString().toUpperCase() ?? 'ACTIVE';
        final isSettled = status == 'SETTLED' || (snapshot?['isSettled'] == true);
        final settledAt = DateTime.tryParse(debt['settledAt']?.toString() ?? '');
        final badgeBg = isSettled
            ? const Color(0xFFDCFCE7)
            : (overdueDays > 0 ? const Color(0xFFFEE2E2) : const Color(0xFFDBEAFE));
        final badgeColor = isSettled
            ? const Color(0xFF166534)
            : (overdueDays > 0 ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8));
        final badgeLabel = isSettled ? 'Quitada' : (overdueDays > 0 ? 'Em atraso' : 'Ativa');
        final installments =
            (debt['installments'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .toList();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        debt['title']?.toString().trim().isNotEmpty == true
                            ? debt['title'].toString()
                            : 'Dívida #${debt['id']}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: badgeBg,
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (borrowedAt != null)
                  Text(
                    'Empréstimo: ${DateFormat('dd/MM/yyyy').format(borrowedAt)}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                if (dueDate != null)
                  Text(
                    'Vencimento: ${DateFormat('dd/MM/yyyy').format(dueDate)}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                if (isSettled && settledAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Quitada em: ${DateFormat('dd/MM/yyyy').format(settledAt)}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    Text('Principal: ${_currency(principalOutstanding)}'),
                    Text('Juros: ${_currency(interestOutstanding)}'),
                    Text('Diária: ${_currency(dailyAccrued)}'),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Total: ${_currency(totalDue)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: isSettled
                        ? const Color(0xFF16A34A)
                        : (overdueDays > 0 ? const Color(0xFFDC2626) : const Color(0xFF111827)),
                  ),
                ),
                if (overdueDays > 0 && !isSettled) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '$overdueDays dia(s) em atraso',
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (installments.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Parcelas',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textStrong,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...installments.map((installment) {
                    final installmentDueDate = DateTime.tryParse(
                      installment['dueDate']?.toString() ?? '',
                    );
                    final paidAmount = _readDouble(installment['paidAmount']);
                    final amount = _readDouble(installment['amount']);
                    final status =
                        installment['status']?.toString().toUpperCase() ?? 'PENDING';
                    final remaining = math.max(0, amount - paidAmount).toDouble();
                    final statusLabel = switch (status) {
                      'PAID' => 'Paga',
                      'OVERDUE' => 'Em atraso',
                      'PARTIAL' => 'Parcial',
                      _ => 'Pendente',
                    };
                    final canPay = remaining > 0 && status != 'PAID';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Parcela ${installment['installmentNumber']} • ${installmentDueDate == null ? 'sem vencimento' : DateFormat('dd/MM/yyyy').format(installmentDueDate)}',
                              style: const TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                          Text(
                            '${_currency(remaining)} • $statusLabel',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (canPay) ...[
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _isCreatingPix
                                  ? null
                                  : () => _payInstallmentWithPix(installment),
                              icon: const Icon(Icons.pix_rounded, size: 18),
                              label: const Text('Pagar Pix'),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PixPaymentDialog extends StatefulWidget {
  final Map<String, dynamic> initialIntent;
  final Future<void> Function() onRefresh;

  const _PixPaymentDialog({
    required this.initialIntent,
    required this.onRefresh,
  });

  @override
  State<_PixPaymentDialog> createState() => _PixPaymentDialogState();
}

class _PixPaymentDialogState extends State<_PixPaymentDialog> {
  late Map<String, dynamic> _intent;
  Timer? _pollTimer;
  bool _isChecking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _intent = Map<String, dynamic>.from(widget.initialIntent);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  int? get _intentId => (_intent['id'] as num?)?.toInt();

  String get _status => (_intent['status']?.toString().toUpperCase() ?? 'PENDING');

  String get _qrCode => _intent['qrCode']?.toString() ?? '';

  Uint8List? get _qrCodeImageBytes {
    final raw = _intent['qrCodeBase64']?.toString() ?? '';
    if (raw.isEmpty) return null;
    try {
      return base64Decode(raw.contains(',') ? raw.split(',').last : raw);
    } catch (_) {
      return null;
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isChecking && _status != 'APPROVED') {
        _checkStatus(showSnack: false);
      }
    });
  }

  Future<void> _checkStatus({bool showSnack = true}) async {
    final id = _intentId;
    if (id == null) return;

    setState(() => _isChecking = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null || token.isEmpty) {
        throw const ApiException(statusCode: 401, message: 'Sessao expirada.');
      }

      final updatedIntent = await ApiService.fetchPixIntentStatus(
        token: token,
        intentId: id,
      );

      if (!mounted) return;
      setState(() {
        _intent = updatedIntent;
        _message = _status == 'APPROVED'
            ? 'Pagamento aprovado. Atualizando parcela...'
            : (showSnack ? 'Pagamento ainda nao confirmado.' : _message);
      });

      if (_status == 'APPROVED') {
        _pollTimer?.cancel();
        await widget.onRefresh();
        if (mounted) Navigator.of(context).pop();
      }
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _message = err is ApiException ? err.message : 'Erro ao consultar pagamento.';
      });
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _copyPix() async {
    if (_qrCode.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _qrCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pix copia e cola copiado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = _readDouble(_intent['amount']);
    final imageBytes = _qrCodeImageBytes;

    return AlertDialog(
      title: const Text('Pagamento Pix'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _currency(amount),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: _qrCode.isNotEmpty
                      ? QrImageView(data: _qrCode, backgroundColor: Colors.white)
                      : (imageBytes == null
                          ? const Center(child: Text('QR Code indisponivel.'))
                          : Image.memory(imageBytes, fit: BoxFit.contain)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_qrCode.isNotEmpty)
                SelectableText(
                  _qrCode,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _status == 'APPROVED' ? 'Pago' : 'Aguardando pagamento',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _status == 'APPROVED' ? const Color(0xFF16A34A) : AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isChecking ? null : () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
        FilledButton.icon(
          onPressed: _qrCode.isEmpty ? null : _copyPix,
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copiar Pix'),
        ),
        FilledButton.icon(
          onPressed: _isChecking ? null : () => _checkStatus(),
          icon: _isChecking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Verificar'),
        ),
      ],
    );
  }
}

class _SupportCenterTab extends StatefulWidget {
  final List<Map<String, dynamic>> conversations;
  final Future<void> Function() onRefresh;
  final void Function(String message, {bool isError}) showPortalSnack;
  final bool adminMode;

  const _SupportCenterTab({
    required this.conversations,
    required this.onRefresh,
    required this.showPortalSnack,
    this.adminMode = false,
  });

  @override
  State<_SupportCenterTab> createState() => _SupportCenterTabState();
}

class _SupportCenterTabState extends State<_SupportCenterTab> {
  bool _isSending = false;

  List<Map<String, dynamic>> get _conversations => widget.conversations;

  Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return token == null || token.isEmpty ? null : token;
  }

  Future<void> _startConversation() async {
    final subjectController = TextEditingController(text: 'Atendimento');
    final messageController = TextEditingController();
    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Abrir suporte'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: subjectController,
                  decoration: const InputDecoration(labelText: 'Assunto'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  minLines: 4,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Mensagem',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar'),
            ),
          ],
        ),
      );
      if (submitted != true) return;

      final body = messageController.text.trim();
      if (body.isEmpty) {
        widget.showPortalSnack('Digite uma mensagem para abrir o suporte.', isError: true);
        return;
      }

      final token = await _readToken();
      if (token == null) {
        widget.showPortalSnack('Sessao expirada. Entre novamente.', isError: true);
        return;
      }

      setState(() => _isSending = true);
      await ApiService.createSupportConversation(
        token: token,
        subject: subjectController.text.trim().isEmpty
            ? 'Atendimento'
            : subjectController.text.trim(),
        body: body,
      );
      await widget.onRefresh();
      widget.showPortalSnack('Mensagem enviada para o suporte.');
    } catch (e) {
      widget.showPortalSnack(
        e is ApiException ? e.message : 'Nao foi possivel enviar a mensagem.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
      subjectController.dispose();
      messageController.dispose();
    }
  }

  Future<void> _reply(Map<String, dynamic> conversation) async {
    final controller = TextEditingController();
    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Responder suporte'),
          content: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Resposta',
              alignLabelWithHint: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar'),
            ),
          ],
        ),
      );
      if (submitted != true) return;
      final body = controller.text.trim();
      if (body.isEmpty) return;

      final token = await _readToken();
      final id = (conversation['id'] as num?)?.toInt();
      if (token == null || id == null) {
        widget.showPortalSnack('Nao foi possivel identificar a conversa.', isError: true);
        return;
      }

      setState(() => _isSending = true);
      await ApiService.addSupportMessage(token: token, conversationId: id, body: body);
      await widget.onRefresh();
      widget.showPortalSnack('Resposta enviada.');
    } catch (e) {
      widget.showPortalSnack(
        e is ApiException ? e.message : 'Nao foi possivel responder agora.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 110),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.support_agent_rounded, color: AppColors.success),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Suporte Feronix',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Atendimento interno com historico salvo por conta.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _isSending ? null : _startConversation,
                  icon: const Icon(Icons.add_comment_rounded),
                  label: Text(widget.adminMode ? 'Novo' : 'Abrir'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_conversations.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text(
                'Nenhuma conversa de suporte ainda.',
                style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
              ),
            ),
          )
        else
          for (final conversation in _conversations) ...[
            _SupportConversationCard(
              conversation: conversation,
              onReply: () => _reply(conversation),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _SupportConversationCard extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback onReply;

  const _SupportConversationCard({
    required this.conversation,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final messages = (conversation['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final client = conversation['client'] as Map<String, dynamic>?;
    final subject = conversation['subject']?.toString().trim().isNotEmpty == true
        ? conversation['subject'].toString()
        : 'Atendimento';
    final status = conversation['status']?.toString() ?? 'OPEN';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    client == null ? subject : '$subject - ${client['name'] ?? 'Cliente'}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                _StatusPill(
                  text: status,
                  color: status == 'OPEN' ? AppColors.success : AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (messages.isEmpty)
              const Text('Sem mensagens.', style: TextStyle(color: AppColors.textMuted))
            else
              for (final message in messages.take(5)) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (message['direction']?.toString() == 'OUTBOUND'
                            ? AppColors.success
                            : AppColors.primary)
                        .withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    message['body']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onReply,
                icon: const Icon(Icons.reply_rounded),
                label: const Text('Responder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditLogList extends StatelessWidget {
  final List<Map<String, dynamic>> logs;

  const _AuditLogList({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum log de auditoria encontrado.',
          style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemBuilder: (context, index) {
        final log = logs[index];
        final createdAt = DateTime.tryParse(log['createdAt']?.toString() ?? '');
        final user = log['user'] as Map<String, dynamic>?;
        final severity = log['severity']?.toString() ?? 'INFO';
        final color = severity == 'ERROR'
            ? AppColors.danger
            : severity == 'WARNING'
                ? AppColors.warning
                : AppColors.success;

        return Card(
          child: ListTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.fact_check_rounded, color: color),
            ),
            title: Text(
              log['action']?.toString() ?? 'AUDIT_LOG',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              [
                if (user != null) user['email']?.toString() ?? user['name']?.toString(),
                if (createdAt != null) DateFormat('dd/MM/yyyy HH:mm').format(createdAt),
                if (log['entity'] != null) log['entity'].toString(),
              ].whereType<String>().where((item) => item.trim().isNotEmpty).join(' • '),
              style: const TextStyle(color: AppColors.textMuted),
            ),
            trailing: _StatusPill(text: severity, color: color),
          ),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: logs.length,
    );
  }
}

class _MercadoPagoAdminPanel extends StatelessWidget {
  final Map<String, dynamic>? summary;

  const _MercadoPagoAdminPanel({required this.summary});

  Map<String, dynamic> _map(String key) {
    final value = summary?[key];
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is List) {
      return value.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  String _statusText(dynamic value) => value == true ? 'OK' : 'Pendente';

  Color _statusColor(dynamic value) => value == true ? AppColors.success : AppColors.warning;

  @override
  Widget build(BuildContext context) {
    final integration = _map('integration');
    final local = _map('local');
    final webhook = _map('webhook');
    final api = _map('mercadoPagoApi');
    final recentIntents = _list(local, 'recentIntents');
    final recentLogs = _list(webhook, 'recentLogs');
    final recentPayments = _list(api, 'recentPayments');
    final apiStatus = api['status']?.toString() ?? 'NOT_CHECKED';
    final apiOk = apiStatus == 'OK';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatusPill(
              text: 'Token ${_statusText(integration['accessTokenConfigured'])}',
              color: _statusColor(integration['accessTokenConfigured']),
            ),
            _StatusPill(
              text: 'Public key ${_statusText(integration['publicKeyConfigured'])}',
              color: _statusColor(integration['publicKeyConfigured']),
            ),
            _StatusPill(
              text: 'Webhook secret ${_statusText(integration['webhookSecretConfigured'])}',
              color: _statusColor(integration['webhookSecretConfigured']),
            ),
            _StatusPill(
              text: apiOk ? 'API Mercado Pago OK' : 'API $apiStatus',
              color: apiOk ? AppColors.success : AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MercadoPagoMetricCard(
                  width: compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3,
                  title: 'Recebido local',
                  value: _currency(_readDouble(local['approvedAmount'])),
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                ),
                _MercadoPagoMetricCard(
                  width: compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3,
                  title: 'Pendente local',
                  value: _currency(_readDouble(local['pendingAmount'])),
                  icon: Icons.pending_actions_rounded,
                  color: AppColors.warning,
                ),
                _MercadoPagoMetricCard(
                  width: compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3,
                  title: 'Recebido API',
                  value: _currency(_readDouble(api['approvedAmount'])),
                  icon: Icons.account_balance_wallet_rounded,
                  color: AppColors.primary,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _MercadoPagoInfoCard(
          title: 'Webhook',
          subtitle: integration['webhookUrl']?.toString() ?? 'BACKEND_PUBLIC_URL pendente',
          children: [
            Text(
              'Processados: ${(webhook['counts'] as Map<String, dynamic>?)?['processed'] ?? 0}  |  Falhas: ${(webhook['counts'] as Map<String, dynamic>?)?['failed'] ?? 0}  |  Assinatura invalida: ${(webhook['counts'] as Map<String, dynamic>?)?['invalidSignature'] ?? 0}',
              style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if ((api['error']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          _MercadoPagoInfoCard(
            title: 'Retorno da API',
            subtitle: api['error'].toString(),
            icon: Icons.warning_amber_rounded,
            color: AppColors.warning,
          ),
        ],
        const SizedBox(height: 12),
        _MercadoPagoInfoCard(
          title: 'Ultimas cobrancas Pix',
          subtitle: recentIntents.isEmpty
              ? 'Nenhuma cobranca local encontrada.'
              : '${recentIntents.length} cobranca(s) recentes',
          children: recentIntents
              .map(
                (intent) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    intent['client'] is Map<String, dynamic>
                        ? ((intent['client'] as Map<String, dynamic>)['name']?.toString() ??
                            'Cliente')
                        : 'Cliente',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    [
                      'Parcela ${(intent['installment'] as Map<String, dynamic>?)?['installmentNumber'] ?? '-'}',
                      intent['status']?.toString() ?? 'UNKNOWN',
                      intent['mercadoPagoPaymentId']?.toString(),
                    ].whereType<String>().where((item) => item.trim().isNotEmpty).join(' • '),
                  ),
                  trailing: Text(
                    _currency(_readDouble(intent['amount'])),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              )
              .toList(),
        ),
        if (recentPayments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MercadoPagoInfoCard(
            title: 'Pagamentos recentes na API',
            subtitle: '${recentPayments.length} retorno(s) do Mercado Pago',
            children: recentPayments
                .map(
                  (payment) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      payment['id']?.toString() ?? 'Pagamento',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      [
                        payment['status']?.toString(),
                        payment['paymentMethodId']?.toString(),
                        payment['externalReference']?.toString(),
                      ].whereType<String>().where((item) => item.trim().isNotEmpty).join(' • '),
                    ),
                    trailing: Text(
                      _currency(_readDouble(payment['amount'])),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        if (recentLogs.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MercadoPagoInfoCard(
            title: 'Ultimos webhooks',
            subtitle: '${recentLogs.length} evento(s) recebidos',
            children: recentLogs
                .map(
                  (log) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      log['eventType']?.toString() ?? 'Webhook',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      [
                        log['resourceId']?.toString(),
                        log['processed'] == true ? 'processado' : 'pendente',
                        log['processingError']?.toString(),
                      ].whereType<String>().where((item) => item.trim().isNotEmpty).join(' • '),
                    ),
                    trailing: Icon(
                      log['signatureValid'] == true
                          ? Icons.verified_rounded
                          : Icons.report_problem_rounded,
                      color:
                          log['signatureValid'] == true ? AppColors.success : AppColors.warning,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _MercadoPagoInfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  const _MercadoPagoInfoCard({
    required this.title,
    required this.subtitle,
    this.icon = Icons.pix_rounded,
    this.color = AppColors.primary,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(color: AppColors.textMuted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}

class _MercadoPagoMetricCard extends StatelessWidget {
  final double width;
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MercadoPagoMetricCard({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionAutomationPanel extends StatelessWidget {
  final Map<String, dynamic>? data;
  final ValueChanged<Map<String, dynamic>> onCopy;
  final ValueChanged<Map<String, dynamic>> onWhatsApp;

  const _CollectionAutomationPanel({
    required this.data,
    required this.onCopy,
    required this.onWhatsApp,
  });

  List<Map<String, dynamic>> _items(String key) {
    final value = data?[key];
    if (value is List) return value.whereType<Map<String, dynamic>>().toList();
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final totals = (data?['totals'] as Map<String, dynamic>?) ?? const {};
    final dueToday = _items('dueToday');
    final dueTomorrow = _items('dueTomorrow');
    final overdue = _items('overdue');
    final allEmpty = dueToday.isEmpty && dueTomorrow.isEmpty && overdue.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MercadoPagoMetricCard(
                  width: compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3,
                  title: 'Vencem hoje',
                  value: '${totals['dueToday'] ?? 0}',
                  icon: Icons.today_rounded,
                  color: AppColors.primary,
                ),
                _MercadoPagoMetricCard(
                  width: compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3,
                  title: 'Em atraso',
                  value: '${totals['overdue'] ?? 0}',
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.danger,
                ),
                _MercadoPagoMetricCard(
                  width: compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3,
                  title: 'Valor na fila',
                  value: _currency(_readDouble(totals['totalAmount'])),
                  icon: Icons.payments_rounded,
                  color: AppColors.success,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        if (allEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Nenhuma parcela vencendo ou atrasada no momento.',
                style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w800),
              ),
            ),
          )
        else ...[
          _CollectionAutomationSection(
            title: 'Vencendo hoje',
            items: dueToday,
            color: AppColors.primary,
            onCopy: onCopy,
            onWhatsApp: onWhatsApp,
          ),
          const SizedBox(height: 12),
          _CollectionAutomationSection(
            title: 'Vencendo amanha',
            items: dueTomorrow,
            color: AppColors.warning,
            onCopy: onCopy,
            onWhatsApp: onWhatsApp,
          ),
          const SizedBox(height: 12),
          _CollectionAutomationSection(
            title: 'Atrasadas',
            items: overdue,
            color: AppColors.danger,
            onCopy: onCopy,
            onWhatsApp: onWhatsApp,
          ),
        ],
      ],
    );
  }
}

class _CollectionAutomationSection extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final Color color;
  final ValueChanged<Map<String, dynamic>> onCopy;
  final ValueChanged<Map<String, dynamic>> onWhatsApp;

  const _CollectionAutomationSection({
    required this.title,
    required this.items,
    required this.color,
    required this.onCopy,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return _MercadoPagoInfoCard(
      title: title,
      subtitle: '${items.length} parcela(s) com mensagem pronta',
      icon: Icons.campaign_rounded,
      color: color,
      children: items
          .map(
            (item) => _CollectionAutomationTile(
              item: item,
              color: color,
              onCopy: () => onCopy(item),
              onWhatsApp: () => onWhatsApp(item),
            ),
          )
          .toList(),
    );
  }
}

class _CollectionAutomationTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final Color color;
  final VoidCallback onCopy;
  final VoidCallback onWhatsApp;

  const _CollectionAutomationTile({
    required this.item,
    required this.color,
    required this.onCopy,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    final client = (item['client'] as Map<String, dynamic>?) ?? const {};
    final dueDate = DateTime.tryParse(item['dueDate']?.toString() ?? '');
    final hasWhatsApp = (item['whatsappLink']?.toString() ?? '').isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  client['name']?.toString() ?? 'Cliente',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              _StatusPill(
                text: item['daysLate'] != null && _readDouble(item['daysLate']) > 0
                    ? '${item['daysLate']} dia(s) atraso'
                    : 'No prazo',
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              'Parcela ${item['installmentNumber'] ?? '-'}',
              if (dueDate != null) DateFormat('dd/MM/yyyy').format(dueDate),
              _currency(_readDouble(item['remaining'])),
              client['phone']?.toString(),
            ].whereType<String>().where((entry) => entry.trim().isNotEmpty).join(' | '),
            style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            item['message']?.toString() ?? '',
            style: const TextStyle(color: AppColors.textBody, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.content_copy_rounded),
                label: const Text('Copiar'),
              ),
              FilledButton.icon(
                onPressed: hasWhatsApp ? onWhatsApp : null,
                icon: const Icon(Icons.chat_rounded),
                label: const Text('WhatsApp'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaasPlanPanel extends StatelessWidget {
  final Map<String, dynamic>? data;
  final ValueChanged<String> onSelectPlan;

  const _SaasPlanPanel({
    required this.data,
    required this.onSelectPlan,
  });

  String _price(Map<String, dynamic> plan) {
    final cents = (plan['priceCents'] as num?)?.toInt() ?? 0;
    if (cents <= 0) return 'Gratis';
    return _currency(cents / 100);
  }

  @override
  Widget build(BuildContext context) {
    final subscription = (data?['subscription'] as Map<String, dynamic>?) ?? const {};
    final currentPlan = (subscription['plan'] as Map<String, dynamic>?) ?? const {};
    final usage = (data?['usage'] as Map<String, dynamic>?) ?? const {};
    final plans = (data?['plans'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];
    final activeClients = (usage['activeClients'] as num?)?.toInt() ?? 0;
    final clientLimit = usage['clientLimit'];
    final unlimited = usage['unlimitedClients'] == true;
    final usagePercent = (usage['usagePercent'] as num?)?.toDouble() ?? 0;
    final currentCode = currentPlan['code']?.toString() ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MercadoPagoMetricCard(
                  width: compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3,
                  title: 'Plano atual',
                  value: currentPlan['name']?.toString() ?? 'Gratis',
                  icon: Icons.workspace_premium_rounded,
                  color: AppColors.primary,
                ),
                _MercadoPagoMetricCard(
                  width: compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3,
                  title: 'Clientes ativos',
                  value: unlimited ? '$activeClients / ilimitado' : '$activeClients / $clientLimit',
                  icon: Icons.groups_rounded,
                  color: usage['limitReached'] == true ? AppColors.danger : AppColors.success,
                ),
                _MercadoPagoMetricCard(
                  width: compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3,
                  title: 'Status',
                  value: subscription['status']?.toString() ?? 'TRIAL',
                  icon: Icons.verified_user_rounded,
                  color: AppColors.success,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Uso do limite',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: unlimited ? 0 : (usagePercent / 100).clamp(0.0, 1.0),
                    backgroundColor: AppColors.borderSoft,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      usage['limitReached'] == true ? AppColors.danger : AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  unlimited
                      ? 'Este plano nao possui limite de clientes ativos.'
                      : 'Restam ${usage['remainingClients'] ?? 0} cliente(s) ativo(s) neste plano.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: plans
              .map(
                (plan) => _SaasPlanCard(
                  plan: plan,
                  price: _price(plan),
                  selected: plan['code']?.toString() == currentCode,
                  onSelect: () => onSelectPlan(plan['code']?.toString() ?? ''),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _SaasPlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final String price;
  final bool selected;
  final VoidCallback onSelect;

  const _SaasPlanCard({
    required this.plan,
    required this.price,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final features = (plan['features'] as List?)?.map((item) => item.toString()).toList() ??
        const <String>[];
    final limit = plan['clientLimit'];

    return SizedBox(
      width: 290,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan['name']?.toString() ?? 'Plano',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (selected)
                    const _StatusPill(text: 'Atual', color: AppColors.success),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                price,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                limit == null ? 'Clientes ilimitados' : 'Ate $limit clientes ativos',
                style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...features.take(5).map(
                    (feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              size: 18, color: AppColors.success),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feature,
                              style: const TextStyle(color: AppColors.textBody, height: 1.25),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: selected ? null : onSelect,
                  icon: Icon(selected ? Icons.lock_rounded : Icons.upgrade_rounded),
                  label: Text(selected ? 'Plano atual' : 'Selecionar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientPaymentsList extends StatelessWidget {
  final List<Map<String, dynamic>> payments;

  const _ClientPaymentsList({required this.payments});

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum pagamento encontrado.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 110),
      itemBuilder: (context, index) {
        final payment = payments[index];
        final paidAt = DateTime.tryParse(payment['paidAt']?.toString() ?? '');
        final rawType = payment['type']?.toString() ?? 'PAGAMENTO';
        final type = switch (rawType.toUpperCase()) {
          'JUROS' => 'Pagamento de juros',
          'PARCIAL' => 'Pagamento parcial',
          'TOTAL' => 'Quitação',
          'PARCELA' => 'Parcela paga',
          _ => rawType,
        };
        final amount = _readDouble(payment['amount']);

        return Card(
          child: ListTile(
            title: Text(
              type,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: paidAt == null
                ? null
                : Text(DateFormat('dd/MM/yyyy HH:mm').format(paidAt)),
            trailing: Text(
              _currency(amount),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemCount: payments.length,
    );
  }
}

class MainNavigationPage extends StatefulWidget {
  final UserAccount account;
  final VoidCallback onLogout;
  final Future<void> Function() onDeleteAccount;
  final WindowsLicenseInfo? windowsLicense;
  final AppAccentPreset accentPreset;
  final AppThemePreference themePreference;
  final double fontScale;
  final Future<void> Function(AppAccentPreset preset) onUpdateAccentPreset;
  final Future<void> Function(AppThemePreference preference) onUpdateThemePreference;
  final Future<void> Function(double scale) onUpdateFontScale;
  final Future<void> Function() onResetVisualPreferences;

  const MainNavigationPage({
    super.key,
    required this.account,
    required this.onLogout,
    required this.onDeleteAccount,
    this.windowsLicense,
    required this.accentPreset,
    required this.themePreference,
    required this.fontScale,
    required this.onUpdateAccentPreset,
    required this.onUpdateThemePreference,
    required this.onUpdateFontScale,
    required this.onResetVisualPreferences,
  });

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  final List<Client> _clients = [];
  TextEditingController? _searchController;
  List<CustomReminder>? _customReminders;
  bool _isLoading = true;
  Map<String, dynamic>? dashboardData;
  bool isLoadingDashboard = true;
  AppPlan? _selectedPlan;
  _MainSection _selectedSection = _MainSection.metricas;
  String? _searchQuery;
  _ClientQuickFilter? _activeQuickFilter;
  TextEditingController? _paymentHistorySearchController;
  String? _paymentHistoryQuery;
  _PaymentHistoryQuickFilter? _paymentHistoryFilter;
  bool _bulkSelectionMode = false;
  final Set<String> _selectedClientIds = <String>{};
  Uint8List? _profilePhotoBytes;
  String? _profileDisplayName;
  double _profilePhotoOffsetX = 0;
  double _profilePhotoOffsetY = 0;
  double _profilePhotoScale = 1.85;
  double _profilePhotoAspectRatio = 0.75;
  String? _adminInviteCode;
  int? _adminInviteAccountId;
  List<Map<String, dynamic>> _creditRequests = const [];
  bool _isLoadingCreditRequests = false;
  String? _creditRequestsError;
  List<Map<String, dynamic>> _supportConversations = const [];
  bool _isLoadingSupport = false;
  String? _supportError;
  Map<String, dynamic>? _premiumSettings;
  bool _isSavingPremiumSettings = false;
  List<Map<String, dynamic>> _auditLogs = const [];
  bool _isLoadingAudit = false;
  String? _auditError;
  Map<String, dynamic>? _mercadoPagoSummary;
  bool _isLoadingMercadoPago = false;
  String? _mercadoPagoError;
  Map<String, dynamic>? _collectionAutomation;
  bool _isLoadingCollections = false;
  String? _collectionAutomationError;
  Map<String, dynamic>? _saasStatus;
  bool _isLoadingSaas = false;
  String? _saasError;

  TextEditingController get _safeSearchController => _searchController ??= TextEditingController();
  AppPlan get _safeSelectedPlan => _selectedPlan ??= AppPlan.basic;
  String get _safeSearchQuery => _searchQuery ??= '';
  _ClientQuickFilter get _safeActiveQuickFilter => _activeQuickFilter ??= _ClientQuickFilter.todos;
  List<CustomReminder> get _safeCustomReminders => _customReminders ??= [];
  TextEditingController get _safePaymentHistorySearchController =>
      _paymentHistorySearchController ??= TextEditingController();
  String get _safePaymentHistoryQuery => _paymentHistoryQuery ??= '';
  _PaymentHistoryQuickFilter get _safePaymentHistoryFilter =>
      _paymentHistoryFilter ??= _PaymentHistoryQuickFilter.todos;
  String get _safeProfileDisplayName {
    final localName = _profileDisplayName?.trim() ?? '';
    if (localName.isNotEmpty) return localName;
    final accountName = widget.account.name.trim();
    if (accountName.isNotEmpty) return accountName;
    return 'Usuário COBREJÁ';
  }

  Future<String?> _readAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Client _clientFromBackendDetails({
    required Map<String, dynamic> clientItem,
    required Map<String, dynamic> details,
    required Client? previous,
  }) {
    String? _optionalString(dynamic value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    int? _optionalInt(dynamic value) {
      if (value is num) return value.toInt();
      if (value == null) return null;
      return int.tryParse(value.toString());
    }

    DateTime? _optionalDate(dynamic value) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    final debts = (details['debts'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final tabs = (details['tabs'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final activeDebts = debts.where((debt) {
      final status = debt['status']?.toString().toUpperCase();
      final deletedAt = debt['deletedAt'];
      return status == 'ACTIVE' && (deletedAt == null || deletedAt.toString().isEmpty);
    }).toList();

    // UI legacy: ainda usamos um "debt principal" para preencher o card.
    // Quando houver múltiplas dívidas, escolhemos a primeira ativa (ordenada pelo backend por dueDate asc).
    final primaryDebt = activeDebts.isNotEmpty
        ? activeDebts.first
        : (debts.isNotEmpty ? debts.first : <String, dynamic>{});

    final principalAmount = _readDouble(primaryDebt['principalAmount']);
    final principalOutstanding = _readDouble(primaryDebt['principalOutstanding']);

    final borrowedAt = DateTime.tryParse(primaryDebt['borrowedAt']?.toString() ?? '') ??
        previous?.borrowedDate ??
        DateTime.now();
    final dueDate = DateTime.tryParse(primaryDebt['dueDate']?.toString() ?? '') ??
        previous?.dueDate ??
        DateTime.now().add(const Duration(days: 30));

    final backendPrimaryDebtId =
        (primaryDebt['id'] as num?)?.toInt() ?? previous?.backendPrimaryDebtId;

    final monthlyMode = primaryDebt['monthlyInterestMode']?.toString().toUpperCase();
    final monthlyValue = _readDouble(primaryDebt['monthlyInterestValue']);
    final monthlyInterestType = monthlyMode == 'FIXED'
        ? InterestValueType.fixedAmount
        : InterestValueType.percentage;
    final monthlyInterestRate =
        (monthlyMode == 'PERCENTAGE' && monthlyValue > 0) ? monthlyValue : 0.0;
    final monthlyInterestAmount =
        (monthlyMode == 'FIXED' && monthlyValue > 0) ? monthlyValue : 0.0;

    final dailyMode = primaryDebt['dailyInterestMode']?.toString().toUpperCase();
    final dailyValue = _readDouble(
      primaryDebt['dailyInterestValue'] ?? primaryDebt['dailyFee'],
    );
    final dailyInterestType = dailyMode == 'FIXED'
        ? InterestValueType.fixedAmount
        : InterestValueType.percentage;
    final dailyInterestRate =
        (dailyMode == 'PERCENTAGE' && dailyValue > 0) ? dailyValue : 0.0;
    final dailyInterestAmount =
        (dailyMode == 'FIXED' && dailyValue > 0) ? dailyValue : 0.0;

    String paymentLabel(String rawType) {
      switch (rawType) {
        case 'JUROS':
          return 'Pagamento de juros';
        case 'PARCIAL':
          return 'Pagamento parcial';
        case 'TOTAL':
          return 'QuitaÃ§Ã£o';
        case 'PARCELA':
          return 'Pagamento de parcela';
        default:
          return 'Pagamento';
      }
    }

    final payments = (details['payments'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final paymentHistory = payments
        .map((payment) {
          final rawType = payment['type']?.toString().toUpperCase() ?? '';
          final paidAt = DateTime.tryParse(payment['paidAt']?.toString() ?? '') ??
              DateTime.tryParse(payment['createdAt']?.toString() ?? '') ??
              DateTime.now();
          return PaymentRecord(
            id: payment['id']?.toString() ?? '',
            date: paidAt,
            amount: _readDouble(payment['amount']),
            interestPaid: _readDouble(payment['interestAmount']) +
                _readDouble(payment['dailyAmount']),
            dailyPaid: _readDouble(payment['dailyAmount']),
            principalPaid: _readDouble(payment['principalAmount']),
            type: paymentLabel(rawType),
            note: payment['note']?.toString() ?? '',
          );
        })
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final totalInterestCollected = paymentHistory.fold<double>(
      0,
      (sum, payment) => sum + payment.interestPaid,
    );
    final totalPrincipalCollected = paymentHistory.fold<double>(
      0,
      (sum, payment) => sum + payment.principalPaid,
    );

    final isExcludedBackend = (details['status']?.toString().toUpperCase() == 'EXCLUDED') ||
        (tabs['excluded'] == true);
    final isQuitadoBackend = tabs['quitados'] == true;
    final isDevendoBackend = tabs['devendo'] == true || activeDebts.isNotEmpty;

    final status = isExcludedBackend
        ? 'excluído'
        : (isQuitadoBackend ? 'quitado' : (isDevendoBackend ? 'devendo' : (details.isEmpty ? (previous?.status ?? 'devendo') : 'ativo')));

    final backendUserId =
        _optionalInt(details['userId'] ?? clientItem['userId']) ?? previous?.backendUserId;
    final cpf = _optionalString(details['cpf']) ?? previous?.cpf;
    final email = _optionalString(details['email']) ?? previous?.email;
    final address = _optionalString(details['address']) ?? previous?.address;
    final avatarUrl = _optionalString(details['avatarUrl']) ?? previous?.avatarUrl;
    final deletedAt = details.containsKey('deletedAt')
        ? _optionalDate(details['deletedAt'])
        : previous?.deletedAt;

    return Client(
      id: clientItem['id']?.toString() ?? previous?.id ?? '',
      backendUserId: backendUserId,
      cpf: cpf,
      address: address,
      email: email,
      avatarUrl: avatarUrl,
      backendPrimaryDebtId: backendPrimaryDebtId,
      name: clientItem['name']?.toString() ?? previous?.name ?? '',
      phone: clientItem['phone']?.toString() ?? previous?.phone ?? '',
      borrowedAmount: principalAmount,
      // principalAmount - principalOutstanding
      activePrincipalCollected: math.max(0.0, principalAmount - principalOutstanding),
      monthlyInterestRate: monthlyInterestRate,
      monthlyInterestAmount: monthlyInterestAmount,
      monthlyInterestType: monthlyInterestType,
      dailyInterestRate: dailyInterestRate,
      dailyInterestAmount: dailyInterestAmount,
      dailyInterestType: dailyInterestType,
      borrowedDate: borrowedAt,
      dueDate: dueDate,
      originalTermDays: math.max(1, dueDate.difference(borrowedAt).inDays),
      cycleStartDate: DateTime.tryParse(primaryDebt['lastInterestPaidAt']?.toString() ?? '') ??
          borrowedAt,
      deletedAt: deletedAt,
      statusBeforeDeletion: previous?.statusBeforeDeletion,
      status: status,
      pagouJuros: tabs['jurosPagos'] == true,
      isNegotiated: tabs['renegociados'] == true ||
          primaryDebt['kind']?.toString().toUpperCase() == 'RENEGOTIATED' ||
          (previous?.isNegotiated ?? false),
      isMarkedAsLost: previous?.isMarkedAsLost ?? false,
      installmentCount: previous?.installmentCount ?? 0,
      installmentsPaid: previous?.installmentsPaid ?? 0,
      installmentAmount: previous?.installmentAmount ?? 0,
      renegotiatedAt: previous?.renegotiatedAt,
      installmentStartDate: previous?.installmentStartDate,
      lastInterestPaidAt: DateTime.tryParse(primaryDebt['lastInterestPaidAt']?.toString() ?? '') ??
          previous?.lastInterestPaidAt,
      interestPaidCurrentCycle: _readDouble(primaryDebt['currentCycleInterestPaid']),
      totalInterestCollected: totalInterestCollected,
      totalPrincipalCollected: totalPrincipalCollected,
      paymentHistory: paymentHistory,
      backendDebts: debts,
    );
  }

  Future<void> _refreshClientsFromBackend({bool updateLoading = false}) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) return;
    try {
      if (updateLoading && mounted) {
        setState(() => _isLoading = true);
      }
      final list = await ApiService.fetchClients(token: token);
      final localById = {for (final item in _clients) item.id: item};

      if (!mounted) return;
      _clients
        ..clear()
        ..addAll(
          list.map((item) {
            final id = item['id']?.toString() ?? '';
            return _clientFromBackendDetails(
              clientItem: item,
              // O endpoint /clients ja traz debts/payments/tabs. Evitamos fazer N
              // requests extras (um por cliente), o que quebrava atualizacoes e
              // restauracoes quando alguma chamada falhava.
              details: item,
              previous: localById[id],
            );
          }),
        );
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Falha ao atualizar clientes do backend: $e');
      if (updateLoading && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> fetchDashboard() async {
  try {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() => isLoadingDashboard = false);
      return;
    }
    final data = await ApiService.fetchClientsSummary(token: token);

    if (!mounted) return;
    setState(() {
      dashboardData = data;
      isLoadingDashboard = false;
    });

  } catch (e) {
    debugPrint('Erro ao buscar dashboard: $e');
    if (!mounted) return;
    setState(() => isLoadingDashboard = false);
  }
}

  void _ensureCreditRequestsLoaded() {
    if (_creditRequests.isNotEmpty || _isLoadingCreditRequests) return;
    _refreshCreditRequests(updateLoading: true);
  }

  Future<void> _refreshCreditRequests({bool updateLoading = false}) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) return;

    try {
      if (updateLoading && mounted) {
        setState(() {
          _isLoadingCreditRequests = true;
          _creditRequestsError = null;
        });
      }

      final requests = await ApiService.fetchCreditRequests(token: token);

      if (!mounted) return;
      setState(() {
        _creditRequests = requests;
        _isLoadingCreditRequests = false;
      });
    } catch (e) {
      debugPrint('Erro ao buscar solicitações: $e');
      if (!mounted) return;
      setState(() {
        _creditRequestsError =
            e is ApiException ? e.message : 'Não foi possível carregar as solicitações.';
        _isLoadingCreditRequests = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _safeSearchController.addListener(() {
      final next = _safeSearchController.text.trim();
      if (next == _safeSearchQuery) return;
      setState(() {
        _searchQuery = next;
      });
    });
    _safePaymentHistorySearchController.addListener(() {
      final next = _safePaymentHistorySearchController.text.trim();
      if (next == _safePaymentHistoryQuery) return;
      setState(() {
        _paymentHistoryQuery = next;
      });
    });
    _loadClients();
    _loadAdminInviteCode();
    _refreshSupportConversations();
    _loadPremiumSettings();
    _refreshAuditLogs();
    _refreshMercadoPagoSummary();
    _refreshCollectionAutomation();
    _refreshSaasStatus();
    fetchDashboard();
  }

  Future<void> _refreshSaasStatus({bool updateLoading = false}) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) return;
    try {
      if (updateLoading && mounted) {
        setState(() {
          _isLoadingSaas = true;
          _saasError = null;
        });
      }
      final status = await ApiService.fetchSaasStatus(token: token);
      if (!mounted) return;
      setState(() {
        _saasStatus = status;
        _isLoadingSaas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saasError = e is ApiException ? e.message : 'Nao foi possivel carregar o plano.';
        _isLoadingSaas = false;
      });
    }
  }

  Future<void> _selectSaasPlan(String planCode) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) {
      _showSnack('Sessao expirada. Entre novamente.', tone: _FeedbackTone.error);
      return;
    }
    try {
      setState(() => _isLoadingSaas = true);
      final result = await ApiService.selectSaasPlan(token: token, planCode: planCode);
      final overview = (result['overview'] as Map<String, dynamic>?) ?? result;
      if (!mounted) return;
      setState(() {
        _saasStatus = overview;
        _isLoadingSaas = false;
      });
      _showSnack(
        'Plano atualizado com sucesso.',
        tone: _FeedbackTone.success,
        title: 'SaaS',
      );
      _refreshAuditLogs();
    } catch (e) {
      if (mounted) setState(() => _isLoadingSaas = false);
      _showSnack(
        e is ApiException ? e.message : 'Nao foi possivel alterar o plano.',
        tone: _FeedbackTone.error,
        title: 'Plano nao alterado',
      );
    }
  }

  Future<void> _openSaasPlanPanel() async {
    await _refreshSaasStatus(updateLoading: true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Planos e limites',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Atualizar',
                      onPressed: () => _refreshSaasStatus(updateLoading: true),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (_isLoadingSaas)
                const Expanded(child: _CobrejaLoading(label: 'Carregando plano'))
              else if (_saasError != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _saasError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: _SaasPlanPanel(
                    data: _saasStatus,
                    onSelectPlan: _selectSaasPlan,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshCollectionAutomation({bool updateLoading = false}) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) return;
    try {
      if (updateLoading && mounted) {
        setState(() {
          _isLoadingCollections = true;
          _collectionAutomationError = null;
        });
      }
      final data = await ApiService.fetchCollectionAutomation(token: token);
      if (!mounted) return;
      setState(() {
        _collectionAutomation = data;
        _isLoadingCollections = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _collectionAutomationError =
            e is ApiException ? e.message : 'Nao foi possivel carregar cobrancas.';
        _isLoadingCollections = false;
      });
    }
  }

  Future<void> _registerAndUseCollectionItem(
    Map<String, dynamic> item, {
    required bool openWhatsApp,
  }) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) {
      _showSnack('Sessao expirada. Entre novamente.', tone: _FeedbackTone.error);
      return;
    }

    final installmentId = (item['installmentId'] as num?)?.toInt();
    final message = item['message']?.toString() ?? '';
    if (installmentId == null || message.trim().isEmpty) {
      _showSnack('Cobranca invalida para gerar mensagem.', tone: _FeedbackTone.warning);
      return;
    }

    try {
      await ApiService.registerCollectionGenerated(
        token: token,
        installmentId: installmentId,
        channel: openWhatsApp ? 'WHATSAPP_LINK' : 'COPY_MESSAGE',
      );
      await Clipboard.setData(ClipboardData(text: message));

      if (openWhatsApp) {
        final link = item['whatsappLink']?.toString() ?? '';
        if (link.trim().isEmpty) {
          _showSnack(
            'Mensagem copiada, mas este cliente nao tem telefone cadastrado.',
            tone: _FeedbackTone.warning,
            title: 'WhatsApp indisponivel',
          );
          return;
        }
        final uri = Uri.parse(link);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      _showSnack(
        openWhatsApp
            ? 'Cobranca registrada e WhatsApp aberto.'
            : 'Mensagem copiada e cobranca registrada.',
        tone: _FeedbackTone.success,
        title: 'Cobranca gerada',
      );
      _refreshAuditLogs();
    } catch (e) {
      _showSnack(
        e is ApiException ? e.message : 'Nao foi possivel registrar a cobranca.',
        tone: _FeedbackTone.error,
        title: 'Erro na cobranca',
      );
    }
  }

  Future<void> _openCollectionAutomationPanel() async {
    await _refreshCollectionAutomation(updateLoading: true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 780),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Automacoes de cobranca',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Atualizar',
                      onPressed: () => _refreshCollectionAutomation(updateLoading: true),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (_isLoadingCollections)
                const Expanded(child: _CobrejaLoading(label: 'Carregando cobrancas'))
              else if (_collectionAutomationError != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _collectionAutomationError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: _CollectionAutomationPanel(
                    data: _collectionAutomation,
                    onCopy: (item) =>
                        _registerAndUseCollectionItem(item, openWhatsApp: false),
                    onWhatsApp: (item) =>
                        _registerAndUseCollectionItem(item, openWhatsApp: true),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshMercadoPagoSummary({bool updateLoading = false}) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) return;
    try {
      if (updateLoading && mounted) {
        setState(() {
          _isLoadingMercadoPago = true;
          _mercadoPagoError = null;
        });
      }
      final summary = await ApiService.fetchMercadoPagoSummary(token: token);
      if (!mounted) return;
      setState(() {
        _mercadoPagoSummary = summary;
        _isLoadingMercadoPago = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mercadoPagoError =
            e is ApiException ? e.message : 'Nao foi possivel carregar Mercado Pago.';
        _isLoadingMercadoPago = false;
      });
    }
  }

  Future<void> _openMercadoPagoPanel() async {
    await _refreshMercadoPagoSummary(updateLoading: true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Mercado Pago',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Atualizar',
                      onPressed: () => _refreshMercadoPagoSummary(updateLoading: true),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (_isLoadingMercadoPago)
                const Expanded(child: _CobrejaLoading(label: 'Carregando Mercado Pago'))
              else if (_mercadoPagoError != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _mercadoPagoError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: _MercadoPagoAdminPanel(summary: _mercadoPagoSummary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshAuditLogs({bool updateLoading = false}) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) return;
    try {
      if (updateLoading && mounted) {
        setState(() {
          _isLoadingAudit = true;
          _auditError = null;
        });
      }
      final logs = await ApiService.listAuditLogs(token: token);
      if (!mounted) return;
      setState(() {
        _auditLogs = logs.whereType<Map<String, dynamic>>().toList();
        _isLoadingAudit = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _auditError = e is ApiException ? e.message : 'Nao foi possivel carregar auditoria.';
        _isLoadingAudit = false;
      });
    }
  }

  Future<void> _openAuditPanel() async {
    await _refreshAuditLogs(updateLoading: true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Auditoria',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (_isLoadingAudit)
                const Expanded(child: _CobrejaLoading(label: 'Carregando auditoria'))
              else if (_auditError != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _auditError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: _AuditLogList(logs: _auditLogs),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadPremiumSettings() async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) return;
    try {
      final settings = await ApiService.getPremiumSettings(token: token);
      if (!mounted) return;
      setState(() => _premiumSettings = settings);
    } catch (e) {
      debugPrint('Falha ao carregar configuracoes premium: $e');
    }
  }

  Future<void> _openPremiumSettingsDialog() async {
    final settings = _premiumSettings ?? const <String, dynamic>{};
    final company = (settings['company'] as Map<String, dynamic>?) ?? const {};
    final finance = (settings['finance'] as Map<String, dynamic>?) ?? const {};
    final notifications =
        (settings['notifications'] as Map<String, dynamic>?) ?? const {};
    final nameController = TextEditingController(
      text: company['name']?.toString() ?? widget.account.name,
    );
    final cnpjController = TextEditingController(text: company['cnpj']?.toString() ?? '');
    final phoneController = TextEditingController(text: company['phone']?.toString() ?? '');
    final emailController = TextEditingController(text: company['email']?.toString() ?? '');
    final addressController = TextEditingController(text: company['address']?.toString() ?? '');
    final monthlyController =
        TextEditingController(text: finance['monthlyInterest']?.toString() ?? '0');
    final dailyController =
        TextEditingController(text: finance['dailyInterest']?.toString() ?? '0');
    final maxInstallmentsController =
        TextEditingController(text: finance['maxInstallments']?.toString() ?? '12');
    var billingNotifications = notifications['billing'] != false;
    var whatsappNotifications = notifications['whatsapp'] != false;

    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Configurações premium'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Empresa',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nome da empresa'),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: 190,
                          child: TextField(
                            controller: cnpjController,
                            decoration: const InputDecoration(labelText: 'CNPJ'),
                          ),
                        ),
                        SizedBox(
                          width: 190,
                          child: TextField(
                            controller: phoneController,
                            decoration: const InputDecoration(labelText: 'Telefone'),
                          ),
                        ),
                        SizedBox(
                          width: 190,
                          child: TextField(
                            controller: emailController,
                            decoration: const InputDecoration(labelText: 'Email'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(labelText: 'Endereço'),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Financeiro padrão',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: monthlyController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Juros mensal'),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: dailyController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Juros diário'),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: maxInstallmentsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Parcelas máximas'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: billingNotifications,
                      title: const Text('Notificações de cobrança'),
                      onChanged: (value) =>
                          setDialogState(() => billingNotifications = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: whatsappNotifications,
                      title: const Text('Notificações WhatsApp'),
                      onChanged: (value) =>
                          setDialogState(() => whatsappNotifications = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isSavingPremiumSettings
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: _isSavingPremiumSettings
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.save_rounded),
                label: const Text('Salvar'),
              ),
            ],
          ),
        ),
      );
      if (submitted != true) return;

      final token = await _readAuthToken();
      if (token == null || token.isEmpty) {
        _showAdminSupportSnack('Sessao expirada. Entre novamente.', isError: true);
        return;
      }

      setState(() => _isSavingPremiumSettings = true);
      final updated = await ApiService.updatePremiumSettings(
        token: token,
        settings: {
          'company': {
            'name': nameController.text.trim(),
            'cnpj': cnpjController.text.trim(),
            'phone': phoneController.text.trim(),
            'email': emailController.text.trim(),
            'address': addressController.text.trim(),
          },
          'finance': {
            'monthlyInterest': _readDouble(monthlyController.text),
            'dailyInterest': _readDouble(dailyController.text),
            'maxInstallments':
                int.tryParse(maxInstallmentsController.text.trim()) ?? 12,
          },
          'notifications': {
            'billing': billingNotifications,
            'whatsapp': whatsappNotifications,
          },
        },
      );

      if (!mounted) return;
      setState(() => _premiumSettings = updated);
      _showAdminSupportSnack('Configuracoes premium salvas.');
    } catch (e) {
      if (!mounted) return;
      _showAdminSupportSnack(
        e is ApiException ? e.message : 'Nao foi possivel salvar configuracoes.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSavingPremiumSettings = false);
      nameController.dispose();
      cnpjController.dispose();
      phoneController.dispose();
      emailController.dispose();
      addressController.dispose();
      monthlyController.dispose();
      dailyController.dispose();
      maxInstallmentsController.dispose();
    }
  }

  void _showAdminSupportSnack(String message, {bool isError = false}) {
    _showSnack(
      message,
      tone: isError ? _FeedbackTone.error : _FeedbackTone.success,
      title: isError ? 'Suporte' : 'Tudo certo',
    );
  }

  Future<void> _refreshSupportConversations({bool updateLoading = false}) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) return;
    try {
      if (updateLoading && mounted) {
        setState(() {
          _isLoadingSupport = true;
          _supportError = null;
        });
      }
      final conversations = await ApiService.listSupportConversations(token: token);
      if (!mounted) return;
      setState(() {
        _supportConversations = conversations
            .whereType<Map<String, dynamic>>()
            .toList();
        _isLoadingSupport = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _supportError = e is ApiException
            ? e.message
            : 'Nao foi possivel carregar o suporte.';
        _isLoadingSupport = false;
      });
    }
  }

  Future<void> _openSupportPanel() async {
    await _refreshSupportConversations(updateLoading: true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Painel de suporte',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (_isLoadingSupport)
                const Expanded(child: _CobrejaLoading(label: 'Carregando suporte'))
              else if (_supportError != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _supportError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: _SupportCenterTab(
                    conversations: _supportConversations,
                    onRefresh: () => _refreshSupportConversations(updateLoading: true),
                    showPortalSnack: _showAdminSupportSnack,
                    adminMode: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadAdminInviteCode() async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) return;
    try {
      final me = await ApiService.fetchMe(token: token);
      final account = me['account'];
      if (account is! Map<String, dynamic>) return;
      final inviteCode = account['inviteCode']?.toString().trim();
      final accountId = int.tryParse(account['id']?.toString() ?? '');
      if ((inviteCode == null || inviteCode.isEmpty) && accountId == null) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _adminInviteCode = inviteCode == null || inviteCode.isEmpty
            ? null
            : inviteCode;
        _adminInviteAccountId = accountId;
      });
    } catch (e) {
      debugPrint('Falha ao carregar convite do administrador: $e');
    }
  }

  String _buildClientInviteLink(String inviteCode) {
    return Uri.base
        .replace(
          path: '/',
          queryParameters: {'convite': inviteCode},
          fragment: '',
        )
        .toString();
  }

  String _buildClientAccountInviteLink(int accountId) {
    return Uri.base
        .replace(
          path: '/',
          queryParameters: {'conta': accountId.toString()},
          fragment: '',
        )
        .toString();
  }

  Future<void> _copyClientInviteLink() async {
    if ((_adminInviteCode == null || _adminInviteCode!.isEmpty) &&
        _adminInviteAccountId == null) {
      await _loadAdminInviteCode();
    }
    final resolvedCode = _adminInviteCode;
    final resolvedAccountId = _adminInviteAccountId;
    if ((resolvedCode == null || resolvedCode.isEmpty) &&
        resolvedAccountId == null) {
      _showSnack(
        'Nao consegui carregar o codigo de convite agora. Tente novamente em instantes.',
        tone: _FeedbackTone.warning,
        title: 'Convite indisponivel',
      );
      return;
    }
    final inviteLink = resolvedCode != null && resolvedCode.isNotEmpty
        ? _buildClientInviteLink(resolvedCode)
        : _buildClientAccountInviteLink(resolvedAccountId!);
    await Clipboard.setData(
      ClipboardData(text: inviteLink),
    );
    if (!mounted) return;
    _showSnack(
      'Link de cadastro do cliente copiado.',
      tone: _FeedbackTone.success,
      title: 'Convite copiado',
    );
  }

  @override
  void dispose() {
    _searchController?.dispose();
    _paymentHistorySearchController?.dispose();
    super.dispose();
  }

  void _clearBulkSelection() {
    if (!mounted) return;
    setState(() {
      _bulkSelectionMode = false;
      _selectedClientIds.clear();
    });
  }

  bool _isExcludedClient(Client client) =>
      client.status == 'excluído' || client.status == 'excluido';

  bool _isQuitadoClient(Client client) =>
      !_isExcludedClient(client) &&
      (client.status == 'quitado' || client.remainingPrincipal <= 0.009);

  bool _hasInterestHistory(Client client) =>
      client.pagouJuros ||
      client.paymentHistory.any((payment) => payment.type == 'Pagamento de juros');

  bool _isOverdueClient(Client client) {
    if (_isExcludedClient(client) || _isQuitadoClient(client) || client.isNegotiated) {
      return false;
    }
    return FinanceService.calculateDebt(client).isOverdue;
  }

  bool _isInicioVisibleClient(Client client) {
    return false;
  }

  bool _isDevendoVisibleClient(Client client) {
    if (_isExcludedClient(client) || _isQuitadoClient(client)) {
      return false;
    }
    return client.status == 'devendo';
  }

  DateTime _nextMonthlyDueDate(Client client, {DateTime? fromDate}) {
    final base = fromDate ?? client.dueDate;
    final nextMonth = DateTime(base.year, base.month + 1, 1);
    final maxDay = DateUtils.getDaysInMonth(nextMonth.year, nextMonth.month);
    final anchorDay = math.min(client.borrowedDate.day, maxDay);
    return DateTime(nextMonth.year, nextMonth.month, anchorDay);
  }

  DateTime _anchoredDueDateFromReference({
    required DateTime borrowedDate,
    required DateTime referenceDate,
  }) {
    final nextMonth = DateTime(referenceDate.year, referenceDate.month + 1, 1);
    final maxDay = DateUtils.getDaysInMonth(nextMonth.year, nextMonth.month);
    final anchorDay = math.min(borrowedDate.day, maxDay);
    return DateTime(nextMonth.year, nextMonth.month, anchorDay);
  }

  List<Client> _clientsForSection(
    String tabType, {
    bool includeAllActive = false,
    _ClientQuickFilter overrideFilter = _ClientQuickFilter.todos,
  }) {
    List<Client> filteredClients;

    if (includeAllActive) {
      filteredClients = _clients.where(_isInicioVisibleClient).toList();
    } else {
      switch (tabType) {
        case 'devendo':
          filteredClients = _clients.where(_isDevendoVisibleClient).toList();
          break;
        case 'juros':
          filteredClients = _clients
              .where(
                (item) =>
                    !_isExcludedClient(item) &&
                    !_isQuitadoClient(item) &&
                    !item.isNegotiated &&
                    _hasInterestHistory(item),
              )
              .toList();
          break;
        case 'quitado':
          filteredClients = _clients.where(_isQuitadoClient).toList();
          break;
        case 'excluído':
        case 'excluido':
          filteredClients = _clients.where(_isExcludedClient).toList();
          break;
        default:
          filteredClients = _clients.where((item) => item.status == tabType).toList();
      }
    }

    filteredClients = filteredClients.where((client) {
      final debt = FinanceService.calculateDebt(client);
      switch (overrideFilter) {
        case _ClientQuickFilter.todos:
          return true;
        case _ClientQuickFilter.atrasados:
          return !_isExcludedClient(client) &&
              !_isQuitadoClient(client) &&
              !client.isNegotiated &&
              debt.isOverdue;
        case _ClientQuickFilter.venceHoje:
          return !_isExcludedClient(client) &&
              !_isQuitadoClient(client) &&
              !client.isNegotiated &&
              !client.pagouJuros &&
              debt.isDueToday;
        case _ClientQuickFilter.renegociados:
          return !_isExcludedClient(client) &&
              !_isQuitadoClient(client) &&
              client.isNegotiated;
      }
    }).toList();

    if (_safeSearchQuery.isNotEmpty) {
      filteredClients = filteredClients.where(_matchesClientSearch).toList();
    }

    filteredClients.sort((a, b) {
      final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (nameCompare != 0) return nameCompare;
      return a.borrowedDate.compareTo(b.borrowedDate);
    });

    return filteredClients;
  }

  List<Client> _visibleClientsForSelectedSection() {
    switch (_selectedSection) {
      case _MainSection.inicio:
        return _clientsForSection('todos', includeAllActive: true);
      case _MainSection.devendo:
        return _clientsForSection('devendo');
      case _MainSection.juros:
        return const [];
      case _MainSection.parcelasPagas:
        return const [];
      case _MainSection.quitados:
        return _clientsForSection('quitado');
      case _MainSection.excluidos:
        return _clientsForSection('excluído');
      case _MainSection.emAtraso:
        return _clientsForSection(
          'devendo',
          overrideFilter: _ClientQuickFilter.atrasados,
        );
      case _MainSection.venceHoje:
        return _clientsForSection(
          'devendo',
          overrideFilter: _ClientQuickFilter.venceHoje,
        );
      case _MainSection.renegociados:
        return _clientsForSection(
          'todos',
          includeAllActive: true,
          overrideFilter: _ClientQuickFilter.renegociados,
        );
      case _MainSection.solicitacoes:
        return const [];
      case _MainSection.metricas:
      case _MainSection.configuracoes:
        return const [];
    }
  }

  void _toggleSelectAllVisibleClients() {
    final visibleIds = _visibleClientsForSelectedSection()
        .map((client) => client.id)
        .toSet();
    if (visibleIds.isEmpty) return;

    setState(() {
      final allSelected = visibleIds.every(_selectedClientIds.contains);
      if (allSelected) {
        _selectedClientIds.removeAll(visibleIds);
      } else {
        _selectedClientIds.addAll(visibleIds);
      }
    });
  }

  Future<void> _permanentlyDeleteSelectedClients() async {
    final confirmed = await _confirmDestructiveAction(
      title: 'Eliminar selecionados',
      message:
          'Essa ação remove definitivamente os registros selecionados da área de excluídos. Eles deixam de existir no sistema e não poderão ser restaurados depois. Deseja continuar?',
      confirmLabel: 'Eliminar',
    );
    if (!confirmed) return;

    final token = await _readAuthToken();
    if (token == null || token.isEmpty) return;

    for (final id in _selectedClientIds.toList()) {
      final clientId = int.tryParse(id);
      if (clientId == null) continue;
      try {
        await ApiService.permanentlyDeleteClient(token: token, clientId: clientId);
      } catch (e) {
        debugPrint('Falha ao eliminar cliente $clientId no backend: $e');
      }
    }

    _clients.removeWhere((client) => _selectedClientIds.contains(client.id));
    await _refreshClientsFromBackend();
    await fetchDashboard();
    _clearBulkSelection();
    if (!mounted) return;
    _showSnack(
      'Os registros selecionados foram eliminados definitivamente.',
      tone: _FeedbackTone.warning,
      title: 'Registros eliminados',
    );
  }

  void _showWindowsLicenseDetails() {
    final license = widget.windowsLicense;
    if (license == null) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Licença do Windows'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFDCE9FF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReceiptLine('Tipo da licença', license.typeLabel),
                    _buildReceiptLine('Cliente', license.customerName),
                    _buildReceiptLine('Licença', license.licenseId),
                    _buildReceiptLine(
                      'Emitida em',
                      DateFormat('dd/MM/yyyy HH:mm').format(license.issuedAt.toLocal()),
                    ),
                    _buildReceiptLine(
                      'Validade',
                      license.expiresAt == null
                          ? 'Sem vencimento'
                          : DateFormat('dd/MM/yyyy HH:mm')
                              .format(license.expiresAt!.toLocal()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadClients() async {
    final prefs = await SharedPreferences.getInstance();
    final remindersJson = prefs.getString('custom_reminders');
    final rawPlan = prefs.getString('app_plan');
    final profilePhotoBase64 = prefs.getString('profile_photo_base64');
    final profileDisplayName = prefs.getString('profile_display_name');
    final profilePhotoOffsetX = prefs.getDouble('profile_photo_offset_x');
    final profilePhotoOffsetY = prefs.getDouble('profile_photo_offset_y');
    final profilePhotoScale = prefs.getDouble('profile_photo_scale');

    if (remindersJson != null && remindersJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(remindersJson) as List<dynamic>;
        _customReminders = decoded
            .map((item) => CustomReminder.fromMap(item as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    if (rawPlan != null && rawPlan.isNotEmpty) {
      try {
        _selectedPlan = AppPlan.values.firstWhere(
          (item) => item.name == rawPlan,
        );
      } catch (_) {
        _selectedPlan = AppPlan.basic;
      }
    }

    if (profilePhotoBase64 != null && profilePhotoBase64.isNotEmpty) {
      try {
        _profilePhotoBytes = base64Decode(profilePhotoBase64);
        await _updateProfilePhotoMetadata(_profilePhotoBytes!);
      } catch (_) {
        _profilePhotoBytes = null;
      }
    }
    _profileDisplayName = profileDisplayName;
    _profilePhotoOffsetX = (profilePhotoOffsetX ?? 0).clamp(-1.0, 1.0);
    _profilePhotoOffsetY = (profilePhotoOffsetY ?? 0).clamp(-1.0, 1.0);
    _profilePhotoScale = (profilePhotoScale ?? 1.85).clamp(1.0, 4.0);

    await _refreshClientsFromBackend();

    _purgeExpiredExcludedClients();

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveClients() async {
    _purgeExpiredExcludedClients();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'custom_reminders',
      jsonEncode(_safeCustomReminders.map((item) => item.toMap()).toList()),
    );
    if (mounted) {
      setState(() {});
      fetchDashboard();
    }
  }

  Future<void> _savePlan(AppPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_plan', plan.name);
  }

  Future<void> _saveProfilePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (_profilePhotoBytes != null && _profilePhotoBytes!.isNotEmpty) {
      await prefs.setString(
        'profile_photo_base64',
        base64Encode(_profilePhotoBytes!),
      );
    } else {
      await prefs.remove('profile_photo_base64');
    }

    final trimmedName = _safeProfileDisplayName.trim();
    if (trimmedName.isEmpty || trimmedName == widget.account.name.trim()) {
      await prefs.remove('profile_display_name');
    } else {
      await prefs.setString('profile_display_name', trimmedName);
    }
    await prefs.setDouble('profile_photo_offset_x', _profilePhotoOffsetX);
    await prefs.setDouble('profile_photo_offset_y', _profilePhotoOffsetY);
    await prefs.setDouble('profile_photo_scale', _profilePhotoScale);
  }

  Future<void> _pickProfilePhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file =
        result != null && result.files.isNotEmpty ? result.files.first : null;
    if (file?.bytes == null || file!.bytes!.isEmpty) {
      return;
    }

    _profilePhotoBytes = file.bytes;
    await _updateProfilePhotoMetadata(_profilePhotoBytes!);
    _profilePhotoOffsetX = 0;
    _profilePhotoOffsetY = _profilePhotoAspectRatio < 0.85 ? -0.45 : 0;
    _profilePhotoScale = _profilePhotoAspectRatio < 0.85 ? 2.3 : 1.6;
    await _saveProfilePreferences();
    if (!mounted) return;
    setState(() {});
    _showSnack(
      'A foto de perfil foi atualizada no menu do sistema.',
      tone: _FeedbackTone.success,
      title: 'Perfil atualizado',
    );
  }

  Future<void> _removeProfilePhoto() async {
    _profilePhotoBytes = null;
    _profilePhotoOffsetX = 0;
    _profilePhotoOffsetY = 0;
    _profilePhotoScale = 1.85;
    _profilePhotoAspectRatio = 0.75;
    await _saveProfilePreferences();
    if (!mounted) return;
    setState(() {});
    _showSnack(
      'A foto de perfil foi removida do menu.',
      tone: _FeedbackTone.info,
      title: 'Foto removida',
    );
  }

  Future<void> _renameProfile() async {
    final controller = TextEditingController(text: _safeProfileDisplayName);
    final nextName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nome do perfil'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nome exibido no menu',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim(),
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (nextName == null || nextName.trim().isEmpty) return;
    _profileDisplayName = nextName.trim();
    await _saveProfilePreferences();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _resetPhotoFraming() async {
    _profilePhotoOffsetX = 0;
    _profilePhotoOffsetY = _profilePhotoAspectRatio < 0.85 ? -0.45 : 0;
    _profilePhotoScale = _profilePhotoAspectRatio < 0.85 ? 2.3 : 1.6;
    await _saveProfilePreferences();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _updateProfilePhotoMetadata(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (image.width > 0 && image.height > 0) {
        _profilePhotoAspectRatio = image.width / image.height;
      }
      image.dispose();
      codec.dispose();
    } catch (_) {
      _profilePhotoAspectRatio = 0.75;
    }
  }

  Future<void> _clearInterfaceCache() async {
    final confirmed = await _confirmDestructiveAction(
      title: 'Limpar cache da interface',
      message:
          'Isso remove apenas dados temporários desta instalação, como buscas, seleções e filtros atuais. Seus clientes, pagamentos e lembretes não serão apagados. Deseja continuar?',
      confirmLabel: 'Limpar cache',
    );
    if (!confirmed) return;

    _safeSearchController.clear();
    _safePaymentHistorySearchController.clear();
    if (!mounted) return;
    setState(() {
      _searchQuery = '';
      _paymentHistoryQuery = '';
      _activeQuickFilter = _ClientQuickFilter.todos;
      _paymentHistoryFilter = _PaymentHistoryQuickFilter.todos;
      _bulkSelectionMode = false;
      _selectedClientIds.clear();
      _selectedSection = _MainSection.inicio;
    });

    _showSnack(
      'Os filtros, buscas e seleções temporárias foram limpos.',
      tone: _FeedbackTone.success,
      title: 'Cache limpo',
    );
  }

  Widget _buildProfilePhotoFrame({
    required double width,
    required double height,
    double borderRadius = 18,
    EdgeInsets padding = const EdgeInsets.all(3),
  }) {
    if (_profilePhotoBytes == null) {
      return Center(
        child: Text(
          _safeProfileDisplayName.isNotEmpty
              ? _safeProfileDisplayName.characters.first.toUpperCase()
              : 'C',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF061C3D),
          ),
        ),
      );
    }
    return Padding(
      padding: padding,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius - 3),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius - 3),
          child: LayoutBuilder(builder: (context, constraints) {
            final frameWidth = constraints.maxWidth;
            final frameHeight = constraints.maxHeight;
            final imageAspect = _profilePhotoAspectRatio <= 0
                ? frameWidth / frameHeight
                : _profilePhotoAspectRatio;
            final frameAspect = frameWidth / frameHeight;
            double baseWidth;
            double baseHeight;
            if (imageAspect > frameAspect) {
              baseHeight = frameHeight;
              baseWidth = baseHeight * imageAspect;
            } else {
              baseWidth = frameWidth;
              baseHeight = baseWidth / imageAspect;
            }
            final scaledWidth = baseWidth * _profilePhotoScale;
            final scaledHeight = baseHeight * _profilePhotoScale;
            final maxHorizontalShift = math.max(0.0, (scaledWidth - frameWidth) / 2);
            final maxVerticalShift = math.max(0.0, (scaledHeight - frameHeight) / 2);
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: (frameWidth - scaledWidth) / 2 -
                      (_profilePhotoOffsetX * maxHorizontalShift),
                  top: (frameHeight - scaledHeight) / 2 -
                      (_profilePhotoOffsetY * maxVerticalShift),
                  width: scaledWidth,
                  height: scaledHeight,
                  child: Image.memory(
                    _profilePhotoBytes!,
                    fit: BoxFit.fill,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
  void _handleProfilePhotoDrag(
    DragUpdateDetails details,
    double frameWidth,
    double frameHeight,
  ) {
    if (_profilePhotoBytes == null) return;
    final scale = _profilePhotoScale.clamp(1.0, 4.0);
    final imageAspect = _profilePhotoAspectRatio <= 0
        ? frameWidth / frameHeight
        : _profilePhotoAspectRatio;
    final frameAspect = frameWidth / frameHeight;
    double baseWidth;
    double baseHeight;
    if (imageAspect > frameAspect) {
      baseHeight = frameHeight;
      baseWidth = baseHeight * imageAspect;
    } else {
      baseWidth = frameWidth;
      baseHeight = baseWidth / imageAspect;
    }
    final extraWidth = math.max(0.0, (baseWidth * scale) - frameWidth);
    final extraHeight = math.max(0.0, (baseHeight * scale) - frameHeight);
    if (extraWidth <= 0 && extraHeight <= 0) return;
    final horizontalStep = extraWidth <= 0 ? 0 : (details.delta.dx * 2) / extraWidth;
    final verticalStep = extraHeight <= 0 ? 0 : (details.delta.dy * 2) / extraHeight;
    setState(() {
      _profilePhotoOffsetX = (_profilePhotoOffsetX - horizontalStep).clamp(-1.0, 1.0);
      _profilePhotoOffsetY = (_profilePhotoOffsetY - verticalStep).clamp(-1.0, 1.0);
    });
  }
  Future<void> _clearAllBusinessData() async {
    final confirmed = await _confirmDestructiveAction(
      title: 'Apagar todos os dados da carteira',
      message:
          'Isso vai apagar clientes, pagamentos, renegociações, lembretes e registros desta instalação. Sua conta de acesso continuará existindo, mas a carteira será zerada. Deseja continuar?',
      confirmLabel: 'Apagar dados',
    );
    if (!confirmed) return;

    _clients.clear();
    _customReminders = [];
    await _saveClients();
    if (!mounted) return;
    setState(() {
      _bulkSelectionMode = false;
      _selectedClientIds.clear();
      _selectedSection = _MainSection.inicio;
    });

    _showSnack(
      'Os dados da carteira foram apagados desta instalação.',
      tone: _FeedbackTone.warning,
      title: 'Carteira zerada',
    );
  }

  bool _hasPlanAccess(AppPlan requiredPlan) {
    return true;
  }

  Future<bool> _ensurePlanAccess({
    required AppPlan requiredPlan,
    required String featureTitle,
    required String description,
  }) async {
    return true;
  }

  Future<void> _activatePlan(AppPlan plan) async {
    await _savePlan(plan);
    if (!mounted) return;
    setState(() {
      _selectedPlan = plan;
    });
    _showSnack(
      'O plano ${plan.label} foi ativado localmente para testes no app.',
      tone: _FeedbackTone.success,
      title: 'Plano atualizado',
    );
  }

  void _showPlansCenter({AppPlan? highlightPlan}) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text('Planos da COBREJÁ'),
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Essa tela já prepara a experiência comercial do app. Por enquanto, a ativação é local para testes. Depois nós conectamos isso à assinatura real da Play Store.',
                style: TextStyle(
                  color: AppColors.textBody,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 640;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: AppPlan.values.map((plan) {
                      return SizedBox(
                        width: compact ? double.infinity : 206,
                        child: _PlanCard(
                          plan: plan,
                          selected: _safeSelectedPlan == plan,
                          highlighted: highlightPlan == plan,
                          onTap: () async {
                            Navigator.pop(dialogContext);
                            await _activatePlan(plan);
                          },
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAccountDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: const Text('Excluir conta local'),
        content: Text(
          'Essa ação remove a conta ${widget.account.email} desta instalação e apaga os dados locais salvos no aparelho, incluindo clientes, pagamentos, renegociações e lembretes. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir conta'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.onDeleteAccount();
    if (!mounted) return;
    _showSnack(
      'A conta local e os dados salvos neste aparelho foram removidos.',
      tone: _FeedbackTone.success,
      title: 'Conta excluída',
    );
  }

  void _purgeExpiredExcludedClients() {
    return;
  }

  Future<bool> _syncClient(
    Client client, {
    bool syncDebt = false,
    bool showPendingFeedback = true,
  }) async {
    if (!_isExcludedClient(client)) {
      if (client.remainingPrincipal <= 0.009) {
        client.status = 'quitado';
        client.pagouJuros = false;
        client.interestPaidCurrentCycle = 0;
      } else {
        client.status = 'devendo';
      }
    }

    String? monthlyMode;
    double? monthlyValue;
    String? dailyMode;
    double? dailyValue;
    if (syncDebt) {
      if (client.monthlyInterestType == InterestValueType.fixedAmount) {
        if (client.monthlyInterestAmount > 0) {
          monthlyMode = 'FIXED';
          monthlyValue = client.monthlyInterestAmount;
        }
      } else {
        if (client.monthlyInterestRate > 0) {
          monthlyMode = 'PERCENTAGE';
          monthlyValue = client.monthlyInterestRate;
        }
      }

      if (client.dailyInterestType == InterestValueType.fixedAmount) {
        if (client.dailyInterestAmount > 0) {
          dailyMode = 'FIXED';
          dailyValue = client.dailyInterestAmount;
        }
      } else {
        if (client.dailyInterestRate > 0) {
          dailyMode = 'PERCENTAGE';
          dailyValue = client.dailyInterestRate;
        }
      }
    }

    final index = _clients.indexWhere((item) => item.id == client.id);
    final isNewClient = index == -1;
    if (index == -1) {
      _clients.add(client);
    } else {
      _clients[index] = client;
    }
    await _saveClients();

    var synced = false;
    try {
      final token = await _readAuthToken();
      if (token != null && token.isNotEmpty) {
        if (isNewClient) {
          final created = await ApiService.createClient(
            token: token,
            name: client.name,
            phone: client.phone,
            cpf: client.cpf,
            address: client.address,
            email: client.email,
            avatarUrl: client.avatarUrl,
          );
          // ApiService.createClient retorna diretamente o payload `data` do backend.
          // Por compatibilidade, aceitamos também o formato antigo { client: { id } }.
          final backendClientId = (created['id'] as num?)?.toInt() ??
              (created['client']?['id'] as num?)?.toInt();
          if (backendClientId != null) {
            client.id = backendClientId.toString();
            if (syncDebt && client.borrowedAmount > 0) {
              final createdDebt = await ApiService.createDebt(
                token: token,
                clientId: backendClientId,
                principalAmount: client.borrowedAmount,
                borrowedAt: client.borrowedDate,
                dueDate: client.dueDate,
                monthlyInterestMode: monthlyMode,
                monthlyInterestValue: monthlyValue,
                dailyInterestMode: dailyMode,
                dailyInterestValue: dailyValue,
              );

              final backendDebtId = (createdDebt['id'] as num?)?.toInt();
              if (backendDebtId != null) {
                client.backendPrimaryDebtId = backendDebtId;
              }
            }
          }
        } else {
          final clientId = int.tryParse(client.id);
          if (clientId != null) {
            await ApiService.updateClient(
              token: token,
              clientId: clientId,
              name: client.name,
              phone: client.phone,
              cpf: client.cpf,
              address: client.address,
              email: client.email,
              avatarUrl: client.avatarUrl,
            );

            if (syncDebt && client.borrowedAmount > 0) {
              final debtId = client.backendPrimaryDebtId;
              if (debtId != null) {
                await ApiService.updateDebt(
                  token: token,
                  debtId: debtId,
                  principalAmount: client.borrowedAmount,
                  borrowedAt: client.borrowedDate,
                  dueDate: client.dueDate,
                  monthlyInterestMode: monthlyMode,
                  monthlyInterestValue: monthlyValue,
                  dailyInterestMode: dailyMode,
                  dailyInterestValue: dailyValue,
                );
              } else {
                final createdDebt = await ApiService.createDebt(
                  token: token,
                  clientId: clientId,
                  principalAmount: client.borrowedAmount,
                  borrowedAt: client.borrowedDate,
                  dueDate: client.dueDate,
                  monthlyInterestMode: monthlyMode,
                  monthlyInterestValue: monthlyValue,
                  dailyInterestMode: dailyMode,
                  dailyInterestValue: dailyValue,
                );
                final backendDebtId = (createdDebt['id'] as num?)?.toInt();
                if (backendDebtId != null) {
                  client.backendPrimaryDebtId = backendDebtId;
                }
              }
            }
          }
        }
        await _refreshClientsFromBackend();
        await fetchDashboard();
        synced = true;
      }
    } catch (e) {
      debugPrint('Falha ao sincronizar cliente no backend: $e');
      if (showPendingFeedback && mounted) {
        _showSnack(
          'Não foi possível sincronizar este cliente com o backend.',
          tone: _FeedbackTone.warning,
          title: 'Sincronização pendente',
        );
      }
    }
    if (mounted) {
      setState(() {});
    }
    return synced;
  }

  void _deleteClient(String id) async {
    final index = _clients.indexWhere((item) => item.id == id);
    if (index == -1) return;
    try {
      final token = await _readAuthToken();
      final clientId = int.tryParse(id);
      if (token != null && clientId != null) {
        await ApiService.deleteClient(token: token, clientId: clientId);
      }
      //_clients.removeAt(index);
      //await _saveClients();
      await _refreshClientsFromBackend();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      debugPrint('Falha ao remover cliente no backend: $e');
      _showSnack(
        'Nao foi possível remover o cliente no backend.',
        tone: _FeedbackTone.error,
        title: 'Falha ao remover',
      );
    }
  }

  Future<void> _restoreExcludedClient(String id, {bool showFeedback = true}) async {
    final token = await _readAuthToken();
    final clientId = int.tryParse(id);
    if (token == null || token.isEmpty || clientId == null) return;

    try {
      await ApiService.restoreClient(token: token, clientId: clientId);
      await _refreshClientsFromBackend();
      await fetchDashboard();
      if (!mounted) return;
      setState(() {
        if (showFeedback && _selectedSection == _MainSection.excluidos) {
          _selectedSection = _MainSection.devendo;
        }
      });
      if (showFeedback) {
        _showSnack(
          'O registro foi removido da área de excluídos e voltou para a carteira.',
          tone: _FeedbackTone.success,
          title: 'Cliente removido dos excluídos',
        );
      }
    } catch (e) {
      debugPrint('Falha ao restaurar cliente no backend: $e');
      if (!mounted) return;
      _showSnack(
        'Não foi possível restaurar o cliente no backend.',
        tone: _FeedbackTone.error,
        title: 'Falha ao restaurar',
      );
    }
  }

  Future<void> _permanentlyDeleteClient(String id) async {
    final token = await _readAuthToken();
    final clientId = int.tryParse(id);
    if (token == null || token.isEmpty || clientId == null) return;

    try {
      await ApiService.permanentlyDeleteClient(token: token, clientId: clientId);
      _clients.removeWhere((client) => client.id == id);
      if (mounted) {
        setState(() {});
      }
      await _refreshClientsFromBackend();
      await fetchDashboard();
      if (!mounted) return;
      _showSnack(
        'O registro foi eliminado definitivamente do sistema.',
        tone: _FeedbackTone.warning,
        title: 'Cliente eliminado',
      );
    } catch (e) {
      debugPrint('Falha ao eliminar cliente no backend: $e');
      if (!mounted) return;
      _showSnack(
        'Não foi possível eliminar o cliente definitivamente no backend.',
        tone: _FeedbackTone.error,
        title: 'Falha ao eliminar',
      );
    }
  }
  Future<bool> _confirmDestructiveAction({
    required String title,
    required String message,
    String confirmLabel = 'Confirmar',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(
          message,
          style: const TextStyle(
            color: Color(0xFF5B6474),
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _rebuildClientFromPaymentHistory(
    Client client,
    List<PaymentRecord> updatedHistory,
  ) {
    final sortedHistory = [...updatedHistory]
      ..sort((a, b) => a.date.compareTo(b.date));
    final wasExcluded =
        client.status == 'excluído' || client.status == 'excluido';

    client.paymentHistory = [...sortedHistory.reversed];
    client.activePrincipalCollected = 0;
    client.totalInterestCollected = 0;
    client.totalPrincipalCollected = 0;
    client.interestPaidCurrentCycle = 0;
    client.pagouJuros = false;

    if (client.isNegotiated) {
      client.installmentsPaid = 0;
      client.dueDate =
          client.installmentStartDate ??
          client.borrowedDate.add(Duration(days: client.originalTermDays));
    } else {
      client.cycleStartDate = client.borrowedDate;
      client.dueDate = client.borrowedDate.add(
        Duration(days: client.originalTermDays),
      );
    }

    for (final payment in sortedHistory) {
      client.totalInterestCollected += payment.interestPaid;
      client.totalPrincipalCollected += payment.principalPaid;
      client.activePrincipalCollected += payment.principalPaid;

      if (client.isNegotiated) {
        if (client.installmentCount > 0 &&
            client.installmentAmount > 0 &&
            client.installmentStartDate != null) {
          final paidInstallments =
              (client.activePrincipalCollected / client.installmentAmount)
                  .floor();
          client.installmentsPaid = math.min(
            client.installmentCount,
            paidInstallments,
          );
          if (client.installmentsPaid < client.installmentCount) {
            client.dueDate = client.installmentStartDate!.add(
              Duration(days: 30 * client.installmentsPaid),
            );
          }
        }
        continue;
      }

      client.interestPaidCurrentCycle += payment.interestPaid;
      final debtAtPayment = FinanceService.calculateDebt(client, now: payment.date);
      final currentCycleTotalInterest =
          debtAtPayment.cycleInterest + debtAtPayment.lateInterest;
      final isCurrentInterestSettled =
          payment.interestPaid > 0 &&
          client.interestPaidCurrentCycle >= currentCycleTotalInterest - 0.01;

      if (isCurrentInterestSettled && client.remainingPrincipal > 0.009) {
        final previousDueDate = client.dueDate;
        client.interestPaidCurrentCycle = 0;
        client.pagouJuros = true;
        client.cycleStartDate = previousDueDate;
        client.dueDate = _nextMonthlyDueDate(
          client,
          fromDate: previousDueDate,
        );
      }

      if (payment.principalPaid > 0 && !isCurrentInterestSettled) {
        client.pagouJuros = false;
      }
    }

      if (client.remainingPrincipal <= 0.009) {
        client.status = 'quitado';
        client.pagouJuros = false;
        client.interestPaidCurrentCycle = 0;
        if (client.isNegotiated) {
        client.installmentsPaid = client.installmentCount;
      }
    } else if (wasExcluded) {
      client.status = 'excluído';
    } else {
      client.status = 'devendo';
    }

    _syncClient(client);
  }

  Future<void> _deletePaymentRecord(Client client, PaymentRecord payment) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) {
      _showSnack(
        'Sua sessão expirou. Entre novamente para continuar.',
        tone: _FeedbackTone.error,
        title: 'Sessão expirada',
      );
      return;
    }

    final paymentId = int.tryParse(payment.id);
    if (paymentId == null) {
      // Pagamento local/legado (sem id numérico do backend): remove apenas da memória.
      final updatedHistory = client.paymentHistory
          .where((item) => item.id != payment.id)
          .toList();
      _rebuildClientFromPaymentHistory(client, updatedHistory);
      _showSnack(
        'O pagamento foi removido localmente. Atualize a tela para sincronizar.',
        tone: _FeedbackTone.warning,
        title: 'Pagamento removido',
      );
      return;
    }

    try {
      await ApiService.deletePayment(token: token, paymentId: paymentId);

      // Fonte de verdade: backend. Recarrega tudo para refletir o recálculo do Prisma.
      await _refreshClientsFromBackend();
      await fetchDashboard();

      _showSnack(
        'O pagamento foi removido do histórico e o saldo do cliente foi recalculado.',
        tone: _FeedbackTone.success,
        title: 'Pagamento excluído',
      );
    } catch (e) {
      debugPrint('Falha ao excluir pagamento no backend: $e');
      _showSnack(
        'Não foi possível excluir o pagamento no servidor. Tente novamente.',
        tone: _FeedbackTone.error,
        title: 'Falha ao excluir',
      );
    }
  }

  void _showEditPaymentDialog(Client client, PaymentRecord payment) {
    final interestController = TextEditingController(
      text: payment.interestPaid.toStringAsFixed(2),
    );
    final principalController = TextEditingController(
      text: payment.principalPaid.toStringAsFixed(2),
    );
    final noteController = TextEditingController(text: payment.note);
    final typeController = TextEditingController(text: payment.type);
    DateTime selectedDate = payment.date;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Editar pagamento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialog(() {
                          selectedDate = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            selectedDate.hour,
                            selectedDate.minute,
                          );
                        });
                      }
                    },
                    icon: const Icon(Icons.event_rounded),
                    label: Text(
                      'Data: ${DateFormat('dd/MM/yyyy HH:mm').format(selectedDate)}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: typeController,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: interestController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Valor em juros'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: principalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Valor em principal',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Observação'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final interestPaid = _readDouble(interestController.text);
                final principalPaid = _readDouble(principalController.text);
                if (interestPaid < 0 || principalPaid < 0) {
                  _showSnack(
                    'Os valores do pagamento nao podem ser negativos.',
                    tone: _FeedbackTone.warning,
                    title: 'Valores inválidos',
                  );
                  return;
                }

                final nextAmount = interestPaid + principalPaid;
                final nextNote = noteController.text.trim();
                final paymentId = int.tryParse(payment.id);
                final token = await _readAuthToken();

                if (token != null && token.isNotEmpty && paymentId != null) {
                  try {
                    await ApiService.updatePayment(
                      token: token,
                      paymentId: paymentId,
                      amount: nextAmount,
                      paidAt: selectedDate,
                      note: nextNote,
                    );
                    await _refreshClientsFromBackend();
                    await fetchDashboard();
                    if (!mounted) return;
                    Navigator.pop(dialogContext);
                    _showSnack(
                      'O pagamento foi atualizado e o saldo do cliente foi recalculado.',
                      tone: _FeedbackTone.success,
                      title: 'Pagamento atualizado',
                    );
                    return;
                  } catch (e) {
                    debugPrint('Falha ao atualizar pagamento no backend: $e');
                    _showSnack(
                      'Não foi possível atualizar o pagamento no servidor. Tente novamente.',
                      tone: _FeedbackTone.error,
                      title: 'Falha ao atualizar',
                    );
                    return;
                  }
                }

                final updatedRecord = PaymentRecord(
                  id: payment.id,
                  date: selectedDate,
                  amount: nextAmount,
                  interestPaid: interestPaid,
                  principalPaid: principalPaid,
                  type: typeController.text.trim().isEmpty
                      ? payment.type
                      : typeController.text.trim(),
                  note: nextNote,
                );

                final updatedHistory = client.paymentHistory
                    .map((item) => item.id == payment.id ? updatedRecord : item)
                    .toList();
                _rebuildClientFromPaymentHistory(client, updatedHistory);
                Navigator.pop(dialogContext);
                _showSnack(
                  'O pagamento foi atualizado e o saldo do cliente foi recalculado.',
                  tone: _FeedbackTone.success,
                  title: 'Pagamento atualizado',
                );
              },
              child: const Text('Atualizar'),
            ),
          ],
        ),
      ),
    );
  }

  DashboardMetrics get _metrics => FinanceService.calculateDashboard(_clients);

  List<ReminderItem> get _reminders => FinanceService.generateReminders(_clients);

  bool get _isDarkTheme => Theme.of(context).brightness == Brightness.dark;

  List<Color> get _shellBackgroundColors => _isDarkTheme
      ? const [
          Color(0xFF06111F),
          Color(0xFF081A2E),
          Color(0xFF092D24),
        ]
      : const [
          AppColors.backgroundTop,
          AppColors.backgroundMid,
          AppColors.backgroundBottom,
        ];

  Color get _shellPanelColor =>
      _isDarkTheme ? const Color(0xFF0B1F36) : Colors.white.withOpacity(0.92);

  Color get _shellPanelSoftColor =>
      _isDarkTheme ? const Color(0xFF102A46) : const Color(0xFFF8FBFF);

  Color get _shellBorderColor =>
      _isDarkTheme ? const Color(0xFF244462) : const Color(0xFFDCE9FF);

  Color get _shellStrongTextColor =>
      _isDarkTheme ? const Color(0xFFF8FBFF) : const Color(0xFF111827);

  Color get _shellMutedTextColor =>
      _isDarkTheme ? const Color(0xFFB6C2D2) : const Color(0xFF5B6474);

  Color get _shellNavTextColor =>
      _isDarkTheme ? const Color(0xFFD7E3F4) : const Color(0xFF22324A);

  Color get _shellNavIconColor =>
      _isDarkTheme ? const Color(0xFF9FB3CC) : const Color(0xFF365071);

  Color get _shellSelectedNavColor =>
      _isDarkTheme ? AppColors.secondary : widget.accentPreset.primaryColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 980;

        return Scaffold(
          drawer: isCompact ? Drawer(child: _buildNavigationRailContent(compact: true)) : null,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _shellBackgroundColors,
              ),
            ),
            child: SafeArea(
              child: _isLoading
                  ? const _CobrejaLoading(label: 'Carregando dashboard')
                  : Row(
                      children: [
                        if (!isCompact)
                          SizedBox(
                            width: 250,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
                              child: _buildNavigationRailContent(compact: false),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            children: [
                              _buildTopBar(showMenuButton: isCompact),
                              Expanded(child: _buildSectionBody()),
                              _buildDeveloperFooter(),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _showAddClientDialog,
            backgroundColor: widget.accentPreset.primaryColor,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Novo'),
            tooltip: 'Cadastrar um novo cliente',
          ),
        );
      },
    );
  }

  Widget _buildDeveloperFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Text(
        '© COBREJÁ • Fernando Morais • 2026',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: _shellMutedTextColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildTopBar({required bool showMenuButton}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildBrandLockup(compact: compact),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (isWindowsDesktopPlatform && widget.windowsLicense != null) ...[
                    Tooltip(
                      message: 'Ver detalhes da licença do Windows',
                      child: InkWell(
                        onTap: _showWindowsLicenseDetails,
                        borderRadius: BorderRadius.circular(999),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _shellPanelSoftColor,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _shellBorderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_user_rounded,
                                color: _shellStrongTextColor,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.windowsLicense!.typeLabel,
                                style: TextStyle(
                                  color: _shellStrongTextColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  _IconBubble(
                    icon: Icons.notifications_active_rounded,
                    badge: _reminders.length,
                    onTap: _showReminderCenter,
                    tooltip: 'Abrir central de lembretes',
                  ),
                  const SizedBox(width: 10),
                  _IconBubble(
                    icon: Icons.cloud_upload_rounded,
                    onTap: _showBackupCenter,
                    tooltip: 'Backup e restauracao dos dados',
                  ),
                  const SizedBox(width: 10),
                  _IconBubble(
                    icon: Icons.logout_rounded,
                    onTap: widget.onLogout,
                    tooltip: 'Sair da conta',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Bem-vindo, ${widget.account.name}',
                style: TextStyle(
                  color: _shellMutedTextColor,
                  fontSize: compact ? 15 : 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (showMenuButton) ...[
                const SizedBox(height: 10),
                Builder(
                  builder: (buttonContext) => Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => Scaffold.of(buttonContext).openDrawer(),
                      icon: const Icon(Icons.menu_rounded),
                      label: const Text('Menu'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavigationRailContent({required bool compact}) {
    final items = [
      (_MainSection.inicio, 'Início', Icons.home_rounded),
      (_MainSection.devendo, 'Devendo', Icons.account_balance_wallet_rounded),
      (_MainSection.juros, 'Juros', Icons.percent_rounded),
      (_MainSection.parcelasPagas, 'Parcelas pagas', Icons.receipt_long_rounded),
      (_MainSection.quitados, 'Quitados', Icons.check_circle_rounded),
      (_MainSection.excluidos, 'Excluídos', Icons.delete_outline_rounded),
      (_MainSection.emAtraso, 'Em atraso', Icons.warning_amber_rounded),
      (_MainSection.venceHoje, 'Vence hoje', Icons.today_rounded),
      (_MainSection.renegociados, 'Renegociados', Icons.currency_exchange_rounded),
      (_MainSection.solicitacoes, 'Solicitações', Icons.inbox_rounded),
      (_MainSection.metricas, 'Métricas', Icons.bar_chart_rounded),
      (_MainSection.configuracoes, 'Configurações', Icons.settings_rounded),
    ];
    final accentPrimary = _shellSelectedNavColor;

    return Container(
      decoration: BoxDecoration(
        color: _shellPanelColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _shellBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Navegação',
                  style: TextStyle(
                    fontSize: compact ? 15 : 16,
                    fontWeight: FontWeight.w800,
                    color: _shellStrongTextColor,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: compact ? 48 : 54,
                  child: SvgPicture.asset(
                    _isDarkTheme
                        ? 'assets/branding/cobreja_logo_white.svg'
                        : 'assets/branding/cobreja_logo.svg',
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cobrança inteligente, recebimento garantido.',
                  style: TextStyle(
                    color: _shellMutedTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _shellPanelSoftColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _shellBorderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 76,
                        decoration: BoxDecoration(
                          color: _isDarkTheme
                              ? const Color(0xFF173452)
                              : const Color(0xFFE8F1FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isDarkTheme
                                ? const Color(0xFF315577)
                                : const Color(0xFFD6E7FF),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildProfilePhotoFrame(
                          width: 56,
                        height: 76,
                          borderRadius: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _safeProfileDisplayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _shellStrongTextColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.account.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _shellMutedTextColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _shellBorderColor),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: items.map((item) {
                final section = item.$1;
                final selected = _selectedSection == section;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      setState(() {
                        _selectedSection = section;
                      });
                      if (section == _MainSection.solicitacoes) {
                        _ensureCreditRequestsLoaded();
                      }
                      if (compact) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Ink(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: selected
                            ? accentPrimary.withOpacity(0.12)
                            : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? accentPrimary.withOpacity(0.34)
                              : _shellBorderColor,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: accentPrimary.withOpacity(0.14),
                                  blurRadius: 12,
                                  offset: Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.$3 as IconData,
                            color: selected ? accentPrimary : _shellNavIconColor,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.$2 as String,
                              style: TextStyle(
                                color: selected ? accentPrimary : _shellNavTextColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBody() {
    final title = _sectionTitle(_selectedSection);
    final subtitle = _sectionSubtitle(_selectedSection);
    final showSearch = _sectionUsesSearch(_selectedSection);
    final canBulkSelect = !{
      _MainSection.inicio,
      _MainSection.juros,
      _MainSection.parcelasPagas,
      _MainSection.solicitacoes,
      _MainSection.metricas,
      _MainSection.configuracoes,
    }.contains(_selectedSection);
    final visibleSelectionCount = _visibleClientsForSelectedSection().length;
    final allVisibleSelected = visibleSelectionCount > 0 &&
        _visibleClientsForSelectedSection()
            .every((client) => _selectedClientIds.contains(client.id));

    return Column(
      children: [
        if (title != null || subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: _shellStrongTextColor,
                      ),
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _shellMutedTextColor,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (canBulkSelect) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _bulkSelectionMode = !_bulkSelectionMode;
                              if (!_bulkSelectionMode) {
                                _selectedClientIds.clear();
                              }
                            });
                          },
                          icon: Icon(
                            _bulkSelectionMode
                                ? Icons.close_rounded
                                : Icons.checklist_rounded,
                          ),
                          label: Text(
                            _bulkSelectionMode
                                ? 'Cancelar seleção'
                                : 'Selecionar vários',
                          ),
                        ),
                        if (_bulkSelectionMode && visibleSelectionCount > 0)
                          OutlinedButton.icon(
                            onPressed: _toggleSelectAllVisibleClients,
                            icon: Icon(
                              allVisibleSelected
                                  ? Icons.deselect_rounded
                                  : Icons.select_all_rounded,
                            ),
                            label: Text(
                              allVisibleSelected
                                  ? 'Desmarcar todos'
                                  : 'Marcar todos',
                            ),
                          ),
                        if (_bulkSelectionMode && _selectedClientIds.isNotEmpty)
                          ..._buildBulkActionButtons(),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (showSearch) _buildSearchBar(),
        Expanded(child: _buildSectionContent()),
      ],
    );
  }

  List<Widget> _buildBulkActionButtons() {
    final isExcludedSection = _selectedSection == _MainSection.excluidos;
    if (isExcludedSection) {
      return [
        OutlinedButton.icon(
          onPressed: _restoreSelectedClients,
          icon: const Icon(Icons.restore_from_trash_rounded),
          label: Text('Restaurar (${_selectedClientIds.length})'),
        ),
        FilledButton.icon(
          onPressed: _permanentlyDeleteSelectedClients,
          icon: const Icon(Icons.delete_forever_rounded),
          label: Text('Eliminar (${_selectedClientIds.length})'),
        ),
      ];
    }
    return [
      FilledButton.icon(
        onPressed: _excludeSelectedClients,
        icon: const Icon(Icons.delete_outline_rounded),
        label: Text('Excluir (${_selectedClientIds.length})'),
      ),
    ];
  }
  Future<void> _excludeSelectedClients() async {
    final confirmed = await _confirmDestructiveAction(
      title: 'Excluir selecionados',
      message:
          'Os registros selecionados serão movidos para a área de excluídos.',
      confirmLabel: 'Excluir',
    );
    if (!confirmed) return;

    for (final id in _selectedClientIds.toList()) {
      _deleteClient(id);
    }
    _clearBulkSelection();
  }

  Future<void> _restoreSelectedClients() async {
    final confirmed = await _confirmDestructiveAction(
      title: 'Remover selecionados dos excluídos',
      message:
          'Os registros selecionados sairão da área de excluídos e voltarão para a carteira.',
      confirmLabel: 'Remover',
    );
    if (!confirmed) return;

    for (final id in _selectedClientIds.toList()) {
      await _restoreExcludedClient(id, showFeedback: false);
    }
    _clearBulkSelection();
    _showSnack(
      'Os registros selecionados foram removidos da área de excluídos e voltaram para a carteira.',
      tone: _FeedbackTone.success,
      title: 'Clientes removidos dos excluídos',
    );
  }

  Widget _buildSectionContent() {
    switch (_selectedSection) {
      case _MainSection.inicio:
        return _buildHomeOverviewPage();
      case _MainSection.devendo:
        return _buildClientList('devendo');
      case _MainSection.juros:
        return _buildInterestPaymentsPage();
      case _MainSection.parcelasPagas:
        return _buildInstallmentPaymentsPage();
      case _MainSection.quitados:
        return _buildClientList('quitado');
      case _MainSection.excluidos:
        return _buildClientList('excluído');
      case _MainSection.emAtraso:
        return _buildClientList(
          'devendo',
          overrideFilter: _ClientQuickFilter.atrasados,
          emptyKey: 'atrasados',
        );
      case _MainSection.venceHoje:
        return _buildClientList(
          'devendo',
          overrideFilter: _ClientQuickFilter.venceHoje,
          emptyKey: 'venceHoje',
        );
      case _MainSection.renegociados:
        return _buildClientList(
          'todos',
          includeAllActive: true,
          overrideFilter: _ClientQuickFilter.renegociados,
          emptyKey: 'renegociados',
        );
      case _MainSection.solicitacoes:
        return _buildCreditRequestsPage();
      case _MainSection.metricas:
        return _buildMetricsPage();
      case _MainSection.configuracoes:
        return _buildSettingsPage();
    }
  }

  Widget _buildMetricsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 110),
      children: [
        _buildDashboard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              if (compact) {
                return Column(
                  children: [
                    _MetricsActionCard(
                      icon: Icons.show_chart_rounded,
                      title: 'Recebimentos mensais',
                      subtitle: 'Abrir visão dos últimos 6 meses em uma tela própria.',
                      onTap: _showMonthlyReceiptsOverviewDialog,
                    ),
                    const SizedBox(height: 12),
                    _MetricsActionCard(
                      icon: Icons.description_rounded,
                      title: 'Relatórios completos',
                      subtitle: 'Exportar CSV e PDF detalhados por cliente e período.',
                      onTap: _showDetailedReportsDialog,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: _MetricsActionCard(
                      icon: Icons.show_chart_rounded,
                      title: 'Recebimentos mensais',
                      subtitle: 'Abrir visão dos últimos 6 meses em uma tela própria.',
                      onTap: _showMonthlyReceiptsOverviewDialog,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricsActionCard(
                      icon: Icons.description_rounded,
                      title: 'Relatórios completos',
                      subtitle: 'Exportar CSV e PDF detalhados por cliente e período.',
                      onTap: _showDetailedReportsDialog,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHomeOverviewPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 110),
      children: [
        _buildReminderStrip(),
        _buildDashboard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: _SettingsCard(
            icon: Icons.space_dashboard_rounded,
            title: 'Resumo da operação',
            subtitle:
                'A tela inicial agora mostra só o panorama da carteira. As listas completas ficam organizadas nas abas Devendo, Em atraso, Juros, Renegociados e Quitados.',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedSection = _MainSection.devendo;
                    });
                  },
                  icon: const Icon(Icons.account_balance_wallet_rounded),
                  label: const Text('Abrir Devendo'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedSection = _MainSection.emAtraso;
                    });
                  },
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Abrir Em atraso'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedSection = _MainSection.juros;
                    });
                  },
                  icon: const Icon(Icons.percent_rounded),
                  label: const Text('Abrir Juros'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<({Client client, PaymentRecord payment})> _buildGlobalPaymentEntries({
    required bool Function(Client client, PaymentRecord payment) matches,
  }) {
    final entries = <({Client client, PaymentRecord payment})>[];
    for (final client in _clients) {
      for (final payment in client.paymentHistory) {
        if (matches(client, payment)) {
          entries.add((client: client, payment: payment));
        }
      }
    }
    entries.sort((a, b) => b.payment.date.compareTo(a.payment.date));
    return entries;
  }

  Widget _buildInterestPaymentsPage() {
    final entries = _buildGlobalPaymentEntries(
      matches: (client, payment) => payment.interestPaid > 0.009,
    );
    return _buildGlobalPaymentHistoryPage(
      entries: entries,
      accentColor: const Color(0xFFF59E0B),
      heroTitle: 'Renovações com juros pagos',
      heroSubtitle:
          'Cada vez que um cliente paga só os juros, o lançamento fica salvo aqui para consulta futura.',
      emptyIcon: Icons.percent_rounded,
      emptyTitle: 'Nenhum juros pago ainda.',
      emptySubtitle:
          'Cada renovação paga entra aqui como histórico, mesmo que o cliente depois quite a dívida.',
      lineBuilder: (entry) {
        final payment = entry.payment;
        final dailyPaid = payment.dailyPaid;
        final monthlyPaid = math.max(0, payment.interestPaid - dailyPaid).toDouble();

        if (dailyPaid > 0.009) {
          return 'Juros ${_currency(monthlyPaid)} • Diária ${_currency(dailyPaid)} • Principal ${_currency(payment.principalPaid)}';
        }

        return 'Juros ${_currency(payment.interestPaid)} • Principal ${_currency(payment.principalPaid)}';
      },
      badgeBuilder: (entry) => _StatusPill(
        text: 'Juros pago',
        color: const Color(0xFFF59E0B),
      ),
    );
  }

  Widget _buildInstallmentPaymentsPage() {
    final entries = _buildGlobalPaymentEntries(
      matches: (client, payment) =>
          client.isNegotiated && payment.principalPaid > 0.009,
    );
    return _buildGlobalPaymentHistoryPage(
      entries: entries,
      accentColor: const Color(0xFF16A34A),
      heroTitle: 'Parcelas recebidas dos acordos',
      heroSubtitle:
          'Aqui você acompanha a sequência das parcelas pagas nos clientes renegociados, com histórico de cada recebimento.',
      emptyIcon: Icons.receipt_long_rounded,
      emptyTitle: 'Nenhuma parcela paga ainda.',
      emptySubtitle:
          'Quando clientes renegociados pagarem parcelas em dia, cada parcela ficará registrada aqui para consulta.',
      lineBuilder: (entry) {
        final installmentNumber = entry.client.installmentAmount > 0
            ? math.max(
                1,
                (entry.payment.principalPaid / entry.client.installmentAmount)
                    .round(),
              )
            : 1;
        return 'Parcela registrada • ${_currency(entry.payment.principalPaid)} • referência ${installmentNumber}/${entry.client.installmentCount}';
      },
      badgeBuilder: (entry) => _StatusPill(
        text: 'Parcela paga',
        color: const Color(0xFF16A34A),
      ),
    );
  }

  Widget _buildCreditRequestsPage() {
    final requests = List<Map<String, dynamic>>.from(_creditRequests);
    final pending = requests
        .where(
          (item) => (item['status']?.toString() ?? 'PENDING')
              .toUpperCase()
              .contains('PENDING'),
        )
        .toList();
    final approved = requests
        .where(
          (item) => (item['status']?.toString() ?? '')
              .toUpperCase()
              .contains('APPROVED'),
        )
        .toList();
    final rejected = requests
        .where(
          (item) => (item['status']?.toString() ?? '')
              .toUpperCase()
              .contains('REJECTED'),
        )
        .toList();

    Color statusColor(String status) {
      switch (status.toUpperCase()) {
        case 'APPROVED':
          return const Color(0xFF16A34A);
        case 'REJECTED':
          return const Color(0xFFDC2626);
        default:
          return const Color(0xFFF59E0B);
      }
    }

    String statusLabel(String status) {
      switch (status.toUpperCase()) {
        case 'APPROVED':
          return 'Aprovado';
        case 'REJECTED':
          return 'Recusado';
        default:
          return 'Pendente';
      }
    }

    Future<void> refreshAll() async {
      await _refreshCreditRequests(updateLoading: true);
      await _refreshClientsFromBackend(updateLoading: true);
      await fetchDashboard();
    }

    Future<void> rejectRequest(Map<String, dynamic> request) async {
      final confirmed = await _confirmDestructiveAction(
        title: 'Recusar solicitação',
        message:
            'Esse pedido será marcado como recusado. O cliente continuará com o histórico de solicitações.',
        confirmLabel: 'Recusar',
      );
      if (!confirmed) return;

      final token = await _readAuthToken();
      if (token == null || token.isEmpty) return;

      try {
        final requestId = (request['id'] as num?)?.toInt();
        if (requestId == null) {
          _showSnack(
            'Não foi possível identificar a solicitação.',
            tone: _FeedbackTone.error,
            title: 'ID inválido',
          );
          return;
        }
        await ApiService.rejectCreditRequest(token: token, requestId: requestId);
        if (!mounted) return;
        _showSnack(
          'Solicitação recusada.',
          tone: _FeedbackTone.success,
          title: 'Atualizado',
        );
        await refreshAll();
      } catch (e) {
        if (!mounted) return;
        _showSnack(
          e is ApiException ? e.message : 'Não foi possível recusar agora.',
          tone: _FeedbackTone.error,
          title: 'Falha',
        );
      }
    }

    Future<void> approveRequest(Map<String, dynamic> request) async {
      final token = await _readAuthToken();
      if (token == null || token.isEmpty) return;

      final requestId = (request['id'] as num?)?.toInt();
      if (requestId == null) {
        _showSnack(
          'Não foi possível identificar a solicitação.',
          tone: _FeedbackTone.error,
          title: 'ID inválido',
        );
        return;
      }

      final dueDateController = TextEditingController();
      final monthlyInterestController = TextEditingController();
      final dailyFeeController = TextEditingController();
      final installmentCountController = TextEditingController(
        text: (request['requestedInstallments']?.toString() ?? '1'),
      );
      final decisionNoteController = TextEditingController();
      DateTime selectedDueDate = DateTime.now().add(const Duration(days: 30));

      double? parseMoney(String raw) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) return null;
        // Aceita "10,50", "10.50", "1.000,00", "1000"
        final normalized = trimmed
            .replaceAll('R\$', '')
            .replaceAll(' ', '')
            .replaceAll('.', '')
            .replaceAll(',', '.');
        final value = double.tryParse(normalized);
        if (value == null || value.isNaN || !value.isFinite) return null;
        return value;
      }

      String formatDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

      dueDateController.text = formatDate(selectedDueDate);

      try {
        final approved = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            String? error;
            bool submitting = false;

            Future<void> pickDueDate(StateSetter setDialog) async {
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: selectedDueDate,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                helpText: 'Escolha o vencimento',
                cancelText: 'Cancelar',
                confirmText: 'Confirmar',
              );
              if (picked == null) return;
              setDialog(() {
                selectedDueDate = picked;
                dueDateController.text = formatDate(picked);
              });
            }

            Future<void> submit(StateSetter setDialog) async {
              final interestValue = parseMoney(monthlyInterestController.text);
              final dailyFee = parseMoney(dailyFeeController.text);
              final installmentCount =
                  int.tryParse(installmentCountController.text.trim()) ?? 1;
              if (installmentCount <= 0) {
                setDialog(() {
                  error = 'Informe uma quantidade de parcelas valida.';
                });
                return;
              }

              setDialog(() {
                submitting = true;
                error = null;
              });

              try {
                await ApiService.approveCreditRequest(
                  token: token,
                  requestId: requestId,
                  dueDate: selectedDueDate,
                  interestValue: interestValue,
                  dailyFee: dailyFee,
                  installmentCount: installmentCount,
                  decisionNote: decisionNoteController.text,
                );
                if (!mounted) return;
                Navigator.of(dialogContext).pop(true);
              } catch (e) {
                setDialog(() {
                  submitting = false;
                  error = e is ApiException
                      ? e.message
                      : 'Não foi possível aprovar agora.';
                });
              }
            }

            return StatefulBuilder(
              builder: (context, setDialog) => AlertDialog(
                title: const Text('Aprovar solicitação'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Você vai criar uma nova dívida para o cliente com o valor solicitado.',
                        style: const TextStyle(
                          color: Color(0xFF5B6474),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: dueDateController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Vencimento',
                          prefixIcon: const Icon(Icons.calendar_today_rounded),
                          suffixIcon: IconButton(
                            tooltip: 'Selecionar data',
                            onPressed: submitting ? null : () => pickDueDate(setDialog),
                            icon: const Icon(Icons.edit_calendar_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: monthlyInterestController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Juros mensal (R\$) (opcional)',
                          prefixIcon: Icon(Icons.percent_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: dailyFeeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Juros diário por atraso (R\$) (opcional)',
                          prefixIcon: Icon(Icons.warning_amber_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: installmentCountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Numero de parcelas',
                          prefixIcon: Icon(Icons.view_week_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: decisionNoteController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Observacao da aprovacao (opcional)',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton.icon(
                    onPressed: submitting ? null : () => submit(setDialog),
                    icon: submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(submitting ? 'Aprovando...' : 'Aprovar'),
                  ),
                ],
              ),
            );
          },
        );

        if (approved != true) return;
        if (!mounted) return;
        _showSnack(
          'Solicitação aprovada e dívida criada.',
          tone: _FeedbackTone.success,
          title: 'Concluído',
        );
        await refreshAll();
      } finally {
        dueDateController.dispose();
        monthlyInterestController.dispose();
        dailyFeeController.dispose();
        installmentCountController.dispose();
        decisionNoteController.dispose();
      }
    }

    Widget buildRequestTile(Map<String, dynamic> request) {
      final status = request['status']?.toString() ?? 'PENDING';
      final createdAt = DateTime.tryParse(request['createdAt']?.toString() ?? '');
      final amount = _readDouble(request['amount']);
      final description = request['description']?.toString().trim() ?? '';
      final desiredTermDays = (request['desiredTermDays'] as num?)?.toInt();
      final requestedInstallments =
          (request['requestedInstallments'] as num?)?.toInt();
      final decisionNote = request['decisionNote']?.toString().trim() ?? '';
      final client = (request['client'] as Map?)?.cast<String, dynamic>();
      final clientName = (client?['name']?.toString() ?? 'Cliente').trim();
      final clientEmail = (client?['email']?.toString() ?? '').trim();
      final clientPhone = (client?['phone']?.toString() ?? '').trim();

      final pill = _StatusPill(
        text: statusLabel(status),
        color: statusColor(status),
      );

      final subtitleLines = <String>[
        if (clientPhone.isNotEmpty) clientPhone,
        if (clientEmail.isNotEmpty) clientEmail,
        if (createdAt != null) 'Enviado em ${DateFormat('dd/MM/yyyy HH:mm').format(createdAt)}',
      ];

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      clientName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  pill,
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Valor solicitado: ${_currency(amount)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (subtitleLines.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final line in subtitleLines)
                  Text(
                    line,
                    style: const TextStyle(
                      color: Color(0xFF5B6474),
                      height: 1.35,
                    ),
                  ),
              ],
              if (desiredTermDays != null || requestedInstallments != null) ...[
                const SizedBox(height: 8),
                Text(
                  [
                    if (desiredTermDays != null) 'Prazo: $desiredTermDays dias',
                    if (requestedInstallments != null)
                      'Parcelas solicitadas: $requestedInstallments',
                  ].join(' • '),
                  style: const TextStyle(
                    color: Color(0xFF374151),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFDCE9FF)),
                  ),
                  child: Text(
                    description,
                    style: const TextStyle(color: Color(0xFF374151), height: 1.35),
                  ),
                ),
              ],
              if (decisionNote.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Resposta: $decisionNote',
                  style: const TextStyle(color: Color(0xFF5B6474)),
                ),
              ],
              if (status.toUpperCase() == 'PENDING') ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () => approveRequest(request),
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text('Aprovar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => rejectRequest(request),
                      icon: const Icon(Icons.cancel_rounded, size: 18),
                      label: const Text('Recusar'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }

    Widget buildSection(String title, List<Map<String, dynamic>> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 10),
            for (final item in items) ...[
              buildRequestTile(item),
              const SizedBox(height: 12),
            ],
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 110),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Painel de solicitações',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pendentes: ${pending.length} • Aprovadas: ${approved.length} • Recusadas: ${rejected.length}',
                        style: const TextStyle(color: Color(0xFF5B6474), height: 1.35),
                      ),
                      if (_creditRequestsError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _creditRequestsError!,
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isLoadingCreditRequests ? null : refreshAll,
                  icon: _isLoadingCreditRequests
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Atualizar'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_isLoadingCreditRequests && requests.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 30),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (requests.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Nenhuma solicitação enviada pelos clientes ainda.',
                style: TextStyle(color: Color(0xFF5B6474), height: 1.35),
              ),
            ),
          )
        else ...[
          buildSection('Pendentes', pending),
          buildSection('Aprovadas', approved),
          buildSection('Recusadas', rejected),
        ],
      ],
    );
  }

  Widget _buildGlobalPaymentHistoryPage({
    required List<({Client client, PaymentRecord payment})> entries,
    required Color accentColor,
    required String heroTitle,
    required String heroSubtitle,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptySubtitle,
    required String Function(({Client client, PaymentRecord payment}) entry)
        lineBuilder,
    required Widget Function(({Client client, PaymentRecord payment}) entry)
        badgeBuilder,
  }) {
    final query = _safePaymentHistoryQuery.toLowerCase();
    final filteredEntries = entries.where((entry) {
      final payment = entry.payment;
      final client = entry.client;
      final matchesQuery =
          query.isEmpty ||
          client.name.toLowerCase().contains(query) ||
          payment.type.toLowerCase().contains(query) ||
          payment.note.toLowerCase().contains(query) ||
          _currency(payment.amount).toLowerCase().contains(query) ||
          DateFormat('dd/MM/yyyy').format(payment.date).contains(query);

      final matchesFilter = switch (_safePaymentHistoryFilter) {
        _PaymentHistoryQuickFilter.todos => true,
        _PaymentHistoryQuickFilter.hoje =>
          _dateOnly(payment.date) == _dateOnly(DateTime.now()),
        _PaymentHistoryQuickFilter.ultimos7Dias =>
          !_dateOnly(payment.date).isBefore(
            _dateOnly(DateTime.now().subtract(const Duration(days: 6))),
          ),
        _PaymentHistoryQuickFilter.ultimos30Dias =>
          !_dateOnly(payment.date).isBefore(
            _dateOnly(DateTime.now().subtract(const Duration(days: 29))),
          ),
        _PaymentHistoryQuickFilter.juros =>
          payment.interestPaid > 0.009 && payment.principalPaid <= 0.009,
        _PaymentHistoryQuickFilter.principal =>
          payment.principalPaid > 0.009 && payment.interestPaid <= 0.009,
        _PaymentHistoryQuickFilter.quitacao =>
          payment.type.toLowerCase().contains('quit'),
      };

      return matchesQuery && matchesFilter;
    }).toList();

    final totalAmount = filteredEntries.fold<double>(
      0,
      (sum, entry) => sum + entry.payment.amount,
    );
    final uniqueClients = filteredEntries
        .map((entry) => _normalizeClientName(entry.client.name))
        .toSet()
        .length;
    final latestPayment = filteredEntries.isEmpty ? null : filteredEntries.first.payment;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDCE9FF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 54,
                    width: 54,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      emptyIcon,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          heroTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          heroSubtitle,
                          style: const TextStyle(
                            color: Color(0xFF5B6474),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 720;
                  final cards = [
                    _HistorySummaryCardData(
                      label: 'Lançamentos',
                      value: '${filteredEntries.length}',
                      accentColor: accentColor,
                    ),
                    _HistorySummaryCardData(
                      label: 'Clientes',
                      value: '$uniqueClients',
                      accentColor: accentColor,
                    ),
                    _HistorySummaryCardData(
                      label: 'Total no filtro',
                      value: _currency(totalAmount),
                      accentColor: accentColor,
                    ),
                    _HistorySummaryCardData(
                      label: 'Último registro',
                      value: latestPayment == null
                          ? 'Nenhum'
                          : DateFormat('dd/MM/yyyy').format(latestPayment.date),
                      accentColor: accentColor,
                    ),
                  ];

                  if (compact) {
                    return Column(
                      children: cards
                          .map(
                            (card) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _HistorySummaryCard(data: card),
                            ),
                          )
                          .toList(),
                    );
                  }

                  return Row(
                    children: cards
                        .map(
                          (card) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: card == cards.last ? 0 : 10,
                              ),
                              child: _HistorySummaryCard(data: card),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _safePaymentHistorySearchController,
          decoration: InputDecoration(
            hintText: 'Buscar no histórico',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _safePaymentHistoryQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca do histórico',
                    onPressed: () {
                      _safePaymentHistorySearchController.clear();
                      setState(() {
                        _paymentHistoryQuery = '';
                        _paymentHistoryFilter = _PaymentHistoryQuickFilter.todos;
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildPaymentHistoryChip(
                label: 'Todos',
                filter: _PaymentHistoryQuickFilter.todos,
              ),
              _buildPaymentHistoryChip(
                label: 'Hoje',
                filter: _PaymentHistoryQuickFilter.hoje,
              ),
              _buildPaymentHistoryChip(
                label: '7 dias',
                filter: _PaymentHistoryQuickFilter.ultimos7Dias,
              ),
              _buildPaymentHistoryChip(
                label: '30 dias',
                filter: _PaymentHistoryQuickFilter.ultimos30Dias,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (filteredEntries.isEmpty)
          _buildSimpleHistoryEmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            subtitle: emptySubtitle,
          )
        else
          ...filteredEntries.map(
            (entry) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFDCE9FF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A0F172A),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 54,
                    width: 54,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F1FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Color(0xFF061C3D),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.client.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ),
                            badgeBuilder(entry),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(
                            entry.payment.date,
                          ),
                          style: const TextStyle(
                            color: Color(0xFF5B6474),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lineBuilder(entry),
                          style: const TextStyle(
                            color: Color(0xFF374151),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FAFF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFDCE9FF)),
                          ),
                          child: Text(
                            'Tipo: ${entry.payment.type}',
                            style: const TextStyle(
                              color: Color(0xFF365071),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (entry.payment.note.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            entry.payment.note.trim(),
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _currency(entry.payment.amount),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 6),
                      IconButton(
                        tooltip: 'Abrir comprovante',
                        onPressed: () => _showPaymentReceiptDialog(
                          entry.client,
                          entry.payment,
                        ),
                        icon: const Icon(
                          Icons.receipt_long_rounded,
                          color: Color(0xFF061C3D),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Ações do pagamento',
                        onSelected: (value) {
                          if (value == 'edit') {
                            _showEditPaymentDialog(entry.client, entry.payment);
                          } else if (value == 'delete') {
                            _confirmDestructiveAction(
                              title: 'Excluir pagamento',
                              message:
                                  'Esse registro será removido do histórico e o saldo do cliente será recalculado.',
                              confirmLabel: 'Excluir',
                            ).then((confirmed) {
                              if (!confirmed) return;
                              _deletePaymentRecord(entry.client, entry.payment);
                            });
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Editar pagamento'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Excluir pagamento'),
                          ),
                        ],
                        icon: const Icon(Icons.more_vert_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSimpleHistoryEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFDCE9FF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 28,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 84,
              width: 84,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF061C3D), Color(0xFF22C55E)],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(icon, color: Colors.white, size: 38),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF5B6474),
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPage() {
    final mercadoPagoIntegration =
        (_mercadoPagoSummary?['integration'] as Map<String, dynamic>?) ?? const {};
    final mercadoPagoApi =
        (_mercadoPagoSummary?['mercadoPagoApi'] as Map<String, dynamic>?) ?? const {};
    final mercadoPagoReady = mercadoPagoIntegration['accessTokenConfigured'] == true &&
        mercadoPagoIntegration['webhookSecretConfigured'] == true &&
        mercadoPagoIntegration['backendPublicUrlConfigured'] == true;
    final mercadoPagoApiStatus = mercadoPagoApi['status']?.toString() ?? 'PENDENTE';
    final collectionTotals =
        (_collectionAutomation?['totals'] as Map<String, dynamic>?) ?? const {};
    final saasSubscription =
        (_saasStatus?['subscription'] as Map<String, dynamic>?) ?? const {};
    final saasPlan = (saasSubscription['plan'] as Map<String, dynamic>?) ?? const {};
    final saasUsage = (_saasStatus?['usage'] as Map<String, dynamic>?) ?? const {};

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 110),
      children: [
        _PremiumFoundationCard(
          onEditSettings: _openPremiumSettingsDialog,
          sections: const [
            _PremiumFoundationSection(
              title: 'Empresa',
              subtitle: 'Logo, favicon, CNPJ, contato, endereco e dominio.',
              icon: Icons.apartment_rounded,
              status: 'Base criada',
              color: AppColors.success,
            ),
            _PremiumFoundationSection(
              title: 'Conta/Admin',
              subtitle: 'Perfil, seguranca, sessoes ativas e foto.',
              icon: Icons.admin_panel_settings_rounded,
              status: 'Em estrutura',
              color: AppColors.primary,
            ),
            _PremiumFoundationSection(
              title: 'Financeiro',
              subtitle: 'Juros, multa, carencia, parcelas e renegociacao.',
              icon: Icons.calculate_rounded,
              status: 'Base criada',
              color: AppColors.success,
            ),
            _PremiumFoundationSection(
              title: 'Mercado Pago',
              subtitle: 'Status, webhook, Pix, taxas e recebimentos.',
              icon: Icons.pix_rounded,
              status: 'Pix em deploy',
              color: AppColors.warning,
            ),
            _PremiumFoundationSection(
              title: 'WhatsApp',
              subtitle: 'Conexao, templates e automacoes de cobranca.',
              icon: Icons.chat_rounded,
              status: 'Preparado',
              color: AppColors.warning,
            ),
            _PremiumFoundationSection(
              title: 'SaaS',
              subtitle: 'Plano, trial, limites, assinatura e upgrade.',
              icon: Icons.workspace_premium_rounded,
              status: 'Base criada',
              color: AppColors.success,
            ),
            _PremiumFoundationSection(
              title: 'Aparencia',
              subtitle: 'Dark, light, cores e layout compacto.',
              icon: Icons.palette_rounded,
              status: 'Ativo',
              color: AppColors.success,
            ),
            _PremiumFoundationSection(
              title: 'Notificacoes',
              subtitle: 'Email, WhatsApp, push e alertas de cobranca.',
              icon: Icons.notifications_active_rounded,
              status: 'Preparado',
              color: AppColors.warning,
            ),
            _PremiumFoundationSection(
              title: 'Auditoria',
              subtitle: 'Logs de acessos, alteracoes e acoes criticas.',
              icon: Icons.fact_check_rounded,
              status: 'Base criada',
              color: AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          icon: Icons.workspace_premium_rounded,
          title: 'Planos e limites SaaS',
          subtitle:
              'Controle o plano atual, trial, limite de clientes e estrutura de upgrade.',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _openSaasPlanPanel,
                icon: const Icon(Icons.workspace_premium_rounded),
                label: Text(_isLoadingSaas ? 'Carregando...' : 'Abrir planos'),
              ),
              _StatusPill(
                text: 'Plano ${saasPlan['name']?.toString() ?? 'Gratis'}',
                color: AppColors.primary,
              ),
              _StatusPill(
                text: saasUsage['unlimitedClients'] == true
                    ? '${saasUsage['activeClients'] ?? 0} clientes'
                    : '${saasUsage['activeClients'] ?? 0}/${saasUsage['clientLimit'] ?? '-'} clientes',
                color: saasUsage['limitReached'] == true ? AppColors.danger : AppColors.success,
              ),
              _StatusPill(
                text: saasSubscription['status']?.toString() ?? 'TRIAL',
                color: AppColors.warning,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          icon: Icons.campaign_rounded,
          title: 'Automacoes de cobranca',
          subtitle:
              'Veja vencimentos, atrasos e mensagens prontas para cobrar por WhatsApp.',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _openCollectionAutomationPanel,
                icon: const Icon(Icons.send_rounded),
                label: Text(_isLoadingCollections ? 'Carregando...' : 'Abrir central'),
              ),
              _StatusPill(
                text: '${collectionTotals['dueToday'] ?? 0} vencem hoje',
                color: AppColors.primary,
              ),
              _StatusPill(
                text: '${collectionTotals['overdue'] ?? 0} atrasadas',
                color: AppColors.danger,
              ),
              const _StatusPill(text: 'Historico em auditoria', color: AppColors.success),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          icon: Icons.pix_rounded,
          title: 'Mercado Pago',
          subtitle:
              'Acompanhe Pix por parcela, webhook, recebimentos confirmados e retorno da API.',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _openMercadoPagoPanel,
                icon: const Icon(Icons.account_balance_wallet_rounded),
                label: Text(_isLoadingMercadoPago ? 'Carregando...' : 'Abrir painel'),
              ),
              _StatusPill(
                text: mercadoPagoReady ? 'Integracao configurada' : 'Configurar ambiente',
                color: mercadoPagoReady ? AppColors.success : AppColors.warning,
              ),
              _StatusPill(
                text: mercadoPagoApiStatus == 'OK' ? 'API respondendo' : 'API $mercadoPagoApiStatus',
                color: mercadoPagoApiStatus == 'OK' ? AppColors.success : AppColors.warning,
              ),
              _StatusPill(
                text: 'Pix por parcela',
                color: AppColors.success,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          icon: Icons.support_agent_rounded,
          title: 'Suporte integrado',
          subtitle:
              'Chat interno com historico por conta, pronto para sincronizar WhatsApp do admin.',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _openSupportPanel,
                icon: const Icon(Icons.forum_rounded),
                label: Text('Abrir painel (${_supportConversations.length})'),
              ),
              const _StatusPill(text: 'Chat no banco', color: AppColors.success),
              const _StatusPill(text: 'Painel admin ativo', color: AppColors.success),
              const _StatusPill(text: 'WhatsApp API futuro', color: AppColors.warning),
              const _StatusPill(text: 'Anexos futuro', color: AppColors.warning),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          icon: Icons.fact_check_rounded,
          title: 'Auditoria',
          subtitle:
              'Acompanhe alteracoes, suporte, acessos e acoes criticas registradas por conta.',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _openAuditPanel,
                icon: const Icon(Icons.receipt_long_rounded),
                label: Text('Ver logs (${_auditLogs.length})'),
              ),
              const _StatusPill(text: 'Isolado por conta', color: AppColors.success),
              const _StatusPill(text: 'Acoes criticas', color: AppColors.warning),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          icon: Icons.account_circle_rounded,
          title: 'Perfil no menu',
          subtitle:
              'Mostre sua foto e ajuste o nome exibido no menu lateral ou drawer.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickProfilePhoto,
                    icon: const Icon(Icons.photo_camera_back_rounded),
                    label: Text(
                      _profilePhotoBytes == null ? 'Escolher foto' : 'Trocar foto',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _renameProfile,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Editar nome'),
                  ),
                  if (_profilePhotoBytes != null)
                    OutlinedButton.icon(
                      onPressed: _removeProfilePhoto,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remover foto'),
                    ),
                  if (_profilePhotoBytes != null)
                    OutlinedButton.icon(
                      onPressed: _resetPhotoFraming,
                      icon: const Icon(Icons.center_focus_strong_rounded),
                      label: const Text('Resetar enquadramento'),
                    ),
                ],
              ),
              if (_profilePhotoBytes != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFDCE9FF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ajustar foto',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Arrume o enquadramento para o rosto aparecer melhor no menu.',
                        style: TextStyle(
                          color: Color(0xFF5B6474),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: Column(
                          children: [
                            GestureDetector(
                              onPanUpdate: (details) =>
                                  _handleProfilePhotoDrag(details, 150, 210),
                              onPanEnd: (_) => _saveProfilePreferences(),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Container(
                                  width: 150,
                                  height: 210,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F1FF),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: const Color(0xFFDCE9FF)),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _buildProfilePhotoFrame(
                                    width: 150,
                                  height: 210,
                                    borderRadius: 24,
                                    padding: const EdgeInsets.all(4),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Clique e arraste a foto para posicionar melhor.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF5B6474),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Zoom',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Slider(
                        value: _profilePhotoScale,
                        min: 1.0,
                        max: 4.0,
                        divisions: 30,
                        label: _profilePhotoScale.toStringAsFixed(2),
                        onChanged: (value) {
                          setState(() {
                            _profilePhotoScale = value;
                          });
                        },
                        onChangeEnd: (_) => _saveProfilePreferences(),
                      ),
                      const Text(
                        'Mover para os lados',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Slider(
                        value: _profilePhotoOffsetX,
                        min: -1.0,
                        max: 1.0,
                        divisions: 20,
                        label: _profilePhotoOffsetX.toStringAsFixed(2),
                        onChanged: (value) {
                          setState(() {
                            _profilePhotoOffsetX = value;
                          });
                        },
                        onChangeEnd: (_) => _saveProfilePreferences(),
                      ),
                      const Text(
                        'Mover para cima ou para baixo',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Slider(
                        value: _profilePhotoOffsetY,
                        min: -1.0,
                        max: 1.0,
                        divisions: 20,
                        label: _profilePhotoOffsetY.toStringAsFixed(2),
                        onChanged: (value) {
                          setState(() {
                            _profilePhotoOffsetY = value;
                          });
                        },
                        onChangeEnd: (_) => _saveProfilePreferences(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          icon: Icons.link_rounded,
          title: 'Convite de clientes',
          subtitle:
              'Envie este link para clientes novos criarem conta direto na sua carteira.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                _adminInviteCode != null
                    ? 'Codigo: $_adminInviteCode'
                    : _adminInviteAccountId != null
                        ? 'Link vinculado a sua carteira'
                        : 'Carregando codigo de convite...',
                style: const TextStyle(
                  color: AppColors.textStrong,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_adminInviteCode != null || _adminInviteAccountId != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  _adminInviteCode != null
                      ? _buildClientInviteLink(_adminInviteCode!)
                      : _buildClientAccountInviteLink(_adminInviteAccountId!),
                  style: const TextStyle(
                    color: Color(0xFF5B6474),
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _copyClientInviteLink,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copiar link'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loadAdminInviteCode,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Atualizar'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          icon: Icons.palette_rounded,
          title: 'Aparência',
          subtitle:
              'Brinque com as cores e a escala da fonte sem mexer nos seus dados.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tema do sistema',
                style: TextStyle(
                  color: AppColors.textStrong,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppThemePreference.values.map((preference) {
                  final selected = widget.themePreference == preference;
                  return ChoiceChip(
                    avatar: Icon(
                      preference.icon,
                      size: 18,
                      color: selected ? Colors.white : AppColors.primary,
                    ),
                    label: Text(preference.label),
                    selected: selected,
                    onSelected: (_) => widget.onUpdateThemePreference(preference),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textStrong,
                      fontWeight: FontWeight.w800,
                    ),
                    showCheckmark: false,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: selected ? AppColors.primary : AppColors.borderSoft,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              const Text(
                'Cor de destaque',
                style: TextStyle(
                  color: AppColors.textStrong,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppAccentPreset.values.map((preset) {
                  final selected = widget.accentPreset == preset;
                  final selectedChipColor = widget.themePreference == AppThemePreference.escuro
                      ? (preset == AppAccentPreset.cobreja
                          ? AppColors.secondary
                          : preset.primaryColor)
                      : preset.primaryColor;
                  return ChoiceChip(
                    label: Text(preset.label),
                    selected: selected,
                    onSelected: (_) => widget.onUpdateAccentPreset(preset),
                    selectedColor: selectedChipColor,
                    side: BorderSide(
                      color: selected
                          ? selectedChipColor
                          : const Color(0xFFD8E2F0),
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? Colors.white
                          : const Color(0xFF4B5563),
                      fontWeight: FontWeight.w700,
                    ),
                    showCheckmark: false,
                    backgroundColor: Colors.white,
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              Text(
                'Tamanho da fonte: ${(widget.fontScale * 100).round()}%',
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Slider(
                value: widget.fontScale.clamp(0.85, 1.30),
                min: 0.85,
                max: 1.30,
                divisions: 9,
                label: '${(widget.fontScale * 100).round()}%',
                onChanged: (value) => widget.onUpdateFontScale(value),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onResetVisualPreferences,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Voltar ao visual padrão'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          icon: Icons.storage_rounded,
          title: 'Cache e dados locais',
          subtitle:
              'Limpe apenas o cache da interface ou apague toda a carteira desta instalação.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: _clearInterfaceCache,
                icon: const Icon(Icons.cleaning_services_rounded),
                label: const Text('Limpar cache'),
              ),
              OutlinedButton.icon(
                onPressed: _downloadBackupFile,
                icon: const Icon(Icons.download_for_offline_rounded),
                label: const Text('Baixar backup dos dados'),
              ),
              OutlinedButton.icon(
                onPressed: _downloadLegacyLocalBackupFile,
                icon: const Icon(Icons.history_rounded),
                label: const Text('Recuperar backup antigo local'),
              ),
              FilledButton.icon(
                onPressed: _clearAllBusinessData,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.delete_sweep_rounded),
                label: const Text('Apagar todos os dados'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _sectionTitle(_MainSection section) {
    switch (section) {
      case _MainSection.inicio:
        return null;
      case _MainSection.devendo:
        return 'Clientes devendo';
      case _MainSection.juros:
        return 'Histórico de juros pagos';
      case _MainSection.parcelasPagas:
        return 'Parcelas pagas';
      case _MainSection.quitados:
        return 'Clientes quitados';
      case _MainSection.excluidos:
        return 'Clientes excluídos';
      case _MainSection.emAtraso:
        return 'Cobranças em atraso';
      case _MainSection.venceHoje:
        return 'Vencimentos de hoje';
      case _MainSection.renegociados:
        return 'Renegociados';
      case _MainSection.solicitacoes:
        return 'Solicitações de crédito';
      case _MainSection.metricas:
        return 'Métricas da carteira';
      case _MainSection.configuracoes:
        return 'Configurações do sistema';
    }
  }

  String? _sectionSubtitle(_MainSection section) {
    switch (section) {
      case _MainSection.inicio:
        return null;
      case _MainSection.devendo:
        return 'Veja quem ainda está em aberto e acompanhe a carteira ativa.';
      case _MainSection.juros:
        return 'Histórico permanente de cada renovação com juros paga pelos clientes.';
      case _MainSection.parcelasPagas:
        return 'Acompanhe cada parcela paga nos acordos renegociados, mantendo a linha do tempo dos pagamentos em dia.';
      case _MainSection.quitados:
        return 'Histórico dos clientes que já quitaram a dívida.';
      case _MainSection.excluidos:
        return 'Área de arquivamento para registros removidos da visão principal, com opção de restauração.';
      case _MainSection.emAtraso:
        return 'Cobranças que já passaram do vencimento e exigem atenção.';
      case _MainSection.venceHoje:
        return 'Clientes com vencimento marcado para hoje.';
      case _MainSection.renegociados:
        return 'Acordos parcelados e clientes que foram renegociados.';
      case _MainSection.solicitacoes:
        return 'Pedidos de empréstimo enviados pelos clientes para você aprovar ou recusar.';
      case _MainSection.metricas:
        return 'Acompanhe indicadores, relatórios e evolução mensal dos recebimentos.';
      case _MainSection.configuracoes:
        return 'Personalize a aparência, atualize seu perfil no menu e gerencie cache e dados locais.';
    }
  }

  bool _sectionUsesSearch(_MainSection section) =>
      !{
        _MainSection.inicio,
        _MainSection.juros,
        _MainSection.parcelasPagas,
        _MainSection.solicitacoes,
        _MainSection.metricas,
        _MainSection.configuracoes,
      }.contains(section);

  Widget _buildBrandLockup({required bool compact}) {
    return SvgPicture.asset(
      _isDarkTheme
          ? 'assets/branding/cobreja_logo_white.svg'
          : 'assets/branding/cobreja_logo.svg',
      height: compact ? 52 : 60,
      fit: BoxFit.fitHeight,
      alignment: Alignment.centerLeft,
    );
  }

  double get _monthlyInterestReceivable {
    return _clients.fold<double>(0, (sum, client) {
      if (client.status != 'devendo') return sum;
      final debt = FinanceService.calculateDebt(client);
      return sum + debt.cycleInterest + debt.lateInterest;
    });
  }

  String get _currentMonthRangeLabel {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    final last = DateTime(now.year, now.month + 1, 0);
    final format = DateFormat('dd/MM/yyyy');
    return '${format.format(first)} ate ${format.format(last)}';
  }

  List<({String title, String subtitle, double value, IconData icon, Color color})>
      _metricDetailRows(_MetricCardKind kind) {
    final rows =
        <({String title, String subtitle, double value, IconData icon, Color color})>[];
    final dateFormat = DateFormat('dd/MM/yyyy');

    switch (kind) {
      case _MetricCardKind.totalToReceive:
        for (final client in _clients.where((item) => item.status == 'devendo')) {
          final debt = FinanceService.calculateDebt(client);
          if (debt.totalDebt <= 0.009) continue;
          rows.add((
            title: client.name,
            subtitle:
                'Principal ${_currency(debt.remainingPrincipal)} + juros ${_currency(debt.totalInterestDue)}. Vence ${dateFormat.format(client.dueDate)}.',
            value: debt.totalDebt,
            icon: Icons.account_balance_wallet_rounded,
            color: debt.isOverdue ? AppColors.danger : AppColors.success,
          ));
        }
      case _MetricCardKind.totalReceived:
        for (final client in _clients) {
          final value =
              client.totalInterestCollected + client.totalPrincipalCollected;
          if (value <= 0.009) continue;
          rows.add((
            title: client.name,
            subtitle:
                'Juros ${_currency(client.totalInterestCollected)} + principal ${_currency(client.totalPrincipalCollected)}.',
            value: value,
            icon: Icons.savings_rounded,
            color: AppColors.success,
          ));
        }
      case _MetricCardKind.totalOverdue:
        for (final client in _clients.where((item) => item.status == 'devendo')) {
          final debt = FinanceService.calculateDebt(client);
          if (!debt.isOverdue || debt.totalDebt <= 0.009) continue;
          rows.add((
            title: client.name,
            subtitle:
                '${debt.overdueDays} dia(s) em atraso. Diaria ${_currency(debt.lateInterest)}. Venceu em ${dateFormat.format(client.dueDate)}.',
            value: debt.totalDebt,
            icon: Icons.warning_amber_rounded,
            color: AppColors.danger,
          ));
        }
      case _MetricCardKind.monthlyInterestReceivable:
        for (final client in _clients.where((item) => item.status == 'devendo')) {
          final debt = FinanceService.calculateDebt(client);
          final value = debt.cycleInterest + debt.lateInterest;
          if (value <= 0.009) continue;
          rows.add((
            title: client.name,
            subtitle:
                'Juros do ciclo ${_currency(debt.cycleInterest)} + diaria em atraso ${_currency(debt.lateInterest)}. Periodo $_currentMonthRangeLabel.',
            value: value,
            icon: Icons.percent_rounded,
            color: debt.isOverdue ? AppColors.danger : const Color(0xFFF59E0B),
          ));
        }
      case _MetricCardKind.totalProfit:
        for (final client in _clients) {
          if (client.totalInterestCollected <= 0.009) continue;
          rows.add((
            title: client.name,
            subtitle: 'Somente juros ja recebidos no historico do cliente.',
            value: client.totalInterestCollected,
            icon: Icons.trending_up_rounded,
            color: const Color(0xFF8B5CF6),
          ));
        }
      case _MetricCardKind.totalLent:
        for (final client in _clients.where((item) => item.status != 'excluido')) {
          if (client.borrowedAmount <= 0.009) continue;
          rows.add((
            title: client.name,
            subtitle:
                'Emprestado em ${dateFormat.format(client.borrowedDate)}. Principal atual ${_currency(client.remainingPrincipal)}.',
            value: client.borrowedAmount,
            icon: Icons.request_quote_rounded,
            color: const Color(0xFF2563EB),
          ));
        }
      case _MetricCardKind.estimatedLoss:
        for (final client in _clients.where((item) => item.status == 'devendo')) {
          final debt = FinanceService.calculateDebt(client);
          if (!FinanceService.isEstimatedLoss(client) || debt.totalDebt <= 0.009) {
            continue;
          }
          rows.add((
            title: client.name,
            subtitle:
                client.isMarkedAsLostSafe ? 'Marcado como prejuizo.' : '${debt.overdueDays} dia(s) em atraso.',
            value: debt.totalDebt,
            icon: Icons.trending_down_rounded,
            color: const Color(0xFFB91C1C),
          ));
        }
    }

    rows.sort((a, b) => b.value.compareTo(a.value));
    return rows;
  }

  void _showMetricDetails(_MetricCardData card) {
    final rows = _metricDetailRows(card.kind);
    final total = rows.fold<double>(0, (sum, row) => sum + row.value);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(card.title),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildReceiptLine('Total do card', _currency(total)),
              _buildReceiptLine('Referencia', card.subtitle),
              if (card.kind == _MetricCardKind.monthlyInterestReceivable)
                _buildReceiptLine('Periodo', _currentMonthRangeLabel),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: rows.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          'Nenhum item compoe este valor no momento.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: row.color.withOpacity(0.12),
                              child: Icon(row.icon, color: row.color, size: 20),
                            ),
                            title: Text(
                              row.title,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(row.subtitle),
                            trailing: Text(
                              _currency(row.value),
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    double dashboardNumber(List<String> keys, {required double fallback}) {
      for (final key in keys) {
        dynamic value = dashboardData?[key];
        final dynamic cards = dashboardData?['cards'];
        if (value == null && cards is Map<String, dynamic>) {
          value = cards[key];
        }
        if (value is num) return value.toDouble();
        if (value is String) {
          final parsed = double.tryParse(value.replaceAll(',', '.'));
          if (parsed != null) return parsed;
        }
      }
      return fallback;
    }

    int dashboardCount(List<String> keys, {required int fallback}) {
      for (final key in keys) {
        final dynamic value = dashboardData?[key];
        if (value is List) return value.length;
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
      return fallback;
    }

    final totalToReceive = dashboardNumber([
      'totalToReceive',
      'totalReceivable',
      'totalAReceber',
    ], fallback: _metrics.totalToReceive);
    final totalReceived = dashboardNumber(
      ['totalReceived', 'totalRecebido'],
      fallback: _metrics.totalReceived,
    );
    final totalOverdue = dashboardNumber(
      ['totalOverdue', 'totalEmAtraso'],
      fallback: _metrics.totalOverdue,
    );
    final totalProfit = dashboardNumber(
      ['totalProfit', 'totalLucro'],
      fallback: _metrics.totalProfit,
    );
    final totalLent = dashboardNumber(
      ['totalLent', 'totalEmprestado'],
      fallback: _metrics.totalLent,
    );
    final totalLoss = dashboardNumber(
      ['totalLoss', 'totalPrejuizo', 'estimatedLoss'],
      fallback: _metrics.estimatedLoss,
    );
    final monthlyInterestReceivable = dashboardNumber(
      [
        'monthlyInterestReceivable',
        'totalMonthlyInterestReceivable',
        'jurosDoMesAReceber',
      ],
      fallback: _monthlyInterestReceivable,
    );
    final activeClients = dashboardCount([
      'activeClients',
      'totalClients',
      'clientsCount',
      'clients',
    ], fallback: _clients.where((item) => item.status == 'devendo').length);

    final cards = [
      _MetricCardData(
        title: 'Total a receber',
        value: _currency(
        totalToReceive
      ),
        subtitle: '$activeClients clientes ativos',
        color: const Color(0xFF061C3D),
        icon: Icons.account_balance_wallet_rounded,
        kind: _MetricCardKind.totalToReceive,
      ),
      _MetricCardData(
        title: 'Total recebido',
        value: _currency(
        totalReceived
      ),
        subtitle: 'Entradas registradas',
        color: const Color(0xFF0EA5A4),
        icon: Icons.savings_rounded,
        kind: _MetricCardKind.totalReceived,
      ),
      _MetricCardData(
        title: 'Total em atraso',
        value: _currency(
        totalOverdue
      ),
        subtitle: 'Cobrança urgente',
        color: const Color(0xFFEF4444),
        icon: Icons.warning_amber_rounded,
        kind: _MetricCardKind.totalOverdue,
      ),
      _MetricCardData(
        title: 'Juros do mes',
        value: _currency(monthlyInterestReceivable),
        subtitle: '01 ao ultimo dia + diaria',
        color: const Color(0xFFF59E0B),
        icon: Icons.percent_rounded,
        kind: _MetricCardKind.monthlyInterestReceivable,
      ),
      _MetricCardData(
        title: 'Lucro gerado',
        value: _currency(totalProfit),
        subtitle: 'Juros recebidos',
        color: const Color(0xFF8B5CF6),
        icon: Icons.trending_up_rounded,
        kind: _MetricCardKind.totalProfit,
      ),
      _MetricCardData(
        title: 'Total emprestado',
        value: _currency(
        totalLent
      ),
        subtitle: 'Principal sem juros',
        color: const Color(0xFF2563EB),
        icon: Icons.request_quote_rounded,
        kind: _MetricCardKind.totalLent,
      ),
      _MetricCardData(
        title: 'Prejuízo estimado',
        value: _currency(totalLoss),
        subtitle: 'Perdidos e atrasos +90 dias',
        color: const Color(0xFFB91C1C),
        icon: Icons.trending_down_rounded,
        kind: _MetricCardKind.estimatedLoss,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width < 760) {
          final cardWidth = math.min(math.max(width * 0.70, 214.0), 292.0);

          return SizedBox(
            height: 170,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => SizedBox(
                width: cardWidth,
                child: _MetricCard(
                  data: cards[index],
                  onTap: () => _showMetricDetails(cards[index]),
                ),
              ),
            ),
          );
        }

        final crossAxisCount = width >= 1200
            ? 4
            : 2;
        final cardHeight = width >= 1200 ? 184.0 : 174.0;
        final totalSpacing = (crossAxisCount - 1) * 12.0;
        final horizontalPadding = 36.0;
        final itemWidth =
            (width - horizontalPadding - totalSpacing) / crossAxisCount;
        final aspectRatio = itemWidth / cardHeight;

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
          child: GridView.builder(
            itemCount: cards.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: aspectRatio,
            ),
            itemBuilder: (context, index) => _MetricCard(
              data: cards[index],
              onTap: () => _showMetricDetails(cards[index]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReminderStrip() {
    if (_reminders.isEmpty && _safeCustomReminders.isEmpty) {
      return const SizedBox(height: 8);
    }

    final hasSystemReminder = _reminders.isNotEmpty;
    final firstTitle = hasSystemReminder
        ? _reminders.first.title
        : _safeCustomReminders.first.title;
    final firstSubtitle = hasSystemReminder
        ? _reminders.first.subtitle
        : _safeCustomReminders.first.description;
    final firstColor =
        hasSystemReminder ? _reminders.first.color : const Color(0xFF061C3D);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Tooltip(
        message: 'Abrir lembretes e cobrar clientes rápidamente',
        child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _showReminderCenter,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF7ED), Color(0xFFFFFBEB)],
            ),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: firstColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.alarm_rounded, color: firstColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      firstSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildClientList(
    String tabType, {
    bool includeAllActive = false,
    _ClientQuickFilter overrideFilter = _ClientQuickFilter.todos,
    String? emptyKey,
  }) {
    final filteredClients = _clientsForSection(
      tabType,
      includeAllActive: includeAllActive,
      overrideFilter: overrideFilter,
    );

    if (filteredClients.isEmpty) {
      return _buildEmptyState(
        emptyKey ?? tabType,
        hasFilter: overrideFilter != _ClientQuickFilter.todos,
      );
    }

    final groupedClients = <String, List<Client>>{};
    for (final client in filteredClients) {
      final key = _normalizeClientName(client.name);
      groupedClients.putIfAbsent(key, () => []);
      groupedClients[key]!.add(client);
    }

    final groupEntries = groupedClients.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final showGroupedOnly =
        tabType == 'devendo' && !_bulkSelectionMode;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 110),
      children: groupEntries
          .expand((entry) {
            final clients = entry.value;
            if (showGroupedOnly) {
              final summaries = clients
                  .map((client) => FinanceService.calculateDebt(client))
                  .toList();
              final totalDebt = summaries.fold<double>(
                0,
                (sum, item) => sum + item.totalDebt,
              );
              final totalPrincipal = summaries.fold<double>(
                0,
                (sum, item) => sum + item.remainingPrincipal,
              );
              final totalInterest = summaries.fold<double>(
                0,
                (sum, item) => sum + item.cycleInterest,
              );
              final totalLate = summaries.fold<double>(
                0,
                (sum, item) => sum + item.lateInterest,
              );
              final overdueCount = summaries.where((item) => item.isOverdue).length;

              return [
                _ClientGroupCard(
                  name: clients.first.name,
                  recordCount: clients.length,
                  overdueCount: overdueCount,
                  totalDebt: totalDebt,
                  totalPrincipal: totalPrincipal,
                  totalInterest: totalInterest,
                  totalLate: totalLate,
                  onOpen: () => _openClientGroupProfile(entry.key),
                ),
                const SizedBox(height: 8),
              ];
            }

            final header = Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      clients.first.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F1FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${clients.length} registro(s)',
                      style: const TextStyle(
                        color: Color(0xFF061C3D),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );

            final items = clients.map((client) {
              final debt = FinanceService.calculateDebt(client);
              return _ClientCard(
                client: client,
                debt: debt,
                tabType: tabType,
                onOpen: () => _showClientDetails(client),
                onCharge: () => _launchWhatsApp(client, debt, automatic: true),
                onChargeAll: () => _launchWhatsApp(
                  client,
                  debt,
                  automatic: true,
                  includeRelatedDebts: true,
                ),
                tooltip: 'Abrir detalhes de ${client.name}',
                selectable: _bulkSelectionMode,
                selected: _selectedClientIds.contains(client.id),
                onToggleSelected: () {
                  setState(() {
                    if (_selectedClientIds.contains(client.id)) {
                      _selectedClientIds.remove(client.id);
                    } else {
                      _selectedClientIds.add(client.id);
                    }
                  });
                },
              );
            });

            return [header, ...items, const SizedBox(height: 8)];
          })
          .toList(),
    );
  }

  Future<void> _openClientGroupProfile(String nameKey) async {
    List<Client> _groupFromLocal() {
      final group = _clients
          .where((client) => _normalizeClientName(client.name) == nameKey)
          .toList();
      group.sort((a, b) => a.borrowedDate.compareTo(b.borrowedDate));
      return group;
    }

    final initial = _groupFromLocal();
    final displayName =
        initial.isNotEmpty ? initial.first.name : nameKey;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AdminClientGroupProfilePage(
          nameKey: nameKey,
          displayName: displayName,
          initialClients: initial,
          loadLatest: () async {
            await _refreshClientsFromBackend(updateLoading: false);
            await fetchDashboard();
            return _groupFromLocal();
          },
          openDebtDetails: (client) => _showClientDetails(client),
        ),
      ),
    );
  }

  bool _matchesClientSearch(Client client) {
    final query = _safeSearchQuery.toLowerCase();
    if (query.isEmpty) return true;

    final debt = FinanceService.calculateDebt(client);
    final haystack = [
      client.name,
      client.phone,
      client.borrowedAmount.toStringAsFixed(2),
      debt.totalDebt.toStringAsFixed(2),
      debt.totalInterestDue.toStringAsFixed(2),
      debt.remainingPrincipal.toStringAsFixed(2),
    ].join(' ').toLowerCase();

    return haystack.contains(query);
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: TextField(
            controller: _safeSearchController,
            decoration: InputDecoration(
              hintText: 'Buscar por nome, telefone ou valor',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _safeSearchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      onPressed: () {
                        _safeSearchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              TextField(
                controller: _safeSearchController,
                decoration: InputDecoration(
                  hintText: 'Buscar por nome, telefone ou valor',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _safeSearchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar busca',
                          onPressed: () {
                            _safeSearchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _activeQuickFilter = _ClientQuickFilter.todos;
                            });
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickFilterChip(
                      label: 'Todos',
                      selected: _safeActiveQuickFilter == _ClientQuickFilter.todos,
                      onTap: () => setState(() => _activeQuickFilter = _ClientQuickFilter.todos),
                    ),
                    const SizedBox(width: 8),
                    _buildQuickFilterChip(
                      label: 'Em atraso',
                      selected: _safeActiveQuickFilter == _ClientQuickFilter.atrasados,
                      onTap: () => setState(() => _activeQuickFilter = _ClientQuickFilter.atrasados),
                    ),
                    const SizedBox(width: 8),
                    _buildQuickFilterChip(
                      label: 'Vence hoje',
                      selected: _safeActiveQuickFilter == _ClientQuickFilter.venceHoje,
                      onTap: () => setState(() => _activeQuickFilter = _ClientQuickFilter.venceHoje),
                    ),
                    const SizedBox(width: 8),
                    _buildQuickFilterChip(
                      label: 'Renegociados',
                      selected: _safeActiveQuickFilter == _ClientQuickFilter.renegociados,
                      onTap: () => setState(() => _activeQuickFilter = _ClientQuickFilter.renegociados),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_MonthlyReceiptPoint> _buildMonthlyReceiptPoints({int months = 6}) {
    final now = DateTime.now();
    final monthKeys = List.generate(
      months,
      (index) {
        final month = DateTime(now.year, now.month - (months - 1 - index), 1);
        return month;
      },
    );

    final buckets = <DateTime, (double total, double interest, double principal)>{
      for (final month in monthKeys) month: (0, 0, 0),
    };

    for (final client in _clients) {
      for (final payment in client.paymentHistory) {
        if (payment.amount <= 0.009) continue;
        final key = DateTime(payment.date.year, payment.date.month, 1);
        final current = buckets[key];
        if (current == null) continue;
        buckets[key] = (
          current.$1 + payment.amount,
          current.$2 + payment.interestPaid,
          current.$3 + payment.principalPaid,
        );
      }
    }

    return monthKeys
        .map(
          (month) => _MonthlyReceiptPoint(
            month: month,
            total: buckets[month]!.$1,
            interest: buckets[month]!.$2,
            principal: buckets[month]!.$3,
          ),
        )
        .toList();
  }

  Widget _buildMonthlyReceiptsPanel() {
    final points = _buildMonthlyReceiptPoints();
    final maxValue = points.fold<double>(
      0,
      (max, item) => math.max(max, item.total),
    );
    final latest = points.isEmpty ? null : points.last;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDCE9FF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recebimentos mensais',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Visão dos últimos 6 meses, com destaque para juros e principal recebidos.',
                      style: TextStyle(
                        color: Color(0xFF5B6474),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (latest != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFDCE9FF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        DateFormat('MM/yyyy').format(latest.month),
                        style: const TextStyle(
                          color: Color(0xFF5B6474),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currency(latest.total),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF061C3D),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points.map((point) {
                final ratio =
                    maxValue <= 0 ? 0.08 : (point.total / maxValue).clamp(0.08, 1.0);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _currency(point.total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF5B6474),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: double.infinity,
                              height: 120 * ratio,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: const LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Color(0xFF061C3D),
                                    Color(0xFF22C55E),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          DateFormat('MM/yy').format(point.month),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'J ${_currency(point.interest)}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF7C3AED),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'P ${_currency(point.principal)}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF16A34A),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showMonthlyReceiptsOverviewDialog() {
    if (!_hasPlanAccess(AppPlan.premium)) {
      _ensurePlanAccess(
        requiredPlan: AppPlan.premium,
        featureTitle: 'Visão mensal de recebimentos',
        description:
            'Esse painel mostra a evolução mensal dos recebimentos e fica disponível no plano Premium.',
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recebimentos mensais'),
        content: SizedBox(
          width: 920,
          child: SingleChildScrollView(
            child: _buildMonthlyReceiptsPanel(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFFE8F1FF),
      side: BorderSide(
        color: selected ? const Color(0xFF061C3D) : const Color(0xFFD8E2F0),
      ),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF061C3D) : const Color(0xFF4B5563),
        fontWeight: FontWeight.w700,
      ),
      showCheckmark: false,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
  Widget _buildEmptyState(String tabType, {bool hasFilter = false}) {
    final titles = {
      'todos': 'Nenhum cliente encontrado.',
      'devendo': 'Nenhuma cobrança ativa por enquanto.',
      'juros': 'Nenhum cliente renovado com juros pagos.',
      'quitado': 'Nenhum cliente quitado ainda.',
      'excluido': 'Nenhum cliente excluído.',
      'excluído': 'Nenhum cliente excluído.',
      'atrasados': 'Nenhuma cobrança em atraso no momento.',
      'venceHoje': 'Nenhum vencimento para hoje.',
      'renegociados': 'Nenhum acordo renegociado encontrado.',
    };

    final subtitles = {
      'todos': 'Assim que houver clientes cadastrados, eles aparecerão aqui agrupados por nome para facilitar a consulta da carteira.',
      'devendo': 'Cadastre seu primeiro cliente para acompanhar valores, vencimentos, juros e renegociações com mais clareza.',
      'juros': 'Quando algum cliente renovar a dívida pagando juros, ele aparecerá aqui em destaque para facilitar o acompanhamento.',
      'quitado': 'As cobranças encerradas ficam salvas aqui para consulta futura, histórico e conferência da carteira.',
      'excluido': 'Os registros removidos da visão principal continuam disponíveis aqui, de forma organizada.',
      'excluído': 'Os registros removidos da visão principal continuam disponíveis aqui, de forma organizada.',
      'atrasados': 'As cobranças que passarem do vencimento aparecerão aqui para você agir mais rápido.',
      'venceHoje': 'Quando houver clientes vencendo hoje, eles aparecerão aqui para facilitar sua rotina de cobrança.',
      'renegociados': 'As renegociações parceladas e os acordos ativos aparecerão aqui de forma separada.',
    };

    final icons = {
      'todos': Icons.groups_rounded,
      'devendo': Icons.account_balance_wallet_outlined,
      'juros': Icons.sync_alt_rounded,
      'quitado': Icons.verified_rounded,
      'excluido': Icons.archive_outlined,
      'excluído': Icons.archive_outlined,
      'atrasados': Icons.warning_amber_rounded,
      'venceHoje': Icons.today_rounded,
      'renegociados': Icons.currency_exchange_rounded,
    };

    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - 60),
              maxWidth: 540,
            ),
            child: Center(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: const Color(0xFFDCE9FF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 28,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 84,
                      width: 84,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF061C3D), Color(0xFF22C55E)],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF061C3D).withOpacity(0.18),
                            blurRadius: 22,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Icon(
                        icons[tabType] ?? Icons.inbox_outlined,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      (_safeSearchQuery.isNotEmpty || hasFilter)
                          ? 'Nenhum resultado encontrado.'
                          : (titles[tabType] ?? 'Nenhum registro encontrado.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitles[tabType] ?? 'Assim que houver movimentações, elas aparecerão aqui.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF5B6474),
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6FAFF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE5EEF9)),
                      ),
                      child: const Text(
                        'O painel sera preenchido automaticamente conforme voce cadastrar clientes, registrar pagamentos e organizar sua carteira.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF667085),
                          height: 1.45,
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

  Future<bool> _showClientFormDialog({
    Client? sourceClient,
    bool duplicate = false,
  }) async {
    final isEditing = sourceClient != null && !duplicate;
    final isDuplicating = sourceClient != null && duplicate;
    final baseClient = sourceClient;

    final nameController = TextEditingController(
      text: baseClient?.name ?? '',
    );
    final phoneController = TextEditingController(
      text: baseClient?.phone ?? '',
    );
    final cpfController = TextEditingController(
      text: (baseClient?.cpf ?? '').trim(),
    );
    final emailController = TextEditingController(
      text: (baseClient?.email ?? '').trim(),
    );
    final addressController = TextEditingController(
      text: (baseClient?.address ?? '').trim(),
    );
    final avatarController = TextEditingController(
      text: (baseClient?.avatarUrl ?? '').trim(),
    );
    final amountController = TextEditingController(
      text: baseClient == null
          ? ''
          : baseClient.borrowedAmount.toStringAsFixed(2),
    );
    final monthlyController = TextEditingController(
      text: baseClient == null
          ? ''
          : (baseClient.monthlyInterestType == InterestValueType.fixedAmount
              ? baseClient.monthlyInterestAmount.toStringAsFixed(2)
              : baseClient.monthlyInterestRate.toStringAsFixed(2)),
    );
    final dailyController = TextEditingController(
      text: baseClient == null
          ? ''
          : (baseClient.dailyInterestType == InterestValueType.fixedAmount
              ? baseClient.dailyInterestAmount.toStringAsFixed(2)
              : baseClient.dailyInterestRate.toStringAsFixed(2)),
    );
    InterestValueType monthlyInterestType =
        baseClient?.monthlyInterestType ?? InterestValueType.percentage;
    InterestValueType dailyInterestType =
        baseClient?.dailyInterestType ?? InterestValueType.percentage;
    DateTime selectedBorrowedDate = baseClient?.borrowedDate ?? DateTime.now();
    DateTime selectedDueDate =
        baseClient?.dueDate ?? DateTime.now().add(const Duration(days: 30));
    DateTime? selectedLastInterestPaidAt = baseClient?.lastInterestPaidAt;
    bool isRemovingLastInterestPayment = false;
    bool isSaving = false;

    final dialogTitle = isEditing
        ? 'Editar dívida'
        : isDuplicating
            ? 'Duplicar e editar dívida'
            : 'Novo cliente';
    final actionLabel = isEditing ? 'Atualizar' : 'Salvar';

    final didSave = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(dialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Telefone com DDI',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cpfController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'CPF (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Endereço (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: avatarController,
                  decoration: const InputDecoration(
                    labelText: 'Foto (URL) (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Valor emprestado',
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Juros mensal',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildModeChip(
                      label: 'Em %',
                      selected: monthlyInterestType == InterestValueType.percentage,
                      onTap: () => setDialog(
                        () => monthlyInterestType = InterestValueType.percentage,
                      ),
                    ),
                    _buildModeChip(
                      label: 'Em R\$',
                      selected: monthlyInterestType == InterestValueType.fixedAmount,
                      onTap: () => setDialog(
                        () => monthlyInterestType = InterestValueType.fixedAmount,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: monthlyController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: monthlyInterestType == InterestValueType.fixedAmount
                        ? 'Juros mensal (R\$)'
                        : 'Juros mensal (%)',
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Juros diário por atraso',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildModeChip(
                      label: 'Em %',
                      selected: dailyInterestType == InterestValueType.percentage,
                      onTap: () => setDialog(
                        () => dailyInterestType = InterestValueType.percentage,
                      ),
                    ),
                    _buildModeChip(
                      label: 'Em R\$',
                      selected: dailyInterestType == InterestValueType.fixedAmount,
                      onTap: () => setDialog(
                        () => dailyInterestType = InterestValueType.fixedAmount,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dailyController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: dailyInterestType == InterestValueType.fixedAmount
                        ? 'Juros diário (R\$)'
                        : 'Juros diário (%)',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedBorrowedDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 3650),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setDialog(() {
                          selectedBorrowedDate = picked;
                          if (selectedLastInterestPaidAt != null) {
                            selectedDueDate = _anchoredDueDateFromReference(
                              borrowedDate: selectedBorrowedDate,
                              referenceDate: selectedLastInterestPaidAt!,
                            );
                          } else if (selectedDueDate.isBefore(selectedBorrowedDate)) {
                            selectedDueDate = selectedBorrowedDate;
                          }
                        });
                      }
                    },
                    icon: const Icon(Icons.history_rounded),
                    label: Text(
                      'Empréstimo: ${DateFormat('dd/MM/yyyy').format(selectedBorrowedDate)}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedLastInterestPaidAt ?? selectedDueDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 3650),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setDialog(() {
                          selectedLastInterestPaidAt = picked;
                          selectedDueDate = _anchoredDueDateFromReference(
                            borrowedDate: selectedBorrowedDate,
                            referenceDate: picked,
                          );
                        });
                      }
                    },
                    icon: const Icon(Icons.paid_rounded),
                    label: Text(
                      selectedLastInterestPaidAt == null
                          ? 'Último juros pago (opcional)'
                          : 'Último juros pago: ${DateFormat('dd/MM/yyyy').format(selectedLastInterestPaidAt!)}',
                    ),
                  ),
                ),
                if (selectedLastInterestPaidAt != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: isRemovingLastInterestPayment
                          ? null
                          : () async {
                              // Se ainda não existe cliente no backend (novo/duplicado),
                              // esse campo é apenas visual, então basta limpar.
                              if (!isEditing ||
                                  baseClient == null ||
                                  baseClient.backendPrimaryDebtId == null) {
                                setDialog(() {
                                  selectedLastInterestPaidAt = null;
                                });
                                return;
                              }

                              final backendClientId =
                                  int.tryParse(baseClient.id);
                              final backendDebtId =
                                  baseClient.backendPrimaryDebtId;
                              if (backendClientId == null ||
                                  backendDebtId == null) {
                                setDialog(() {
                                  selectedLastInterestPaidAt = null;
                                });
                                return;
                              }

                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  title:
                                      const Text('Remover último juros pago?'),
                                  content: const Text(
                                    'Isso vai excluir o último pagamento de juros do histórico e recalcular a dívida deste cliente.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(
                                        dialogContext,
                                        false,
                                      ),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.danger,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => Navigator.pop(
                                        dialogContext,
                                        true,
                                      ),
                                      child: const Text('Remover'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed != true) return;

                              final token = await _readAuthToken();
                              if (token == null || token.isEmpty) {
                                if (!mounted) return;
                                _showSnack(
                                  'Você precisa estar logado para remover o pagamento.',
                                  tone: _FeedbackTone.warning,
                                  title: 'Sessão expirada',
                                );
                                return;
                              }

                              setDialog(() {
                                isRemovingLastInterestPayment = true;
                              });

                              int? _optionalInt(dynamic value) {
                                if (value is num) return value.toInt();
                                if (value == null) return null;
                                return int.tryParse(value.toString());
                              }

                              DateTime _paymentDate(
                                Map<String, dynamic> payment,
                              ) {
                                return DateTime.tryParse(
                                      payment['paidAt']?.toString() ?? '',
                                    ) ??
                                    DateTime.tryParse(
                                      payment['createdAt']?.toString() ?? '',
                                    ) ??
                                    DateTime.fromMillisecondsSinceEpoch(0);
                              }

                              try {
                                final details =
                                    await ApiService.fetchClientById(
                                  token: token,
                                  clientId: backendClientId,
                                );
                                final rawPayments =
                                    (details['payments'] as List<dynamic>? ??
                                            const [])
                                        .whereType<Map<String, dynamic>>()
                                        .toList();

                                final jurosPayments = rawPayments.where(
                                  (payment) {
                                    final type = payment['type']
                                        ?.toString()
                                        .toUpperCase();
                                    final debtId =
                                        _optionalInt(payment['debtId']);
                                    return type == 'JUROS' &&
                                        debtId == backendDebtId;
                                  },
                                ).toList();

                                if (jurosPayments.isEmpty) {
                                  setDialog(() {
                                    isRemovingLastInterestPayment = false;
                                    selectedLastInterestPaidAt = null;
                                  });
                                  if (!mounted) return;
                                  _showSnack(
                                    'Nenhum pagamento de juros foi encontrado para esta dívida.',
                                    tone: _FeedbackTone.info,
                                  );
                                  return;
                                }

                                jurosPayments.sort(
                                  (a, b) => _paymentDate(b).compareTo(
                                    _paymentDate(a),
                                  ),
                                );

                                final latest = jurosPayments.first;
                                final paymentId = _optionalInt(latest['id']);
                                if (paymentId == null) {
                                  throw const ApiException(
                                    statusCode: 0,
                                    message: 'ID do pagamento inválido.',
                                  );
                                }

                                await ApiService.deletePayment(
                                  token: token,
                                  paymentId: paymentId,
                                );

                                final refreshed =
                                    await ApiService.fetchClientById(
                                  token: token,
                                  clientId: backendClientId,
                                );

                                final debts =
                                    (refreshed['debts'] as List<dynamic>? ??
                                            const [])
                                        .whereType<Map<String, dynamic>>()
                                        .toList();
                                final updatedDebt = debts.firstWhere(
                                  (debt) =>
                                      _optionalInt(debt['id']) ==
                                      backendDebtId,
                                  orElse: () => debts.isNotEmpty
                                      ? debts.first
                                      : <String, dynamic>{},
                                );

                                final updatedDueDate = DateTime.tryParse(
                                      updatedDebt['dueDate']?.toString() ??
                                          '',
                                    ) ??
                                    selectedDueDate;
                                final updatedLastInterestPaidAt =
                                    DateTime.tryParse(
                                  updatedDebt['lastInterestPaidAt']?.toString() ??
                                      '',
                                );

                                setDialog(() {
                                  isRemovingLastInterestPayment = false;
                                  selectedDueDate = updatedDueDate;
                                  selectedLastInterestPaidAt =
                                      updatedLastInterestPaidAt;
                                });

                                await _refreshClientsFromBackend();
                                await fetchDashboard();

                                if (!mounted) return;
                                _showSnack(
                                  'Último pagamento de juros removido e dívida recalculada.',
                                  tone: _FeedbackTone.success,
                                  title: 'Juros removido',
                                );
                              } catch (e) {
                                debugPrint(
                                  'Falha ao remover último juros pago: $e',
                                );
                                setDialog(() {
                                  isRemovingLastInterestPayment = false;
                                });
                                if (!mounted) return;
                                final message = e is ApiException
                                    ? e.message
                                    : 'Não foi possível remover o último juros pago.';
                                _showSnack(
                                  message,
                                  tone: _FeedbackTone.error,
                                  title: 'Falha ao remover',
                                );
                              }
                            },
                      icon: isRemovingLastInterestPayment
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Remover último juros pago'),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDueDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 3650),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setDialog(() {
                          selectedDueDate = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text(
                      'Vencimento: ${DateFormat('dd/MM/yyyy').format(selectedDueDate)}',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                final borrowedDate = selectedBorrowedDate;
                final termDays =
                    math.max(1, selectedDueDate.difference(borrowedDate).inDays);
                final normalizedCpf = cpfController.text.trim();
                final normalizedEmail = emailController.text.trim();
                final normalizedAddress = addressController.text.trim();
                final normalizedAvatar = avatarController.text.trim();
                final client = Client(
                  id: isEditing
                      ? baseClient!.id
                      : DateTime.now().microsecondsSinceEpoch.toString(),
                  backendPrimaryDebtId:
                      isEditing ? baseClient!.backendPrimaryDebtId : null,
                  cpf: normalizedCpf.isEmpty ? null : normalizedCpf,
                  email: normalizedEmail.isEmpty ? null : normalizedEmail,
                  address: normalizedAddress.isEmpty ? null : normalizedAddress,
                  avatarUrl: normalizedAvatar.isEmpty ? null : normalizedAvatar,
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  borrowedAmount: _readDouble(amountController.text),
                  monthlyInterestRate:
                      monthlyInterestType == InterestValueType.percentage
                          ? _readDouble(monthlyController.text)
                          : 0,
                  monthlyInterestAmount:
                      monthlyInterestType == InterestValueType.fixedAmount
                          ? _readDouble(monthlyController.text)
                          : 0,
                  monthlyInterestType: monthlyInterestType,
                  dailyInterestRate:
                      dailyInterestType == InterestValueType.percentage
                          ? _readDouble(dailyController.text)
                          : 0,
                  dailyInterestAmount:
                      dailyInterestType == InterestValueType.fixedAmount
                          ? _readDouble(dailyController.text)
                          : 0,
                  dailyInterestType: dailyInterestType,
                  borrowedDate: borrowedDate,
                  dueDate: selectedDueDate,
                  originalTermDays: termDays,
                  cycleStartDate: borrowedDate,
                  status: isEditing ? baseClient!.status : 'devendo',
                  pagouJuros: isEditing ? baseClient!.pagouJuros : false,
                  isNegotiated: isEditing ? baseClient!.isNegotiated : false,
                  isMarkedAsLost: isEditing ? baseClient!.isMarkedAsLostSafe : false,
                  installmentCount: isEditing ? baseClient!.installmentCount : 0,
                  installmentsPaid: isEditing ? baseClient!.installmentsPaid : 0,
                  installmentAmount: isEditing ? baseClient!.installmentAmount : 0,
                  renegotiatedAt: isEditing ? baseClient!.renegotiatedAt : null,
                  installmentStartDate:
                      isEditing ? baseClient!.installmentStartDate : null,
                  lastInterestPaidAt: selectedLastInterestPaidAt,
                  interestPaidCurrentCycle:
                      isEditing ? baseClient!.interestPaidCurrentCycle : 0,
                  activePrincipalCollected:
                      isEditing ? baseClient!.activePrincipalCollected : 0,
                  totalInterestCollected:
                      isEditing ? baseClient!.totalInterestCollected : 0,
                  totalPrincipalCollected:
                      isEditing ? baseClient!.totalPrincipalCollected : 0,
                  paymentHistory:
                      isEditing ? [...baseClient!.paymentHistory] : const [],
                );

                if (client.name.isEmpty || client.borrowedAmount <= 0) {
                  _showSnack('Informe nome e valor válido.');
                  return;
                }

                setDialog(() {
                  isSaving = true;
                });

                final synced = await _syncClient(client, syncDebt: true);

                if (!mounted) return;

                if (!synced) {
                  setDialog(() {
                    isSaving = false;
                  });
                  return;
                }

                Navigator.pop(context, true);
              },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(actionLabel),
            ),
          ],
        ),
      ),
    );
    return didSave == true;
  }

  void _showAddClientDialog() {
    _showClientFormDialog();
  }

  void _showDuplicateClientDialog(Client client) {
    _showClientFormDialog(
      sourceClient: client,
      duplicate: true,
    );
  }

  void _showEditClientDialog(Client client) {
    _showClientFormDialog(sourceClient: client);
  }

  Future<void> _showClientAccessInfoDialog(Client client) async {
    final email = (client.email ?? '').trim();
    final cpf = (client.cpf ?? '').trim();
    final hasEmail = email.isNotEmpty;
    final hasCpf = cpf.isNotEmpty;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Acesso do cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Este cliente já possui um login vinculado.',
              style: TextStyle(
                color: Color(0xFF5B6474),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            if (hasEmail)
              SelectableText('Email: $email')
            else
              const Text('Email: (não informado)'),
            if (hasCpf)
              SelectableText('CPF: $cpf')
            else
              const Text('CPF: (não informado)'),
            const SizedBox(height: 12),
            const Text(
              'O cliente pode entrar usando Email ou CPF e verá apenas os próprios dados.',
              style: TextStyle(
                color: Color(0xFF5B6474),
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final token = await _readAuthToken();
              final clientId = int.tryParse(client.id);
              if (token == null || token.isEmpty || clientId == null) {
                if (!mounted) return;
                _showSnack(
                  'NÃ£o foi possÃ­vel autenticar para unificar agora.',
                  tone: _FeedbackTone.error,
                  title: 'SessÃ£o invÃ¡lida',
                );
                return;
              }

              final confirmed = await _confirmDestructiveAction(
                title: 'Unificar dÃ­vidas',
                message:
                    'Isso vai consolidar todos os registros com o nome \"${client.name}\" em um Ãºnico perfil (os duplicados vÃ£o para ExcluÃ­dos). Use apenas se vocÃª tem vÃ¡rios cadastros da mesma pessoa.',
                confirmLabel: 'Unificar',
              );
              if (!confirmed) return;

              try {
                final payload = await ApiService.mergeClientDuplicates(
                  token: token,
                  clientId: clientId,
                  mergeByName: true,
                );
                await _refreshClientsFromBackend(updateLoading: true);
                await fetchDashboard();

                if (!mounted) return;
                final mergedClients =
                    (payload['mergedClients'] as num?)?.toInt() ?? 0;
                final mergedDebts = (payload['mergedDebts'] as num?)?.toInt() ?? 0;
                _showSnack(
                  mergedClients > 0
                      ? 'Unificado: $mergedClients registro(s) e $mergedDebts dÃ­vida(s).'
                      : 'Nenhum duplicado encontrado para este nome.',
                  tone: _FeedbackTone.success,
                  title: 'ConcluÃ­do',
                );
              } catch (e) {
                if (!mounted) return;
                _showSnack(
                  e is ApiException
                      ? e.message
                      : 'NÃ£o foi possÃ­vel unificar agora.',
                  tone: _FeedbackTone.error,
                  title: 'Falha',
                );
              }
            },
            icon: const Icon(Icons.merge_type_rounded, size: 18),
            label: const Text('Unificar dÃ­vidas'),
          ),
          if (hasEmail)
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: email));
                if (!mounted) return;
                _showSnack('Email copiado.');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copiar email'),
            ),
        ],
      ),
    );
  }

  Future<void> _showCreateClientLoginDialog(Client client) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      _showSnack(
        'Sua sessão expirou. Faça login novamente.',
        tone: _FeedbackTone.warning,
        title: 'Sessão expirada',
      );
      return;
    }

    final clientId = int.tryParse(client.id);
    if (clientId == null) {
      if (!mounted) return;
      _showSnack(
        'Não foi possível identificar o cliente no servidor.',
        tone: _FeedbackTone.error,
        title: 'ID inválido',
      );
      return;
    }

    final emailController = TextEditingController(text: (client.email ?? '').trim());
    final cpfController = TextEditingController(text: (client.cpf ?? '').trim());
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    try {
      final result = await showDialog<Map<String, dynamic>?>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          String? errorText;
          var obscurePassword = true;
          var obscureConfirm = true;
          var isSubmitting = false;
          var mergeByName = true;

          Future<void> submit(StateSetter setDialog) async {
            final password = passwordController.text.trim();
            final confirm = confirmController.text.trim();
            final emailInput = emailController.text.trim();
            final cpfInput = cpfController.text.trim();

            if (password.length < 4) {
              setDialog(() => errorText = 'A senha precisa ter pelo menos 4 caracteres.');
              return;
            }
            if (confirm != password) {
              setDialog(() => errorText = 'As senhas não conferem.');
              return;
            }

            final hasEmail = emailInput.isNotEmpty;
            final hasCpf = cpfInput.isNotEmpty;
            if (!hasEmail && !hasCpf) {
              setDialog(() => errorText = 'Informe o email ou CPF do cliente para criar o acesso.');
              return;
            }

            // Validação simples de email (o backend ainda valida de verdade)
            if (hasEmail && (!emailInput.contains('@') || !emailInput.contains('.'))) {
              setDialog(() => errorText = 'Informe um email válido.');
              return;
            }

            setDialog(() {
              errorText = null;
              isSubmitting = true;
            });

            try {
              final payload = await ApiService.createClientLogin(
                token: token,
                clientId: clientId,
                password: password,
                email: emailInput,
                cpf: cpfInput,
                mergeByName: mergeByName,
              );

              if (!mounted) return;
              Navigator.pop(dialogContext, {
                'payload': payload,
                'password': password,
              });
            } catch (e) {
              final message = e is ApiException
                  ? e.message
                  : 'Não foi possível criar o acesso agora.';
              setDialog(() {
                errorText = message;
                isSubmitting = false;
              });
            }
          }

          return StatefulBuilder(
            builder: (context, setDialog) => AlertDialog(
              title: const Text('Criar acesso do cliente'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Defina uma senha para este cliente acessar o sistema e ver somente os dados dele.',
                      style: TextStyle(
                        color: Color(0xFF5B6474),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email do cliente (para login)',
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: cpfController,
                      decoration: const InputDecoration(
                        labelText: 'CPF do cliente (opcional)',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Senha do cliente',
                        suffixIcon: IconButton(
                          tooltip: obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                          onPressed: () => setDialog(() => obscurePassword = !obscurePassword),
                          icon: Icon(
                            obscurePassword ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmController,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirmar senha',
                        suffixIcon: IconButton(
                          tooltip: obscureConfirm ? 'Mostrar senha' : 'Ocultar senha',
                          onPressed: () => setDialog(() => obscureConfirm = !obscureConfirm),
                          icon: Icon(
                            obscureConfirm ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: mergeByName,
                      onChanged: isSubmitting
                          ? null
                          : (value) => setDialog(() => mergeByName = value ?? true),
                      title: const Text(
                        'Unificar dÃ­vidas com o mesmo nome',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text(
                        'Se vocÃª tiver vÃ¡rios registros deste cliente (ex.: um por emprÃ©stimo), o sistema consolida tudo em um Ãºnico perfil para o cliente ver todas as dÃ­vidas.',
                        style: TextStyle(color: Color(0xFF5B6474), height: 1.35),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: isSubmitting ? null : () => submit(setDialog),
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open_rounded, size: 18),
                  label: Text(isSubmitting ? 'Criando...' : 'Criar acesso'),
                ),
              ],
            ),
          );
        },
      );

      if (result == null) return;
      final payload = (result['payload'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      final createdPassword = (result['password']?.toString() ?? '').trim();
      final user = (payload['user'] as Map?)?.cast<String, dynamic>();

      await _refreshClientsFromBackend(updateLoading: true);
      await fetchDashboard();

      if (!mounted) return;
      _showSnack(
        'Acesso criado com sucesso.',
        tone: _FeedbackTone.success,
        title: 'Acesso liberado',
      );

      final createdEmail = (user?['email']?.toString() ?? '').trim();
      final createdCpf = (user?['cpf']?.toString() ?? '').trim();
      final messageLines = <String>[
        'Acesso do cliente criado:',
        if (createdEmail.isNotEmpty) 'Email: $createdEmail',
        if (createdCpf.isNotEmpty) 'CPF: $createdCpf',
        if (createdPassword.isNotEmpty) 'Senha: $createdPassword',
        '',
        'O cliente pode entrar com Email ou CPF.',
      ];
      final shareText = messageLines.join('\n');

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Enviar ao cliente'),
          content: SelectableText(shareText),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: shareText));
                if (!mounted) return;
                _showSnack('Dados copiados.');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copiar'),
            ),
          ],
        ),
      );
    } finally {
      emailController.dispose();
      cpfController.dispose();
      passwordController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _showClientDetails(Client client) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            final debt = FinanceService.calculateDebt(client);
            final screenWidth = MediaQuery.of(context).size.width;
            final compact = screenWidth < 640;
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FBFF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 54,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 16 : 20,
                        20,
                        compact ? 16 : 20,
                        30,
                      ),
                      children: [
                        if (compact)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                client.name,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                client.phone,
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _StatusPill(
                                text: client.status == 'quitado'
                                    ? 'Quitado'
                                    : debt.isOverdue
                                        ? 'Em atraso'
                                        : client.pagouJuros
                                            ? 'Renovou juros'
                                            : 'Ativo',
                                color: client.status == 'quitado'
                                    ? const Color(0xFF16A34A)
                                    : debt.isOverdue
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF061C3D),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      client.name,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      client.phone,
                                      style: const TextStyle(
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _StatusPill(
                                text: client.status == 'quitado'
                                    ? 'Quitado'
                                    : debt.isOverdue
                                        ? 'Em atraso'
                                        : client.pagouJuros
                                            ? 'Renovou juros'
                                            : 'Ativo',
                                color: client.status == 'quitado'
                                    ? const Color(0xFF16A34A)
                                    : debt.isOverdue
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF061C3D),
                              ),
                            ],
                          ),
                        const SizedBox(height: 20),
                        _buildSummaryGrid(client, debt),
                        const SizedBox(height: 20),
                        _buildActions(client, debt),
                        const SizedBox(height: 22),
                        _buildTimeline(
                          client,
                          onRefresh: () => setDialog(() {}),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryGrid(Client client, DebtSummary debt) {
      final items = [
        _SummaryItem(
          debt.isNegotiated ? 'Empréstimo original' : 'Empréstimo',
          DateFormat('dd/MM/yyyy').format(client.borrowedDate),
        ),
        _SummaryItem('Principal em aberto', _currency(debt.remainingPrincipal)),
        _SummaryItem('Juros do ciclo', _currency(debt.cycleInterest)),
        _SummaryItem('Juros por atraso', _currency(debt.lateInterest)),
        _SummaryItem('Apenas juros', _currency(debt.totalInterestDue)),
        _SummaryItem('Total atualizado', _currency(debt.totalDebt)),
        if (!debt.isNegotiated)
          _SummaryItem(
            'Juros mensal',
            _formatInterestRule(
              type: client.monthlyInterestType,
              percentageValue: client.monthlyInterestRate,
              amountValue: client.monthlyInterestAmount,
              suffix: 'a.m.',
            ),
          ),
        _SummaryItem(
          'Juros diário',
          _formatInterestRule(
            type: client.dailyInterestType,
            percentageValue: client.dailyInterestRate,
            amountValue: client.dailyInterestAmount,
            suffix: 'a.d.',
          ),
        ),
        if (!debt.isNegotiated)
          _SummaryItem('Ciclos de juros', '${debt.monthlyCyclesDue} ciclo(s)'),
        if (debt.isNegotiated)
          _SummaryItem(
            'Parcelas',
            '${debt.installmentsPaid}/${debt.installmentCount} • ${_currency(debt.installmentAmount)}',
          ),
        if (debt.isNegotiated)
          _SummaryItem(
            'Regra do atraso',
            _formatInterestRule(
              type: client.dailyInterestType,
              percentageValue: client.dailyInterestRate,
              amountValue: client.dailyInterestAmount,
              suffix: 'a.d.',
            ),
          ),
        if (debt.isNegotiated && client.renegotiatedAt != null)
          _SummaryItem(
            'Início da renegociação',
            DateFormat('dd/MM/yyyy').format(client.renegotiatedAt!),
          ),
      _SummaryItem(
        'Vencimento',
        DateFormat('dd/MM/yyyy').format(client.dueDate),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 3
            : width >= 560
                ? 2
                : 1;
        final itemWidth = (width - ((columns - 1) * 12)) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildActions(Client client, DebtSummary debt) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Ações rápidas',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _ActionChip(
            icon: Icons.edit_rounded,
            label: 'Editar dívida',
            color: const Color(0xFF061C3D),
            onTap: () {
              Navigator.pop(context);
              _showEditClientDialog(client);
            },
          ),

          if (client.backendUserId == null)
            _ActionChip(
              icon: Icons.person_add_alt_1_rounded,
              label: 'Criar acesso',
              color: const Color(0xFF2563EB),
              onTap: () {
                Navigator.pop(context);
                _showCreateClientLoginDialog(client);
              },
            )
          else
            _ActionChip(
              icon: Icons.verified_user_rounded,
              label: 'Acesso criado',
              color: const Color(0xFF059669),
              onTap: () {
                Navigator.pop(context);
                _showClientAccessInfoDialog(client);
              },
            ),

          _ActionChip(
            icon: Icons.currency_exchange_rounded,
            label: 'Pagou juros',
            color: const Color(0xFFF59E0B),
            onTap: () {
              Navigator.pop(context);
              _registerInterestSettlement(client);
            },
          ),

          _ActionChip(
            icon: Icons.payments_rounded,
            label: 'Pagamento parcial',
            color: const Color(0xFF061C3D),
            onTap: () {
              Navigator.pop(context);
              _showPaymentDialog(client);
            },
          ),

          _ActionChip(
            icon: Icons.check_circle_rounded,
            label: 'Quitar agora',
            color: const Color(0xFF16A34A),
            onTap: () {
              Navigator.pop(context);
              _settleClient(client);
            },
          ),

          _ActionChip(
            icon: Icons.restart_alt_rounded,
            label: 'Renegociar',
            color: const Color(0xFF7C3AED),
            onTap: () {
              Navigator.pop(context);
              _showRenegotiateDialog(client);
            },
          ),

          _ActionChip(
            icon: Icons.copy_all_rounded,
            label: 'Duplicar e editar',
            color: const Color(0xFF2563EB),
            onTap: () {
              Navigator.pop(context);
              _showDuplicateClientDialog(client);
            },
          ),

          _ActionChip(
            icon: Icons.message_rounded,
            label: 'Cobrar automático',
            color: const Color(0xFF22C55E),
            onTap: () => _launchWhatsApp(client, debt, automatic: true),
          ),

          _ActionChip(
            icon: client.isMarkedAsLostSafe
                ? Icons.heart_broken_rounded
                : Icons.money_off_csred_rounded,
            label: client.isMarkedAsLostSafe
                ? 'Remover prejuízo'
                : 'Marcar prejuízo',
            color: const Color(0xFFB91C1C),
            onTap: () {
              Navigator.pop(context);
              _toggleLossFlag(client);
            },
          ),

          _ActionChip(
            icon: Icons.delete_rounded,
            label: 'Excluir',
            color: const Color(0xFFDC2626),
            onTap: () async {
              final confirmed = await _confirmDestructiveAction(
                title: 'Excluir cliente',
                message:
                    'Esse cliente vai para a lista de excluídos.',
                confirmLabel: 'Excluir',
              );
              if (!confirmed) return;
              _deleteClient(client.id);

              setState(() {}); // 🔥 força atualizar lista

              Navigator.pop(context);
            },
          ),

          if (client.status == 'excluido' ||
              client.status == 'excluído') ...[
            _ActionChip(
              icon: Icons.restore_from_trash_rounded,
              label: 'Restaurar',
              color: const Color(0xFF2563EB),
              onTap: () async {
                final confirmed = await _confirmDestructiveAction(
                  title: 'Restaurar cliente',
                  message:
                      'Esse registro voltará para a carteira.',
                  confirmLabel: 'Restaurar',
                );

                if (!confirmed) return;

                await _restoreExcludedClient(client.id);
                Navigator.pop(context);
              },
            ),

            _ActionChip(
              icon: Icons.delete_forever,
              label: 'Eliminar de vez',
              color: const Color(0xFFD32F2F),
              onTap: () async {
                final confirmed = await _confirmDestructiveAction(
                  title: 'Eliminar cliente',
                  message:
                      'Esse registro será apagado definitivamente.',
                  confirmLabel: 'Eliminar',
                );

                if (!confirmed) return;

                await _permanentlyDeleteClient(client.id);
                Navigator.pop(context);
              },
            ),
          ],
        ],
      ),
    ],
  );
}

  Widget _buildTimeline(Client client, {VoidCallback? onRefresh}) {
    final history = [...client.paymentHistory]
      ..sort((a, b) => b.date.compareTo(a.date));
    final query = _safePaymentHistoryQuery.toLowerCase();
    final filteredHistory = history.where((payment) {
      final matchesQuery =
          query.isEmpty ||
          payment.type.toLowerCase().contains(query) ||
          payment.note.toLowerCase().contains(query) ||
          _currency(payment.amount).toLowerCase().contains(query) ||
          DateFormat('dd/MM/yyyy').format(payment.date).contains(query);

      final matchesFilter = switch (_safePaymentHistoryFilter) {
        _PaymentHistoryQuickFilter.todos => true,
        _PaymentHistoryQuickFilter.hoje =>
          _dateOnly(payment.date) == _dateOnly(DateTime.now()),
        _PaymentHistoryQuickFilter.ultimos7Dias =>
          !_dateOnly(payment.date).isBefore(
            _dateOnly(DateTime.now().subtract(const Duration(days: 6))),
          ),
        _PaymentHistoryQuickFilter.ultimos30Dias =>
          !_dateOnly(payment.date).isBefore(
            _dateOnly(DateTime.now().subtract(const Duration(days: 29))),
          ),
        _PaymentHistoryQuickFilter.juros =>
          payment.interestPaid > 0.009 && payment.principalPaid <= 0.009,
        _PaymentHistoryQuickFilter.principal =>
          payment.principalPaid > 0.009 && payment.interestPaid <= 0.009,
        _PaymentHistoryQuickFilter.quitacao =>
          payment.type.toLowerCase().contains('quit'),
      };

      return matchesQuery && matchesFilter;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Histórico de pagamentos',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _safePaymentHistorySearchController,
          decoration: InputDecoration(
            hintText: 'Buscar no histórico',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _safePaymentHistoryQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca do histórico',
                    onPressed: () {
                      _safePaymentHistorySearchController.clear();
                      setState(() {
                        _paymentHistoryQuery = '';
                        _paymentHistoryFilter = _PaymentHistoryQuickFilter.todos;
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildPaymentHistoryChip(
                label: 'Todos',
                filter: _PaymentHistoryQuickFilter.todos,
              ),
              _buildPaymentHistoryChip(
                label: 'Hoje',
                filter: _PaymentHistoryQuickFilter.hoje,
              ),
              _buildPaymentHistoryChip(
                label: '7 dias',
                filter: _PaymentHistoryQuickFilter.ultimos7Dias,
              ),
              _buildPaymentHistoryChip(
                label: '30 dias',
                filter: _PaymentHistoryQuickFilter.ultimos30Dias,
              ),
              _buildPaymentHistoryChip(
                label: 'Juros',
                filter: _PaymentHistoryQuickFilter.juros,
              ),
              _buildPaymentHistoryChip(
                label: 'Principal',
                filter: _PaymentHistoryQuickFilter.principal,
              ),
              _buildPaymentHistoryChip(
                label: 'Quitação',
                filter: _PaymentHistoryQuickFilter.quitacao,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (filteredHistory.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              history.isEmpty
                  ? 'Nenhum pagamento registrado ainda.'
                  : 'Nenhum pagamento encontrado com os filtros atuais.',
            ),
          )
        else
          ...filteredHistory.map(
            (payment) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Container(
                    height: 46,
                    width: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F1FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Color(0xFF061C3D),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          payment.type,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${DateFormat('dd/MM/yyyy HH:mm').format(payment.date)} • '
                          'Juros ${_currency(payment.interestPaid)} • '
                          'Principal ${_currency(payment.principalPaid)}',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                        if (payment.note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            payment.note,
                            style: const TextStyle(
                              color: Color(0xFF374151),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _currency(payment.amount),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      IconButton(
                        tooltip: 'Abrir comprovante deste pagamento',
                        onPressed: () => _showPaymentReceiptDialog(
                          client,
                          payment,
                        ),
                        icon: const Icon(
                          Icons.receipt_long_rounded,
                          color: Color(0xFF061C3D),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (payment.amount > 0.009)
                        PopupMenuButton<String>(
                          tooltip: 'Ações do pagamento',
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditPaymentDialog(client, payment);
                            } else if (value == 'delete') {
                              _confirmDestructiveAction(
                                title: 'Excluir pagamento',
                                message:
                                    'Esse pagamento será removido do histórico e o saldo do cliente será recalculado.',
                                confirmLabel: 'Excluir',
                              ).then((confirmed) {
                                if (!confirmed) return;
                                _deletePaymentRecord(client, payment);                                
                                onRefresh?.call();
                              });
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Editar pagamento'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Excluir pagamento'),
                            ),
                          ],
                          icon: const Icon(Icons.more_vert_rounded),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentHistoryChip({
    required String label,
    required _PaymentHistoryQuickFilter filter,
  }) {
    final selected = _safePaymentHistoryFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _paymentHistoryFilter = filter;
          });
        },
      ),
    );
  }

  String _buildBackupPayload() {
    final payload = {
      'app': 'COBREJA',
      'schema': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'clients': _clients.map((client) => client.toMap()).toList(),
      'customReminders': _safeCustomReminders.map((item) => item.toMap()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<String?> _buildLegacyLocalBackupPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = <String>{
      'clients',
      'cobreja_clients',
      'cobreja_local_clients',
      'local_clients',
      'client_list',
      'flutter.clients',
      ...prefs.getKeys(),
    };

    List<dynamic>? decodedClients;
    String? sourceKey;

    for (final key in keys) {
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) continue;

      try {
        final decoded = jsonDecode(raw);
        final candidate = decoded is List
            ? decoded
            : decoded is Map && decoded['clients'] is List
                ? decoded['clients'] as List
                : null;

        if (candidate != null && candidate.any(_looksLikeLegacyClientMap)) {
          decodedClients = candidate;
          sourceKey = key;
          break;
        }
      } catch (_) {
        continue;
      }
    }

    if (decodedClients == null || decodedClients.isEmpty) {
      return null;
    }

    var decodedReminders = const <dynamic>[];
    for (final key in const [
      'custom_reminders',
      'cobreja_custom_reminders',
      'flutter.custom_reminders',
    ]) {
      final rawReminders = prefs.getString(key);
      if (rawReminders == null || rawReminders.trim().isEmpty) continue;
      try {
        final parsed = jsonDecode(rawReminders);
        if (parsed is List) {
          decodedReminders = parsed;
          break;
        }
      } catch (_) {}
    }

    final payload = {
      'app': 'COBREJA',
      'schema': 1,
      'source': 'legacy_local_shared_preferences_scan',
      'sourceKey': sourceKey,
      'exportedAt': DateTime.now().toIso8601String(),
      'clients': decodedClients,
      'customReminders': decodedReminders,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  bool _looksLikeLegacyClientMap(dynamic item) {
    if (item is! Map) return false;
    final keys = item.keys.map((key) => key.toString()).toSet();
    final hasName = keys.contains('name') || keys.contains('nome');
    final hasFinancialField = keys.contains('borrowedAmount') ||
        keys.contains('borrowed_amount') ||
        keys.contains('amount') ||
        keys.contains('valor') ||
        keys.contains('payments') ||
        keys.contains('paymentHistory');
    final hasDateOrStatus = keys.contains('dueDate') ||
        keys.contains('borrowedDate') ||
        keys.contains('status') ||
        keys.contains('vencimento');
    return hasName && (hasFinancialField || hasDateOrStatus);
  }

  String _buildCsvPayload() {
    final buffer = StringBuffer();
    buffer.writeln('Nome,Telefone,Status,Emprestimo,Vencimento,Valor emprestado,Principal em aberto,Juros em aberto,Total atualizado,Renegociado');

    for (final client in _clients) {
      final debt = FinanceService.calculateDebt(client);
      final values = [
        client.name,
        client.phone,
        client.status,
        DateFormat('dd/MM/yyyy').format(client.borrowedDate),
        DateFormat('dd/MM/yyyy').format(client.dueDate),
        client.borrowedAmount.toStringAsFixed(2),
        debt.remainingPrincipal.toStringAsFixed(2),
        debt.totalInterestDue.toStringAsFixed(2),
        debt.totalDebt.toStringAsFixed(2),
        client.isNegotiated ? 'Sim' : 'Nao',
      ].map(_escapeCsvField).join(',');
      buffer.writeln(values);
    }

    return buffer.toString();
  }

  String _escapeCsvField(String value) {
    final normalized = value.replaceAll('"', '""');
    return '"$normalized"';
  }

  String _buildPaymentReceiptText(Client client, PaymentRecord payment) {
    final buffer = StringBuffer();
    buffer.writeln('COBREJA - Comprovante de pagamento');
    buffer.writeln(
      'Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
    );
    buffer.writeln('');
    buffer.writeln('Cliente: ${client.name}');
    buffer.writeln('Telefone: ${client.phone}');
    buffer.writeln(
      'Data do pagamento: ${DateFormat('dd/MM/yyyy HH:mm').format(payment.date)}',
    );
    buffer.writeln('Tipo: ${payment.type}');
    buffer.writeln('Valor total: ${_currency(payment.amount)}');
    if (payment.dailyPaid > 0.009) {
      buffer.writeln(
        'Valor em juros: ${_currency(math.max(0, payment.interestPaid - payment.dailyPaid))}',
      );
      buffer.writeln('Valor em diÃ¡ria: ${_currency(payment.dailyPaid)}');
    } else {
      buffer.writeln('Valor em juros: ${_currency(payment.interestPaid)}');
    }
    buffer.writeln('Valor em principal: ${_currency(payment.principalPaid)}');
    if (payment.note.trim().isNotEmpty) {
      buffer.writeln('Observação: ${payment.note.trim()}');
    }
    return buffer.toString().trim();
  }

  Future<void> _downloadPaymentReceiptPdf(
    Client client,
    PaymentRecord payment,
  ) async {
    final pdf = pw.Document();
    final generatedAt = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final paymentDate = DateFormat('dd/MM/yyyy HH:mm').format(payment.date);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'COBREJA - Comprovante de pagamento',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Gerado em $generatedAt'),
            pw.SizedBox(height: 18),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromHex('#DCE9FF')),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Cliente: ${client.name}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text('Telefone: ${client.phone}'),
                  pw.Text('Data do pagamento: $paymentDate'),
                  pw.Text('Tipo: ${payment.type}'),
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F7FAFF'),
                border: pw.Border.all(color: PdfColor.fromHex('#DCE9FF')),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Resumo do pagamento',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text('Valor total: ${_currency(payment.amount)}'),
                  if (payment.dailyPaid > 0.009) ...[
                    pw.Text(
                      'Juros: ${_currency(math.max(0, payment.interestPaid - payment.dailyPaid))}',
                    ),
                    pw.Text('DiÃ¡ria: ${_currency(payment.dailyPaid)}'),
                  ] else
                    pw.Text('Juros: ${_currency(payment.interestPaid)}'),
                  pw.Text('Principal: ${_currency(payment.principalPaid)}'),
                  if (payment.note.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 8),
                    pw.Text('Observação: ${payment.note.trim()}'),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final bytes = await pdf.save();
    await _downloadPdfExport(
      bytes: bytes,
      fileName: _buildExportFileName(
        'cobreja_comprovante_${client.name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), "_")}',
        'pdf',
      ),
      successTitle: 'Comprovante salvo',
    );
  }

  Future<void> _showPaymentReceiptDialog(
    Client client,
    PaymentRecord payment,
  ) async {
    final receiptText = _buildPaymentReceiptText(client, payment);

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Comprovante de pagamento'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pagamento de ${_currency(payment.amount)} em ${DateFormat('dd/MM/yyyy HH:mm').format(payment.date)}',
                  style: const TextStyle(
                    color: Color(0xFF5B6474),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFDCE9FF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildReceiptLine('Tipo', payment.type),
                      _buildReceiptLine('Valor total', _currency(payment.amount)),
                      if (payment.dailyPaid > 0.009) ...[
                        _buildReceiptLine(
                          'Valor em juros',
                          _currency(math.max(0, payment.interestPaid - payment.dailyPaid)),
                        ),
                        _buildReceiptLine(
                          'Valor em diÃ¡ria',
                          _currency(payment.dailyPaid),
                        ),
                      ] else
                        _buildReceiptLine(
                          'Valor em juros',
                          _currency(payment.interestPaid),
                        ),
                      _buildReceiptLine(
                        'Valor em principal',
                        _currency(payment.principalPaid),
                      ),
                      if (payment.note.trim().isNotEmpty)
                        _buildReceiptLine('Observação', payment.note.trim()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: receiptText));
              if (mounted) {
                _showSnack(
                  'O comprovante foi copiado para a area de transferencia.',
                  tone: _FeedbackTone.success,
                  title: 'Comprovante copiado',
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar comprovante'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final allowed = await _ensurePlanAccess(
                requiredPlan: AppPlan.premium,
                featureTitle: 'Comprovante em PDF',
                description:
                    'O download do comprovante em PDF faz parte do plano Premium, pensado para um uso mais profissional da carteira.',
              );
              if (!allowed) return;
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              await _downloadPaymentReceiptPdf(client, payment);
            },
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('Baixar PDF'),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: Color(0xFF111827),
            height: 1.45,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String _buildExportFileName(String prefix, String extension) {
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${prefix}_$stamp.$extension';
  }

  Future<void> _downloadTextExport({
    required String content,
    required String fileName,
    required String mimeType,
    required String successTitle,
  }) async {
    final path = await saveFileBytes(
      bytes: Uint8List.fromList(utf8.encode(content)),
      fileName: fileName,
      mimeType: mimeType,
    );

    if (!mounted) return;

    if (path == null) {
      _showSnack(
        'Nao foi possivel salvar o arquivo neste dispositivo.',
        tone: _FeedbackTone.error,
        title: 'Falha ao baixar arquivo',
      );
      return;
    }

    _showSnack(
      'Arquivo salvo com sucesso: $path',
      tone: _FeedbackTone.success,
      title: successTitle,
    );
  }

  Future<void> _downloadPdfExport({
    required Uint8List bytes,
    required String fileName,
    required String successTitle,
  }) async {
    final path = await saveFileBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/pdf',
    );

    if (!mounted) return;

    if (path == null) {
      _showSnack(
        'Nao foi possivel salvar o PDF neste dispositivo.',
        tone: _FeedbackTone.error,
        title: 'Falha ao baixar PDF',
      );
      return;
    }

    _showSnack(
      'PDF salvo com sucesso: $path',
      tone: _FeedbackTone.success,
      title: successTitle,
    );
  }

  Future<void> _downloadBackupFile() async {
    await _downloadTextExport(
      content: _buildBackupPayload(),
      fileName: _buildExportFileName('cobreja_backup', 'json'),
      mimeType: 'application/json',
      successTitle: 'Backup baixado',
    );
  }

  Future<void> _downloadLegacyLocalBackupFile() async {
    try {
      final payload = await _buildLegacyLocalBackupPayload();
      if (payload == null) {
        _showSnack(
          'Nao encontrei dados antigos salvos localmente nesta instalacao.',
          tone: _FeedbackTone.warning,
          title: 'Backup antigo nao encontrado',
        );
        return;
      }

      await _downloadTextExport(
        content: payload,
        fileName: _buildExportFileName('cobreja_backup_local_antigo', 'json'),
        mimeType: 'application/json',
        successTitle: 'Backup antigo baixado',
      );
    } catch (_) {
      _showSnack(
        'Encontrei a chave antiga, mas ela nao esta em um formato valido de backup.',
        tone: _FeedbackTone.error,
        title: 'Falha ao recuperar',
      );
    }
  }

  Future<void> _exportCsvReport() async {
    final payload = _buildCsvPayload();
    await Clipboard.setData(ClipboardData(text: payload));
    await _downloadTextExport(
      content: payload,
      fileName: _buildExportFileName('cobreja_relatorio_simples', 'csv'),
      mimeType: 'text/csv',
      successTitle: 'CSV salvo',
    );
    if (!mounted) return;
    _showSnack(
      'O relatorio CSV foi copiado e baixado em arquivo.',
      tone: _FeedbackTone.success,
      title: 'CSV copiado',
    );
  }

  Future<void> _exportPdfReport() async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy');
    final clients = [..._clients]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text(
            'COBREJA - Relatorio da carteira',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}'),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColor.fromHex('#DCE9FF')),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Resumo financeiro', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text('Total a receber: ${_currency(_metrics.totalToReceive)}'),
                pw.Text('Total recebido: ${_currency(_metrics.totalReceived)}'),
                pw.Text('Total em atraso: ${_currency(_metrics.totalOverdue)}'),
                pw.Text('Lucro gerado: ${_currency(_metrics.totalProfit)}'),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['Cliente', 'Status', 'Emprestimo', 'Vencimento', 'Principal', 'Juros', 'Total'],
            data: clients.map((client) {
              final debt = FinanceService.calculateDebt(client);
              return [
                client.name,
                client.status,
                dateFormat.format(client.borrowedDate),
                dateFormat.format(client.dueDate),
                _currency(debt.remainingPrincipal),
                _currency(debt.totalInterestDue),
                _currency(debt.totalDebt),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF061C3D)),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(6),
            border: pw.TableBorder.all(color: PdfColor.fromHex('#DCE9FF')),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await _downloadPdfExport(
      bytes: bytes,
      fileName: _buildExportFileName('cobreja_relatorio_simples', 'pdf'),
      successTitle: 'PDF salvo',
    );
  }
  DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  _ResolvedReportPeriod _resolveReportPeriod(
    _ReportPeriodPreset preset, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final now = DateTime.now();
    final today = _dateOnly(now);

    switch (preset) {
      case _ReportPeriodPreset.todoPeriodo:
        return const _ResolvedReportPeriod(
          startDate: null,
          endDate: null,
          label: 'Todo o período',
        );
      case _ReportPeriodPreset.hoje:
        return _ResolvedReportPeriod(
          startDate: today,
          endDate: today,
          label: 'Hoje',
        );
      case _ReportPeriodPreset.ultimos7Dias:
        return _ResolvedReportPeriod(
          startDate: today.subtract(const Duration(days: 6)),
          endDate: today,
          label: 'Últimos 7 dias',
        );
      case _ReportPeriodPreset.ultimos30Dias:
        return _ResolvedReportPeriod(
          startDate: today.subtract(const Duration(days: 29)),
          endDate: today,
          label: 'Últimos 30 dias',
        );
      case _ReportPeriodPreset.esteMes:
        return _ResolvedReportPeriod(
          startDate: DateTime(today.year, today.month, 1),
          endDate: today,
          label: 'Este mês',
        );
      case _ReportPeriodPreset.personalizado:
        if (customStart == null || customEnd == null) {
          return const _ResolvedReportPeriod(
            startDate: null,
            endDate: null,
            label: 'Período personalizado',
          );
        }
        final start = _dateOnly(customStart);
        final end = _dateOnly(customEnd);
        return _ResolvedReportPeriod(
          startDate: start.isBefore(end) ? start : end,
          endDate: start.isBefore(end) ? end : start,
          label: 'Período personalizado',
        );
    }
  }

  bool _isWithinReportRange(
    DateTime value, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final date = _dateOnly(value);
    if (startDate != null && date.isBefore(_dateOnly(startDate))) {
      return false;
    }
    if (endDate != null && date.isAfter(_dateOnly(endDate))) {
      return false;
    }
    return true;
  }

  List<Client> _reportClients({String? clientId}) {
    final clients = clientId == null
        ? [..._clients]
        : _clients.where((client) => client.id == clientId).toList();
    clients.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return clients;
  }

  List<Map<String, dynamic>> _reportPayments({
    String? clientId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final entries = <Map<String, dynamic>>[];
    for (final client in _reportClients(clientId: clientId)) {
      for (final payment in client.paymentHistory) {
        if (!_isWithinReportRange(
          payment.date,
          startDate: startDate,
          endDate: endDate,
        )) {
          continue;
        }
        entries.add({'client': client, 'payment': payment});
      }
    }

    entries.sort((a, b) {
      final paymentA = a['payment'] as PaymentRecord;
      final paymentB = b['payment'] as PaymentRecord;
      return paymentB.date.compareTo(paymentA.date);
    });

    return entries;
  }

  String _reportClientLabel(String? clientId) {
    if (clientId == null) return 'Todos os clientes';
    final client = _clients.cast<Client?>().firstWhere(
      (item) => item?.id == clientId,
      orElse: () => null,
    );
    if (client == null) return 'Cliente selecionado';
    return '${client.name} • ${DateFormat('dd/MM/yyyy').format(client.borrowedDate)}';
  }

  String _buildDetailedCsvPayload({
    String? clientId,
    DateTime? startDate,
    DateTime? endDate,
    required String periodLabel,
  }) {
    final clients = _reportClients(clientId: clientId);
    final payments = _reportPayments(
      clientId: clientId,
      startDate: startDate,
      endDate: endDate,
    );
    final interestReceived = payments.fold<double>(
      0,
      (sum, entry) => sum + (entry['payment'] as PaymentRecord).interestPaid,
    );
    final principalReceived = payments.fold<double>(
      0,
      (sum, entry) => sum + (entry['payment'] as PaymentRecord).principalPaid,
    );
    final totalReceived = payments.fold<double>(
      0,
      (sum, entry) => sum + (entry['payment'] as PaymentRecord).amount,
    );

    final buffer = StringBuffer();
    buffer.writeln('Relatorio,COBREJA');
    buffer.writeln('Cliente,${_escapeCsvField(_reportClientLabel(clientId))}');
    buffer.writeln('Periodo,${_escapeCsvField(periodLabel)}');
    buffer.writeln('Data de emissao,${_escapeCsvField(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()))}');
    buffer.writeln('');
    buffer.writeln('Resumo,Valor');
    buffer.writeln('Clientes selecionados,${clients.length}');
    buffer.writeln('Pagamentos no periodo,${payments.length}');
    buffer.writeln('Total recebido,${_escapeCsvField(totalReceived.toStringAsFixed(2))}');
    buffer.writeln('Juros recebidos,${_escapeCsvField(interestReceived.toStringAsFixed(2))}');
    buffer.writeln('Principal recebido,${_escapeCsvField(principalReceived.toStringAsFixed(2))}');
    buffer.writeln('');
    buffer.writeln('Carteira atual');
    buffer.writeln('Nome,Telefone,Status,Emprestimo,Vencimento,Principal em aberto,Juros em aberto,Total atualizado,Renegociado,Parcelas');

    for (final client in clients) {
      final debt = FinanceService.calculateDebt(client);
      final installmentLabel = client.isNegotiated
          ? '${client.installmentsPaid}/${client.installmentCount}'
          : '-';
      buffer.writeln([
        client.name,
        client.phone,
        client.status,
        DateFormat('dd/MM/yyyy').format(client.borrowedDate),
        DateFormat('dd/MM/yyyy').format(client.dueDate),
        debt.remainingPrincipal.toStringAsFixed(2),
        debt.totalInterestDue.toStringAsFixed(2),
        debt.totalDebt.toStringAsFixed(2),
        client.isNegotiated ? 'Sim' : 'Nao',
        installmentLabel,
      ].map(_escapeCsvField).join(','));
    }

    buffer.writeln('');
    buffer.writeln('Pagamentos no periodo');
    buffer.writeln('Data,Cliente,Tipo,Valor,Juros,Principal,Observacao');

    for (final entry in payments) {
      final client = entry['client'] as Client;
      final payment = entry['payment'] as PaymentRecord;
      buffer.writeln([
        DateFormat('dd/MM/yyyy HH:mm').format(payment.date),
        client.name,
        payment.type,
        payment.amount.toStringAsFixed(2),
        payment.interestPaid.toStringAsFixed(2),
        payment.principalPaid.toStringAsFixed(2),
        payment.note,
      ].map((value) => _escapeCsvField(value.toString())).join(','));
    }

    return buffer.toString();
  }

  Future<void> _exportDetailedCsvReport({
    String? clientId,
    DateTime? startDate,
    DateTime? endDate,
    required String periodLabel,
  }) async {
    final payload = _buildDetailedCsvPayload(
      clientId: clientId,
      startDate: startDate,
      endDate: endDate,
      periodLabel: periodLabel,
    );
    await Clipboard.setData(ClipboardData(text: payload));
    await _downloadTextExport(
      content: payload,
      fileName: _buildExportFileName('cobreja_relatorio_detalhado', 'csv'),
      mimeType: 'text/csv',
      successTitle: 'CSV detalhado salvo',
    );
    if (!mounted) return;
    _showSnack(
      'O relatorio detalhado em CSV foi copiado e baixado em arquivo.',
      tone: _FeedbackTone.success,
      title: 'CSV detalhado copiado',
    );
  }

  Future<void> _exportDetailedPdfReport({
    String? clientId,
    DateTime? startDate,
    DateTime? endDate,
    required String periodLabel,
  }) async {
    final clients = _reportClients(clientId: clientId);
    final payments = _reportPayments(
      clientId: clientId,
      startDate: startDate,
      endDate: endDate,
    );
    final interestReceived = payments.fold<double>(
      0,
      (sum, entry) => sum + (entry['payment'] as PaymentRecord).interestPaid,
    );
    final principalReceived = payments.fold<double>(
      0,
      (sum, entry) => sum + (entry['payment'] as PaymentRecord).principalPaid,
    );
    final totalReceived = payments.fold<double>(
      0,
      (sum, entry) => sum + (entry['payment'] as PaymentRecord).amount,
    );

    final pdf = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text(
            'COBREJA - Relatorio detalhado',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Cliente: ${_reportClientLabel(clientId)}'),
          pw.Text('Periodo: $periodLabel'),
          pw.Text('Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}'),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColor.fromHex('#DCE9FF')),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Resumo do periodo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text('Clientes selecionados: ${clients.length}'),
                pw.Text('Pagamentos encontrados: ${payments.length}'),
                pw.Text('Total recebido: ${_currency(totalReceived)}'),
                pw.Text('Juros recebidos: ${_currency(interestReceived)}'),
                pw.Text('Principal recebido: ${_currency(principalReceived)}'),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text('Carteira atual', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['Cliente', 'Status', 'Vencimento', 'Principal', 'Juros', 'Total'],
            data: clients.map((client) {
              final debt = FinanceService.calculateDebt(client);
              return [
                client.name,
                client.status,
                dateFormat.format(client.dueDate),
                _currency(debt.remainingPrincipal),
                _currency(debt.totalInterestDue),
                _currency(debt.totalDebt),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF061C3D)),
            cellPadding: const pw.EdgeInsets.all(6),
            border: pw.TableBorder.all(color: PdfColor.fromHex('#DCE9FF')),
          ),
          pw.SizedBox(height: 18),
          pw.Text('Pagamentos do periodo', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (payments.isEmpty)
            pw.Text('Nenhum pagamento encontrado para esse filtro.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Data', 'Cliente', 'Tipo', 'Valor', 'Juros', 'Principal'],
              data: payments.map((entry) {
                final client = entry['client'] as Client;
                final payment = entry['payment'] as PaymentRecord;
                return [
                  DateFormat('dd/MM/yyyy').format(payment.date),
                  client.name,
                  payment.type,
                  _currency(payment.amount),
                  _currency(payment.interestPaid),
                  _currency(payment.principalPaid),
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF22C55E)),
              cellPadding: const pw.EdgeInsets.all(6),
              border: pw.TableBorder.all(color: PdfColor.fromHex('#DCE9FF')),
            ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await _downloadPdfExport(
      bytes: bytes,
      fileName: _buildExportFileName('cobreja_relatorio_detalhado', 'pdf'),
      successTitle: 'PDF detalhado salvo',
    );
  }

  void _showDetailedReportsDialog() {
    if (!_hasPlanAccess(AppPlan.premium)) {
      _ensurePlanAccess(
        requiredPlan: AppPlan.premium,
        featureTitle: 'Relatórios completos',
        description:
            'Os relatórios detalhados por cliente e período ajudam a vender mais valor para quem precisa de visão gerencial da carteira.',
      );
      return;
    }

    String? selectedClientId;
    var selectedPreset = _ReportPeriodPreset.ultimos30Dias;
    DateTime? customStart;
    DateTime? customEnd;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          final resolved = _resolveReportPeriod(
            selectedPreset,
            customStart: customStart,
            customEnd: customEnd,
          );
          final selectedClients = _reportClients(clientId: selectedClientId);
          final selectedPayments = _reportPayments(
            clientId: selectedClientId,
            startDate: resolved.startDate,
            endDate: resolved.endDate,
          );

          Future<void> pickDate({required bool isStart}) async {
            final initialDate = isStart
                ? (customStart ?? DateTime.now())
                : (customEnd ?? customStart ?? DateTime.now());
            final picked = await showDatePicker(
              context: dialogContext,
              initialDate: initialDate,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked == null) return;
            setDialog(() {
              if (isStart) {
                customStart = picked;
              } else {
                customEnd = picked;
              }
            });
          }

          return AlertDialog(
            title: const Text('Relatorios detalhados'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filtre por cliente e periodo para gerar um relatorio mais completo da carteira e dos recebimentos.',
                      style: TextStyle(color: Color(0xFF5B6474), height: 1.45),
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedClientId,
                      decoration: const InputDecoration(labelText: 'Cliente'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Todos os clientes'),
                        ),
                        ..._clients.map(
                          (client) => DropdownMenuItem<String?>(
                            value: client.id,
                            child: Text(
                              '${client.name} • ${DateFormat('dd/MM/yyyy').format(client.borrowedDate)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setDialog(() => selectedClientId = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<_ReportPeriodPreset>(
                      initialValue: selectedPreset,
                      decoration: const InputDecoration(labelText: 'Período'),
                      items: const [
                        DropdownMenuItem(
                          value: _ReportPeriodPreset.todoPeriodo,
                          child: Text('Todo o período'),
                        ),
                        DropdownMenuItem(
                          value: _ReportPeriodPreset.hoje,
                          child: Text('Hoje'),
                        ),
                        DropdownMenuItem(
                          value: _ReportPeriodPreset.ultimos7Dias,
                          child: Text('Últimos 7 dias'),
                        ),
                        DropdownMenuItem(
                          value: _ReportPeriodPreset.ultimos30Dias,
                          child: Text('Últimos 30 dias'),
                        ),
                        DropdownMenuItem(
                          value: _ReportPeriodPreset.esteMes,
                          child: Text('Este mês'),
                        ),
                        DropdownMenuItem(
                          value: _ReportPeriodPreset.personalizado,
                          child: Text('Personalizado'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialog(() => selectedPreset = value);
                      },
                    ),
                    if (selectedPreset == _ReportPeriodPreset.personalizado) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickDate(isStart: true),
                              icon: const Icon(Icons.event_rounded),
                              label: Text(
                                customStart == null
                                    ? 'Data inicial'
                                    : DateFormat('dd/MM/yyyy').format(customStart!),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickDate(isStart: false),
                              icon: const Icon(Icons.event_available_rounded),
                              label: Text(
                                customEnd == null
                                    ? 'Data final'
                                    : DateFormat('dd/MM/yyyy').format(customEnd!),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAFF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDCE9FF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _reportClientLabel(selectedClientId),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            resolved.label,
                            style: const TextStyle(color: Color(0xFF5B6474)),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${selectedClients.length} cliente(s) • ${selectedPayments.length} pagamento(s) no período',
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fechar'),
              ),
              OutlinedButton.icon(
                onPressed: selectedPreset == _ReportPeriodPreset.personalizado && (customStart == null || customEnd == null)
                    ? null
                    : () async {
                        await _exportDetailedCsvReport(
                          clientId: selectedClientId,
                          startDate: resolved.startDate,
                          endDate: resolved.endDate,
                          periodLabel: resolved.label,
                        );
                      },
                icon: const Icon(Icons.table_rows_rounded),
                label: const Text('CSV detalhado'),
              ),
              FilledButton.icon(
                onPressed: selectedPreset == _ReportPeriodPreset.personalizado && (customStart == null || customEnd == null)
                    ? null
                    : () async {
                        await _exportDetailedPdfReport(
                          clientId: selectedClientId,
                          startDate: resolved.startDate,
                          endDate: resolved.endDate,
                          periodLabel: resolved.label,
                        );
                      },
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('PDF detalhado'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBackupCenter() {
    showDialog(
      context: context,
      builder: (context) {
        final media = MediaQuery.of(context);
        final maxDialogHeight = math.min(media.size.height * 0.72, 560.0);
        return AlertDialog(
          title: const Text('Backup dos dados'),
          content: SizedBox(
            width: 460,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxDialogHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFDCE9FF)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Proteja sua carteira',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Exporte seus clientes e lembretes em JSON para guardar uma copia segura ou restaurar depois.',
                      style: TextStyle(
                        color: Color(0xFF5B6474),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      _showExportBackupDialog();
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Exportar backup'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _downloadBackupFile();
                  },
                  icon: const Icon(Icons.download_for_offline_rounded),
                  label: const Text('Baixar backup .json'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _downloadLegacyLocalBackupFile();
                  },
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Recuperar backup antigo local'),
                ),
              ),
                const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showMonthlyReceiptsOverviewDialog();
                  },
                  icon: const Icon(Icons.insights_rounded),
                  label: const Text('Recebimentos mensais'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showDetailedReportsDialog();
                  },
                  icon: const Icon(Icons.analytics_rounded),
                  label: const Text('Relatorios completos'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final allowed = await _ensurePlanAccess(
                      requiredPlan: AppPlan.professional,
                      featureTitle: 'Exportar CSV simples',
                      description:
                          'A exportação simples em CSV é um recurso do Profissional para levar sua carteira ao Excel ou Google Sheets.',
                    );
                    if (!allowed || !context.mounted) return;
                    Navigator.pop(context);
                    await _exportCsvReport();
                  },
                  icon: const Icon(Icons.table_rows_rounded),
                  label: const Text('Exportar CSV simples'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final allowed = await _ensurePlanAccess(
                      requiredPlan: AppPlan.professional,
                      featureTitle: 'Exportar PDF simples',
                      description:
                          'A exportação em PDF ajuda a apresentar a carteira com aparência mais profissional para consulta e impressão.',
                    );
                    if (!allowed || !context.mounted) return;
                    Navigator.pop(context);
                    await _exportPdfReport();
                  },
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Exportar PDF simples'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final allowed = await _ensurePlanAccess(
                      requiredPlan: AppPlan.professional,
                      featureTitle: 'Restaurar backup',
                      description:
                          'A restauração de backup fica liberada no Profissional para recuperar dados e trocar de aparelho com mais segurança.',
                    );
                    if (!allowed || !context.mounted) return;
                    Navigator.pop(context);
                    _showImportBackupDialog();
                  },
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Restaurar backup'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showPrivacyPolicyDialog(this.context);
                  },
                  icon: const Icon(Icons.privacy_tip_rounded),
                  label: const Text('Política de privacidade'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showAccountDeletionInfoDialog(this.context);
                  },
                  icon: const Icon(Icons.manage_accounts_rounded),
                  label: const Text('Como excluir a conta'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: Color(0xFFF1B7B7)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _confirmAccountDeletion();
                  },
                  icon: const Icon(Icons.person_remove_alt_1_rounded),
                  label: const Text('Excluir conta local'),
                ),
              ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  void _showExportBackupDialog() {
    final payload = _buildBackupPayload();
    final controller = TextEditingController(text: payload);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exportar backup'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Copie este conteudo e salve em um local seguro. Ele contem sua carteira e seus lembretes.',
                style: TextStyle(
                  color: Color(0xFF5B6474),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                readOnly: true,
                minLines: 10,
                maxLines: 16,
                decoration: const InputDecoration(
                  labelText: 'Conteudo do backup',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _downloadBackupFile();
              },
              icon: const Icon(Icons.download_for_offline_rounded),
              label: const Text('Baixar .json'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: payload));
                if (!mounted) return;
                Navigator.pop(context);
              _showSnack(
                'O backup foi copiado para a area de transferencia.',
                tone: _FeedbackTone.success,
                title: 'Backup copiado',
              );
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar backup'),
          ),
        ],
      ),
    );
  }

  void _showImportBackupDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar backup'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selecione um arquivo .json exportado pela COBREJA ou cole o conteúdo manualmente. Os dados atuais serão substituídos pelos dados do backup.',
                style: TextStyle(
                  color: Color(0xFF5B6474),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _pickAndRestoreBackupFile();
                  },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('Selecionar arquivo .json'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ou, se preferir:',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    final clipboardText = data?.text?.trim() ?? '';
                    if (clipboardText.isEmpty) {
                      _showSnack(
                        'Não encontrei conteúdo na área de transferência.',
                        tone: _FeedbackTone.warning,
                        title: 'Área de transferência vazia',
                      );
                      return;
                    }
                    controller.text = clipboardText;
                    controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: controller.text.length),
                    );
                    _showSnack(
                      'O conteúdo copiado foi colado no campo de backup.',
                      tone: _FeedbackTone.success,
                      title: 'Conteúdo colado',
                    );
                  },
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('Colar da área de transferência'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 10,
                maxLines: 16,
                decoration: const InputDecoration(
                  labelText: 'Cole o backup aqui',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              _restoreBackup(controller.text);
            },
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Restaurar agora'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndRestoreBackupFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      final content =
          file.bytes == null ? null : utf8.decode(file.bytes!);

      if (content == null || content.trim().isEmpty) {
        _showSnack(
          'Não foi possível ler esse arquivo de backup.',
          tone: _FeedbackTone.error,
          title: 'Arquivo inválido',
        );
        return;
      }

      await _restoreBackup(content);
    } catch (_) {
      _showSnack(
        'Não foi possível abrir esse arquivo agora. Tente novamente ou use a opção de colar o backup.',
        tone: _FeedbackTone.error,
        title: 'Falha ao selecionar arquivo',
      );
    }
  }

  Future<void> _restoreBackup(String rawBackup) async {
    final raw = rawBackup.trim();
    if (raw.isEmpty) {
      _showSnack(
        'Cole um backup valido antes de restaurar os dados.',
        tone: _FeedbackTone.warning,
        title: 'Backup vazio',
      );
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Formato invalido.');
      }

      final clientsRaw = decoded['clients'];
      final remindersRaw = decoded['customReminders'];
      if (clientsRaw is! List) {
        throw const FormatException('Backup sem lista de clientes.');
      }

      final restoredClients = clientsRaw
          .map((item) => Client.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
      final restoredReminders = remindersRaw is List
          ? remindersRaw
              .map((item) => CustomReminder.fromMap(Map<String, dynamic>.from(item as Map)))
              .toList()
          : <CustomReminder>[];

      _clients
        ..clear()
        ..addAll(restoredClients);
      _customReminders = restoredReminders;
      _searchController?.clear();
      _searchQuery = '';
      _activeQuickFilter = _ClientQuickFilter.todos;
      await _saveClients();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {});
      _showSnack(
        'Os dados do backup foram restaurados com sucesso.',
        tone: _FeedbackTone.success,
        title: 'Backup restaurado',
      );
    } catch (_) {
      _showSnack(
        'Nao foi possivel restaurar esse backup. Verifique o conteudo e tente novamente.',
        tone: _FeedbackTone.error,
        title: 'Falha ao restaurar',
      );
    }
  }
  void _showReminderCenter() {
    final reminders = _reminders;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Central de lembretes')),
            IconButton(
              tooltip: 'Criar novo lembrete',
              onPressed: () async {
                final allowed = await _ensurePlanAccess(
                  requiredPlan: AppPlan.professional,
                  featureTitle: 'Lembretes personalizados',
                  description:
                      'O plano Profissional libera a criação de lembretes próprios além dos alertas automáticos da carteira.',
                );
                if (!allowed || !context.mounted) return;
                Navigator.pop(context);
                _showCreateReminderDialog();
              },
              icon: const Icon(Icons.add_alert_rounded),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: (_safeCustomReminders.isEmpty && reminders.isEmpty)
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nenhum alerta no momento.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        final allowed = await _ensurePlanAccess(
                          requiredPlan: AppPlan.professional,
                          featureTitle: 'Lembretes personalizados',
                          description:
                              'Esse recurso pertence ao plano Profissional e ajuda a organizar cobranças e tarefas fora do fluxo automático.',
                        );
                        if (!allowed || !context.mounted) return;
                        Navigator.pop(context);
                        _showCreateReminderDialog();
                      },
                      icon: const Icon(Icons.add_alert_rounded),
                      label: const Text('Criar lembrete'),
                    ),
                  ],
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    if (_safeCustomReminders.isNotEmpty) ...[
                      const Text(
                        'Lembretes personalizados',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      ..._safeCustomReminders.map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE8F1FF),
                            child: Icon(
                              Icons.edit_calendar_rounded,
                              color: Color(0xFF061C3D),
                            ),
                          ),
                          title: Text(item.title),
                          subtitle: Text(item.description),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar lembrete',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  final allowed = await _ensurePlanAccess(
                                    requiredPlan: AppPlan.professional,
                                    featureTitle: 'Editar lembretes',
                                    description:
                                        'A edição de lembretes personalizados faz parte do plano Profissional.',
                                  );
                                  if (!allowed || !context.mounted) return;
                                  Navigator.pop(context);
                                  _showEditReminderDialog(item);
                                },
                              ),
                              IconButton(
                                tooltip: 'Excluir lembrete',
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _deleteReminder(item.id);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_safeCustomReminders.isNotEmpty && reminders.isNotEmpty)
                      const Divider(height: 24),
                    if (reminders.isNotEmpty) ...[
                      const Text(
                        'Alertas automáticos',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      ...reminders.map(
                        (reminder) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: reminder.color.withOpacity(0.12),
                            child: Icon(Icons.notifications, color: reminder.color),
                          ),
                          title: Text(reminder.title),
                          subtitle: Text(reminder.subtitle),
                          trailing: IconButton(
                            tooltip: 'Cobrar no WhatsApp',
                            icon: const Icon(Icons.message_rounded),
                            onPressed: () {
                              Navigator.pop(context);
                              _launchWhatsApp(
                                reminder.client,
                                FinanceService.calculateDebt(reminder.client),
                                automatic: true,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final allowed = await _ensurePlanAccess(
                requiredPlan: AppPlan.professional,
                featureTitle: 'Novo lembrete',
                description:
                    'A criação de lembretes personalizados está disponível a partir do plano Profissional.',
              );
              if (!allowed || !context.mounted) return;
              Navigator.pop(context);
              _showCreateReminderDialog();
            },
            icon: const Icon(Icons.add_alert_rounded),
            label: const Text('Novo lembrete'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showReminderDialog({CustomReminder? reminder}) {
    final isEditing = reminder != null;
    final titleController = TextEditingController(text: reminder?.title ?? '');
    final descriptionController = TextEditingController(
      text: reminder?.description ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Editar lembrete' : 'Criar lembrete'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              final description = descriptionController.text.trim();
              if (title.isEmpty || description.isEmpty) {
                _showSnack('Preencha titulo e descricao para salvar o lembrete.', tone: _FeedbackTone.warning, title: 'Campos pendentes');
                return;
              }

              final updatedReminder = CustomReminder(
                id: reminder?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                title: title,
                description: description,
                createdAt: reminder?.createdAt ?? DateTime.now(),
              );

              final nextReminders = [..._safeCustomReminders];
              if (isEditing) {
                final index = nextReminders.indexWhere(
                  (item) => item.id == reminder.id,
                );
                if (index >= 0) {
                  nextReminders[index] = updatedReminder;
                } else {
                  nextReminders.insert(0, updatedReminder);
                }
              } else {
                nextReminders.insert(0, updatedReminder);
              }

              _customReminders = nextReminders;
              _saveClients();
              setState(() {});
              Navigator.pop(context);
              _showSnack(
                isEditing
                    ? 'O lembrete foi atualizado com sucesso.'
                    : 'O lembrete foi salvo e ja esta disponivel na central.',
                tone: _FeedbackTone.success,
                title: isEditing ? 'Lembrete atualizado' : 'Lembrete criado',
              );
            },
            child: Text(isEditing ? 'Atualizar' : 'Salvar'),
          ),
        ],
      ),
    );
  }

  void _showCreateReminderDialog() {
    if (!_hasPlanAccess(AppPlan.professional)) {
      _ensurePlanAccess(
        requiredPlan: AppPlan.professional,
        featureTitle: 'Lembretes personalizados',
        description:
            'O plano Profissional libera lembretes manuais para complementar os alertas automáticos.',
      );
      return;
    }
    _showReminderDialog();
  }

  void _showEditReminderDialog(CustomReminder reminder) {
    _showReminderDialog(reminder: reminder);
  }

  void _deleteReminder(String id) {
    _customReminders =
        _safeCustomReminders.where((item) => item.id != id).toList();
    _saveClients();
    setState(() {});
    _showSnack('O lembrete foi removido da central com sucesso.', tone: _FeedbackTone.info, title: 'Lembrete removido');
  }

  void _toggleLossFlag(Client client) {
    final debt = FinanceService.calculateDebt(client);
    if (client.status != 'devendo' || debt.totalDebt <= 0.009) {
      _showSnack('Esse cliente não possui saldo em aberto para entrar no prejuízo.', tone: _FeedbackTone.info, title: 'Nada para marcar');
      return;
    }

    client.isMarkedAsLost = !client.isMarkedAsLostSafe;
    _syncClient(client);

    if (client.isMarkedAsLostSafe) {
      _showSnack('O cliente foi incluído no prejuízo estimado e sai automaticamente se o saldo cair.', tone: _FeedbackTone.warning, title: 'Prejuízo marcado');
    } else {
      _showSnack('O cliente foi removido do prejuízo manual.', tone: _FeedbackTone.success, title: 'Prejuízo removido');
    }
  }

  Future<void> _registerInterestSettlement(Client client) async {
    final clientId = int.tryParse(client.id);
    final token = await _readAuthToken();

    // Backend-first: registra o pagamento no servidor e recarrega a carteira.
    // Se falhar, cai no fluxo local (para nao travar o uso).
    if (clientId != null && token != null && token.isNotEmpty) {
      try {
        final details = await ApiService.fetchClientById(
          token: token,
          clientId: clientId,
        );

        final debts = (details['debts'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        final activeDebts = debts.where((debt) {
          final status = debt['status']?.toString().toUpperCase();
          final deletedAt = debt['deletedAt'];
          return status == 'ACTIVE' &&
              (deletedAt == null || deletedAt.toString().isEmpty);
        }).toList();

        if (activeDebts.isNotEmpty) {
          final primaryDebt = activeDebts.first;
          final debtId = (primaryDebt['id'] as num?)?.toInt();
          final snapshot = primaryDebt['snapshot'] is Map<String, dynamic>
              ? (primaryDebt['snapshot'] as Map<String, dynamic>)
              : null;

          final interestOutstanding = snapshot != null
              ? _readDouble(snapshot['interestOutstanding'])
              : 0.0;
          final dailyAccrued = snapshot != null
              ? _readDouble(snapshot['dailyAccruedAmount'])
              : 0.0;

          if (interestOutstanding <= 0.009) {
            _showSnack(
              'No momento nao ha juros pendentes para este cliente.',
              tone: _FeedbackTone.info,
              title: 'Nada pendente',
            );
            return;
          }

          final totalCycleCharge = interestOutstanding + dailyAccrued;
          final paymentData = await ApiService.createPayment(
            token: token,
            clientId: clientId,
            debtId: debtId,
            amount: totalCycleCharge,
            type: 'juros',
            date: DateTime.now(),
            note: 'Juros pagos e ciclo reiniciado.',
          );

          final paidAt =
              DateTime.tryParse(paymentData['paidAt']?.toString() ?? '') ??
                  DateTime.tryParse(
                        paymentData['createdAt']?.toString() ?? '',
                      ) ??
                  DateTime.now();

          final receipt = PaymentRecord(
            id: paymentData['id']?.toString() ?? '',
            date: paidAt,
            amount: _readDouble(paymentData['amount']),
            interestPaid: _readDouble(paymentData['interestAmount']) +
                _readDouble(paymentData['dailyAmount']),
            dailyPaid: _readDouble(paymentData['dailyAmount']),
            principalPaid: _readDouble(paymentData['principalAmount']),
            type: 'Pagamento de juros',
            note: paymentData['note']?.toString() ?? 'Juros pagos e ciclo reiniciado.',
          );

          await _refreshClientsFromBackend();
          await fetchDashboard();

          _showSnack(
            'O pagamento de juros foi registrado e o ciclo foi atualizado.',
            tone: _FeedbackTone.success,
            title: 'Juros registrados',
          );
          _showPaymentReceiptDialog(client, receipt);
          return;
        }
      } catch (e) {
        debugPrint('Falha ao registrar juros no backend: $e');
        // segue para o fluxo local abaixo
      }
    }

    final debt = FinanceService.calculateDebt(client);
    // "Pagou juros" registra apenas o juro mensal do ciclo atual.
    // A diÃ¡ria (mora) pode ser cobrada separadamente via pagamento parcial.
    if (debt.cycleInterest <= 0) {
      _showSnack('No momento nao ha juros pendentes para este cliente.', tone: _FeedbackTone.info, title: 'Nada pendente');
      return;
    }

    final totalCycleCharge = debt.cycleInterest + debt.lateInterest;
    final receipt = _applyPayment(
      client: client,
      amount: totalCycleCharge,
      mode: PaymentMode.interestOnly,
      note: 'Juros pagos e ciclo reiniciado.',
    );
    _showSnack('O pagamento de juros foi registrado e o ciclo foi atualizado.', tone: _FeedbackTone.success, title: 'Juros registrados');
    if (receipt != null) {
      _showPaymentReceiptDialog(client, receipt);
    }
  }

  void _settleClient(Client client) {
    final debt = FinanceService.calculateDebt(client);
    if (debt.totalDebt <= 0) {
      _showSnack('Este cliente ja esta quitado e nao possui saldo em aberto.', tone: _FeedbackTone.info, title: 'Dívida encerrada');
      return;
    }

    final receipt = _applyPayment(
      client: client,
      amount: debt.totalDebt,
      mode: PaymentMode.settlement,
      note: 'Quitação total da dívida.',
    );
    _showSnack('A dívida foi quitada com sucesso e saiu da carteira ativa.', tone: _FeedbackTone.success, title: 'Cliente quitado');
    if (receipt != null) {
      _showPaymentReceiptDialog(client, receipt);
    }
  }

  void _showPaymentDialog(Client client) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    PaymentMode mode = PaymentMode.automatic;
    final debt = FinanceService.calculateDebt(client);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Registrar pagamento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Em aberto: ${_currency(debt.totalDebt)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Apenas juros: ${_currency(debt.totalInterestDue)} • '
                  'Principal: ${_currency(debt.remainingPrincipal)}',
                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Valor pago'),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildModeChip(
                      label: 'Automático',
                      selected: mode == PaymentMode.automatic,
                      onTap: () => setDialog(() => mode = PaymentMode.automatic),
                    ),
                    _buildModeChip(
                      label: 'Somente juros',
                      selected: mode == PaymentMode.interestOnly,
                      onTap: () =>
                          setDialog(() => mode = PaymentMode.interestOnly),
                    ),
                    _buildModeChip(
                      label: 'Somente principal',
                      selected: mode == PaymentMode.principalOnly,
                      onTap: () =>
                          setDialog(() => mode = PaymentMode.principalOnly),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(labelText: 'Observação'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final amount = _readDouble(amountController.text);
                if (amount <= 0) {
                  _showSnack('Digite um valor maior que zero para registrar o pagamento.', tone: _FeedbackTone.warning, title: 'Valor inválido');
                  return;
                }

                final receipt = _applyPayment(
                  client: client,
                  amount: amount,
                  mode: mode,
                  note: noteController.text.trim(),
                );
                Navigator.pop(context);
                _showSnack('O pagamento foi registrado com sucesso no histórico do cliente.', tone: _FeedbackTone.success, title: 'Pagamento salvo');
                if (receipt != null) {
                  _showPaymentReceiptDialog(client, receipt);
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenegotiateDialog(Client client) {
    if (!_hasPlanAccess(AppPlan.professional)) {
      _ensurePlanAccess(
        requiredPlan: AppPlan.professional,
        featureTitle: 'Renegociação de dívida',
        description:
            'A renegociação parcelada é um recurso do plano Profissional pensado para quem precisa reorganizar dívidas complicadas.',
      );
      return;
    }

    final debt = FinanceService.calculateDebt(client);
    final multiplierController = TextEditingController(text: '1');
    final installmentsController = TextEditingController(text: '10');
    final customTotalController = TextEditingController();
    final dailyLateController = TextEditingController(
      text: client.dailyInterestType == InterestValueType.fixedAmount
          ? client.dailyInterestAmount.toStringAsFixed(2)
          : client.dailyInterestRate.toStringAsFixed(2),
    );
    InterestValueType dailyLateType = client.dailyInterestType;
    DateTime renegotiationDate = DateTime.now();
    DateTime firstInstallmentDate = DateTime.now().add(const Duration(days: 30));

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Renegociar dívida'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dívida atual: ${_currency(debt.totalDebt)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: multiplierController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialog(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Multiplicador da dívida',
                    hintText: 'Ex.: 2 ou 3',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: installmentsController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialog(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Quantidade de parcelas',
                    hintText: 'Ex: 10, 20, 50',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: customTotalController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialog(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Valor final da dívida (opcional)',
                    hintText: 'Se preencher, ele substitui o multiplicador',
                  ),
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final multiplier = _readDouble(multiplierController.text);
                    final installments =
                        int.tryParse(installmentsController.text.trim()) ?? 0;
                    final dailyLateValue = _readDouble(dailyLateController.text);
                    final customTotal = _readDouble(customTotalController.text);
                    final negotiatedTotal = customTotal > 0
                        ? customTotal
                        : multiplier <= 0
                            ? debt.totalDebt
                            : debt.totalDebt * multiplier;
                    final installmentValue = installments <= 0
                        ? 0.0
                        : negotiatedTotal / installments;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAFF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDCE9FF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Prévia da renegociação',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text('Dívida atual: ${_currency(debt.totalDebt)}'),
                          const SizedBox(height: 6),
                          Text(
                            customTotal > 0
                                ? 'Valor final manual: ${_currency(customTotal)}'
                                : 'Multiplicador aplicado: ${multiplier > 0 ? multiplier.toStringAsFixed(multiplier.truncateToDouble() == multiplier ? 0 : 2) : 'Não definido'}x',
                          ),
                          const SizedBox(height: 6),
                          Text('Novo total: ${_currency(negotiatedTotal)}'),
                          const SizedBox(height: 6),
                          Text(
                            'Valor por parcela: ${installmentValue > 0 ? _currency(installmentValue) : 'Defina as parcelas'}',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Empréstimo original: ${DateFormat('dd/MM/yyyy').format(client.borrowedDate)}',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Início da renegociação: ${DateFormat('dd/MM/yyyy').format(renegotiationDate)}',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Primeiro vencimento: ${DateFormat('dd/MM/yyyy').format(firstInstallmentDate)}',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Atraso por dia: ${dailyLateValue > 0 ? _formatInterestRule(type: dailyLateType, percentageValue: dailyLateType == InterestValueType.percentage ? dailyLateValue : 0, amountValue: dailyLateType == InterestValueType.fixedAmount ? dailyLateValue : 0, suffix: 'a.d.') : 'Sem juros diário definido'}',
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: renegotiationDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 3650),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setDialog(() {
                          renegotiationDate = picked;
                          if (firstInstallmentDate.isBefore(renegotiationDate)) {
                            firstInstallmentDate = renegotiationDate;
                          }
                        });
                      }
                    },
                    icon: const Icon(Icons.history_toggle_off_rounded),
                    label: Text(
                      'Início da renegociação: ${DateFormat('dd/MM/yyyy').format(renegotiationDate)}',
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: firstInstallmentDate,
                        firstDate: renegotiationDate,
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setDialog(() {
                          firstInstallmentDate = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.event_note_rounded),
                    label: Text(
                      'Primeira parcela: ${DateFormat('dd/MM/yyyy').format(firstInstallmentDate)}',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Juros diário por atraso da renegociação',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildModeChip(
                      label: 'Em %',
                      selected: dailyLateType == InterestValueType.percentage,
                      onTap: () => setDialog(
                        () => dailyLateType = InterestValueType.percentage,
                      ),
                    ),
                    _buildModeChip(
                      label: 'Em R\$',
                      selected: dailyLateType == InterestValueType.fixedAmount,
                      onTap: () => setDialog(
                        () => dailyLateType = InterestValueType.fixedAmount,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dailyLateController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: dailyLateType == InterestValueType.fixedAmount
                        ? 'Juros diário por atraso (R\$)'
                        : 'Juros diário por atraso (%)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final multiplier = _readDouble(multiplierController.text);
                final installments =
                    int.tryParse(installmentsController.text.trim()) ?? 0;
                final customTotal = _readDouble(customTotalController.text);

                if ((multiplier <= 0 && customTotal <= 0) || installments <= 0) {
                  _showSnack('Informe um valor final da dívida ou um multiplicador, além da quantidade de parcelas.', tone: _FeedbackTone.warning, title: 'Dados inválidos');
                  return;
                }

                _renegotiateClient(
                  client: client,
                  multiplier: multiplier,
                  customNegotiatedTotal: customTotal > 0 ? customTotal : null,
                  installmentCount: installments,
                  renegotiatedAt: renegotiationDate,
                  firstInstallmentDate: firstInstallmentDate,
                  renegotiationDailyInterestType: dailyLateType,
                  renegotiationDailyInterestValue:
                      _readDouble(dailyLateController.text),
                );
                Navigator.pop(context);
              },
              child: const Text('Renegociar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: 'Selecionar: $label',
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  void _renegotiateClient({
    required Client client,
    required double multiplier,
    double? customNegotiatedTotal,
    required int installmentCount,
    required DateTime renegotiatedAt,
    required DateTime firstInstallmentDate,
    required InterestValueType renegotiationDailyInterestType,
    required double renegotiationDailyInterestValue,
  }) {
    final debt = FinanceService.calculateDebt(client);
    final negotiatedTotal =
        customNegotiatedTotal != null && customNegotiatedTotal > 0
            ? customNegotiatedTotal
            : debt.totalDebt * multiplier;
    final installmentAmount = negotiatedTotal / installmentCount;
    final now = DateTime.now();
    final dailyLateRule = renegotiationDailyInterestValue <= 0
        ? 'Sem juros diário por atraso'
        : _formatInterestRule(
            type: renegotiationDailyInterestType,
            percentageValue: renegotiationDailyInterestType ==
                    InterestValueType.percentage
                ? renegotiationDailyInterestValue
                : 0,
            amountValue:
                renegotiationDailyInterestType == InterestValueType.fixedAmount
                    ? renegotiationDailyInterestValue
                    : 0,
            suffix: 'a.d.',
          );

    client.paymentHistory = [
      PaymentRecord(
        id: now.microsecondsSinceEpoch.toString(),
        date: now,
        amount: 0,
        interestPaid: 0,
        principalPaid: 0,
        type: 'Renegociacao',
        note:
            'Dívida renegociada em ${installmentCount}x de ${_currency(installmentAmount)}. Total novo: ${_currency(negotiatedTotal)}.${customNegotiatedTotal != null && customNegotiatedTotal > 0 ? ' Valor final definido manualmente.' : ' Multiplicador aplicado: ${multiplier.toStringAsFixed(multiplier.truncateToDouble() == multiplier ? 0 : 2)}x.'} Início: ${DateFormat('dd/MM/yyyy').format(renegotiatedAt)}. Primeiro vencimento: ${DateFormat('dd/MM/yyyy').format(firstInstallmentDate)}. Atraso diário: $dailyLateRule.',
      ),
      ...client.paymentHistory,
    ];

    client.borrowedAmount = negotiatedTotal;
    client.activePrincipalCollected = 0;
    client.interestPaidCurrentCycle = 0;
    client.monthlyInterestRate = 0;
    client.monthlyInterestAmount = 0;
    client.monthlyInterestType = InterestValueType.fixedAmount;
    client.dailyInterestRate =
        renegotiationDailyInterestType == InterestValueType.percentage
            ? renegotiationDailyInterestValue
            : 0;
    client.dailyInterestAmount =
        renegotiationDailyInterestType == InterestValueType.fixedAmount
            ? renegotiationDailyInterestValue
            : 0;
    client.dailyInterestType = renegotiationDailyInterestType;
    client.renegotiatedAt = renegotiatedAt;
    client.cycleStartDate = renegotiatedAt;
    client.dueDate = firstInstallmentDate;
    client.originalTermDays = 30;
    client.pagouJuros = false;
    client.isNegotiated = true;
    client.installmentCount = installmentCount;
    client.installmentsPaid = 0;
    client.installmentAmount = installmentAmount;
    client.installmentStartDate = firstInstallmentDate;
    client.status = 'devendo';

    _syncClient(client);
    final clientId = int.tryParse(client.id);
    if (clientId != null) {
      _syncRenegotiationToBackend(
        clientId: clientId,
        newTotal: negotiatedTotal,
        newDueDate: firstInstallmentDate,
      );
    }
    _showSnack('A renegociacao foi aplicada e o novo acordo ja esta valendo.', tone: _FeedbackTone.success, title: 'Dívida renegociada');
  }

  PaymentRecord? _applyPayment({
    required Client client,
    required double amount,
    required PaymentMode mode,
    String note = '',
  }) {
    final now = DateTime.now();
    final debt = FinanceService.calculateDebt(client, now: now);
    final interestOutstanding = debt.cycleInterest;
    final dailyOutstanding = debt.lateInterest;

    double monthlyInterestPaid = 0;
    double dailyPaid = 0;
    double principalPaid = 0;

    switch (mode) {
      case PaymentMode.interestOnly:
        {
          double remaining = amount;
          dailyPaid = math.min(remaining, dailyOutstanding);
          remaining = math.max(0, remaining - dailyPaid);
          monthlyInterestPaid = math.min(remaining, interestOutstanding);
        }
        break;
      case PaymentMode.principalOnly:
        // No backend, pagamentos "parciais" sempre abatem primeiro mora/juros e depois principal.
        // Mantemos esse comportamento para nÃ£o divergir dos cÃ¡lculos oficiais.
        {
          double remaining = amount;
          dailyPaid = math.min(remaining, dailyOutstanding);
          remaining = math.max(0, remaining - dailyPaid);
          monthlyInterestPaid = math.min(remaining, interestOutstanding);
          remaining = math.max(0, remaining - monthlyInterestPaid);
          principalPaid = math.min(remaining, debt.remainingPrincipal);
        }
        break;
      case PaymentMode.automatic:
        {
          double remaining = amount;
          dailyPaid = math.min(remaining, dailyOutstanding);
          remaining = math.max(0, remaining - dailyPaid);
          monthlyInterestPaid = math.min(remaining, interestOutstanding);
          remaining = math.max(0, remaining - monthlyInterestPaid);
          principalPaid = math.min(remaining, debt.remainingPrincipal);
        }
        break;
      case PaymentMode.settlement:
        monthlyInterestPaid = interestOutstanding;
        dailyPaid = dailyOutstanding;
        principalPaid = debt.remainingPrincipal;
        amount = monthlyInterestPaid + dailyPaid + principalPaid;
        break;
    }

    final interestPaid = monthlyInterestPaid + dailyPaid;

    if (interestPaid <= 0 && principalPaid <= 0) {
      _showSnack('Esse pagamento nao gerou abatimento nem juros registrados.', tone: _FeedbackTone.warning, title: 'Nada para registrar');
      return null;
    }

    final paymentRecord = PaymentRecord(
      id: now.microsecondsSinceEpoch.toString(),
      date: now,
      amount: interestPaid + principalPaid,
      interestPaid: interestPaid,
      dailyPaid: dailyPaid,
      principalPaid: principalPaid,
      type: _paymentModeLabel(mode),
      note: note,
    );

    // No backend, `currentCycleInterestPaid` registra apenas o juro mensal (sem a mora diÃ¡ria).
    client.interestPaidCurrentCycle += monthlyInterestPaid;
    client.totalInterestCollected += interestPaid;
    client.totalPrincipalCollected += principalPaid;
    client.activePrincipalCollected += principalPaid;
    client.paymentHistory = [
      paymentRecord,
      ...client.paymentHistory,
    ];

    final dailySettled =
        dailyOutstanding <= 0.009 || dailyPaid >= dailyOutstanding - 0.01;
    final isCurrentInterestSettled = monthlyInterestPaid > 0 &&
        interestOutstanding > 0 &&
        monthlyInterestPaid >= interestOutstanding - 0.01 &&
        dailySettled;

    if (isCurrentInterestSettled && client.remainingPrincipal > 0.009) {
      final previousDueDate = client.dueDate;
      client.interestPaidCurrentCycle = 0;
      client.pagouJuros = true;
      client.lastInterestPaidAt = previousDueDate;
      client.cycleStartDate = previousDueDate;
      client.dueDate = _nextMonthlyDueDate(
        client,
        fromDate: previousDueDate,
      );
    }

    if (principalPaid > 0 && !isCurrentInterestSettled) {
      client.pagouJuros = false;
    }

    if (client.isNegotiated &&
        client.installmentCount > 0 &&
        client.installmentAmount > 0 &&
        client.installmentStartDate != null) {
      final paidInstallments =
          (client.activePrincipalCollected / client.installmentAmount).floor();
      client.installmentsPaid = math.min(client.installmentCount, paidInstallments);
      if (client.installmentsPaid < client.installmentCount) {
        client.dueDate = client.installmentStartDate!.add(
          Duration(days: 30 * client.installmentsPaid),
        );
      }
    }

      if (client.remainingPrincipal <= 0.009) {
        client.status = 'quitado';
        client.pagouJuros = false;
        client.interestPaidCurrentCycle = 0;
      client.installmentsPaid = client.installmentCount;
    } else if (client.status != 'excluído') {
      client.status = 'devendo';
    }

    _syncClient(client);
    final clientId = int.tryParse(client.id);
    if (clientId != null) {
      _syncPaymentToBackend(
        clientId: clientId,
        debtId: client.backendPrimaryDebtId,
        amount: paymentRecord.amount,
        type: _backendPaymentType(mode),
        date: paymentRecord.date,
        note: note,
      );
    }
    return paymentRecord;
  }

  String _backendPaymentType(PaymentMode mode) {
    switch (mode) {
      case PaymentMode.settlement:
        return 'total';
      case PaymentMode.interestOnly:
        return 'juros';
      case PaymentMode.principalOnly:
      case PaymentMode.automatic:
        return 'parcial';
    }
  }

  void _syncPaymentToBackend({
    required int clientId,
    required double amount,
    required String type,
    required DateTime date,
    int? debtId,
    int? installmentId,
    String? note,
  }) async {
    try {
      final token = await _readAuthToken();
      if (token == null || token.isEmpty) return;
      await ApiService.createPayment(
        token: token,
        clientId: clientId,
        debtId: debtId,
        installmentId: installmentId,
        amount: amount,
        type: type,
        date: date,
        note: note,
      );
      await _refreshClientsFromBackend();
      await fetchDashboard();
    } catch (e) {
      debugPrint('Falha ao registrar pagamento no backend: $e');
      _showSnack(
        'Pagamento salvo localmente, mas falhou no backend.',
        tone: _FeedbackTone.warning,
        title: 'Sincronização pendente',
      );
    }
  }

  void _syncRenegotiationToBackend({
    required int clientId,
    required double newTotal,
    required DateTime newDueDate,
  }) async {
    try {
      final token = await _readAuthToken();
      if (token == null || token.isEmpty) return;
      await ApiService.createRenegotiation(
        token: token,
        clientId: clientId,
        newTotal: newTotal,
        newDueDate: newDueDate,
      );
      await _refreshClientsFromBackend();
      await fetchDashboard();
    } catch (e) {
      debugPrint('Falha ao registrar renegociacao no backend: $e');
      _showSnack(
        'Renegociacao salva localmente, mas falhou no backend.',
        tone: _FeedbackTone.warning,
        title: 'Sincronização pendente',
      );
    }
  }

  String _paymentModeLabel(PaymentMode mode) {
    switch (mode) {
      case PaymentMode.interestOnly:
        return 'Pagamento de juros';
      case PaymentMode.principalOnly:
        return 'Abatimento no principal';
      case PaymentMode.automatic:
        return 'Pagamento parcial';
      case PaymentMode.settlement:
        return 'Quitação';
    }
  }

  Future<void> _launchWhatsApp(
    Client client,
    DebtSummary debt, {
    bool automatic = false,
    bool includeRelatedDebts = false,
  }) async {
    final relatedClients = includeRelatedDebts
        ? _buildRelatedChargeClients(client)
        : [client];
    final chargeMode = automatic
        ? await _showChargeModeSelector(client, relatedClients)
        : _ChargeCollectionMode.total;

    if (automatic && chargeMode == null) {
      return;
    }

    final resolvedMode = chargeMode ?? _ChargeCollectionMode.total;
    final totalDebt = _calculateChargeAmount(relatedClients, resolvedMode);

    if (totalDebt <= 0.009) {
      final warning = resolvedMode == _ChargeCollectionMode.installment
          ? 'Nao encontrei parcelas em aberto para cobrar dessa pessoa agora.'
          : resolvedMode == _ChargeCollectionMode.interestOnly
              ? 'Nao ha juros do mês pendentes para essa cobranca neste momento.'
              : resolvedMode == _ChargeCollectionMode.currentCycle
                  ? 'Nao ha valor do ciclo atual para cobrar agora.'
                  : resolvedMode == _ChargeCollectionMode.dailyOnly
                      ? 'Nao ha diária acumulada para essa cobranca neste momento.'
              : 'Nao encontrei valores em aberto para essa cobranca.';
      _showSnack(
        warning,
        tone: _FeedbackTone.warning,
        title: 'Nada para cobrar',
      );
      return;
    }

    final message = automatic
        ? _buildAutomaticChargeMessage(
            client,
            relatedClients,
            resolvedMode,
          )
        : _buildManualChargeMessage(client, relatedClients, debt);
    final pixPayload = _buildPixPayload(totalDebt);

    if (!mounted) return;

    await _showPixChargePreview(
      client: client,
      message: message,
      pixPayload: pixPayload,
      totalDebt: totalDebt,
      chargeMode: resolvedMode,
    );
  }

  Future<_ChargeCollectionMode?> _showChargeModeSelector(
    Client client,
    List<Client> relatedClients,
  ) async {
    final selectedDebt = FinanceService.calculateDebt(client);
    final totalAmount = _calculateChargeAmount(
      relatedClients,
      _ChargeCollectionMode.total,
    );
    final interestAmount = _calculateChargeAmount(
      relatedClients,
      _ChargeCollectionMode.interestOnly,
    );
    final currentCycleAmount = _calculateChargeAmount(
      relatedClients,
      _ChargeCollectionMode.currentCycle,
    );
    final dailyOnlyAmount = _calculateChargeAmount(
      relatedClients,
      _ChargeCollectionMode.dailyOnly,
    );
    final installmentAmount = _calculateChargeAmount(
      relatedClients,
      _ChargeCollectionMode.installment,
    );

    return showDialog<_ChargeCollectionMode>(
      context: context,
      builder: (dialogContext) {
        final screenHeight = MediaQuery.of(dialogContext).size.height;
        final selectedStatusText = selectedDebt.isOverdue
            ? '${selectedDebt.overdueDays} dia(s) de atraso neste débito.'
            : selectedDebt.isDueToday
                ? 'Este débito vence hoje.'
                : 'Este débito está dentro do prazo.';
        return AlertDialog(
          title: const Text('Tipo de cobranca'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: screenHeight * 0.68,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Escolha como deseja cobrar ${client.name} agora.',
                    style: const TextStyle(
                      color: Color(0xFF5B6474),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    selectedStatusText,
                    style: TextStyle(
                      color: selectedDebt.isOverdue
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF5B6474),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildChargeModeOption(
                    context: dialogContext,
                    mode: _ChargeCollectionMode.total,
                    title: 'Cobrar total',
                    subtitle: 'Principal + juros de todos os débitos em aberto.',
                    amount: totalAmount,
                    enabled: totalAmount > 0.009,
                  ),
                  const SizedBox(height: 10),
                  _buildChargeModeOption(
                    context: dialogContext,
                    mode: _ChargeCollectionMode.interestOnly,
                    title: 'Cobrar só juros',
                    subtitle: 'Cobra só o juro do mês, sem incluir a diária.',
                    amount: interestAmount,
                    enabled: interestAmount > 0.009,
                  ),
                  const SizedBox(height: 10),
                  _buildChargeModeOption(
                    context: dialogContext,
                    mode: _ChargeCollectionMode.currentCycle,
                    title: 'Cobrar mês atual',
                    subtitle:
                        'Cobra juros do mês + diária acumulada, sem puxar o principal.',
                    amount: currentCycleAmount,
                    enabled: currentCycleAmount > 0.009,
                  ),
                  const SizedBox(height: 10),
                  _buildChargeModeOption(
                    context: dialogContext,
                    mode: _ChargeCollectionMode.dailyOnly,
                    title: 'Cobrar só diária',
                    subtitle: 'Usa somente a mora pelos dias em atraso.',
                    amount: dailyOnlyAmount,
                    enabled: dailyOnlyAmount > 0.009,
                  ),
                  const SizedBox(height: 10),
                  _buildChargeModeOption(
                    context: dialogContext,
                    mode: _ChargeCollectionMode.installment,
                    title: 'Cobrar parcela',
                    subtitle: 'Usa o valor das parcelas das dívidas renegociadas.',
                    amount: installmentAmount,
                    enabled: installmentAmount > 0.009,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChargeModeOption({
    required BuildContext context,
    required _ChargeCollectionMode mode,
    required String title,
    required String subtitle,
    required double amount,
    required bool enabled,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => Navigator.pop(context, mode) : null,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: enabled ? Colors.white : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: enabled
                  ? const Color(0xFFDCE9FF)
                  : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: enabled
                            ? const Color(0xFF111827)
                            : const Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: enabled
                            ? const Color(0xFF5B6474)
                            : const Color(0xFF9CA3AF),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _currency(amount),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: enabled
                      ? const Color(0xFF061C3D)
                      : const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _calculateChargeAmount(
    List<Client> relatedClients,
    _ChargeCollectionMode mode,
  ) {
    return relatedClients.fold<double>(0, (sum, relatedClient) {
      final debt = FinanceService.calculateDebt(relatedClient);
      final amount = switch (mode) {
        _ChargeCollectionMode.total => debt.totalDebt,
        _ChargeCollectionMode.interestOnly => debt.cycleInterest,
        _ChargeCollectionMode.currentCycle =>
          debt.cycleInterest + debt.lateInterest,
        _ChargeCollectionMode.dailyOnly => debt.lateInterest,
        _ChargeCollectionMode.installment =>
          relatedClient.isNegotiated && relatedClient.installmentAmount > 0
              ? math.min(relatedClient.installmentAmount, debt.totalDebt)
              : 0,
      };
      return sum + amount;
    });
  }

  String _formatPixAmount(double amount) {
    final normalized = amount <= 0 ? 0.01 : amount;
    return normalized.toStringAsFixed(2);
  }

  String _pixField(String id, String value) {
    final length = value.length.toString().padLeft(2, '0');
    return '$id$length$value';
  }

  int _crc16Ccitt(String value) {
    var crc = 0xFFFF;
    for (final codeUnit in value.codeUnits) {
      crc ^= (codeUnit << 8);
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc & 0xFFFF;
  }

  String _buildPixPayload(double amount) {
    final amountText = _formatPixAmount(amount);
    final merchantAccount = _pixField(
      '26',
      '${_pixField('00', 'br.gov.bcb.pix')}${_pixField('01', _pixPrimaryKey)}',
    );
    final additionalData = _pixField('62', _pixField('05', 'COBREJA'));
    final basePayload =
        '${_pixField('00', '01')}'
        '${_pixField('52', '0000')}'
        '${_pixField('53', '986')}'
        '$merchantAccount'
        '${_pixField('54', amountText)}'
        '${_pixField('58', 'BR')}'
        '${_pixField('59', _pixMerchantName)}'
        '${_pixField('60', _pixMerchantCity)}'
        '$additionalData'
        '6304';
    final crc = _crc16Ccitt(basePayload).toRadixString(16).toUpperCase().padLeft(4, '0');
    return '$basePayload$crc';
  }

  Future<void> _showPixChargePreview({
    required Client client,
    required String message,
    required String pixPayload,
    required double totalDebt,
    required _ChargeCollectionMode chargeMode,
  }) async {
    final normalizedPhone = client.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final appUri = Uri.parse(
      'whatsapp://send?phone=$normalizedPhone&text=${Uri.encodeComponent(message)}',
    );
    final webUri = Uri.parse(
      'https://wa.me/$normalizedPhone?text=${Uri.encodeComponent(message)}',
    );

    final chargeModeLabel = switch (chargeMode) {
      _ChargeCollectionMode.total => 'Cobranca total',
      _ChargeCollectionMode.interestOnly => 'Cobranca so de juros',
      _ChargeCollectionMode.currentCycle => 'Cobranca do mes atual',
      _ChargeCollectionMode.dailyOnly => 'Cobranca so da diaria',
      _ChargeCollectionMode.installment => 'Cobranca de parcela',
    };

    final chargeModeDescription = switch (chargeMode) {
      _ChargeCollectionMode.total =>
        'O WhatsApp vai abrir com a cobranca completa pronta e o QR Code Pix no valor total.',
      _ChargeCollectionMode.interestOnly =>
        'O WhatsApp vai abrir com a cobranca so do juro do mês pronta e o QR Code Pix no valor correspondente.',
      _ChargeCollectionMode.currentCycle =>
        'O WhatsApp vai abrir com a cobranca do ciclo atual, somando o juro do mês com a diária acumulada, sem puxar o principal.',
      _ChargeCollectionMode.dailyOnly =>
        'O WhatsApp vai abrir com a cobranca somente da diária acumulada até agora.',
      _ChargeCollectionMode.installment =>
        'O WhatsApp vai abrir com a cobranca das parcelas pronta e o QR Code Pix no valor correspondente.',
    };

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$chargeModeLabel com Pix'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Valor desta cobranca: ${_currency(totalDebt)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  chargeModeDescription,
                  style: TextStyle(
                    color: Color(0xFF5B6474),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFDCE9FF)),
                    ),
                    child: QrImageView(
                      data: pixPayload,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFDCE9FF)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chave Pix principal',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'CPF: 12704258708',
                        style: TextStyle(color: Color(0xFF5B6474)),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Telefone alternativo: 21965680720',
                        style: TextStyle(color: Color(0xFF5B6474)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                const ClipboardData(text: _pixPrimaryKey),
              );
              if (mounted) {
                _showSnack(
                  'A chave Pix CPF foi copiada para a area de transferencia.',
                  tone: _FeedbackTone.success,
                  title: 'Chave Pix copiada',
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar chave Pix'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: pixPayload),
              );
              if (mounted) {
                _showSnack(
                  'O codigo Pix foi copiado para a area de transferencia.',
                  tone: _FeedbackTone.success,
                  title: 'Codigo Pix copiado',
                );
              }
            },
            icon: const Icon(Icons.qr_code_rounded),
            label: const Text('Copiar codigo Pix'),
          ),
          FilledButton.icon(
            onPressed: () async {
              if (await canLaunchUrl(appUri)) {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                await launchUrl(appUri, mode: LaunchMode.externalApplication);
              } else if (await canLaunchUrl(webUri)) {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                await launchUrl(webUri, mode: LaunchMode.externalApplication);
              } else if (mounted) {
                _showSnack(
                  'Nao foi possível abrir o WhatsApp neste dispositivo agora.',
                  tone: _FeedbackTone.error,
                  title: 'Falha ao abrir WhatsApp',
                );
              }
            },
            icon: const Icon(Icons.message_rounded),
            label: const Text('Abrir WhatsApp'),
          ),
        ],
      ),
    );
  }

  List<Client> _buildRelatedChargeClients(Client client) {
    // O botão de cobrança do card deve refletir o débito mostrado na tela,
    // sem somar automaticamente outros registros da mesma pessoa.
    return [client];
  }

  String _buildManualChargeMessage(
    Client client,
    List<Client> relatedClients,
    DebtSummary debt,
  ) {
    if (relatedClients.length <= 1) {
      final date = DateFormat('dd/MM/yyyy').format(client.dueDate);
      return 'Olá ${client.name}, seu valor atualizado é ${_currency(debt.totalDebt)}. '
          'Vencimento: $date.';
    }

    return _buildAutomaticChargeMessage(
      client,
      relatedClients,
      _ChargeCollectionMode.total,
    );
  }

  String _buildAutomaticChargeMessage(
    Client client,
    List<Client> relatedClients,
    _ChargeCollectionMode chargeMode,
  ) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final entries = relatedClients.map((relatedClient) {
      final relatedDebt = FinanceService.calculateDebt(relatedClient);
      return (client: relatedClient, debt: relatedDebt);
    }).where((entry) => entry.debt.totalDebt > 0.009).toList();

    if (entries.isEmpty) {
      final debt = FinanceService.calculateDebt(client);
      final date = dateFormat.format(client.dueDate);
      return 'Olá ${client.name}, seu valor atualizado é ${_currency(debt.totalDebt)}. '
          'Vencimento: $date.';
    }

    final totalPrincipal = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.debt.remainingPrincipal,
    );
    final totalCycleInterest = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.debt.cycleInterest,
    );
    final totalLateInterest = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.debt.lateInterest,
    );
    final totalInterest = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.debt.totalInterestDue,
    );
    final totalDebt = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.debt.totalDebt,
    );
    final totalInstallments = entries.fold<double>(
      0,
      (sum, entry) =>
          sum +
          (entry.client.isNegotiated && entry.client.installmentAmount > 0
              ? math.min(entry.client.installmentAmount, entry.debt.totalDebt)
              : 0),
    );
    final overdueCount = entries.where((entry) => entry.debt.isOverdue).length;
    final dueTodayCount =
        entries.where((entry) => entry.debt.isDueToday).length;

    final buffer = StringBuffer();
    final intro = switch (chargeMode) {
      _ChargeCollectionMode.total =>
        'Olá ${client.name}, hoje você tem ${entries.length} débito(s) em aberto com a COBREJA.',
      _ChargeCollectionMode.interestOnly =>
        'Olá ${client.name}, hoje estou te enviando a cobrança somente do juro do mês em aberto com a COBREJA.',
      _ChargeCollectionMode.currentCycle =>
        'Olá ${client.name}, hoje estou te enviando a cobrança do mês atual com a COBREJA.',
      _ChargeCollectionMode.dailyOnly =>
        'Olá ${client.name}, hoje estou te enviando a cobrança somente da diária acumulada com a COBREJA.',
      _ChargeCollectionMode.installment =>
        'Olá ${client.name}, hoje estou te enviando a cobrança das parcelas em aberto com a COBREJA.',
    };
    buffer.writeln(intro);

    if (overdueCount > 0 || dueTodayCount > 0) {
      final statusParts = <String>[];
      if (overdueCount > 0) {
        statusParts.add('$overdueCount em atraso');
      }
      if (dueTodayCount > 0) {
        statusParts.add('$dueTodayCount vencendo hoje');
      }
      buffer.writeln('Situação: ${statusParts.join(' • ')}.');
    }

    switch (chargeMode) {
      case _ChargeCollectionMode.total:
        buffer.writeln(
          'Total geral: ${_currency(totalDebt)} '
          '(principal ${_currency(totalPrincipal)} + juros ${_currency(totalInterest)}).',
        );
        break;
      case _ChargeCollectionMode.interestOnly:
        buffer.writeln(
          'Total do juro do mês para hoje: ${_currency(totalCycleInterest)}.',
        );
        break;
      case _ChargeCollectionMode.currentCycle:
        buffer.writeln(
          'Total do mês atual: ${_currency(totalCycleInterest + totalLateInterest)} '
          '(juros ${_currency(totalCycleInterest)} + diária ${_currency(totalLateInterest)}).',
        );
        break;
      case _ChargeCollectionMode.dailyOnly:
        buffer.writeln(
          'Total da diária acumulada para hoje: ${_currency(totalLateInterest)}.',
        );
        break;
      case _ChargeCollectionMode.installment:
        buffer.writeln(
          'Total das parcelas para hoje: ${_currency(totalInstallments)}.',
        );
        break;
    }
    buffer.writeln('');
    buffer.writeln('Detalhamento:');

    var lineNumber = 1;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final itemClient = entry.client;
      final itemDebt = entry.debt;
      final dueDate = dateFormat.format(itemClient.dueDate);
      final status = itemDebt.isOverdue
          ? '${itemDebt.overdueDays} dia(s) de atraso'
          : itemDebt.isDueToday
              ? 'vence hoje'
              : 'vence em $dueDate';

      switch (chargeMode) {
        case _ChargeCollectionMode.total:
          buffer.writeln(
            '${lineNumber++}. Total ${_currency(itemDebt.totalDebt)} • '
            'juros ${_currency(itemDebt.totalInterestDue)} • '
            'principal ${_currency(itemDebt.remainingPrincipal)} • '
            '$status.',
          );
          break;
        case _ChargeCollectionMode.interestOnly:
          if (itemDebt.cycleInterest <= 0.009) {
            continue;
          }
          buffer.writeln(
            '${lineNumber++}. Juros do mês ${_currency(itemDebt.cycleInterest)} • $status.',
          );
          break;
        case _ChargeCollectionMode.currentCycle:
          final currentCycleAmount = itemDebt.cycleInterest + itemDebt.lateInterest;
          if (currentCycleAmount <= 0.009) {
            continue;
          }
          buffer.writeln(
            '${lineNumber++}. Mês atual ${_currency(currentCycleAmount)} • juros ${_currency(itemDebt.cycleInterest)} • diária ${_currency(itemDebt.lateInterest)} • $status.',
          );
          break;
        case _ChargeCollectionMode.dailyOnly:
          if (itemDebt.lateInterest <= 0.009) {
            continue;
          }
          buffer.writeln(
            '${lineNumber++}. Diária ${_currency(itemDebt.lateInterest)} • $status.',
          );
          break;
        case _ChargeCollectionMode.installment:
          final installmentValue =
              itemClient.isNegotiated && itemClient.installmentAmount > 0
                  ? math.min(itemClient.installmentAmount, itemDebt.totalDebt)
                  : 0.0;
          if (installmentValue <= 0.009) {
            continue;
          }
          final installmentInfo =
              itemClient.installmentCount > 0
                  ? 'parcela ${math.min(itemClient.installmentsPaid + 1, itemClient.installmentCount)}/${itemClient.installmentCount}'
                  : 'parcela atual';
          buffer.writeln(
            '${lineNumber++}. $installmentInfo • ${_currency(installmentValue)} • $status.',
          );
          break;
      }
    }

    buffer.writeln('');
    buffer.writeln('Pix CPF: $_pixPrimaryKey.');
    buffer.writeln('Telefone Pix alternativo: $_pixFallbackPhoneKey.');
    buffer.write('Se preferir, me avise para regularizarmos.');
    return buffer.toString();
  }

  void _showSnack(
    String message, {
    _FeedbackTone tone = _FeedbackTone.info,
    String? title,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final style = switch (tone) {
      _FeedbackTone.success => (
          background: const Color(0xFFECFDF5),
          border: const Color(0xFFA7F3D0),
          iconColor: const Color(0xFF047857),
          textColor: const Color(0xFF064E3B),
          icon: Icons.check_circle_rounded,
          fallbackTitle: 'Tudo certo'
        ),
      _FeedbackTone.warning => (
          background: const Color(0xFFFFFBEB),
          border: const Color(0xFFFDE68A),
          iconColor: const Color(0xFFB45309),
          textColor: const Color(0xFF78350F),
          icon: Icons.error_outline_rounded,
          fallbackTitle: 'Atencao'
        ),
      _FeedbackTone.error => (
          background: const Color(0xFFFEF2F2),
          border: const Color(0xFFFECACA),
          iconColor: const Color(0xFFB91C1C),
          textColor: const Color(0xFF7F1D1D),
          icon: Icons.cancel_rounded,
          fallbackTitle: 'Algo deu errado'
        ),
      _FeedbackTone.info => (
          background: const Color(0xFFEFF6FF),
          border: const Color(0xFFBFDBFE),
          iconColor: const Color(0xFF1D4ED8),
          textColor: const Color(0xFF1E3A8A),
          icon: Icons.info_rounded,
          fallbackTitle: 'Aviso'
        ),
    };

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        padding: EdgeInsets.zero,
        duration: const Duration(seconds: 4),
        content: Container(
          decoration: BoxDecoration(
            color: style.background,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: style.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 22,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.72),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(style.icon, color: style.iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? style.fallbackTitle,
                        style: TextStyle(
                          color: style.textColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: TextStyle(
                          color: style.textColor,
                          height: 1.4,
                          fontSize: 13.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final int? badge;
  final VoidCallback onTap;
  final String tooltip;

  const _IconBubble({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Ink(
                height: 48,
                width: 48,
                child: Icon(icon, color: const Color(0xFF111827)),
              ),
            ),
          ),
          if ((badge ?? 0) > 0)
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${badge!}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricCardData {
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;
  final _MetricCardKind kind;

  const _MetricCardData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.kind,
  });
}

class _MetricsActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MetricsActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDCE9FF)),
        ),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF061C3D), Color(0xFF22C55E)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF5B6474),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }
}

class _PlanBadge extends StatelessWidget {
  final AppPlan plan;
  final VoidCallback onTap;

  const _PlanBadge({
    required this.plan,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: plan.color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: plan.color.withOpacity(0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded, size: 16, color: plan.color),
            const SizedBox(width: 8),
            Text(
              'Plano ${plan.label}',
              style: TextStyle(
                color: plan.color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final AppPlan plan;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected || highlighted
              ? plan.color
              : const Color(0xFFDCE9FF),
          width: selected || highlighted ? 1.6 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: plan.color.withOpacity(0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]
            : const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
              if (selected)
                const _StatusPill(
                  text: 'Ativo',
                  color: AppColors.success,
                )
              else if (highlighted)
                _StatusPill(
                  text: 'Recomendado',
                  color: plan.color,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            plan.subtitle,
            style: const TextStyle(
              color: AppColors.textMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          _StatusPill(
            text: plan.priceLabel,
            color: plan.color,
          ),
          const SizedBox(height: 14),
          ...plan.highlights.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, color: plan.color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: AppColors.textBody,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: plan.color,
                foregroundColor: Colors.white,
              ),
              onPressed: onTap,
              child: Text(selected ? 'Plano atual' : 'Ativar para testes'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final _MetricCardData data;
  final VoidCallback? onTap;

  const _MetricCard({required this.data, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [data.color, data.color.withOpacity(0.85)],
            ),
            boxShadow: [
              BoxShadow(
                color: data.color.withOpacity(0.20),
                blurRadius: 24,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 250;
          final ultraCompact = constraints.maxWidth < 228;

          final leftInset = ultraCompact ? 12.0 : compact ? 13.0 : 16.0;
          final rightInset = ultraCompact ? 12.0 : compact ? 13.0 : 16.0;
          final topInset = ultraCompact ? 10.0 : compact ? 11.0 : 14.0;
          final iconSize = ultraCompact ? 32.0 : compact ? 34.0 : 40.0;
          final trendSize = ultraCompact ? 17.0 : compact ? 18.0 : 21.0;
          final titleTop = ultraCompact ? 54.0 : compact ? 58.0 : 68.0;
          final valueTop = ultraCompact ? 69.0 : compact ? 73.0 : 87.0;
          final subtitleBottom = ultraCompact ? 9.0 : compact ? 11.0 : 13.0;

          return Stack(
            children: [
              Positioned(
                left: leftInset,
                top: topInset,
                child: Container(
                  height: iconSize,
                  width: iconSize,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    data.icon,
                    color: Colors.white,
                    size: ultraCompact ? 16 : compact ? 17 : 20,
                  ),
                ),
              ),
              Positioned(
                top: topInset + 2,
                right: rightInset,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: trendSize,
                ),
              ),
              Positioned(
                left: leftInset,
                right: rightInset,
                top: titleTop,
                child: Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: ultraCompact ? 11 : compact ? 12 : 14,
                  ),
                ),
              ),
              Positioned(
                left: leftInset,
                right: rightInset,
                top: valueTop,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    data.value,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: ultraCompact ? 16 : compact ? 18 : 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: leftInset,
                right: rightInset,
                bottom: subtitleBottom,
                child: Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: ultraCompact ? 9.5 : compact ? 10.5 : 12,
                  ),
                ),
              ),
            ],
          );
        },
          ),
      ),
      ),
    );
  }
}

enum _ClientProfileFilter { todas, ativas, emAtraso, quitadas }

class _ClientGroupCard extends StatelessWidget {
  final String name;
  final int recordCount;
  final int overdueCount;
  final double totalDebt;
  final double totalPrincipal;
  final double totalInterest;
  final double totalLate;
  final VoidCallback onOpen;

  const _ClientGroupCard({
    required this.name,
    required this.recordCount,
    required this.overdueCount,
    required this.totalDebt,
    required this.totalPrincipal,
    required this.totalInterest,
    required this.totalLate,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final compact = screenWidth < 520;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlightColor =
        overdueCount > 0 ? const Color(0xFFDC2626) : AppColors.success;
    final titleColor = isDark ? const Color(0xFFF8FAFC) : AppColors.textStrong;
    final bodyColor = isDark ? const Color(0xFFD6E0EC) : const Color(0xFF4B5563);
    final mutedColor = isDark ? const Color(0xFFA9B7C8) : const Color(0xFF6B7280);
    final cardGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF102A43), Color(0xFF0B2137)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF8FBFF)],
          );
    final borderColor =
        isDark ? const Color(0xFF244462) : const Color(0xFFE5E7EB);

    final hasLate = totalLate > 0.009;
    final subtitleParts = <String>[
      '$recordCount divida(s)',
      if (overdueCount > 0) '$overdueCount em atraso',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: cardGradient,
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C0F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onOpen,
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: compact ? 50 : 58,
                  width: compact ? 50 : 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [
                        highlightColor.withOpacity(0.22),
                        highlightColor.withOpacity(0.08),
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.people_alt_rounded,
                    color: highlightColor,
                    size: compact ? 24 : 28,
                  ),
                ),
                SizedBox(width: compact ? 12 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: compact ? 17 : 19,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                            ),
                          ),
                          _StatusPill(
                            text: subtitleParts.join(' • '),
                            color: highlightColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Total: ${_currency(totalDebt)}',
                        style: TextStyle(
                          fontSize: compact ? 15 : 16,
                          fontWeight: FontWeight.w900,
                          color: highlightColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Principal: ${_currency(totalPrincipal)} • Juros: ${_currency(totalInterest)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bodyColor,
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasLate) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Diaria acumulada: ${_currency(totalLate)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: highlightColor,
                            fontSize: compact ? 11 : 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        'Toque para ver o perfil completo com todas as dividas.',
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.chevron_right_rounded, color: highlightColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminClientGroupProfilePage extends StatefulWidget {
  final String nameKey;
  final String displayName;
  final List<Client> initialClients;
  final Future<List<Client>> Function() loadLatest;
  final Future<void> Function(Client client) openDebtDetails;

  const _AdminClientGroupProfilePage({
    required this.nameKey,
    required this.displayName,
    required this.initialClients,
    required this.loadLatest,
    required this.openDebtDetails,
  });

  @override
  State<_AdminClientGroupProfilePage> createState() =>
      _AdminClientGroupProfilePageState();
}

class _AdminClientGroupProfilePageState
    extends State<_AdminClientGroupProfilePage> {
  bool _isLoading = false;
  String? _error;
  late List<Client> _clients;
  _ClientProfileFilter _filter = _ClientProfileFilter.ativas;

  @override
  void initState() {
    super.initState();
    _clients = [...widget.initialClients];
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final latest = await widget.loadLatest();
      if (!mounted) return;
      setState(() {
        _clients = [...latest];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Client> _filteredClients() {
    switch (_filter) {
      case _ClientProfileFilter.todas:
        return _clients;
      case _ClientProfileFilter.ativas:
        return _clients.where((client) => client.status == 'devendo').toList();
      case _ClientProfileFilter.emAtraso:
        return _clients
            .where((client) => FinanceService.calculateDebt(client).isOverdue)
            .toList();
      case _ClientProfileFilter.quitadas:
        return _clients.where((client) => client.status == 'quitado').toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredClients();

    final summaries = _clients
        .where((client) => client.status != 'excluido' && client.status != 'excluído')
        .map((client) => FinanceService.calculateDebt(client))
        .toList();

    final totalDebt =
        summaries.fold<double>(0, (sum, item) => sum + item.totalDebt);
    final totalPrincipal =
        summaries.fold<double>(0, (sum, item) => sum + item.remainingPrincipal);
    final totalInterest =
        summaries.fold<double>(0, (sum, item) => sum + item.cycleInterest);
    final totalLate =
        summaries.fold<double>(0, (sum, item) => sum + item.lateInterest);
    final overdueCount = summaries.where((item) => item.isOverdue).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FF),
      appBar: AppBar(
        title: Text(widget.displayName),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _isLoading ? null : _refresh,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 110),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ProfileMetricCard(
                  title: 'Total atualizado',
                  value: _currency(totalDebt),
                  color: overdueCount > 0
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF061C3D),
                  icon: Icons.assessment_rounded,
                ),
                _ProfileMetricCard(
                  title: 'Principal em aberto',
                  value: _currency(totalPrincipal),
                  color: const Color(0xFF061C3D),
                  icon: Icons.account_balance_wallet_rounded,
                ),
                _ProfileMetricCard(
                  title: 'Juros do ciclo',
                  value: _currency(totalInterest),
                  color: const Color(0xFF7C3AED),
                  icon: Icons.percent_rounded,
                ),
                _ProfileMetricCard(
                  title: 'Diaria acumulada',
                  value: _currency(totalLate),
                  color: const Color(0xFFDC2626),
                  icon: Icons.timer_rounded,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ProfileFilterChip(
                  label: 'Todas',
                  selected: _filter == _ClientProfileFilter.todas,
                  onTap: () => setState(() => _filter = _ClientProfileFilter.todas),
                ),
                _ProfileFilterChip(
                  label: 'Ativas',
                  selected: _filter == _ClientProfileFilter.ativas,
                  onTap: () => setState(() => _filter = _ClientProfileFilter.ativas),
                ),
                _ProfileFilterChip(
                  label: 'Em atraso',
                  selected: _filter == _ClientProfileFilter.emAtraso,
                  onTap: () => setState(() => _filter = _ClientProfileFilter.emAtraso),
                ),
                _ProfileFilterChip(
                  label: 'Quitadas',
                  selected: _filter == _ClientProfileFilter.quitadas,
                  onTap: () => setState(() => _filter = _ClientProfileFilter.quitadas),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Text(
              'Mostrando ${visible.length} de ${_clients.length} registro(s).',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Nenhum registro para este filtro.',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              ...visible.map((client) {
                final debt = FinanceService.calculateDebt(client);
                return _ClientCard(
                  client: client,
                  debt: debt,
                  tabType: 'devendo',
                  onOpen: () async {
                    await widget.openDebtDetails(client);
                    await _refresh();
                  },
                  onCharge: () {},
                  onChargeAll: () {},
                  tooltip: 'Abrir detalhes de ${client.name}',
                  onToggleSelected: () {},
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _ProfileMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _ProfileMetricCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderSoft),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 12,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7ED) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFFF97316) : AppColors.borderSoft,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFFF97316) : const Color(0xFF111827),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final Client client;
  final DebtSummary debt;
  final String tabType;
  final VoidCallback onOpen;
  final VoidCallback onCharge;
  final VoidCallback onChargeAll;
  final String tooltip;
  final bool selectable;
  final bool selected;
  final VoidCallback onToggleSelected;

  const _ClientCard({
    required this.client,
    required this.debt,
    required this.tabType,
    required this.onOpen,
    required this.onCharge,
    required this.onChargeAll,
    required this.tooltip,
    this.selectable = false,
    this.selected = false,
    required this.onToggleSelected,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final compact = screenWidth < 520;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlightColor = client.status == 'quitado'
        ? const Color(0xFF16A34A)
        : debt.isOverdue
            ? const Color(0xFFDC2626)
            : AppColors.success;
    final titleColor = isDark ? const Color(0xFFF8FAFC) : AppColors.textStrong;
    final bodyColor = isDark ? const Color(0xFFD6E0EC) : const Color(0xFF4B5563);
    final mutedColor = isDark ? const Color(0xFFA9B7C8) : const Color(0xFF6B7280);
    final cardGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF102A43), Color(0xFF0B2137)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF8FBFF)],
          );
    final borderColor =
        isDark ? const Color(0xFF244462) : const Color(0xFFE5E7EB);

    final valueText = tabType == 'juros'
        ? 'Apenas juros: ${_currency(debt.totalInterestDue)}'
        : client.status == 'quitado'
            ? 'Recebido: ${_currency(client.totalInterestCollected + client.totalPrincipalCollected)}'
            : 'Total: ${_currency(debt.totalDebt)}';
    final ratesText = client.isNegotiated
        ? 'Acordo parcelado • atraso ${_formatInterestRule(type: client.dailyInterestType, percentageValue: client.dailyInterestRate, amountValue: client.dailyInterestAmount, suffix: 'a.d.')}'
        : '${_formatInterestRule(type: client.monthlyInterestType, percentageValue: client.monthlyInterestRate, amountValue: client.monthlyInterestAmount, suffix: 'a.m.')} • ${_formatInterestRule(type: client.dailyInterestType, percentageValue: client.dailyInterestRate, amountValue: client.dailyInterestAmount, suffix: 'a.d.')}';
    final hasInterestBreakdown =
        tabType != 'juros' &&
        client.status != 'quitado' &&
        (debt.totalInterestDue > 0.009 || debt.lateInterest > 0.009);
    final principalBreakdownText =
        'Principal: ${_currency(debt.remainingPrincipal)} • Juros: ${_currency(debt.cycleInterest)}';
    final dailyBreakdownText = debt.lateInterest > 0.009
        ? 'Diária acumulada: ${_currency(debt.lateInterest)}'
        : null;
    final hasMultipleCycles =
        !client.isNegotiated &&
        client.status == 'devendo' &&
        debt.monthlyCyclesDue > 1;

    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: cardGradient,
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C0F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: selectable ? onToggleSelected : onOpen,
            child: Padding(
              padding: EdgeInsets.all(compact ? 14 : 18),
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectable) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 10, top: 4),
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => onToggleSelected(),
                    ),
                  ),
                ],
                Container(
                  height: compact ? 50 : 58,
                  width: compact ? 50 : 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [
                        highlightColor.withOpacity(0.22),
                        highlightColor.withOpacity(0.08),
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    color: highlightColor,
                    size: compact ? 24 : 28,
                  ),
                ),
                SizedBox(width: compact ? 12 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            client.name,
                            style: TextStyle(
                              fontSize: compact ? 17 : 19,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                            ),
                          ),
                          if (tabType == 'juros')
                            const _StatusPill(
                              text: 'Juros pago',
                              color: Color(0xFFF59E0B),
                            ),
                          if (hasMultipleCycles)
                            _StatusPill(
                              text: '${debt.monthlyCyclesDue} ciclos',
                              color: const Color(0xFF7C3AED),
                            ),
                          if (client.isMarkedAsLostSafe || debt.overdueDays >= _estimatedLossOverdueDays)
                            const _StatusPill(
                              text: 'Prejuízo',
                              color: Color(0xFFB91C1C),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Vencimento: ${DateFormat('dd/MM/yyyy').format(client.dueDate)}',
                        style: TextStyle(
                          color: bodyColor,
                          fontSize: compact ? 12 : 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Empréstimo: ${DateFormat('dd/MM/yyyy').format(client.borrowedDate)}',
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: compact ? 11 : 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ratesText,
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (debt.isOverdue && client.status == 'devendo') ...[
                        const SizedBox(height: 4),
                        Text(
                          '${debt.overdueDays} dia(s) de atraso',
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (hasInterestBreakdown) ...[
                        Text(
                          principalBreakdownText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: bodyColor,
                            fontSize: compact ? 11 : 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (dailyBreakdownText != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            dailyBreakdownText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: debt.isOverdue
                                  ? const Color(0xFFDC2626)
                                  : bodyColor,
                              fontSize: compact ? 11 : 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                      ],
                      Text(
                        valueText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tabType == 'juros'
                              ? const Color(0xFFF97316)
                              : client.status == 'quitado'
                                  ? const Color(0xFF16A34A)
                                  : debt.isOverdue
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF16A34A),
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 15 : 16,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!selectable)
                      PopupMenuButton<String>(
                        tooltip: 'Opções de cobrança no WhatsApp',
                        onSelected: (value) {
                          if (value == 'single') {
                            onCharge();
                          } else if (value == 'all') {
                            onChargeAll();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem<String>(
                            value: 'single',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.chat_bubble_outline_rounded),
                              title: Text('Cobrar este débito'),
                              subtitle: Text('Usa só o valor deste card'),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'all',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.forum_rounded),
                              title: Text('Cobrar todos os débitos'),
                              subtitle: Text('Soma tudo dessa pessoa'),
                            ),
                          ),
                        ],
                        child: Icon(
                          Icons.message_rounded,
                          color: const Color(0xFF16A34A),
                          size: compact ? 24 : 28,
                        ),
                      ),
                    if (!selectable) ...[
                      const SizedBox(height: 10),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ],
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusPill({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumFoundationSection {
  final String title;
  final String subtitle;
  final IconData icon;
  final String status;
  final Color color;

  const _PremiumFoundationSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    required this.color,
  });
}

class _PremiumFoundationCard extends StatelessWidget {
  final List<_PremiumFoundationSection> sections;
  final VoidCallback? onEditSettings;

  const _PremiumFoundationCard({
    required this.sections,
    this.onEditSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textStrong;
    final bodyColor = isDark ? const Color(0xFFD6E0EC) : AppColors.textMuted;
    final panelColor = isDark ? const Color(0xFF102A43) : Colors.white.withOpacity(0.96);
    final tileColor = isDark ? const Color(0xFF0B2137) : const Color(0xFFF8FBFF);
    final borderColor = isDark ? const Color(0xFF244462) : const Color(0xFFDCE9FF);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF102A43), Color(0xFF061C3D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Colors.white, Color(0xFFF1FFF7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Feronix Premium',
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fundacao SaaS para configuracoes, suporte, auditoria, Pix, automacoes e paineis financeiros.',
                      style: TextStyle(color: bodyColor, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 980
                  ? 3
                  : constraints.maxWidth > 620
                      ? 2
                      : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sections.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: columns == 1 ? 4.1 : 3.1,
                ),
                itemBuilder: (context, index) {
                  final section = sections[index];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: tileColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 40,
                          width: 40,
                          decoration: BoxDecoration(
                            color: section.color.withOpacity(0.13),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(section.icon, color: section.color, size: 21),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                section.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: titleColor,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                section.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: bodyColor,
                                  fontSize: 12,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusPill(text: section.status, color: section.color),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panelColor.withOpacity(isDark ? 0.72 : 0.88),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                const Icon(Icons.security_rounded, color: AppColors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'A base nova respeita JWT, roles ADMIN/CLIENT e isolamento por accountId.',
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (onEditSettings != null) ...[
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: onEditSettings,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Editar'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDCE9FF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFF061C3D)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF5B6474),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _HistorySummaryCardData {
  final String label;
  final String value;
  final Color accentColor;

  const _HistorySummaryCardData({
    required this.label,
    required this.value,
    required this.accentColor,
  });
}

class _HistorySummaryCard extends StatelessWidget {
  final _HistorySummaryCardData data;

  const _HistorySummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE9FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.label,
            style: const TextStyle(
              color: Color(0xFF5B6474),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.value,
            style: TextStyle(
              color: data.accentColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem {
  final String label;
  final String value;

  const _SummaryItem(this.label, this.value);
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('CobreJá'),
      ),
      body: Center(
        child: Text('Bem-vindo ao sistema! 🚀'),
      ),
    );
  }
}


