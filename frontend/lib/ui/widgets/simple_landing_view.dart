import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/deal_models.dart';
import '../../providers/deal_providers.dart';
import '../../repositories/local_deal_store.dart';
import 'cart_builder_dialog.dart';
import 'price_history_dialog.dart';
import 'product_thumbnail.dart';

class SimpleLandingView extends ConsumerStatefulWidget {
  final DealDashboardState data;
  final VoidCallback onSwitchToPowerMode;

  const SimpleLandingView({
    super.key,
    required this.data,
    required this.onSwitchToPowerMode,
  });

  @override
  ConsumerState<SimpleLandingView> createState() => _SimpleLandingViewState();
}

class _SimpleLandingViewState extends ConsumerState<SimpleLandingView> {
  String _selectedCategory = 'top_picks';
  final _quickAddCtrl = TextEditingController();

  @override
  void dispose() {
    _quickAddCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitQuickAdd([String? preset]) async {
    final text = (preset ?? _quickAddCtrl.text).trim();
    if (text.isEmpty) return;
    _quickAddCtrl.clear();
    final created =
        await ref.read(dealDashboardProvider.notifier).translateAndAddIntent(text);
    if (!mounted) return;
    if (_selectedCategory != 'top_picks' &&
        _selectedCategory != 'all' &&
        _selectedCategory != created.categoryTag) {
      setState(() => _selectedCategory = created.categoryTag);
    }
    if (created.options.isNotEmpty) {
      final opt = created.options.first;
      if (!opt.hasPrice) {
        showDialog(
          context: context,
          builder: (_) => PriceHistoryDialog(option: opt),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${opt.title}" (${opt.siteName}) to your watchlist!'),
          ),
        );
      }
    }
  }

