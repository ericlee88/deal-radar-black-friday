import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/deal_models.dart';
import 'product_thumbnail.dart';

class AmazonCartBuilderDialog extends StatefulWidget {
  final AmazonCartBuilderPlan plan;

  const AmazonCartBuilderDialog({
    super.key,
    required this.plan,
  });

  @override
  State<AmazonCartBuilderDialog> createState() => _AmazonCartBuilderDialogState();
}

class _AmazonCartBuilderDialogState extends State<AmazonCartBuilderDialog> {
  final Set<int> _checkedSteps = {};

  Future<void> _launchUrl(String? rawUrl) async {
    if (rawUrl == null || rawUrl.isEmpty) return;
    final uri = Uri.tryParse(rawUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;

    return Dialog(
      backgroundColor: const Color(0xFF111621),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.shopping_cart_checkout_rounded,
                          color: Color(0xFFFBBF24),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '1-Click Amazon Multi-ASIN Cart & Checkout Plan',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${plan.directAsinCount} Verified Amazon ASINs Ready for Batch Add-to-Cart | ${plan.checklistSteps.length}-Step Promo Execution Plan',
                            style: const TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Financial Savings Summary Bar
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _metricColumn('MSRP Total', '\$${plan.totalMsrp.toStringAsFixed(2)}', Colors.white54, strike: true),
                    _metricColumn('Sale Subtotal', '\$${plan.totalSalePrice.toStringAsFixed(2)}', Colors.white),
                    _metricColumn('Clip Coupons', '-\$${plan.totalCouponSavings.toStringAsFixed(2)}', const Color(0xFFF59E0B)),
                    _metricColumn('15% S&S Tier', '-\$${plan.totalSnsSavings.toStringAsFixed(2)}', const Color(0xFF38BDF8)),
                    _metricColumn('P&G \$100 Bonus', '-\$${plan.pgCreditSavings.toStringAsFixed(2)}', const Color(0xFF10B981)),
                    _metricColumn('3-for-2 Free Game', '-\$${plan.b2g1FreeSavings.toStringAsFixed(2)}', const Color(0xFFA78BFA)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'EST. NET CHECKOUT (-${plan.effectiveDiscountPct}%)',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4ADE80),
                            ),
                          ),
                          Text(
                            '\$${plan.netEstimatedCheckout.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            'Total Saved: \$${plan.totalSavings.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFF4ADE80)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 1-Click Amazon Cart Launch Buttons
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (plan.cartAddUrl != null)
                    FilledButton.icon(
                      onPressed: () => _launchUrl(plan.cartAddUrl),
                      icon: const Icon(Icons.rocket_launch_rounded, size: 17),
                      label: Text('1-Click Add All ${plan.directAsinCount} ASINs to Amazon Cart'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                  if (plan.snsCartAddUrl != null)
                    FilledButton.tonalIcon(
                      onPressed: () => _launchUrl(plan.snsCartAddUrl),
                      icon: const Icon(Icons.autorenew_rounded, size: 16),
                      label: const Text('Open S&S + P&G 5-Item Cart'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                        foregroundColor: const Color(0xFF4ADE80),
                      ),
                    ),
                  if (plan.b2g1CartAddUrl != null)
                    FilledButton.tonalIcon(
                      onPressed: () => _launchUrl(plan.b2g1CartAddUrl),
                      icon: const Icon(Icons.extension_rounded, size: 16),
                      label: const Text('Open 3-for-2 Board Game Cart'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                        foregroundColor: const Color(0xFFC4B5FD),
                      ),
                    ),
                  if (plan.cartAddUrl != null)
                    OutlinedButton.icon(
                      onPressed: () => _copyToClipboard(plan.cartAddUrl!, 'Multi-ASIN Amazon Cart URL'),
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: const Text('Copy Cart Link'),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Body: Two-Column or Scrollable Checklist + Items
              Expanded(
                child: ListView(
                  children: [
                    const Text(
                      'STEP-BY-STEP CHECKOUT EXECUTION CHECKLIST',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF38BDF8),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...plan.checklistSteps.map((step) {
                      final done = _checkedSteps.contains(step.stepNumber);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: done
                              ? const Color(0xFF064E3B).withValues(alpha: 0.25)
                              : const Color(0xFF161C28),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: done
                                ? const Color(0xFF10B981).withValues(alpha: 0.5)
                                : Colors.white12,
                          ),
                        ),
                        child: CheckboxListTile(
                          value: done,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _checkedSteps.add(step.stepNumber);
                              } else {
                                _checkedSteps.remove(step.stepNumber);
                              }
                            });
                          },
                          activeColor: const Color(0xFF10B981),
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0EA5E9).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  'STEP ${step.stepNumber}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF38BDF8),
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  step.title,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: done ? Colors.white60 : Colors.white,
                                    decoration: done ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E).withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  step.badge,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF4ADE80),
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              step.detail,
                              style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.35),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 14),
                    Text(
                      'INCLUDED ITEMS IN 1-CLICK MULTI-ASIN CART (${plan.directAsinItems.length})',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFBBF24),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...plan.directAsinItems.map(
                      (item) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161C28),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 56,
                              child: ProductThumbnail(
                                option: item,
                                categoryTag: item.snsEligible
                                    ? 'consumables'
                                    : (item.b2g1Eligible ? 'games' : 'tools'),
                                height: 46,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'ASIN: ${item.asinOrSku} | Sale: \$${item.currentPrice.toStringAsFixed(2)}'
                                    '${item.clipCouponAmount > 0 ? " | Coupon: -\$${item.clipCouponAmount.toStringAsFixed(2)}" : ""}'
                                    ' | Net: \$${item.effectivePrice.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.white60,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _launchUrl(item.amazonUrl),
                              icon: const Icon(Icons.open_in_new_rounded, size: 14),
                              label: const Text('Page', style: TextStyle(fontSize: 11.5)),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
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

  Widget _metricColumn(String label, String value, Color valueColor, {bool strike = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: valueColor,
            fontFamily: 'monospace',
            decoration: strike ? TextDecoration.lineThrough : null,
          ),
        ),
      ],
    );
  }
}
