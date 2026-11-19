import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/deal_models.dart';
import '../providers/deal_providers.dart';
import 'widgets/mission_card.dart';
import 'widgets/simple_landing_view.dart';

class DealDashboardScreen extends ConsumerStatefulWidget {
  const DealDashboardScreen({super.key});

  @override
  ConsumerState<DealDashboardScreen> createState() => _DealDashboardScreenState();
}

class _DealDashboardScreenState extends ConsumerState<DealDashboardScreen> {
  bool _isPowerUserMode = false;
  int _activeTab = 0;
  final _intentCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();

  @override
  void dispose() {
    _intentCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitIntent() async {
    final text = _intentCtrl.text.trim();
    if (text.isEmpty) return;
    final budget = double.tryParse(_budgetCtrl.text.trim());
    _intentCtrl.clear();
    _budgetCtrl.clear();
    await ref
        .read(dealDashboardProvider.notifier)
        .translateAndAddIntent(text, budgetHint: budget);
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(dealDashboardProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF090C10),
      body: SafeArea(
        child: asyncState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, st) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text(
                    'Backend Connection Error: $err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => ref.read(dealDashboardProvider.notifier).refreshAll(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Connection'),
                  ),
                ],
              ),
            ),
          ),
          data: (data) => _buildContent(context, data),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, DealDashboardState data) {
    final allOptions = data.missions.expand((m) => m.options).toList();
    final readyCount = allOptions.where((o) => o.isBelowStrike).length;
    final snaggedOpts = allOptions.where((o) => o.snagged).toList();
    final snaggedSaved = snaggedOpts.fold<double>(
      0.0,
      (acc, o) => acc + (o.msrp - o.effectivePrice).clamp(0.0, double.infinity),
    );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // 1. Top Navigation & Mode Switcher (Simple Shopper vs Power User Mode)
              _buildHeaderBar(data),
              const SizedBox(height: 18),

              if (!_isPowerUserMode)
                SimpleLandingView(
                  data: data,
                  onSwitchToPowerMode: () => setState(() => _isPowerUserMode = true),
                )
              else ...[
                // 2. LLM Fuzzy-Intent-to-DAG Composer Bar
                _buildIntentComposer(data.isBusy),
                const SizedBox(height: 16),

                // 3. KPI Summary Strip
                _buildKpiStrip(
                  missionCount: data.missions.length,
                  optionCount: allOptions.length,
                  readyCount: readyCount,
                  stackSummary: data.stackSummary,
                  snaggedCount: snaggedOpts.length,
                  snaggedSaved: snaggedSaved,
                  alertCount: data.alerts.length,
                ),
                const SizedBox(height: 18),

                // 4. Primary Navigation Tabs
                _buildTabSelector(data.alerts.length),
                const SizedBox(height: 16),

                // 5. Active Tab Body
                if (_activeTab == 0) _buildMissionDagTab(data),
                if (_activeTab == 1) _buildCombinatoricStackTab(data),
                if (_activeTab == 2) _buildWebhookAlertsTab(data),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBar(DealDashboardState data) {
    final llmMode = data.health['active_llm_provider'] ?? 'mock';
    final priceMode = data.health['active_price_provider'] ?? 'mock';
    final webhookMode = data.health['webhook_provider'] ?? 'local_inbox';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF141821),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 14,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.radar_rounded, color: Color(0xFF38BDF8), size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Deal Radar',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _providerPill('BLACK FRIDAY', const Color(0xFF0EA5E9)),
                      if (_isPowerUserMode) ...[
                        const SizedBox(width: 6),
                        _providerPill('LLM: ${llmMode.toString().toUpperCase()}', const Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        _providerPill('PRICE: ${priceMode.toString().toUpperCase()}', const Color(0xFFF59E0B)),
                        const SizedBox(width: 6),
                        _providerPill('WEBHOOK: ${webhookMode.toString().toUpperCase()}', const Color(0xFFEC4899)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _isPowerUserMode
                        ? 'Power User Mode: Polymorphic Shopping Mission DAG & Strike-Price Engine'
                        : 'Personal Black Friday Deal Finder • Curated Picks, Coupons & Cart Bundles',
                    style: const TextStyle(fontSize: 12.5, color: Colors.white60),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Mode Switcher Segmented Control
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0E14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _modeButton(
                      selected: !_isPowerUserMode,
                      icon: Icons.grid_view_rounded,
                      label: 'Simple Shopper',
                      onTap: () => setState(() => _isPowerUserMode = false),
                    ),
                    _modeButton(
                      selected: _isPowerUserMode,
                      icon: Icons.account_tree_outlined,
                      label: 'Power User (DAG)',
                      onTap: () => setState(() => _isPowerUserMode = true),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: data.isBusy
                    ? null
                    : () => ref
                        .read(dealDashboardProvider.notifier)
                        .runPoller(simulateDrop: true),
                icon: const Icon(Icons.bolt, size: 16),
                label: const Text('Simulate Price Drop'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0EA5E9),
                  foregroundColor: Colors.white,
                ),
              ),
              if (_isPowerUserMode)
                OutlinedButton.icon(
                  onPressed: data.isBusy
                      ? null
                      : () => ref.read(dealDashboardProvider.notifier).sendTestAlert(),
                  icon: const Icon(Icons.notifications_active_outlined, size: 15),
                  label: const Text('Test Webhook'),
                ),
              OutlinedButton.icon(
                onPressed: data.isBusy
                    ? null
                    : () => ref.read(dealDashboardProvider.notifier).resetSeed(),
                icon: const Icon(Icons.restart_alt, size: 15),
                label: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeButton({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0284C7) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildIntentComposer(bool isBusy) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141821),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF38BDF8), size: 20),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: TextField(
              controller: _intentCtrl,
              onSubmitted: (_) => _submitIntent(),
              style: const TextStyle(fontSize: 13.5, color: Colors.white),
              decoration: const InputDecoration(
                hintText:
                    'Enter fuzzy or exact shopping intent (e.g., "Anker 140W GaN charger vs Ugreen Nexode" or "Knipex Cobra pliers set")...',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _budgetCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 13, color: Colors.white, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: 'Strike \$ (opt)',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: isBusy ? null : _submitIntent,
            child: Text(isBusy ? 'Translating...' : 'Add to Mission DAG'),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiStrip({
    required int missionCount,
    required int optionCount,
    required int readyCount,
    required CombinatoricStackSummary? stackSummary,
    required int snaggedCount,
    required double snaggedSaved,
    required int alertCount,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _kpiBox(
          title: 'Polymorphic DAG Nodes',
          value: '$missionCount Missions / $optionCount SKUs',
          sub: 'EXACT | XOR_FORK | FUNNEL | STACK',
          valueColor: Colors.white,
        ),
        _kpiBox(
          title: 'At / Below Strike Price',
          value: '$readyCount Ready Now',
          sub: 'Green-lit to buy immediately',
          valueColor: const Color(0xFF22C55E),
        ),
        _kpiBox(
          title: 'S&S 15% + \$25 P&G Net Stack',
          value: stackSummary != null
              ? '\$${stackSummary.consumablesNetOutOfPocket.toStringAsFixed(2)} (-${stackSummary.consumablesEffectiveDiscountPct}%)'
              : '--',
          sub: stackSummary != null && stackSummary.snsUnlocked15Pct
              ? '15% Tier + \$${stackSummary.pgCreditUnlocked.toStringAsFixed(0)} Credit Unlocked'
              : 'Toggle 5+ S&S items in Tab 2',
          valueColor: const Color(0xFF38BDF8),
        ),
        _kpiBox(
          title: '3-for-2 Board Game Bundle',
          value: stackSummary != null
              ? '\$${stackSummary.b2g1NetTotal.toStringAsFixed(2)} (Save \$${stackSummary.b2g1FreeItemDeduction.toStringAsFixed(2)})'
              : '--',
          sub: stackSummary?.b2g1HarmonyVerdict ?? '',
          valueColor: const Color(0xFFF59E0B),
        ),
        _kpiBox(
          title: 'Snagged & Webhook Alerts',
          value: '\$${snaggedSaved.toStringAsFixed(2)} Saved ($snaggedCount)',
          sub: '$alertCount strike alerts logged',
          valueColor: const Color(0xFF10B981),
        ),
      ],
    );
  }

  Widget _kpiBox({
    required String title,
    required String value,
    required String sub,
    required Color valueColor,
  }) {
    return Container(
      width: 235,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141821),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: valueColor,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector(int alertCount) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('1. Polymorphic Mission DAG (All 7 Missions)'),
          selected: _activeTab == 0,
          onSelected: (_) => setState(() => _activeTab = 0),
        ),
        ChoiceChip(
          label: const Text('2. Combinatoric Promo & S&S Stack Solver'),
          selected: _activeTab == 1,
          onSelected: (_) => setState(() => _activeTab = 1),
        ),
        ChoiceChip(
          label: Text('3. Webhook Strike Alert Log ($alertCount)'),
          selected: _activeTab == 2,
          onSelected: (_) => setState(() => _activeTab = 2),
        ),
      ],
    );
  }

  Widget _buildMissionDagTab(DealDashboardState data) {
    final selectedType = ref.watch(selectedNodeTypeFilterProvider);
    final onlyStrike = ref.watch(onlyBelowStrikeProvider);
    final query = ref.watch(searchQueryProvider).toLowerCase();

    final filtered = data.missions.where((m) {
      if (selectedType != null && m.nodeType != selectedType) return false;
      if (onlyStrike && !m.options.any((o) => o.isBelowStrike)) return false;
      if (query.isNotEmpty) {
        final hay =
            '${m.title} ${m.rawIntent} ${m.options.map((o) => '${o.title} ${o.asinOrSku}').join(' ')}'
                .toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141821),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('DAG Node Type:', style: TextStyle(fontSize: 12, color: Colors.white60)),
              FilterChip(
                label: const Text('All Types', style: TextStyle(fontSize: 11.5)),
                selected: selectedType == null,
                onSelected: (_) =>
                    ref.read(selectedNodeTypeFilterProvider.notifier).state = null,
              ),
              ...MissionNodeType.values.map(
                (t) => FilterChip(
                  label: Text(t.label, style: const TextStyle(fontSize: 11.5)),
                  selected: selectedType == t,
                  onSelected: (_) => ref
                      .read(selectedNodeTypeFilterProvider.notifier)
                      .state = (selectedType == t ? null : t),
                ),
              ),
              FilterChip(
                label: const Text('[STRIKE] At/Below Strike Only', style: TextStyle(fontSize: 11.5)),
                selected: onlyStrike,
                onSelected: (v) => ref.read(onlyBelowStrikeProvider.notifier).state = v,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...filtered.map((m) => MissionDagCard(mission: m)),
      ],
    );
  }

  Widget _buildCombinatoricStackTab(DealDashboardState data) {
    final stack = data.stackSummary;
    if (stack == null) return const SizedBox.shrink();

    final allOpts = data.missions.expand((m) => m.options).toList();
    final snsOpts = allOpts.where((o) => o.snsEligible).toList();
    final b2g1Opts = allOpts.where((o) => o.b2g1Eligible).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // S&S + P&G Stock-Up Combinatoric Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF141821),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Subscribe & Save 5-Item Step Function + P&G \$100->\$25 Promo Solver',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                'Active S&S Items: ${stack.snsActiveCount} (${(stack.snsTierRate * 100).toStringAsFixed(0)}% Tier) | '
                'P&G Qualifying Subtotal: \$${stack.pgQualifyingSubtotal.toStringAsFixed(2)} / \$100.00 | '
                'Net Out-of-Pocket: \$${stack.consumablesNetOutOfPocket.toStringAsFixed(2)} (-${stack.consumablesEffectiveDiscountPct}% off \$${stack.consumablesMsrpTotal.toStringAsFixed(2)} MSRP)',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF22C55E),
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 14),
              ...snsOpts.map(
                (opt) => CheckboxListTile(
                  value: opt.selectedInStack,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    opt.title,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                  subtitle: Text(
                    'Sale: \$${opt.currentPrice.toStringAsFixed(2)} | Clip Coupon: -\$${opt.clipCouponAmount.toStringAsFixed(2)} | Net: \$${opt.effectivePrice.toStringAsFixed(2)} (${opt.pgStockupEligible ? "P&G \$100->\$25 Eligible" : "Standard S&S"})',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white60,
                      fontFamily: 'monospace',
                    ),
                  ),
                  onChanged: (v) {
                    ref.read(dealDashboardProvider.notifier).patchOption(
                          optionId: opt.id,
                          selectedInStack: v ?? false,
                        );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3-for-2 Board Game Harmony Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF141821),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Amazon "Get 3 for the Price of 2" (Buy 2, Get 1 Free) Board Game Optimizer',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                '${stack.b2g1HarmonyVerdict} | Free Item Deduction: -\$${stack.b2g1FreeItemDeduction.toStringAsFixed(2)} | Final Bundle Total: \$${stack.b2g1NetTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFF59E0B),
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              ...b2g1Opts.map(
                (opt) => CheckboxListTile(
                  value: opt.selectedInStack,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    opt.title,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                  subtitle: Text(
                    'BF Price: \$${opt.currentPrice.toStringAsFixed(2)} (MSRP \$${opt.msrp.toStringAsFixed(2)})',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white60,
                      fontFamily: 'monospace',
                    ),
                  ),
                  onChanged: (v) {
                    ref.read(dealDashboardProvider.notifier).patchOption(
                          optionId: opt.id,
                          selectedInStack: v ?? false,
                        );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWebhookAlertsTab(DealDashboardState data) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141821),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Webhook & Push Alert Audit Log (Telegram / Discord / Slack / ntfy.sh)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Automatically dispatches whenever an item\'s Net Effective Price crosses at or below its Strike Target.',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
              FilledButton.tonalIcon(
                onPressed: () => ref.read(dealDashboardProvider.notifier).sendTestAlert(),
                icon: const Icon(Icons.send, size: 15),
                label: const Text('Dispatch Test Alert'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (data.alerts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No alerts dispatched yet. Click "Simulate BF Price Drop + Alert" in the top bar or lower an item\'s price below its Strike Price.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            )
          else
            ...data.alerts.map(
              (a) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1017),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '[STRIKE HIT] ${a.optionTitle}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Effective: \$${a.effectivePrice.toStringAsFixed(2)} <= Strike: \$${a.strikePrice.toStringAsFixed(2)} | Channel: ${a.channel} (${a.status})',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF22C55E),
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      a.createdAt.length >= 19 ? a.createdAt.substring(11, 19) : a.createdAt,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