  Future<void> _showAddProductLinkDialog() async {
    final urlCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final currentCtrl = TextEditingController();
    final strikeCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String selectedCategory = 'custom';
    String detectedSite = '';
    String? errorText;
    bool submitting = false;
    bool titleEditedManually = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void onUrlChanged(String raw) {
            final parsed = LocalDealStore.parseProductLink(raw);
            setModalState(() {
              errorText = null;
              if (parsed != null) {
                detectedSite = parsed.siteName;
                if (!titleEditedManually && parsed.title.isNotEmpty) {
                  titleCtrl.text = parsed.title;
                }
                if (parsed.inlinePrice != null && currentCtrl.text.trim().isEmpty) {
                  currentCtrl.text = parsed.inlinePrice!.toStringAsFixed(2);
                }
              } else {
                detectedSite = '';
              }
            });
          }

          Future<void> submit() async {
            final rawUrl = urlCtrl.text.trim();
            if (!rawUrl.toLowerCase().startsWith('http://') &&
                !rawUrl.toLowerCase().startsWith('https://')) {
              setModalState(() {
                errorText = 'Please paste a full link starting with https:// or http://';
              });
              return;
            }
            setModalState(() {
              submitting = true;
              errorText = null;
            });
            try {
              final cur = double.tryParse(currentCtrl.text.trim());
              final strike = double.tryParse(strikeCtrl.text.trim());
              final created = await ref
                  .read(dealDashboardProvider.notifier)
                  .addCustomProductLink(
                    productUrl: rawUrl,
                    title: titleCtrl.text.trim().isNotEmpty ? titleCtrl.text.trim() : null,
                    currentPrice: cur,
                    strikePrice: strike,
                    categoryTag: selectedCategory,
                    scoutNotes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                  );
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) {
                if (_selectedCategory != 'top_picks' &&
                    _selectedCategory != 'all' &&
                    _selectedCategory != created.categoryTag) {
                  setState(() => _selectedCategory = created.categoryTag);
                }
                final site = created.options.isNotEmpty
                    ? created.options.first.siteName
                    : 'Web Store';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added $site link: ${created.title}'),
                  ),
                );
              }
            } catch (e) {
              setModalState(() {
                submitting = false;
                errorText = '$e';
              });
            }
          }

          return Dialog(
            backgroundColor: const Color(0xFF131822),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Colors.white12),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.add_link_rounded, color: Color(0xFF38BDF8), size: 22),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Add Custom Product Link (Any Site)',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (detectedSite.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E).withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF22C55E).withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                detectedSite.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF4ADE80),
                                ),
                              ),
                            ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close, color: Colors.white60),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Supports Amazon, Walmart, Target, Best Buy, Home Depot, Costco, Lowe\'s, Dyson, REI, or any retail URL.',
                        style: TextStyle(fontSize: 12.5, color: Colors.white60),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: urlCtrl,
                        onChanged: onUrlChanged,
                        autofocus: true,
                        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          labelText: 'Product URL *',
                          hintText: 'https://www.walmart.com/ip/... or https://www.bestbuy.com/site/...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleCtrl,
                        onChanged: (_) => titleEditedManually = true,
                        style: const TextStyle(fontSize: 13.5),
                        decoration: const InputDecoration(
                          labelText: 'Product Name (auto-filled from link)',
                          hintText: 'e.g. Sony WH-1000XM5 Wireless Headphones',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: currentCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                              decoration: const InputDecoration(
                                labelText: 'Current Price (\$)',
                                hintText: 'Optional',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: strikeCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                              decoration: const InputDecoration(
                                labelText: 'Target Strike Price (\$)',
                                hintText: 'Optional',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        dropdownColor: const Color(0xFF1A1F2C),
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'custom', child: Text('My Links')),
                          DropdownMenuItem(value: 'kitchen', child: Text('Kitchen & 304 Basins')),
                          DropdownMenuItem(value: 'tools', child: Text('Tools & Hardware')),
                          DropdownMenuItem(value: 'vacuums', child: Text('Vacuums & Home')),
                          DropdownMenuItem(value: 'consumables', child: Text('Home Essentials')),
                          DropdownMenuItem(value: 'health', child: Text('Health & Supplements')),
                          DropdownMenuItem(value: 'games', child: Text('Games & Puzzles')),
                        ],
                        onChanged: (v) {
                          if (v != null) setModalState(() => selectedCategory = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 12.5),
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText: 'e.g. Watch for Black Friday promo code or store pickup deal',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          errorText!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFF87171)),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: submitting ? null : submit,
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: Text(submitting ? 'Adding...' : 'Add to Radar'),
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
            ),
          );
        },
      ),
    );

    urlCtrl.dispose();
    titleCtrl.dispose();
    currentCtrl.dispose();
    strikeCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _launchAmazon(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  List<_ProductCardEntry> _buildVisibleEntries() {
    final entries = <_ProductCardEntry>[];
    for (final mission in widget.data.missions) {
      for (final opt in mission.options) {
        if (opt.isTrapWarning) continue;
        if (_selectedCategory == 'top_picks' && !opt.isRecommendedBranch) {
          continue;
        }
        if (_selectedCategory != 'top_picks' &&
            _selectedCategory != 'all' &&
            mission.categoryTag != _selectedCategory) {
          continue;
        }
        entries.add(_ProductCardEntry(mission: mission, option: opt));
      }
    }
    return entries;
  }

  void _showComparisonModal(BuildContext context, ShoppingMission mission) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF131822),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.white12),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Compare Options: ${mission.title}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            mission.decisionFraming,
                            style: const TextStyle(fontSize: 13, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, color: Colors.white60),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Colors.white12),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: mission.options.map((opt) {
                        return SizedBox(
                          width: 275,
                          child: _SimpleProductCard(
                            entry: _ProductCardEntry(mission: mission, option: opt),
                            insideModal: true,
                            onCompare: () {},
                            onLaunchAmazon: () => _launchAmazon(opt.openUrl),
                          ),
                        );
                      }).toList(),
                    ),
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
    final allOptions = widget.data.missions.expand((m) => m.options).toList();
    final readyDeals = allOptions.where((o) => o.isBelowStrike && !o.isTrapWarning).length;
    final stack = widget.data.stackSummary;
    final bundleSaved = stack != null
        ? ((stack.consumablesMsrpTotal - stack.consumablesNetOutOfPocket) +
                (stack.b2g1MsrpTotal - stack.b2g1NetTotal))
            .clamp(0.0, double.infinity)
        : 0.0;
    final visibleEntries = _buildVisibleEntries();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Friendly Consumer Hero Card
        _buildFriendlyHero(readyDeals: readyDeals, bundleSaved: bundleSaved),
        const SizedBox(height: 20),

        // 2. Category Filter Bar
        _buildCategoryPills(),
        const SizedBox(height: 16),

        // 3. Visual Product Thumbnail Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth > 1120
                ? 3
                : (constraints.maxWidth > 700 ? 2 : 1);
            final spacing = 16.0;
            final cardWidth =
                (constraints.maxWidth - (spacing * (cols - 1))) / cols;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: visibleEntries.map((entry) {
                return SizedBox(
                  width: cardWidth,
                  child: _SimpleProductCard(
                    entry: entry,
                    onCompare: () => _showComparisonModal(context, entry.mission),
                    onLaunchAmazon: () => _launchAmazon(entry.option.openUrl),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 28),

        // 4. Easy Smart Cart Bundles Section
        if (stack != null) _buildSmartCartBundles(stack, allOptions),
      ],
    );
  }

  Widget _buildFriendlyHero({required int readyDeals, required double bundleSaved}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF152238),
            Color(0xFF111827),
          ],
        ),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 13, color: Color(0xFF4ADE80)),
                          SizedBox(width: 5),
                          Text(
                            'BLACK FRIDAY SHOPPING ASSISTANT | SIMPLE VIEW',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4ADE80),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Your Black Friday Shopping List, Solved.',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'We checked 90-day price history, clipped hidden coupons, and filtered out fake discounts so you can shop the best pick for every item on your list in one click.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              // Quick Stats Badges
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _heroStatBadge(
                    icon: Icons.verified_rounded,
                    color: const Color(0xFF22C55E),
                    value: '$readyDeals Deals Ready',
                    label: 'At or below target price',
                  ),
                  _heroStatBadge(
                    icon: Icons.savings_rounded,
                    color: const Color(0xFF38BDF8),
                    value: 'Save \$${bundleSaved.toStringAsFixed(0)}+',
                    label: 'Auto-bundled cart promos',
                  ),
                  if (widget.data.cartPlan != null)
                    FilledButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => AmazonCartBuilderDialog(plan: widget.data.cartPlan!),
                        );
                      },
                      icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
                      label: Text(
                        '1-Click Amazon Cart (${widget.data.cartPlan!.directAsinCount} Items | -${widget.data.cartPlan!.effectiveDiscountPct}%)',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Simple Search / Add Item Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0F17),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, color: Color(0xFF38BDF8), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _quickAddCtrl,
                    onSubmitted: (_) => _submitQuickAdd(),
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                    decoration: const InputDecoration(
                      hintText:
                          'Paste any product URL (Amazon, Walmart, Target, Best Buy, Home Depot...) or item + \$price...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13.5),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: widget.data.isBusy ? null : _showAddProductLinkDialog,
                  icon: const Icon(Icons.add_link_rounded, size: 17),
                  label: const Text('Add Link'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: widget.data.isBusy ? null : () => _submitQuickAdd(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(widget.data.isBusy ? 'Finding Deals...' : 'Find Best Deal'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0EA5E9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Quick try:',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              _suggestionChip('Anker 140W GaN Charger vs Ugreen Nexode'),
              _suggestionChip('Knipex Cobra Pliers Set'),
              _suggestionChip('Lego 8+ Technic Set'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggestionChip(String label) {
    return ActionChip(
      onPressed: widget.data.isBusy ? null : () => _submitQuickAdd(label),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      visualDensity: VisualDensity.compact,
      label: Text(
        '+ $label',
        style: const TextStyle(fontSize: 11.5, color: Colors.white70),
      ),
    );
  }

  Widget _heroStatBadge({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F17).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11.5, color: Colors.white60),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPills() {
    final totalDeals = widget.data.missions
        .expand((m) => m.options)
        .where((o) => !o.isTrapWarning)
        .length;
    final customCount = widget.data.missions
        .where((m) => m.categoryTag == 'custom')
        .expand((m) => m.options)
        .where((o) => !o.isTrapWarning)
        .length;

    final categories = [
      ('top_picks', 'Top Recommended Picks', Icons.auto_awesome_rounded),
      ('all', 'All Deals ($totalDeals)', Icons.grid_view_rounded),
      ('custom', customCount > 0 ? 'My Links ($customCount)' : 'My Links', Icons.link_rounded),
      ('kitchen', 'Kitchen & 304 Basins', Icons.restaurant_menu_rounded),
      ('tools', 'Tools & DeWalt', Icons.handyman_rounded),
      ('vacuums', 'Dyson Vacuums', Icons.cleaning_services_rounded),
      ('consumables', 'Home & S&S Essentials', Icons.inventory_2_outlined),
      ('health', 'Health & Collagen', Icons.favorite_border_rounded),
      ('games', 'Kids 8+ Games (3-for-2)', Icons.extension_rounded),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(
                cat.$3,
                size: 16,
                color: isSelected ? Colors.white : Colors.white70,
              ),
              label: Text(
                cat.$2,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
              selected: isSelected,
              selectedColor: const Color(0xFF0284C7),
              backgroundColor: const Color(0xFF141821),
              onSelected: (_) => setState(() => _selectedCategory = cat.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSmartCartBundles(
    CombinatoricStackSummary stack,
    List<DealOptionNode> allOptions,
  ) {
    final snsItems = allOptions.where((o) => o.snsEligible).toList();
    final gameItems = allOptions.where((o) => o.b2g1Eligible).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.auto_fix_high_rounded, color: Color(0xFF38BDF8), size: 22),
            SizedBox(width: 8),
            Text(
              'Smart Cart Bundles (Automatic Extra Discounts)',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'These items unlock extra Amazon cart discounts when ordered together.',
          style: TextStyle(fontSize: 13.5, color: Colors.white60),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 860;
            final cardW = isWide ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                // Card 1: Household S&S + P&G $25 Credit
                SizedBox(
                  width: cardW,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141821),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E).withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '15% SUBSCRIBE & SAVE + \$25 P&G BONUS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF4ADE80),
                                ),
                              ),
                            ),
                            Text(
                              'Save ${stack.consumablesEffectiveDiscountPct}%',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF4ADE80),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Household Essentials 5-Item Box',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pay \$${stack.consumablesNetOutOfPocket.toStringAsFixed(2)} instead of \$${stack.consumablesMsrpTotal.toStringAsFixed(2)} MSRP (includes -\$${stack.consumablesCouponSavings.toStringAsFixed(2)} coupons, -\$${stack.consumablesSnsSavings.toStringAsFixed(2)} S&S, and -\$${stack.pgCreditUnlocked.toStringAsFixed(0)} P&G credit).',
                          style: const TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        ...snsItems.map((item) => CheckboxListTile(
                              value: item.selectedInStack,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: const Color(0xFF22C55E),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: Colors.white),
                              ),
                              subtitle: Text(
                                'Net \$${item.effectivePrice.toStringAsFixed(2)} (was \$${item.msrp.toStringAsFixed(2)})',
                                style: const TextStyle(fontSize: 11.5, color: Colors.white54),
                              ),
                              onChanged: (v) {
                                ref.read(dealDashboardProvider.notifier).patchOption(
                                      optionId: item.id,
                                      selectedInStack: v ?? false,
                                    );
                              },
                            )),
                      ],
                    ),
                  ),
                ),

                // Card 2: 3-for-2 Board Games
                SizedBox(
                  width: cardW,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141821),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'AMAZON BUY 2, GET 1 FREE PROMO',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFFBBF24),
                                ),
                              ),
                            ),
                            Text(
                              '1 Game FREE (-\$$_freeGameAmount)',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFBBF24),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Kids 8+ Strategy Board Games & Marble Run Trio',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pay \$${stack.b2g1NetTotal.toStringAsFixed(2)} total for all 3 games (regularly \$${stack.b2g1MsrpTotal.toStringAsFixed(2)}). Grouping three ~\$25 games maximizes the free-item discount.',
                          style: const TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        ...gameItems.map((item) => CheckboxListTile(
                              value: item.selectedInStack,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: const Color(0xFFF59E0B),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: Colors.white),
                              ),
                              subtitle: Text(
                                'Sale \$${item.currentPrice.toStringAsFixed(2)} (was \$${item.msrp.toStringAsFixed(2)})',
                                style: const TextStyle(fontSize: 11.5, color: Colors.white54),
                              ),
                              onChanged: (v) {
                                ref.read(dealDashboardProvider.notifier).patchOption(
                                      optionId: item.id,
                                      selectedInStack: v ?? false,
                                    );
                              },
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  String get _freeGameAmount =>
      (widget.data.stackSummary?.b2g1FreeItemDeduction ?? 0.0).toStringAsFixed(2);
}

