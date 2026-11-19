import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/deal_models.dart';
import 'local_deal_store.dart';

class DealRepository {
  final String? customBaseUrl;
  final http.Client _client;
  late final LocalDealStore localStore;

  static bool? _cachedUseStaticLocal;

  DealRepository({
    this.customBaseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    localStore = LocalDealStore(
      client: _client,
      resolveUri: _endpoint,
    );
  }

  bool get isStaticLocalMode => _cachedUseStaticLocal ?? false;

  Uri _endpoint(String path) {
    const envUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    final baseStr = customBaseUrl ?? envUrl;
    if (baseStr.isNotEmpty) {
      final cleanBase =
          baseStr.endsWith('/') ? baseStr.substring(0, baseStr.length - 1) : baseStr;
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

  /// Auto-detects whether a live FastAPI backend is reachable, or falls back to
  /// Static GitHub Pages + Browser Device Storage (localStorage) mode.
  Future<bool> _shouldUseStaticLocal() async {
    if (_cachedUseStaticLocal != null) return _cachedUseStaticLocal!;
    try {
      final resp = await _client
          .get(_endpoint('api/health'))
          .timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic> && decoded['status'] == 'ok') {
          _cachedUseStaticLocal = false;
          return false;
        }
      }
    } catch (_) {}
    _cachedUseStaticLocal = true;
    await localStore.ensureLoaded();
    return true;
  }

  Future<Map<String, dynamic>> fetchHealth() async {
    if (await _shouldUseStaticLocal()) {
      return localStore.fetchHealth();
    }
    final resp = await _client
        .get(_endpoint('api/health'))
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) {
      throw Exception('Backend health check failed (${resp.statusCode})');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    map['storage_mode'] = 'fastapi_backend';
    return map;
  }

  Future<List<ShoppingMission>> fetchMissions() async {
    if (await _shouldUseStaticLocal()) {
      return localStore.fetchMissions();
    }
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
    if (await _shouldUseStaticLocal()) {
      return localStore.createMissionFromIntent(
        rawIntent: rawIntent,
        budgetHint: budgetHint,
      );
    }
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
    if (await _shouldUseStaticLocal()) {
      await localStore.deleteMission(missionId);
      return;
    }
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
    if (await _shouldUseStaticLocal()) {
      return localStore.patchOptionNode(
        optionId: optionId,
        currentPrice: currentPrice,
        clipCouponAmount: clipCouponAmount,
        strikePrice: strikePrice,
        snsEligible: snsEligible,
        selectedInStack: selectedInStack,
        snagged: snagged,
      );
    }
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
    if (await _shouldUseStaticLocal()) {
      return localStore.fetchStackSummary();
    }
    final resp = await _client.get(_endpoint('api/stack-summary'));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load stack summary');
    }
    return CombinatoricStackSummary.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<List<WebhookAlertLog>> fetchAlerts() async {
    if (await _shouldUseStaticLocal()) {
      return localStore.fetchAlerts();
    }
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
    if (await _shouldUseStaticLocal()) {
      await localStore.triggerPoller(simulateDrop: simulateDrop);
      return;
    }
    await _client.post(
      _endpoint('api/poller/trigger?simulate_drop=$simulateDrop'),
    );
  }

  Future<void> triggerTestWebhook({int? optionId, String? customMessage}) async {
    if (await _shouldUseStaticLocal()) {
      await localStore.triggerPoller(simulateDrop: true);
      return;
    }
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
    if (await _shouldUseStaticLocal()) {
      await localStore.resetDatabase();
      return;
    }
    await _client.post(_endpoint('api/reset'));
  }

  Future<AmazonCartBuilderPlan> fetchCartPlan({String scope = 'recommended'}) async {
    if (await _shouldUseStaticLocal()) {
      return localStore.fetchCartPlan(scope: scope);
    }
    final resp = await _client.get(_endpoint('api/cart-plan?scope=$scope'));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load Amazon cart plan (${resp.statusCode})');
    }
    return AmazonCartBuilderPlan.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<ProviderSettings> fetchSettings() async {
    if (await _shouldUseStaticLocal()) {
      return localStore.fetchSettings();
    }
    final resp = await _client.get(_endpoint('api/settings'));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load provider settings (${resp.statusCode})');
    }
    return ProviderSettings.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<ProviderSettings> updateSettings(Map<String, dynamic> patch) async {
    if (await _shouldUseStaticLocal()) {
      return localStore.fetchSettings();
    }
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

  static final Map<String, Uint8List?> _imageMemoryCache = {};

  Future<Uint8List?> fetchProductImageBytes(int optionId, {String? branchKey}) async {
    final cacheKey = '${optionId}_${branchKey ?? ''}';
    if (_imageMemoryCache.containsKey(cacheKey)) {
      return _imageMemoryCache[cacheKey];
    }

    final useStatic = await _shouldUseStaticLocal();
    if (!useStatic) {
      try {
        final resp = await _client
            .get(_endpoint('api/product-image/$optionId'))
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
          _imageMemoryCache[cacheKey] = resp.bodyBytes;
          return resp.bodyBytes;
        }
      } catch (_) {}
    }

    // Static GitHub Pages fallback (loads bundled JPEG directly from images/products/)
    final staticPath = localStore.resolveStaticImagePath(optionId, branchKey: branchKey) ??
        (branchKey != null && branchKey.isNotEmpty ? 'images/products/$branchKey.jpg' : null);
    if (staticPath != null) {
      try {
        final resp = await _client
            .get(_endpoint(staticPath))
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
          _imageMemoryCache[cacheKey] = resp.bodyBytes;
          return resp.bodyBytes;
        }
      } catch (_) {}
    }

    _imageMemoryCache[cacheKey] = null;
    return null;
  }
}
