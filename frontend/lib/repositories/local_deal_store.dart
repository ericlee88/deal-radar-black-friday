import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/deal_models.dart';
import 'browser_storage.dart';

const _kStateStorageKey = 'deal_radar_state_v1';
const _kGitHubSyncKey = 'deal_radar_github_sync_v1';

class GitHubSyncConfig {
  final String repo;
  final String branch;
  final String token;

  const GitHubSyncConfig({
    this.repo = 'ericlee88/deal-radar-black-friday',
    this.branch = 'feat/github-pages-static-sync',
    this.token = '',
  });

  bool get isEnabled => repo.trim().contains('/') && token.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'repo': repo.trim(),
        'branch': branch.trim().isEmpty ? 'main' : branch.trim(),
        'token': token.trim(),
      };

  factory GitHubSyncConfig.fromJson(Map<String, dynamic> json) {
    return GitHubSyncConfig(
      repo: json['repo'] as String? ?? 'ericlee88/deal-radar-black-friday',
      branch: json['branch'] as String? ?? 'feat/github-pages-static-sync',
      token: json['token'] as String? ?? '',
    );
  }
}

/// Client-side read/write store backed by static deals_snapshot.json + browser localStorage
/// + optional GitHub repository JSON sync (for GitHub Pages / serverless deployments).
class LocalDealStore {
  final http.Client _client;
  final Uri Function(String path) _resolveUri;

  bool _initialized = false;
  String _snapshotGeneratedAt = '';
  List<Map<String, dynamic>> _missions = [];
  List<Map<String, dynamic>> _alerts = [];
  Map<String, String> _imageMap = {};
  String? _lastSyncStatus;
  GitHubSyncConfig _syncConfig = const GitHubSyncConfig();

  LocalDealStore({
    required http.Client client,
    required Uri Function(String path) resolveUri,
  })  : _client = client,
        _resolveUri = resolveUri {
    _loadSyncConfig();
  }

  GitHubSyncConfig get syncConfig => _syncConfig;
  String get snapshotGeneratedAt => _snapshotGeneratedAt;
  String? get lastSyncStatus => _lastSyncStatus;

