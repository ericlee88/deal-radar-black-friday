import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/deal_models.dart';
import '../../providers/deal_providers.dart';
import 'sparkline_painter.dart';

class PriceHistoryDialog extends ConsumerStatefulWidget {
  final DealOptionNode option;

  const PriceHistoryDialog({super.key, required this.option});

  @override
  ConsumerState<PriceHistoryDialog> createState() => _PriceHistoryDialogState();
}

class _PriceHistoryDialogState extends ConsumerState<PriceHistoryDialog> {
  late final TextEditingController _currentCtrl;
  late final TextEditingController _avgCtrl;
  late final TextEditingController _atlCtrl;
  late final TextEditingController _couponCtrl;
  late final TextEditingController _strikeCtrl;
  final TextEditingController _camelPasteCtrl = TextEditingController();

  String _sourceTag = 'camelcamelcamel';
  String? _parseMessage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final o = widget.option;
    _currentCtrl = TextEditingController(text: o.currentPrice.toStringAsFixed(2));
    _avgCtrl = TextEditingController(text: o.avg90dPrice.toStringAsFixed(2));
    _atlCtrl = TextEditingController(text: o.allTimeLow.toStringAsFixed(2));
    _couponCtrl = TextEditingController(text: o.clipCouponAmount.toStringAsFixed(2));
    _strikeCtrl = TextEditingController(text: o.strikePrice.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _avgCtrl.dispose();
    _atlCtrl.dispose();
    _couponCtrl.dispose();
    _strikeCtrl.dispose();
    _camelPasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _launchExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Parses copied text from CamelCamelCamel's summary table (Current / Lowest / Average).
  void _parseCamelText() {
    final raw = _camelPasteCtrl.text;
    if (raw.trim().isEmpty) {
      setState(() => _parseMessage = 'Paste text copied from CamelCamelCamel first.');
      return;
    }

    double? extractAfter(List<String> labels) {
      for (final label in labels) {
        final rx = RegExp(
          '$label[^\\\$0-9]{0,28}\\\$?([0-9]+(?:,[0-9]{3})*(?:\\.[0-9]{1,2})?)',
          caseSensitive: false,
        );
        final m = rx.firstMatch(raw);
        if (m != null) {
          final parsed = double.tryParse(m.group(1)!.replaceAll(',', ''));
          if (parsed != null && parsed > 0) return parsed;
        }
      }
      return null;
    }

    final current = extractAfter(['current', 'amazon price', 'now']);
    final lowest = extractAfter(['lowest', 'all-time low', 'all time low', 'min']);
    final average = extractAfter(['average', 'avg', '90-day', '90 day']);

    final found = <String>[];
    if (current != null) {
      _currentCtrl.text = current.toStringAsFixed(2);
      found.add('Current \$${current.toStringAsFixed(2)}');
    }
    if (average != null) {
      _avgCtrl.text = average.toStringAsFixed(2);
      found.add('Avg \$${average.toStringAsFixed(2)}');
    }
    if (lowest != null) {
      _atlCtrl.text = lowest.toStringAsFixed(2);
      found.add('Low \$${lowest.toStringAsFixed(2)}');
    }

    // Fallback: if no labels matched, grab up to 3 dollar values in order
    if (found.isEmpty) {
      final matches = RegExp(r'\$([0-9]+(?:\.[0-9]{2})?)').allMatches(raw).toList();
      if (matches.isNotEmpty) {
        final v0 = double.tryParse(matches[0].group(1)!);
        if (v0 != null) {
          _currentCtrl.text = v0.toStringAsFixed(2);
          found.add('Current \$${v0.toStringAsFixed(2)}');
        }
      }
      if (matches.length >= 2) {
        final v1 = double.tryParse(matches[1].group(1)!);
        if (v1 != null) {
          _atlCtrl.text = v1.toStringAsFixed(2);
          found.add('Low \$${v1.toStringAsFixed(2)}');
        }
      }
      if (matches.length >= 3) {
        final v2 = double.tryParse(matches[2].group(1)!);
        if (v2 != null) {
          _avgCtrl.text = v2.toStringAsFixed(2);
          found.add('Avg \$${v2.toStringAsFixed(2)}');
        }
      }
    }

    setState(() {
      _sourceTag = 'camelcamelcamel';
      _parseMessage = found.isEmpty
          ? 'Could not detect dollar amounts. Enter them manually below.'
          : 'Parsed: ${found.join(" | ")}';
    });
  }

  Future<void> _saveToLocalStorage() async {
    setState(() => _saving = true);
    try {
      final cur = double.tryParse(_currentCtrl.text.trim());
      final avg = double.tryParse(_avgCtrl.text.trim());
      final atl = double.tryParse(_atlCtrl.text.trim());
      final coupon = double.tryParse(_couponCtrl.text.trim());
      final strike = double.tryParse(_strikeCtrl.text.trim());

      await ref.read(dealDashboardProvider.notifier).patchOption(
            optionId: widget.option.id,
            currentPrice: cur,
            avg90dPrice: avg,
            allTimeLow: atl,
            clipCouponAmount: coupon,
            strikePrice: strike,
            priceSource: _sourceTag,
            appendHistoryPoint: true,
            historyNote: _sourceTag == 'camelcamelcamel'
                ? 'Logged from CamelCamelCamel'
                : 'Manual price check',
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Price history saved to device storage (localStorage).'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final opt = widget.option;
    final chartUrl = opt.camelChartUrl;

    return Dialog(
      backgroundColor: const Color(0xFF131822),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.white12),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: opt.isVerifiedPrice
                                    ? const Color(0xFF22C55E).withValues(alpha: 0.16)
                                    : const Color(0xFFF59E0B).withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                opt.isVerifiedPrice
                                    ? 'VERIFIED (${opt.priceSource.toUpperCase()})'
                                    : 'ESTIMATED SEED PRICE',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: opt.isVerifiedPrice
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFFFBBF24),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (opt.extractedAsin != null)
                              Text(
                                'ASIN: ${opt.extractedAsin}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white54,
                                  fontFamily: 'monospace',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          opt.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white60),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 1-Click External Launchers
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _launchExternal(opt.camelUrl),
                    icon: const Icon(Icons.show_chart_rounded, size: 16),
                    label: const Text('Open CamelCamelCamel'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0EA5E9),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _launchExternal(opt.amazonUrl),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('Open Amazon Product Page'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Colors.white12),
              const SizedBox(height: 14),

              // Scrollable body
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // CamelCamelCamel 1-Year Chart Image (with graceful fallback)
                      if (chartUrl != null) ...[
                        const Text(
                          'CamelCamelCamel 1-Year Amazon Price Chart',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.network(
                            chartUrl,
                            height: 185,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stack) => Container(
                              height: 92,
                              color: const Color(0xFF0B0E14),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  const Icon(Icons.timeline_rounded, color: Color(0xFF38BDF8)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text(
                                          'Live chart preview blocked by browser/network.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Click "Open CamelCamelCamel" above, then copy-paste the price summary below to save it locally.',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.white.withValues(alpha: 0.65),
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
                        const SizedBox(height: 14),
                      ],

                      // Local Sparkline Preview
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B0E14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Device-Saved Price Trend',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${opt.priceHistory.length} points | ${opt.priceLog.length} logged checks',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 180,
                              child: SparklineWidget(
                                history: opt.priceHistory,
                                strikePrice: opt.strikePrice,
                                msrp: opt.msrp,
                                allTimeLow: opt.allTimeLow,
                                isBelowStrike: opt.isBelowStrike,
                                isTrap: opt.isTrapWarning,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Quick Paste from CamelCamelCamel
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF0EA5E9).withValues(alpha: 0.28),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Quick Import from CamelCamelCamel (Paste Summary)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _camelPasteCtrl,
                                    maxLines: 2,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      hintText:
                                          'e.g. Current \$59.95  Lowest \$49.99  Average \$67.50',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonal(
                                  onPressed: _parseCamelText,
                                  child: const Text('Parse'),
                                ),
                              ],
                            ),
                            if (_parseMessage != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                _parseMessage!,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF4ADE80),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Editable Price Fields
                      const Text(
                        'Log Verified Price & Historical Benchmarks (Saved in localStorage)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _numField('Current Price (\$)', _currentCtrl),
                          _numField('90-Day Avg (\$)', _avgCtrl),
                          _numField('All-Time Low (\$)', _atlCtrl),
                          _numField('Clip Coupon (\$)', _couponCtrl),
                          _numField('Strike Target (\$)', _strikeCtrl),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Logged History Table
                      if (opt.priceLog.isNotEmpty) ...[
                        const Text(
                          'Saved Price Check History (On This Device)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B0E14),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            children: opt.priceLog.take(8).map((entry) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      entry.date,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.white54,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '\$${entry.price.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF4ADE80),
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        entry.note.isNotEmpty ? entry.note : entry.source,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.white60,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Footer actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveToLocalStorage,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: Text(_saving ? 'Saving...' : 'Save to Device Storage'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: const Color(0xFF052E16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numField(String label, TextEditingController ctrl) {
    return SizedBox(
      width: 132,
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
