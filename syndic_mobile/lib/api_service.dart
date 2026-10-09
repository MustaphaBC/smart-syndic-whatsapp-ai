import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'main.dart';

class ApiService {
  // ── Auth headers ────────────────────────────────────────────────────────────
  static Future<Map<String, String>> authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Non connecté');
    final token = await user.getIdToken(
      user.metadata.lastSignInTime != null &&
          DateTime.now().difference(user.metadata.lastSignInTime!).inMinutes >
              55,
    );
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // ── GET ──────────────────────────────────────────────────────────────────────
  static Future<dynamic> get(String path) async {
    final headers = await authHeaders();
    final res = await http.get(Uri.parse('$BASE_URL$path'), headers: headers);
    if (res.statusCode == 401) throw Exception('Non autorisé (401)');
    if (res.statusCode >= 400) {
      throw Exception('Erreur ${res.statusCode}: ${res.body}');
    }
    return json.decode(res.body);
  }

  // ── POST ─────────────────────────────────────────────────────────────────────
  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final headers = await authHeaders();
    final res = await http.post(
      Uri.parse('$BASE_URL$path'),
      headers: headers,
      body: json.encode(body),
    );
    if (res.statusCode == 401) throw Exception('Non autorisé (401)');
    if (res.statusCode >= 400) {
      throw Exception('Erreur ${res.statusCode}: ${res.body}');
    }
    return json.decode(res.body);
  }

  // ── PUT ──────────────────────────────────────────────────────────────────────
  static Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final headers = await authHeaders();
    final res = await http.put(
      Uri.parse('$BASE_URL$path'),
      headers: headers,
      body: json.encode(body),
    );
    if (res.statusCode == 401) throw Exception('Non autorisé (401)');
    if (res.statusCode >= 400) {
      throw Exception('Erreur ${res.statusCode}: ${res.body}');
    }
    return json.decode(res.body);
  }

  // ── DELETE ───────────────────────────────────────────────────────────────────
  static Future<dynamic> delete(String path) async {
    final headers = await authHeaders();
    final res = await http.delete(
      Uri.parse('$BASE_URL$path'),
      headers: headers,
    );
    if (res.statusCode == 401) throw Exception('Non autorisé (401)');
    if (res.statusCode >= 400) {
      throw Exception('Erreur ${res.statusCode}: ${res.body}');
    }
    return json.decode(res.body);
  }

  // ── Méthodes métier ──────────────────────────────────────────────────────────
  static Future<int> getPendingCount() async {
    try {
      final data = await get('/api/pending-count');
      return (data['count'] as int?) ?? 0;
    } catch (e) {
      debugPrint("getPendingCount error: $e");
      return 0;
    }
  }

  static Future<Map<String, dynamic>> getAdminStats() async {
    return (await get('/api/admin-stats')) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getResidences() async {
    return (await get('/api/residences-list')) as List<dynamic>;
  }

  static Future<List<dynamic>> getResidents(String residenceId) async {
    return (await get('/api/residents?residence_id=$residenceId'))
        as List<dynamic>;
  }

  static Future<List<dynamic>> getGridStatus(String residenceId) async {
    return (await get('/api/grid-status?residence_id=$residenceId'))
        as List<dynamic>;
  }

  static Future<List<dynamic>> getHistory({
    int limit = 100,
    int days = 30,
    int offset = 0,
  }) async {
    return (await get('/api/history?limit=$limit&days=$days&offset=$offset'))
        as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getAnalytics(int days) async {
    return (await get('/api/analytics?days=$days')) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getSatisfactionStats() async {
    return (await get('/api/satisfaction-stats')) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getTicketDetail(int id) async {
    return (await get('/api/tickets/$id')) as Map<String, dynamic>;
  }
}
