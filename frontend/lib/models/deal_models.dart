String cleanCanvasKitText(String input) {
  return input
      .replaceAll('•', '|')
      .replaceAll('→', '->')
      .replaceAll('—', '--')
      .replaceAll(RegExp(r'[^\x00-\x7F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

enum MissionNodeType {
  exactSku('EXACT_SKU', 'Exact SKU', 'Pinned ASIN / Model'),
  xorFork('XOR_FORK', 'XOR Decision Fork', 'Mutually Exclusive Path A vs Path B'),
  categoryFunnel('CATEGORY_FUNNEL', 'Category Funnel', 'LLM-Expanded Spec Candidates'),
  consumableStack('CONSUMABLE_STACK', 'Consumable Stack', 'S&S 15% + P&G Stock-Up');

  final String wireValue;
  final String label;
  final String subtitle;
  const MissionNodeType(this.wireValue, this.label, this.subtitle);

  static MissionNodeType fromWire(String raw) {
    return MissionNodeType.values.firstWhere(
      (e) => e.wireValue == raw,
      orElse: () => MissionNodeType.categoryFunnel,
    );
  }
}

class DealOptionNode {
  final int id;
  final int missionId;
  final String branchKey;
  final String branchLabel;
  final bool isRecommendedBranch;
  final bool isTrapWarning;
  final String title;
  final String asinOrSku;
  final String amazonQuery;
  final double msrp;
  final double avg90dPrice;
  final double currentPrice;
  final double clipCouponAmount;
  final double strikePrice;
  final double allTimeLow;
  final bool snsEligible;
  final bool pgStockupEligible;
  final bool b2g1Eligible;
  final bool selectedInStack;
  final bool snagged;
  final String unitName;
  final double unitQuantity;
  final List<double> priceHistory;
  final String scoutNotes;
  final double effectivePrice;
  final double unitEffectivePrice;
  final int discountPctOffMsrp;
  final String dealGradeCode;
  final String dealGradeLabel;
  final bool isBelowStrike;
  final String amazonUrl;
  final String camelUrl;

  const DealOptionNode({
    required this.id,
    required this.missionId,
    required this.branchKey,
    required this.branchLabel,
    required this.isRecommendedBranch,
    required this.isTrapWarning,
    required this.title,
    required this.asinOrSku,
    required this.amazonQuery,
    required this.msrp,
    required this.avg90dPrice,
    required this.currentPrice,
    required this.clipCouponAmount,
    required this.strikePrice,
    required this.allTimeLow,
    required this.snsEligible,
    required this.pgStockupEligible,
    required this.b2g1Eligible,
    required this.selectedInStack,
    required this.snagged,
    required this.unitName,
    required this.unitQuantity,
    required this.priceHistory,
    required this.scoutNotes,
    required this.effectivePrice,
    required this.unitEffectivePrice,
    required this.discountPctOffMsrp,
    required this.dealGradeCode,
    required this.dealGradeLabel,
    required this.isBelowStrike,
    required this.amazonUrl,
    required this.camelUrl,
  });

  factory DealOptionNode.fromJson(Map<String, dynamic> json) {
    final histRaw = (json['price_history'] as List<dynamic>? ?? []);
    return DealOptionNode(
      id: (json['id'] as num).toInt(),
      missionId: (json['mission_id'] as num).toInt(),
      branchKey: json['branch_key'] as String? ?? 'primary',
      branchLabel: cleanCanvasKitText(json['branch_label'] as String? ?? 'Candidate'),
      isRecommendedBranch: json['is_recommended_branch'] as bool? ?? false,
      isTrapWarning: json['is_trap_warning'] as bool? ?? false,
      title: cleanCanvasKitText(json['title'] as String? ?? ''),
      asinOrSku: cleanCanvasKitText(json['asin_or_sku'] as String? ?? ''),
      amazonQuery: json['amazon_query'] as String? ?? '',
      msrp: (json['msrp'] as num).toDouble(),
      avg90dPrice: (json['avg_90d_price'] as num).toDouble(),
      currentPrice: (json['current_price'] as num).toDouble(),
      clipCouponAmount: (json['clip_coupon_amount'] as num? ?? 0).toDouble(),
      strikePrice: (json['strike_price'] as num).toDouble(),
      allTimeLow: (json['all_time_low'] as num).toDouble(),
      snsEligible: json['sns_eligible'] as bool? ?? false,
      pgStockupEligible: json['pg_stockup_eligible'] as bool? ?? false,
      b2g1Eligible: json['b2g1_eligible'] as bool? ?? false,
      selectedInStack: json['selected_in_stack'] as bool? ?? false,
      snagged: json['snagged'] as bool? ?? false,
      unitName: cleanCanvasKitText(json['unit_name'] as String? ?? 'unit'),
      unitQuantity: (json['unit_quantity'] as num? ?? 1).toDouble(),
      priceHistory: histRaw.map((e) => (e as num).toDouble()).toList(),
      scoutNotes: cleanCanvasKitText(json['scout_notes'] as String? ?? ''),
      effectivePrice: (json['effective_price'] as num).toDouble(),
      unitEffectivePrice: (json['unit_effective_price'] as num).toDouble(),
      discountPctOffMsrp: (json['discount_pct_off_msrp'] as num).toInt(),
      dealGradeCode: json['deal_grade_code'] as String? ?? 'WAIT',
      dealGradeLabel: cleanCanvasKitText(json['deal_grade_label'] as String? ?? ''),
      isBelowStrike: json['is_below_strike'] as bool? ?? false,
      amazonUrl: json['amazon_url'] as String? ?? '',
      camelUrl: json['camel_url'] as String? ?? '',
    );
  }
}

class ShoppingMission {
  final int id;
  final String slug;
  final String title;
  final String rawIntent;
  final MissionNodeType nodeType;
  final String categoryTag;
  final String icon;
  final String decisionFraming;
  final List<DealOptionNode> options;

  const ShoppingMission({
    required this.id,
    required this.slug,
    required this.title,
    required this.rawIntent,
    required this.nodeType,
    required this.categoryTag,
    required this.icon,
    required this.decisionFraming,
    required this.options,
  });

  factory ShoppingMission.fromJson(Map<String, dynamic> json) {
    final opts = (json['options'] as List<dynamic>? ?? [])
        .map((o) => DealOptionNode.fromJson(o as Map<String, dynamic>))
        .toList();
    return ShoppingMission(
      id: (json['id'] as num).toInt(),
      slug: json['slug'] as String? ?? '',
      title: cleanCanvasKitText(json['title'] as String? ?? ''),
      rawIntent: cleanCanvasKitText(json['raw_intent'] as String? ?? ''),
      nodeType: MissionNodeType.fromWire(json['node_type'] as String? ?? ''),
      categoryTag: json['category_tag'] as String? ?? 'general',
      icon: json['icon'] as String? ?? '',
      decisionFraming: cleanCanvasKitText(json['decision_framing'] as String? ?? ''),
      options: opts,
    );
  }
}

class CombinatoricStackSummary {
  final int snsActiveCount;
  final double snsTierRate;
  final bool snsUnlocked15Pct;
  final double pgQualifyingSubtotal;
  final double pgCreditUnlocked;
  final double pgAmountNeededForCredit;
  final double consumablesMsrpTotal;
  final double consumablesSaleTotal;
  final double consumablesCouponSavings;
  final double consumablesSnsSavings;
  final double consumablesNetOutOfPocket;
  final int consumablesEffectiveDiscountPct;
  final int b2g1SelectedCount;
  final double b2g1MsrpTotal;
  final double b2g1SaleSubtotal;
  final double b2g1FreeItemDeduction;
  final double b2g1NetTotal;
  final int b2g1HarmonyScore;
  final String b2g1HarmonyVerdict;

  const CombinatoricStackSummary({
    required this.snsActiveCount,
    required this.snsTierRate,
    required this.snsUnlocked15Pct,
    required this.pgQualifyingSubtotal,
    required this.pgCreditUnlocked,
    required this.pgAmountNeededForCredit,
    required this.consumablesMsrpTotal,
    required this.consumablesSaleTotal,
    required this.consumablesCouponSavings,
    required this.consumablesSnsSavings,
    required this.consumablesNetOutOfPocket,
    required this.consumablesEffectiveDiscountPct,
    required this.b2g1SelectedCount,
    required this.b2g1MsrpTotal,
    required this.b2g1SaleSubtotal,
    required this.b2g1FreeItemDeduction,
    required this.b2g1NetTotal,
    required this.b2g1HarmonyScore,
    required this.b2g1HarmonyVerdict,
  });

  factory CombinatoricStackSummary.fromJson(Map<String, dynamic> json) {
    return CombinatoricStackSummary(
      snsActiveCount: (json['sns_active_count'] as num).toInt(),
      snsTierRate: (json['sns_tier_rate'] as num).toDouble(),
      snsUnlocked15Pct: json['sns_unlocked_15pct'] as bool? ?? false,
      pgQualifyingSubtotal: (json['pg_qualifying_subtotal'] as num).toDouble(),
      pgCreditUnlocked: (json['pg_credit_unlocked'] as num).toDouble(),
      pgAmountNeededForCredit: (json['pg_amount_needed_for_credit'] as num).toDouble(),
      consumablesMsrpTotal: (json['consumables_msrp_total'] as num).toDouble(),
      consumablesSaleTotal: (json['consumables_sale_total'] as num).toDouble(),
      consumablesCouponSavings: (json['consumables_coupon_savings'] as num).toDouble(),
      consumablesSnsSavings: (json['consumables_sns_savings'] as num).toDouble(),
      consumablesNetOutOfPocket: (json['consumables_net_out_of_pocket'] as num).toDouble(),
      consumablesEffectiveDiscountPct: (json['consumables_effective_discount_pct'] as num).toInt(),
      b2g1SelectedCount: (json['b2g1_selected_count'] as num).toInt(),
      b2g1MsrpTotal: (json['b2g1_msrp_total'] as num).toDouble(),
      b2g1SaleSubtotal: (json['b2g1_sale_subtotal'] as num).toDouble(),
      b2g1FreeItemDeduction: (json['b2g1_free_item_deduction'] as num).toDouble(),
      b2g1NetTotal: (json['b2g1_net_total'] as num).toDouble(),
      b2g1HarmonyScore: (json['b2g1_harmony_score'] as num).toInt(),
      b2g1HarmonyVerdict: cleanCanvasKitText(json['b2g1_harmony_verdict'] as String? ?? ''),
    );
  }
}

class WebhookAlertLog {
  final int id;
  final int optionId;
  final String optionTitle;
  final double effectivePrice;
  final double strikePrice;
  final String channel;
  final String status;
  final String createdAt;

  const WebhookAlertLog({
    required this.id,
    required this.optionId,
    required this.optionTitle,
    required this.effectivePrice,
    required this.strikePrice,
    required this.channel,
    required this.status,
    required this.createdAt,
  });

  factory WebhookAlertLog.fromJson(Map<String, dynamic> json) {
    return WebhookAlertLog(
      id: (json['id'] as num).toInt(),
      optionId: (json['option_id'] as num).toInt(),
      optionTitle: cleanCanvasKitText(json['option_title'] as String? ?? ''),
      effectivePrice: (json['effective_price'] as num).toDouble(),
      strikePrice: (json['strike_price'] as num).toDouble(),
      channel: cleanCanvasKitText(json['channel'] as String? ?? 'local_inbox'),
      status: cleanCanvasKitText(json['status'] as String? ?? 'logged'),
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}
