import 'package:flutter_test/flutter_test.dart';
import 'package:deal_radar_app/models/deal_models.dart';

void main() {
  test('Polymorphic ShoppingMission deserializes DAG nodes accurately', () {
    final raw = {
      'id': 1,
      'slug': 'dewalt-fork',
      'title': 'DeWalt 18V Adapter vs Hammer Drill Kit',
      'raw_intent': 'DeWalt battery adapter or new hammer drill',
      'node_type': 'XOR_FORK',
      'category_tag': 'tools',
      'icon': '🛠️',
      'decision_framing': 'Avoid scalped DCA2203C bundle.',
      'options': [
        {
          'id': 10,
          'mission_id': 1,
          'branch_key': 'path_b',
          'branch_label': 'Path B • DCD805D2 XR Kit',
          'is_recommended_branch': true,
          'is_trap_warning': false,
          'title': 'DeWalt 20V MAX XR Brushless Hammer Drill Kit',
          'asin_or_sku': 'DCD805D2',
          'amazon_query': 'DeWalt+DCD805D2',
          'msrp': 239.0,
          'avg_90d_price': 189.0,
          'current_price': 159.0,
          'clip_coupon_amount': 10.0,
          'strike_price': 149.0,
          'all_time_low': 139.0,
          'sns_eligible': false,
          'pg_stockup_eligible': false,
          'b2g1_eligible': false,
          'selected_in_stack': false,
          'snagged': false,
          'unit_name': 'kit',
          'unit_quantity': 1.0,
          'price_history': [239.0, 189.0, 149.0],
          'scout_notes': 'Best Black Friday value.',
          'effective_price': 149.0,
          'unit_effective_price': 149.0,
          'discount_pct_off_msrp': 38,
          'deal_grade_code': 'STRIKE',
          'deal_grade_label': '✅ AT STRIKE TARGET (-38%)',
          'is_below_strike': true,
          'amazon_url': 'https://www.amazon.com/s?k=DeWalt+DCD805D2',
          'camel_url': 'https://camelcamelcamel.com/search?sq=DeWalt+DCD805D2',
        }
      ],
    };

    final mission = ShoppingMission.fromJson(raw);
    expect(mission.nodeType, MissionNodeType.xorFork);
    expect(mission.options.length, 1);
    expect(mission.options.first.effectivePrice, 149.0);
    expect(mission.options.first.isBelowStrike, isTrue);
  });
}
