import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/deal_models.dart';
import '../repositories/deal_repository.dart';

final dealRepositoryProvider = Provider<DealRepository>((ref) {
  return DealRepository();
});

final selectedNodeTypeFilterProvider = StateProvider<MissionNodeType?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');
final onlyBelowStrikeProvider = StateProvider<bool>((ref) => false);

class DealDashboardState {
  final List<ShoppingMission> missions;
  final CombinatoricStackSummary? stackSummary;
  final List<WebhookAlertLog> alerts;
  final Map<String, dynamic> health;
  final AmazonCartBuilderPlan? cartPlan;
  final ProviderSettings? providerSettings;
  final bool isBusy;

  const DealDashboardState({
    required this.missions,
    required this.stackSummary,
    required this.alerts,
    required this.health,
    this.cartPlan,
    this.providerSettings,
    this.isBusy = false,
  });

  DealDashboardState copyWith({
    List<ShoppingMission>? missions,
    CombinatoricStackSummary? stackSummary,
    List<WebhookAlertLog>? alerts,
    Map<String, dynamic>? health,
    AmazonCartBuilderPlan? cartPlan,
    ProviderSettings? providerSettings,
    bool? isBusy,
  }) {
    return DealDashboardState(
      missions: missions ?? this.missions,
      stackSummary: stackSummary ?? this.stackSummary,
      alerts: alerts ?? this.alerts,
      health: health ?? this.health,
      cartPlan: cartPlan ?? this.cartPlan,
      providerSettings: providerSettings ?? this.providerSettings,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

class DealDashboardNotifier extends AsyncNotifier<DealDashboardState> {
  @override
  Future<DealDashboardState> build() async {
    return _fetchAll();
  }

  Future<DealDashboardState> _fetchAll() async {
    final repo = ref.read(dealRepositoryProvider);
    final results = await Future.wait([
      repo.fetchMissions(),
      repo.fetchStackSummary(),
      repo.fetchAlerts(),
      repo.fetchHealth(),
      repo.fetchCartPlan(scope: 'recommended'),
      repo.fetchSettings(),
    ]);
    return DealDashboardState(
      missions: results[0] as List<ShoppingMission>,
      stackSummary: results[1] as CombinatoricStackSummary,
      alerts: results[2] as List<WebhookAlertLog>,
      health: results[3] as Map<String, dynamic>,
      cartPlan: results[4] as AmazonCartBuilderPlan,
      providerSettings: results[5] as ProviderSettings,
    );
  }

  Future<void> refreshAll() async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(isBusy: true));
    }
    state = await AsyncValue.guard(() => _fetchAll());
  }

  Future<void> translateAndAddIntent(String rawIntent, {double? budgetHint}) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(isBusy: true));
    }
    final repo = ref.read(dealRepositoryProvider);
    await repo.createMissionFromIntent(rawIntent: rawIntent, budgetHint: budgetHint);
    state = await AsyncValue.guard(() => _fetchAll());
  }

  Future<void> deleteMission(int missionId) async {
    final repo = ref.read(dealRepositoryProvider);
    await repo.deleteMission(missionId);
    state = await AsyncValue.guard(() => _fetchAll());
  }

  Future<void> patchOption({
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
    final repo = ref.read(dealRepositoryProvider);
    await repo.patchOptionNode(
      optionId: optionId,
      currentPrice: currentPrice,
      avg90dPrice: avg90dPrice,
      allTimeLow: allTimeLow,
      clipCouponAmount: clipCouponAmount,
      strikePrice: strikePrice,
      snsEligible: snsEligible,
      selectedInStack: selectedInStack,
      snagged: snagged,
      priceSource: priceSource,
      appendHistoryPoint: appendHistoryPoint,
      historyNote: historyNote,
    );
    state = await AsyncValue.guard(() => _fetchAll());
  }

  Future<void> runPoller({bool simulateDrop = false}) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(isBusy: true));
    }
    final repo = ref.read(dealRepositoryProvider);
    await repo.triggerPoller(simulateDrop: simulateDrop);
    state = await AsyncValue.guard(() => _fetchAll());
  }

  Future<void> sendTestAlert({int? optionId, String? customMessage}) async {
    final repo = ref.read(dealRepositoryProvider);
    await repo.triggerTestWebhook(optionId: optionId, customMessage: customMessage);
    state = await AsyncValue.guard(() => _fetchAll());
  }

  Future<void> resetSeed() async {
    final repo = ref.read(dealRepositoryProvider);
    await repo.resetDatabase();
    state = await AsyncValue.guard(() => _fetchAll());
  }

  Future<void> updateProviderSettings(Map<String, dynamic> patch) async {
    final repo = ref.read(dealRepositoryProvider);
    await repo.updateSettings(patch);
    state = await AsyncValue.guard(() => _fetchAll());
  }
}

final dealDashboardProvider =
    AsyncNotifierProvider<DealDashboardNotifier, DealDashboardState>(
  DealDashboardNotifier.new,
);