class _ProductCardEntry {
  final ShoppingMission mission;
  final DealOptionNode option;

  const _ProductCardEntry({required this.mission, required this.option});
}

class _SimpleProductCard extends ConsumerWidget {
  final _ProductCardEntry entry;
  final VoidCallback onCompare;
  final VoidCallback onLaunchAmazon;
  final bool insideModal;

  const _SimpleProductCard({
    required this.entry,
    required this.onCompare,
    required this.onLaunchAmazon,
    this.insideModal = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mission = entry.mission;
    final opt = entry.option;
    final savingsDollar = (opt.msrp - opt.effectivePrice).clamp(0.0, double.infinity);
    final hasAlternatives = mission.options.length > 1 && !insideModal;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: opt.isTrapWarning ? const Color(0xFF231215) : const Color(0xFF141821),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: opt.isTrapWarning
              ? const Color(0xFFEF4444).withValues(alpha: 0.6)
              : (opt.isBelowStrike
                  ? const Color(0xFF22C55E).withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.10)),
          width: opt.isRecommendedBranch ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Visual Product Thumbnail (clickable to open direct Amazon product page)
          InkWell(
            onTap: opt.isTrapWarning ? null : onLaunchAmazon,
            borderRadius: BorderRadius.circular(12),
            child: ProductThumbnail(
              option: opt,
              categoryTag: mission.categoryTag,
              height: insideModal ? 128 : 152,
            ),
          ),
          const SizedBox(height: 12),

          // 2. Shopping List Goal + Store Badge + Compare Options button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (!opt.isAmazon) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          opt.siteName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF7DD3FC),
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        opt.branchLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasAlternatives)
                InkWell(
                  onTap: onCompare,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Compare ${mission.options.length} Options',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // 3. Product Title (clickable to open direct retailer product page)
          InkWell(
            onTap: opt.isTrapWarning ? null : onLaunchAmazon,
            child: Text(
              opt.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.28,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 4. Plain-English "Why We Picked It" Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              opt.scoutNotes,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 5. Big Friendly Price Block
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (opt.hasPrice) ...[
                Text(
                  '\$${opt.effectivePrice.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: opt.isTrapWarning
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF22C55E),
                  ),
                ),
                if (opt.msrp > opt.effectivePrice) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '\$${opt.msrp.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white38,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => PriceHistoryDialog(option: opt),
                    ),
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: opt.isVerifiedPrice
                            ? const Color(0xFF22C55E).withValues(alpha: 0.16)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        opt.isVerifiedPrice ? 'VERIFIED' : 'EST',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: opt.isVerifiedPrice
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFFFBBF24),
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                InkWell(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => PriceHistoryDialog(option: opt),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF0EA5E9).withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_chart_rounded, size: 14, color: Color(0xFF38BDF8)),
                        SizedBox(width: 5),
                        Text(
                          'Log Live Price',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (opt.hasPrice && !opt.isTrapWarning && savingsDollar > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Save \$${savingsDollar.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4ADE80),
                    ),
                  ),
                )
              else if (!opt.hasPrice && opt.strikePrice > 0)
                Text(
                  'Target: \$${opt.strikePrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white54,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _buildFriendlyDiscountNote(opt),
            style: const TextStyle(fontSize: 11.5, color: Colors.white54),
          ),
          const SizedBox(height: 14),

          // 6. Easy 1-Click Action Buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: opt.isTrapWarning ? null : onLaunchAmazon,
                  icon: Icon(
                    opt.isTrapWarning ? Icons.block_rounded : Icons.shopping_bag_outlined,
                    size: 16,
                  ),
                  label: Text(
                    opt.isTrapWarning ? 'Avoid Overpriced SKU' : opt.openButtonLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: opt.isTrapWarning
                        ? Colors.red.withValues(alpha: 0.25)
                        : const Color(0xFF22C55E),
                    foregroundColor:
                        opt.isTrapWarning ? Colors.white60 : const Color(0xFF052E16),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Price History & CamelCamelCamel Log',
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PriceHistoryDialog(option: opt),
                ),
                style: IconButton.styleFrom(
                  backgroundColor: opt.isVerifiedPrice
                      ? const Color(0xFF0EA5E9).withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.07),
                ),
                icon: Icon(
                  Icons.show_chart_rounded,
                  size: 19,
                  color: opt.isVerifiedPrice ? const Color(0xFF38BDF8) : Colors.white70,
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: opt.snagged ? 'Marked as Purchased' : 'Mark as Purchased',
                onPressed: () {
                  ref.read(dealDashboardProvider.notifier).patchOption(
                        optionId: opt.id,
                        snagged: !opt.snagged,
                      );
                },
                style: IconButton.styleFrom(
                  backgroundColor: opt.snagged
                      ? const Color(0xFF22C55E).withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.07),
                ),
                icon: Icon(
                  opt.snagged ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                  size: 19,
                  color: opt.snagged ? const Color(0xFF4ADE80) : Colors.white60,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buildFriendlyDiscountNote(DealOptionNode opt) {
    if (opt.isTrapWarning) {
      return '[TRAP] Discontinued bundle inflated by 3rd-party resellers';
    }
    final parts = <String>[];
    if (opt.clipCouponAmount > 0) {
      parts.add('\$${opt.clipCouponAmount.toStringAsFixed(2)} coupon');
    }
    if (opt.snsEligible) {
      parts.add('15% Subscribe & Save');
    }
    if (opt.b2g1Eligible) {
      parts.add('Buy 2 Get 1 Free eligible');
    }
    if (!opt.hasPrice) {
      final promoSuffix = parts.isEmpty ? '' : ' | ${parts.join(" + ")}';
      return 'No price logged yet -- tap Log Live Price to check CamelCamelCamel$promoSuffix';
    }
    if (parts.isEmpty) {
      final avgStr = opt.avg90dPrice > 0
          ? '90-day avg: \$${opt.avg90dPrice.toStringAsFixed(2)} | '
          : '';
      return '${avgStr}Target: \$${opt.strikePrice.toStringAsFixed(2)}';
    }
    return 'Includes ${parts.join(" + ")}';
  }
}