  void _loadSyncConfig() {
    final raw = readLocalStorage(_kGitHubSyncKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _syncConfig = GitHubSyncConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
  }

  Future<void> saveSyncConfig(GitHubSyncConfig config) async {
    _syncConfig = config;
    writeLocalStorage(_kGitHubSyncKey, jsonEncode(config.toJson()));
    if (config.isEnabled) {
      await pushToGitHub();
    }
  }

  String? resolveStaticImagePath(int optionId, {String? branchKey}) {
    if (_imageMap.containsKey('$optionId')) {
      return _imageMap['$optionId'];
    }
    if (branchKey != null && _imageMap.containsKey(branchKey)) {
      return _imageMap[branchKey];
    }
    if (branchKey != null && branchKey.isNotEmpty) {
      return 'images/products/$branchKey.jpg';
    }
    return null;
  }

  Future<void> ensureLoaded({bool forceReloadSnapshot = false}) async {
    if (_initialized && !forceReloadSnapshot) return;

    // 1. Load static snapshot from GitHub Pages bundle
    Map<String, dynamic> snapshot = {};
    try {
      final resp = await _client
          .get(_resolveUri('data/deals_snapshot.json'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        snapshot = jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}

    _snapshotGeneratedAt = snapshot['generated_at'] as String? ?? '';
    _imageMap = ((snapshot['image_map'] as Map<String, dynamic>?) ?? {})
        .map((k, v) => MapEntry(k, v.toString()));

    final baseMissions = ((snapshot['missions'] as List<dynamic>?) ?? [])
        .map((e) => _deepCopyMap(e as Map<String, dynamic>))
        .toList();
    final baseAlerts = ((snapshot['alerts'] as List<dynamic>?) ?? [])
        .map((e) => _deepCopyMap(e as Map<String, dynamic>))
        .toList();

    // 2. Check localStorage saved user state
    final savedRaw = forceReloadSnapshot ? null : readLocalStorage(_kStateStorageKey);
    if (savedRaw != null && savedRaw.isNotEmpty) {
      try {
        final saved = jsonDecode(savedRaw) as Map<String, dynamic>;
        final savedMissions = ((saved['missions'] as List<dynamic>?) ?? [])
            .map((e) => _deepCopyMap(e as Map<String, dynamic>))
            .toList();
        final savedAlerts = ((saved['alerts'] as List<dynamic>?) ?? [])
            .map((e) => _deepCopyMap(e as Map<String, dynamic>))
            .toList();
        if (savedMissions.isNotEmpty) {
          _missions = _mergeSnapshotPricesIntoSaved(baseMissions, savedMissions);
          _alerts = savedAlerts.isNotEmpty ? savedAlerts : baseAlerts;
          _recomputeAll();
          _persistLocal();
          _initialized = true;
          return;
        }
      } catch (_) {}
    }

    _missions = baseMissions;
    _alerts = baseAlerts;
    _recomputeAll();
    _persistLocal();
    _initialized = true;

    // 3. If GitHub Sync is enabled, pull remote state on startup
    if (_syncConfig.isEnabled && !forceReloadSnapshot) {
      await pullFromGitHub();
    }
  }

  /// Keeps user's custom missions & flags while adopting latest verified ASIN/URL metadata from snapshot.
  List<Map<String, dynamic>> _mergeSnapshotPricesIntoSaved(
    List<Map<String, dynamic>> snapshotMissions,
    List<Map<String, dynamic>> savedMissions,
  ) {
    final snapByOptId = <int, Map<String, dynamic>>{};
    final snapByBranchKey = <String, Map<String, dynamic>>{};
    for (final m in snapshotMissions) {
      for (final o in (m['options'] as List<dynamic>? ?? [])) {
        final om = o as Map<String, dynamic>;
        final id = (om['id'] as num?)?.toInt();
        if (id != null) snapByOptId[id] = om;
        final bk = om['branch_key'] as String? ?? '';
        if (bk.isNotEmpty) snapByBranchKey[bk] = om;
      }
    }
    for (final m in savedMissions) {
      for (final o in (m['options'] as List<dynamic>? ?? [])) {
        final om = o as Map<String, dynamic>;
        final id = (om['id'] as num?)?.toInt();
        final bk = om['branch_key'] as String? ?? '';
        final snapOpt = (bk.isNotEmpty ? snapByBranchKey[bk] : null) ??
            (id != null ? snapByOptId[id] : null);
        if (snapOpt != null) {
          // Always adopt the latest verified ASIN & search query from the deployed snapshot
          om['asin_or_sku'] = snapOpt['asin_or_sku'];
          if ((snapOpt['amazon_query'] as String? ?? '').isNotEmpty) {
            om['amazon_query'] = snapOpt['amazon_query'];
          }
          if ((snapOpt['amazon_url'] as String? ?? '').isNotEmpty) {
            om['amazon_url'] = snapOpt['amazon_url'];
          }
          if ((snapOpt['camel_url'] as String? ?? '').isNotEmpty) {
            om['camel_url'] = snapOpt['camel_url'];
          }
        }
      }
    }
    return savedMissions;
  }

  void _persistLocal() {
    final payload = {
      'schema_version': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'missions': _missions,
      'alerts': _alerts,
    };
    writeLocalStorage(_kStateStorageKey, jsonEncode(payload));
  }

  String exportStateJson() {
    final payload = {
      'schema_version': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'missions': _missions,
      'alerts': _alerts,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> importStateJson(String rawJson) async {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final missions = ((decoded['missions'] as List<dynamic>?) ?? [])
        .map((e) => _deepCopyMap(e as Map<String, dynamic>))
        .toList();
    if (missions.isEmpty) {
      throw Exception('Invalid backup JSON: no missions found.');
    }
    _missions = missions;
    _alerts = ((decoded['alerts'] as List<dynamic>?) ?? [])
        .map((e) => _deepCopyMap(e as Map<String, dynamic>))
        .toList();
    _recomputeAll();
    _persistLocal();
    if (_syncConfig.isEnabled) {
      await pushToGitHub();
    }
  }

  Future<String> pullFromGitHub() async {
    if (!_syncConfig.isEnabled) {
      return 'GitHub Sync not configured.';
    }
    final url = Uri.parse(
      'https://api.github.com/repos/${_syncConfig.repo}/contents/data/user_state.json?ref=${_syncConfig.branch}',
    );
    try {
      final resp = await _client.get(
        url,
        headers: {
          'Authorization': 'Bearer ${_syncConfig.token}',
          'Accept': 'application/vnd.github+json',
        },
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 404) {
        _lastSyncStatus = 'No remote state file yet (will create on next push).';
        return _lastSyncStatus!;
      }
      if (resp.statusCode != 200) {
        _lastSyncStatus = 'GitHub pull failed (HTTP ${resp.statusCode})';
        return _lastSyncStatus!;
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final contentB64 = (body['content'] as String? ?? '').replaceAll('\n', '');
      final decodedText = utf8.decode(base64Decode(contentB64));
      final remote = jsonDecode(decodedText) as Map<String, dynamic>;
      final remoteMissions = ((remote['missions'] as List<dynamic>?) ?? [])
          .map((e) => _deepCopyMap(e as Map<String, dynamic>))
          .toList();
      if (remoteMissions.isNotEmpty) {
        _missions = remoteMissions;
        _alerts = ((remote['alerts'] as List<dynamic>?) ?? [])
            .map((e) => _deepCopyMap(e as Map<String, dynamic>))
            .toList();
        _recomputeAll();
        _persistLocal();
      }
      _lastSyncStatus = 'Synced from GitHub (${_syncConfig.repo})';
      return _lastSyncStatus!;
    } catch (e) {
      _lastSyncStatus = 'GitHub pull error: $e';
      return _lastSyncStatus!;
    }
  }

  Future<String> pushToGitHub() async {
    if (!_syncConfig.isEnabled) {
      return 'GitHub Sync not configured.';
    }
    final getUrl = Uri.parse(
      'https://api.github.com/repos/${_syncConfig.repo}/contents/data/user_state.json?ref=${_syncConfig.branch}',
    );
    final putUrl = Uri.parse(
      'https://api.github.com/repos/${_syncConfig.repo}/contents/data/user_state.json',
    );
    final headers = {
      'Authorization': 'Bearer ${_syncConfig.token}',
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
    };
    try {
      String? existingSha;
      final getResp = await _client
          .get(getUrl, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (getResp.statusCode == 200) {
        final body = jsonDecode(getResp.body) as Map<String, dynamic>;
        existingSha = body['sha'] as String?;
      }

      final contentJson = exportStateJson();
      final payload = <String, dynamic>{
        'message': 'chore(sync): update Deal Radar user state from web app',
        'content': base64Encode(utf8.encode(contentJson)),
        'branch': _syncConfig.branch,
        if (existingSha != null) 'sha': existingSha,
      };
      final putResp = await _client
          .put(putUrl, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 10));
      if (putResp.statusCode == 200 || putResp.statusCode == 201) {
        _lastSyncStatus = 'Saved to GitHub (${_syncConfig.repo})';
        return _lastSyncStatus!;
      }
      _lastSyncStatus = 'GitHub push failed (HTTP ${putResp.statusCode})';
      return _lastSyncStatus!;
    } catch (e) {
      _lastSyncStatus = 'GitHub push error: $e';
      return _lastSyncStatus!;
    }
  }

  Future<String> triggerGitHubPollWorkflow() async {
    if (!_syncConfig.isEnabled) {
      return 'Add a GitHub Token in Settings to trigger on-demand Amazon price polls.';
    }
    final url = Uri.parse(
      'https://api.github.com/repos/${_syncConfig.repo}/actions/workflows/deploy-pages.yml/dispatches',
    );
    try {
      final resp = await _client
          .post(
            url,
            headers: {
              'Authorization': 'Bearer ${_syncConfig.token}',
              'Accept': 'application/vnd.github+json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'ref': _syncConfig.branch}),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 204 || resp.statusCode == 200) {
        _lastSyncStatus = 'Live Amazon poll triggered on GitHub Actions! Refresh in ~1-2 min.';
        return _lastSyncStatus!;
      }
      _lastSyncStatus = 'Workflow dispatch failed (HTTP ${resp.statusCode})';
      return _lastSyncStatus!;
    } catch (e) {
      _lastSyncStatus = 'Workflow dispatch error: $e';
      return _lastSyncStatus!;
    }
  }

  // ---------------------------------------------------------------------------
  // Read & Write API matching DealRepository
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> fetchHealth() async {
    await ensureLoaded();
    int optCount = 0;
    for (final m in _missions) {
      optCount += (m['options'] as List<dynamic>? ?? []).length;
    }
    return {
      'status': 'ok',
      'storage_mode': _syncConfig.isEnabled ? 'github_sync' : 'device_local_storage',
      'missions_count': _missions.length,
      'options_count': optCount,
      'llm_provider': 'local_parser',
      'price_provider': _syncConfig.isEnabled ? 'github_actions_amazon' : 'static_snapshot',
      'snapshot_generated_at': _snapshotGeneratedAt,
    };
  }

  Future<List<ShoppingMission>> fetchMissions() async {
    await ensureLoaded();
    return _missions.map((m) => ShoppingMission.fromJson(m)).toList();
  }

  Future<List<WebhookAlertLog>> fetchAlerts() async {
    await ensureLoaded();
    return _alerts.map((a) => WebhookAlertLog.fromJson(a)).toList();
  }

  Future<DealOptionNode> patchOptionNode({
    required int optionId,
    double? currentPrice,
    double? avg90dPrice,
    double? allTimeLow,
    double? clipCouponAmount,
    double? strikePrice,
    bool? snsEligible,
    bool? selectedInStack,
    bool? snagged,
    String? priceSource,
    bool appendHistoryPoint = false,
    String? historyNote,
  }) async {
    await ensureLoaded();
    Map<String, dynamic>? target;
    for (final m in _missions) {
      for (final o in (m['options'] as List<dynamic>? ?? [])) {
        final om = o as Map<String, dynamic>;
        if ((om['id'] as num).toInt() == optionId) {
          target = om;
          break;
        }
      }
      if (target != null) break;
    }
    if (target == null) {
      throw Exception('Option $optionId not found in local store');
    }

    if (currentPrice != null) target['current_price'] = currentPrice;
    if (avg90dPrice != null) target['avg_90d_price'] = avg90dPrice;
    if (allTimeLow != null) target['all_time_low'] = allTimeLow;
    if (clipCouponAmount != null) target['clip_coupon_amount'] = clipCouponAmount;
    if (strikePrice != null) target['strike_price'] = strikePrice;
    if (snsEligible != null) target['sns_eligible'] = snsEligible;
    if (selectedInStack != null) target['selected_in_stack'] = selectedInStack;
    if (snagged != null) target['snagged'] = snagged;
    if (priceSource != null && priceSource.isNotEmpty) {
      target['price_source'] = priceSource;
    }

    if (appendHistoryPoint && currentPrice != null) {
      final hist = ((target['price_history'] as List<dynamic>?) ?? [])
          .map((e) => (e as num).toDouble())
          .toList();
      hist.add(double.parse(currentPrice.toStringAsFixed(2)));
      target['price_history'] = hist.length > 24 ? hist.sublist(hist.length - 24) : hist;

      final logList = ((target['price_log'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final nowIso = DateTime.now().toIso8601String().substring(0, 10);
      logList.insert(0, {
        'date': nowIso,
        'price': double.parse(currentPrice.toStringAsFixed(2)),
        'source': priceSource ?? 'manual',
        'note': historyNote ?? '',
      });
      target['price_log'] = logList.length > 30 ? logList.sublist(0, 30) : logList;
    }

    _recomputeAll();
    if (target['is_below_strike'] == true && target['is_trap_warning'] != true) {
      _logLocalAlert(target);
    }
    _persistLocal();
    if (_syncConfig.isEnabled) {
      // Fire-and-forget sync to GitHub so UI stays snappy
      pushToGitHub();
    }
    return DealOptionNode.fromJson(target);
  }

  Future<ShoppingMission> createMissionFromIntent({
    required String rawIntent,
    double? budgetHint,
  }) async {
    await ensureLoaded();
    final trimmed = rawIntent.trim();
    int nextMissionId = 1;
    int nextOptionId = 1;
    for (final m in _missions) {
      nextMissionId = math.max(nextMissionId, (m['id'] as num).toInt() + 1);
      for (final o in (m['options'] as List<dynamic>? ?? [])) {
        nextOptionId = math.max(nextOptionId, ((o as Map<String, dynamic>)['id'] as num).toInt() + 1);
      }
    }

    final asin = _extractAmazonAsin(trimmed) ?? '';
    final cleanTitle = trimmed.length > 52 ? '${trimmed.substring(0, 52)}...' : trimmed;
    final strike = budgetHint ?? 49.99;
    final current = double.parse((strike * 1.15).toStringAsFixed(2));
    final msrp = double.parse((strike * 1.4).toStringAsFixed(2));
    final slug = 'custom-$nextMissionId-${DateTime.now().millisecondsSinceEpoch}';

    final newMission = <String, dynamic>{
      'id': nextMissionId,
      'slug': slug,
      'title': cleanTitle.isEmpty ? 'Custom Black Friday Watch' : cleanTitle,
      'raw_intent': trimmed,
      'node_type': asin.isNotEmpty ? 'EXACT_SKU' : 'CATEGORY_FUNNEL',
      'category_tag': 'custom',
      'icon': '',
      'decision_framing': 'Saved on your device. Edit strike price or paste an Amazon ASIN anytime.',
      'options': [
        {
          'id': nextOptionId,
          'mission_id': nextMissionId,
          'branch_key': 'custom_$nextOptionId',
          'branch_label': asin.isNotEmpty ? 'Pinned ASIN' : 'Watchlist Item',
          'is_recommended_branch': true,
          'is_trap_warning': false,
          'title': cleanTitle.isEmpty ? 'Custom Amazon Deal' : cleanTitle,
          'asin_or_sku': asin,
          'amazon_query': Uri.encodeQueryComponent(trimmed),
          'msrp': msrp,
          'avg_90d_price': current,
          'current_price': current,
          'clip_coupon_amount': 0.0,
          'strike_price': strike,
          'all_time_low': double.parse((strike * 0.92).toStringAsFixed(2)),
          'sns_eligible': false,
          'pg_stockup_eligible': false,
          'b2g1_eligible': false,
          'selected_in_stack': true,
          'snagged': false,
          'unit_name': 'item',
          'unit_quantity': 1.0,
          'price_history': [msrp, current, current],
          'scout_notes': 'Added via browser device storage. Tap Edit Price to log Black Friday drops.',
        }
      ],
    };

    _missions.insert(0, newMission);
    _recomputeAll();
    _persistLocal();
    if (_syncConfig.isEnabled) {
      pushToGitHub();
    }
    return ShoppingMission.fromJson(newMission);
  }

  Future<void> deleteMission(int missionId) async {
    await ensureLoaded();
    _missions.removeWhere((m) => (m['id'] as num).toInt() == missionId);
    _recomputeAll();
    _persistLocal();
    if (_syncConfig.isEnabled) {
      pushToGitHub();
    }
  }

  Future<void> triggerPoller({bool simulateDrop = false}) async {
    await ensureLoaded();
    if (simulateDrop) {
      final rng = math.Random();
      for (final m in _missions) {
        for (final o in (m['options'] as List<dynamic>? ?? [])) {
          final om = o as Map<String, dynamic>;
          if (om['is_trap_warning'] == true) continue;
          if (om['is_recommended_branch'] == true && rng.nextDouble() < 0.45) {
            final strike = (om['strike_price'] as num).toDouble();
            final newPrice = double.parse((strike * (0.90 + rng.nextDouble() * 0.08)).toStringAsFixed(2));
            om['current_price'] = newPrice;
            _recomputeAll();
            _logLocalAlert(om);
          }
        }
      }
      _recomputeAll();
      _persistLocal();
      if (_syncConfig.isEnabled) {
        pushToGitHub();
      }
    } else {
      if (_syncConfig.isEnabled) {
        await triggerGitHubPollWorkflow();
      }
      await ensureLoaded(forceReloadSnapshot: true);
    }
  }

  Future<void> resetDatabase() async {
    removeLocalStorage(_kStateStorageKey);
    _initialized = false;
    await ensureLoaded(forceReloadSnapshot: true);
  }

  Future<ProviderSettings> fetchSettings() async {
    await ensureLoaded();
    return ProviderSettings(
      llmProvider: 'auto',
      activeLlmMode: 'device_storage',
      geminiApiKeySet: false,
      geminiApiKeyPreview: 'Static GitHub Pages Mode',
      geminiModel: 'gemini-2.5-flash',
      openaiApiKeySet: false,
      openaiApiKeyPreview: 'Static GitHub Pages Mode',
      openaiModel: 'gpt-4o-mini',
      priceProvider: 'amazon_direct',
      activePriceMode: _syncConfig.isEnabled ? 'github_sync' : 'device_local_storage',
      keepaApiKeySet: false,
      keepaApiKeyPreview: 'Managed via GitHub Actions Secrets',
      webhookProvider: 'none',
      webhookUrl: null,
      telegramBotTokenSet: false,
      telegramChatId: null,
      pollIntervalMinutes: 120,
    );
  }

  // ---------------------------------------------------------------------------
  // Scoring, Stack Summary & 1-Click Amazon Cart Builder (parity with Python)
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _allOptions() {
    final out = <Map<String, dynamic>>[];
    for (final m in _missions) {
      for (final o in (m['options'] as List<dynamic>? ?? [])) {
        out.add(o as Map<String, dynamic>);
      }
    }
    return out;
  }

  double _currentSnsRate() {
    final snsCount = _allOptions()
        .where((o) => o['sns_eligible'] == true && o['selected_in_stack'] == true)
        .length;
    if (snsCount >= 5) return 0.15;
    if (snsCount >= 1) return 0.05;
    return 0.0;
  }

  void _recomputeAll() {
    final snsRate = _currentSnsRate();
    for (final o in _allOptions()) {
      final current = (o['current_price'] as num).toDouble();
      final coupon = (o['clip_coupon_amount'] as num? ?? 0).toDouble();
      final msrp = (o['msrp'] as num).toDouble();
      final avg90 = (o['avg_90d_price'] as num).toDouble();
      final strike = (o['strike_price'] as num).toDouble();
      final atl = (o['all_time_low'] as num).toDouble();
      final snsElig = o['sns_eligible'] == true;
      final isTrap = o['is_trap_warning'] == true;
      final qty = math.max(0.001, (o['unit_quantity'] as num? ?? 1).toDouble());

      final snsDiscount = snsElig ? current * snsRate : 0.0;
      final eff = double.parse(math.max(0.01, current - coupon - snsDiscount).toStringAsFixed(2));
      final unitEff = double.parse((eff / qty).toStringAsFixed(2));
      final pctOff = msrp > 0 ? (((msrp - eff) / msrp) * 100).round() : 0;

      String gradeCode;
      String gradeLabel;
      if (isTrap || eff > msrp * 1.1) {
        gradeCode = 'TRAP';
        gradeLabel = 'SCALPER / TRAP -- DO NOT BUY';
      } else if (eff <= atl + 0.50) {
        gradeCode = 'ATL';
        gradeLabel = 'ALL-TIME LOW ZONE (-$pctOff%)';
      } else if (eff <= strike) {
        gradeCode = 'STRIKE';
        gradeLabel = 'AT STRIKE TARGET (-$pctOff%)';
      } else if (eff <= avg90 * 0.94) {
        gradeCode = 'HOLD';
        gradeLabel = 'NEAR TARGET (-$pctOff% | Target \$${strike.toStringAsFixed(0)})';
      } else {
        gradeCode = 'WAIT';
        gradeLabel = 'ABOVE STRIKE (Wait for Next Wave)';
      }

      final asin = _extractAmazonAsin(o['asin_or_sku'] as String? ?? '');
      final query = o['amazon_query'] as String? ?? Uri.encodeQueryComponent(o['title'] as String? ?? '');
      final amazonUrl = asin != null
          ? 'https://www.amazon.com/dp/$asin?psc=1'
          : 'https://www.amazon.com/s?k=$query';
      final camelUrl = asin != null
          ? 'https://camelcamelcamel.com/product/$asin'
          : 'https://camelcamelcamel.com/search?sq=$query';

      final histRaw = (o['price_history'] as List<dynamic>? ?? []);
      final hist = histRaw.isEmpty
          ? <double>[msrp, avg90, eff]
          : histRaw.map((e) => (e as num).toDouble()).toList();
      hist[hist.length - 1] = eff;

      o['effective_price'] = eff;
      o['unit_effective_price'] = unitEff;
      o['discount_pct_off_msrp'] = pctOff;
      o['deal_grade_code'] = gradeCode;
      o['deal_grade_label'] = gradeLabel;
      o['is_below_strike'] = !isTrap && eff <= strike;
      o['amazon_url'] = amazonUrl;
      o['camel_url'] = camelUrl;
      o['price_history'] = hist;
    }
  }

  void _logLocalAlert(Map<String, dynamic> opt) {
    final nextId = _alerts.isEmpty
        ? 1
        : _alerts.map((a) => (a['id'] as num).toInt()).reduce(math.max) + 1;
    _alerts.insert(0, {
      'id': nextId,
      'option_id': opt['id'],
      'option_title': opt['title'],
      'effective_price': opt['effective_price'],
      'strike_price': opt['strike_price'],
      'channel': 'device_local_inbox',
      'status': 'strike_hit',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (_alerts.length > 30) {
      _alerts = _alerts.sublist(0, 30);
    }
  }

  Future<CombinatoricStackSummary> fetchStackSummary() async {
    await ensureLoaded();
    final allOpts = _allOptions();
    final snsSelected =
        allOpts.where((o) => o['sns_eligible'] == true && o['selected_in_stack'] == true).toList();
    final snsCount = snsSelected.length;
    final snsRate = snsCount >= 5 ? 0.15 : (snsCount >= 1 ? 0.05 : 0.0);

    final pgSubtotal = snsSelected
        .where((o) => o['pg_stockup_eligible'] == true)
        .fold<double>(0.0, (s, o) => s + (o['current_price'] as num).toDouble());
    final pgCredit = pgSubtotal >= 100.0 ? 25.0 : 0.0;
    final pgNeeded = math.max(0.0, 100.0 - pgSubtotal);

    final consMsrp = snsSelected.fold<double>(0.0, (s, o) => s + (o['msrp'] as num).toDouble());
    final consSale = snsSelected.fold<double>(0.0, (s, o) => s + (o['current_price'] as num).toDouble());
    final consCoupons =
        snsSelected.fold<double>(0.0, (s, o) => s + (o['clip_coupon_amount'] as num? ?? 0).toDouble());
    final consSns = consSale * snsRate;
    final consNet = math.max(0.0, consSale - consCoupons - consSns - pgCredit);
    final consPct = consMsrp > 0 ? (((consMsrp - consNet) / consMsrp) * 100).round() : 0;

    final b2g1Selected =
        allOpts.where((o) => o['b2g1_eligible'] == true && o['selected_in_stack'] == true).toList();
    final b2g1Prices = b2g1Selected.map((o) => (o['current_price'] as num).toDouble()).toList()..sort();
    final b2g1Msrp = b2g1Selected.fold<double>(0.0, (s, o) => s + (o['msrp'] as num).toDouble());
    final b2g1Sale = b2g1Prices.fold<double>(0.0, (s, p) => s + p);
    final freeCount = b2g1Prices.length ~/ 3;
    final b2g1Free = b2g1Prices.take(freeCount).fold<double>(0.0, (s, p) => s + p);
    final b2g1Net = b2g1Sale - b2g1Free;

    int harmonyScore = 0;
    String harmonyVerdict = 'Select 3 similarly priced B2G1 games/toys for max 33% savings.';
    if (b2g1Prices.length >= 3) {
      final minP = b2g1Prices.first;
      final maxP = b2g1Prices.last;
      harmonyScore = maxP > 0 ? ((minP / maxP) * 100).round() : 100;
      harmonyVerdict = harmonyScore >= 85
          ? 'Optimal Price Harmony ($harmonyScore/100) -- near full 33% off!'
          : 'Moderate Harmony ($harmonyScore/100) -- pair closer-priced items to avoid waste.';
    }

    return CombinatoricStackSummary(
      snsActiveCount: snsCount,
      snsTierRate: snsRate,
      snsUnlocked15Pct: snsCount >= 5,
      pgQualifyingSubtotal: double.parse(pgSubtotal.toStringAsFixed(2)),
      pgCreditUnlocked: pgCredit,
      pgAmountNeededForCredit: double.parse(pgNeeded.toStringAsFixed(2)),
      consumablesMsrpTotal: double.parse(consMsrp.toStringAsFixed(2)),
      consumablesSaleTotal: double.parse(consSale.toStringAsFixed(2)),
      consumablesCouponSavings: double.parse(consCoupons.toStringAsFixed(2)),
      consumablesSnsSavings: double.parse(consSns.toStringAsFixed(2)),
      consumablesNetOutOfPocket: double.parse(consNet.toStringAsFixed(2)),
      consumablesEffectiveDiscountPct: consPct,
      b2g1SelectedCount: b2g1Selected.length,
      b2g1MsrpTotal: double.parse(b2g1Msrp.toStringAsFixed(2)),
      b2g1SaleSubtotal: double.parse(b2g1Sale.toStringAsFixed(2)),
      b2g1FreeItemDeduction: double.parse(b2g1Free.toStringAsFixed(2)),
      b2g1NetTotal: double.parse(b2g1Net.toStringAsFixed(2)),
      b2g1HarmonyScore: harmonyScore,
      b2g1HarmonyVerdict: harmonyVerdict,
    );
  }

  Future<AmazonCartBuilderPlan> fetchCartPlan({String scope = 'recommended'}) async {
    await ensureLoaded();
    final allOpts = _allOptions().map((o) => DealOptionNode.fromJson(o)).toList();
    final stack = await fetchStackSummary();

    List<DealOptionNode> selected;
    if (scope == 'strike_only') {
      selected = allOpts.where((o) => o.isBelowStrike && !o.isTrapWarning && !o.snagged).toList();
    } else if (scope == 'stack_only') {
      selected = allOpts.where((o) => o.selectedInStack && !o.isTrapWarning && !o.snagged).toList();
    } else {
      selected = allOpts
          .where((o) => (o.isRecommendedBranch || o.selectedInStack) && !o.isTrapWarning && !o.snagged)
          .toList();
    }

    final directItems = <DealOptionNode>[];
    final fallbackItems = <DealOptionNode>[];
    final directAsins = <String>[];
    final snsAsins = <String>[];
    final b2g1Asins = <String>[];

    for (final item in selected) {
      final asin = _extractAmazonAsin(item.asinOrSku);
      if (asin != null) {
        directItems.add(item);
        directAsins.add(asin);
        if (item.snsEligible) snsAsins.add(asin);
        if (item.b2g1Eligible) b2g1Asins.add(asin);
      } else {
        fallbackItems.add(item);
      }
    }

    final totalMsrp = selected.fold<double>(0.0, (s, o) => s + o.msrp);
    final totalSale = selected.fold<double>(0.0, (s, o) => s + o.currentPrice);
    final totalCoupons = selected.fold<double>(0.0, (s, o) => s + o.clipCouponAmount);
    final totalSns = selected
        .where((o) => o.snsEligible)
        .fold<double>(0.0, (s, o) => s + o.currentPrice * stack.snsTierRate);
    final pgSavings = stack.pgCreditUnlocked;
    final b2g1Savings = stack.b2g1FreeItemDeduction;
    final netCheckout = math.max(0.0, totalSale - totalCoupons - totalSns - pgSavings - b2g1Savings);
    final totalSavings = math.max(0.0, totalMsrp - netCheckout);
    final effPct = totalMsrp > 0 ? ((totalSavings / totalMsrp) * 100).round() : 0;

    final steps = <CartChecklistStep>[
      CartChecklistStep(
        stepNumber: 1,
        title: 'Clip On-Page Coupons Before Checkout',
        detail: totalCoupons > 0
            ? 'Open items with green coupons first to save \$${totalCoupons.toStringAsFixed(2)} automatically.'
            : 'No extra clip coupons currently needed on your selected items.',
        badge: '-\$${totalCoupons.toStringAsFixed(2)}',
        category: 'coupons',
      ),
      CartChecklistStep(
        stepNumber: 2,
        title: 'Group Subscribe & Save Items (5+ for 15% Off)',
        detail: stack.snsUnlocked15Pct
            ? '15% S&S tier unlocked with ${stack.snsActiveCount} items (-\$${totalSns.toStringAsFixed(2)}).'
            : 'Currently ${stack.snsActiveCount}/5 S&S items selected. Add ${math.max(0, 5 - stack.snsActiveCount)} more for 15% off.',
        badge: stack.snsUnlocked15Pct ? '15% UNLOCKED' : '${stack.snsActiveCount}/5 S&S',
        category: 'sns',
      ),
      CartChecklistStep(
        stepNumber: 3,
        title: 'Check Out B2G1 Trio Separately',
        detail: b2g1Savings > 0
            ? 'Your B2G1 trio saves \$${b2g1Savings.toStringAsFixed(2)} on the lowest-priced game/toy.'
            : 'Select 3 B2G1-eligible games/toys to unlock the free 3rd item.',
        badge: '-\$${b2g1Savings.toStringAsFixed(2)}',
        category: 'b2g1',
      ),
    ];

    return AmazonCartBuilderPlan(
      scope: scope,
      cartAddUrl: _buildMultiAsinUrl(directAsins),
      snsCartAddUrl: _buildMultiAsinUrl(snsAsins),
      b2g1CartAddUrl: _buildMultiAsinUrl(b2g1Asins),
      directAsinCount: directItems.length,
      totalSelectedCount: selected.length,
      directAsinItems: directItems,
      searchFallbackItems: fallbackItems,
      totalMsrp: double.parse(totalMsrp.toStringAsFixed(2)),
      totalSalePrice: double.parse(totalSale.toStringAsFixed(2)),
      totalCouponSavings: double.parse(totalCoupons.toStringAsFixed(2)),
      totalSnsSavings: double.parse(totalSns.toStringAsFixed(2)),
      pgCreditSavings: pgSavings,
      b2g1FreeSavings: b2g1Savings,
      netEstimatedCheckout: double.parse(netCheckout.toStringAsFixed(2)),
      totalSavings: double.parse(totalSavings.toStringAsFixed(2)),
      effectiveDiscountPct: effPct,
      checklistSteps: steps,
    );
  }

  static String? _extractAmazonAsin(String raw) {
    final match = RegExp(r'\b(B0[A-Z0-9]{8})\b').firstMatch(raw.toUpperCase());
    return match?.group(1);
  }

  static String? _buildMultiAsinUrl(List<String> asins) {
    if (asins.isEmpty) return null;
    final params = <String>[];
    for (int i = 0; i < asins.length; i++) {
      final idx = i + 1;
      params.add('ASIN.$idx=${asins[i]}&Quantity.$idx=1');
    }
    return 'https://www.amazon.com/gp/aws/cart/add.html?${params.join('&')}';
  }

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> src) {
    return jsonDecode(jsonEncode(src)) as Map<String, dynamic>;
  }
}
