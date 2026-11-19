import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/deal_models.dart';

class DealRepository {
  final String? customBaseUrl;
  final http.Client _client;

  DealRepository({
    this.customBaseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Uri _endpoint(String path) {
    const envUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    final baseStr = customBaseUrl ?? envUrl;
    if (baseStr.isNotEmpty) {
      final cleanBase = baseStr.endsWith('/') ? baseStr.substring(0, baseStr.length - 1) : baseStr;
      return Uri.parse('$cleanBase/$path');
    }
    final base = Uri.base;
    if (base.scheme == 'http' || base.scheme == 'https') {
      return base.resolve(path);
    }
    if (base.scheme == 'blob') {
      return Uri.parse(path);
    }
    return Uri.parse('http://localhost:8080/$path');
  }

  Future<Map<String, dynamic>> fetchHealth() async {
    final resp = await _client
        .get(_endpoint('api/health'))
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) {
      throw Exception('Backend health check failed (${resp.statusCode})');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<ShoppingMission>> fetchMissions() async {
    final resp = await _client
        .get(_endpoint('api/missions'))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load missions (${resp.statusCode})');
    }
    final list = jsonDecode(resp.body) as List<dynamic>;
    return list
        .map((e) => ShoppingMission.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ShoppingMission> createMissionFromIntent({
    required String rawIntent,
    double? budgetHint,
  }) async {
    final resp = await _client.post(
      _endpoint('api/missions/from-intent'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'raw_intent': rawIntent,
        if (budgetHint != null) 'budget_hint': budgetHint,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Intent translation failed (${resp.statusCode})');
    }
    return ShoppingMission.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteMission(int missionId) async {
    final resp = await _client.delete(
      _endpoint('api/missions/$missionId'),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to delete mission');
    }
  }

  Future<DealOptionNode> patchOptionNode({
    required int optionId,
    double? currentPrice,
    double? clipCouponAmount,
    double? strikePrice,
    bool? snsEligible,
    bool? selectedInStack,
    bool? snagged,
  }) async {
    final body = <String, dynamic>{};
    if (currentPrice != null) body['current_price'] = currentPrice;
    if (clipCouponAmount != null) body['clip_coupon_amount'] = clipCouponAmount;
    if (strikePrice != null) body['strike_price'] = strikePrice;
    if (snsEligible != null) body['sns_eligible'] = snsEligible;
    if (selectedInStack != null) body['selected_in_stack'] = selectedInStack;
    if (snagged != null) body['snagged'] = snagged;

    final resp = await _client.patch(
      _endpoint('api/options/$optionId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to update option ($optionId)');
    }
    return DealOptionNode.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<CombinatoricStackSummary> fetchStackSummary() async {
    final resp = await _client.get(_endpoint('api/stack-summary'));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load stack summary');
    }
    return CombinatoricStackSummary.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<List<WebhookAlertLog>> fetchAlerts() async {
    final resp = await _client.get(_endpoint('api/alerts'));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load alerts');
    }
    final list = jsonDecode(resp.body) as List<dynamic>;
    return list
        .map((e) => WebhookAlertLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> triggerPoller({bool simulateDrop = false}) async {
    await _client.post(
      _endpoint('api/poller/trigger?simulate_drop=$simulateDrop'),
    );
  }

  Future<void> triggerTestWebhook({int? optionId, String? customMessage}) async {
    await _client.post(
      _endpoint('api/alerts/test'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (optionId != null) 'option_id': optionId,
        if (customMessage != null) 'custom_message': customMessage,
      }),
    );
  }

  Future<void> resetDatabase() async {
    await _client.post(_endpoint('api/reset'));
  }

  Future<AmazonCartBuilderPlan> fetchCartPlan({String scope = 'recommended'}) async {
    final resp = await _client.get(_endpoint('api/cart-plan?scope=$scope'));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load Amazon cart plan (${resp.statusCode})');
    }
    return AmazonCartBuilderPlan.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<ProviderSettings> fetchSettings() async {
    final resp = await _client.get(_endpoint('api/settings'));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load provider settings (${resp.statusCode})');
    }
    return ProviderSettings.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<ProviderSettings> updateSettings(Map<String, dynamic> patch) async {
    final resp = await _client.patch(
      _endpoint('api/settings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(patch),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to update provider settings (${resp.statusCode})');
    }
    return ProviderSettings.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }
}

