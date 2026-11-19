import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/deal_models.dart';
import '../../providers/deal_providers.dart';
import 'price_history_dialog.dart';
import 'product_thumbnail.dart';
import 'sparkline_painter.dart';

class MissionDagCard extends ConsumerWidget {
  final ShoppingMission mission;

  const MissionDagCard({super.key, required this.mission});

  Color _nodeBadgeColor(MissionNodeType t) {
    switch (t) {
      case MissionNodeType.exactSku:
        return const Color(0xFF0EA5E9);
      case MissionNodeType.xorFork:
        return const Color(0xFFF59E0B);
      case MissionNodeType.categoryFunnel:
        return const Color(0xFF10B981);
      case MissionNodeType.consumableStack:
        return const Color(0xFFEC4899);
    }
  }

  IconData _categoryIcon(String tag) {
    switch (tag) {
      case 'kitchen':
        return Icons.restaurant_menu;
      case 'tools':
        return Icons.handyman;
      case 'vacuums':
        return Icons.cleaning_services;
      case 'health':
        return Icons.favorite_border;
      case 'consumables':
        return Icons.inventory_2_outlined;
      case 'games':
        return Icons.extension;
      default:
        return Icons.track_changes;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeColor = _nodeBadgeColor(mission.nodeType);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      color: const Color(0xFF141821),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mission Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_categoryIcon(mission.categoryTag), color: badgeColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: badgeColor.withValues(alpha: 0.45)),
                            ),
                            child: Text(
                              '${mission.nodeType.wireValue} | ${mission.nodeType.subtitle}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: badgeColor,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          Text(
                            'Prompt: "${mission.rawIntent}"',
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        mission.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (mission.decisionFraming.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          mission.decisionFraming,
                          style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete Mission from DAG',
                  onPressed: () {
                    ref.read(dealDashboardProvider.notifier).deleteMission(mission.id);
                  },
                  icon: const Icon(Icons.delete_outline, size: 19, color: Colors.white38),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 14),

            // Candidate Options / Fork Branches Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 760 && mission.options.length > 1;
                if (isWide) {
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: mission.options.map((opt) {
                      final colWidth = mission.options.length >= 3
                          ? (constraints.maxWidth - 24) / 3
                          : (constraints.maxWidth - 12) / 2;
                      return SizedBox(
                        width: colWidth,
                        child: _OptionBranchTile(option: opt),
                      );
                    }).toList(),
                  );
                }
                return Column(
                  children: mission.options
                      .map((opt) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _OptionBranchTile(option: opt),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionBranchTile extends ConsumerWidget {
  final DealOptionNode option;

  const _OptionBranchTile({required this.option});

  Color _gradeColor(String code) {
    switch (code) {
      case 'ATL':
      case 'STRIKE':
        return const Color(0xFF22C55E);
      case 'TRAP':
        return const Color(0xFFEF4444);
      case 'HOLD':
        return const Color(0xFF38BDF8);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Future<void> _launchExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showEditPriceDialog(BuildContext context, WidgetRef ref) {
    final priceCtrl = TextEditingController(text: option.currentPrice.toStringAsFixed(2));
    final couponCtrl = TextEditingController(text: option.clipCouponAmount.toStringAsFixed(2));
    final strikeCtrl = TextEditingController(text: option.strikePrice.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2C),
        title: Text(
          'Live Price Check & Strike Tuning',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(option.title, style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
              const SizedBox(height: 14),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Spotted Amazon Price (\$)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: couponCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Clipped Coupon Deduction (\$)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: strikeCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Your Target Strike Price (\$)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newPrice = double.tryParse(priceCtrl.text);
              final newCoupon = double.tryParse(couponCtrl.text);
              final newStrike = double.tryParse(strikeCtrl.text);
              ref.read(dealDashboardProvider.notifier).patchOption(
                    optionId: option.id,
                    currentPrice: newPrice,
                    clipCouponAmount: newCoupon,
                    strikePrice: newStrike,
                  );
              Navigator.of(ctx).pop();
            },
            child: const Text('Save & Evaluate Strike'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gColor = _gradeColor(option.dealGradeCode);
    final borderColor = option.isTrapWarning
        ? const Color(0xFFEF4444).withValues(alpha: 0.65)
        : (option.isBelowStrike
            ? const Color(0xFF22C55E).withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.12));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1017),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: borderColor, width: option.isRecommendedBranch ? 1.4 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Branch & Grade Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  option.branchLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: option.isTrapWarning
                        ? const Color(0xFFEF4444)
                        : (option.isRecommendedBranch ? const Color(0xFF38BDF8) : Colors.white70),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: gColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: gColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  option.dealGradeLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: gColor,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Thumbnail + Title & SKU
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                child: ProductThumbnail(
                  option: option,
                  categoryTag: '',
                  height: 60,
                  compact: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'SKU/ASIN: ${option.asinOrSku} | \$${option.unitEffectivePrice.toStringAsFixed(2)} / ${option.unitName}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Price & Sparkline Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF141923),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Net Effective',
                        style: TextStyle(fontSize: 10.5, color: Colors.white54),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '\$${option.effectivePrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: gColor,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '\$${option.msrp.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              decoration: TextDecoration.lineThrough,
                              color: Colors.white38,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Strike: \$${option.strikePrice.toStringAsFixed(2)} | ATL: \$${option.allTimeLow.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.white60,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${option.isVerifiedPrice ? "[VERIFIED]" : "[EST]"} 90d Avg: \$${option.avg90dPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: option.isVerifiedPrice
                              ? const Color(0xFF4ADE80)
                              : Colors.white54,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      InkWell(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => PriceHistoryDialog(option: option),
                        ),
                        borderRadius: BorderRadius.circular(6),
                        child: SparklineWidget(
                          history: option.priceHistory,
                          strikePrice: option.strikePrice,
                          msrp: option.msrp,
                          allTimeLow: option.allTimeLow,
                          isBelowStrike: option.isBelowStrike,
                          isTrap: option.isTrapWarning,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Scout Notes
          Text(
            option.scoutNotes,
            style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 12),

          // Action Buttons Row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _launchExternal(option.amazonUrl),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: Text(
                  'Product Page (${option.asinOrSku.split(" ").first})',
                  style: const TextStyle(fontSize: 11.5),
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PriceHistoryDialog(option: option),
                ),
                icon: const Icon(Icons.show_chart_rounded, size: 13),
                label: Text(
                  option.priceLog.isNotEmpty
                      ? 'History/CCC (${option.priceLog.length})'
                      : 'History/CCC',
                  style: const TextStyle(fontSize: 11.5),
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showEditPriceDialog(context, ref),
                icon: const Icon(Icons.tune, size: 13),
                label: const Text('Edit Price/Strike', style: TextStyle(fontSize: 11.5)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
              if (option.snsEligible || option.b2g1Eligible)
                FilterChip(
                  label: Text(
                    option.snsEligible ? 'In S&S Stack' : 'In 3-for-2',
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: option.selectedInStack,
                  visualDensity: VisualDensity.compact,
                  onSelected: (val) {
                    ref.read(dealDashboardProvider.notifier).patchOption(
                          optionId: option.id,
                          selectedInStack: val,
                        );
                  },
                ),
              FilterChip(
                label: Text(
                  option.snagged ? '[Snagged]' : 'Mark Snagged',
                  style: const TextStyle(fontSize: 11),
                ),
                selected: option.snagged,
                selectedColor: const Color(0xFF22C55E).withValues(alpha: 0.25),
                visualDensity: VisualDensity.compact,
                onSelected: (val) {
                  ref.read(dealDashboardProvider.notifier).patchOption(
                        optionId: option.id,
                        snagged: val,
                      );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
