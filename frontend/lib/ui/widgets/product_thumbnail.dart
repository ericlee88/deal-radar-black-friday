import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/deal_models.dart';

class ProductThumbnail extends StatelessWidget {
  final DealOptionNode option;
  final String categoryTag;
  final double height;
  final bool compact;

  const ProductThumbnail({
    super.key,
    required this.option,
    required this.categoryTag,
    this.height = 148,
    this.compact = false,
  });

  _ProductVisualTheme _resolveTheme() {
    final t = '${option.title} ${option.branchKey} ${option.asinOrSku}'.toLowerCase();

    if (option.isTrapWarning) {
      return const _ProductVisualTheme(
        brand: '3P RESELLER TRAP',
        accent: Color(0xFFEF4444),
        secondary: Color(0xFF7F1D1D),
        kind: _IllustrationKind.trapBattery,
        specTag: 'DISCONTINUED SKU',
      );
    }
    if (t.contains('mercer') || t.contains('turner') || t.contains('spatula')) {
      return _ProductVisualTheme(
        brand: t.contains('oxo') ? 'OXO GOOD GRIPS' : 'MERCER CULINARY',
        accent: const Color(0xFF38BDF8),
        secondary: const Color(0xFF0284C7),
        kind: _IllustrationKind.spatula,
        specTag: t.contains('oxo') ? 'BEVELED STEEL' : 'JAPANESE STEEL',
      );
    }
    if (t.contains('basin') || t.contains('rice') || t.contains('colander') || t.contains('304')) {
      return const _ProductVisualTheme(
        brand: 'SUS304 KITCHEN',
        accent: Color(0xFF2DD4BF),
        secondary: Color(0xFF0D9488),
        kind: _IllustrationKind.riceBasin,
        specTag: '1.5MM MICROPOROUS',
      );
    }
    if (t.contains('work sharp') || t.contains('wssa') || t.contains('grit')) {
      return const _ProductVisualTheme(
        brand: 'WORK SHARP',
        accent: Color(0xFFF59E0B),
        secondary: Color(0xFFB45309),
        kind: _IllustrationKind.knifeSharpener,
        specTag: '7-GRIT + STROP KIT',
      );
    }
    if (t.contains('hammer drill') || t.contains('dcd805') || t.contains('dcd798')) {
      return const _ProductVisualTheme(
        brand: 'DEWALT 20V MAX XR',
        accent: Color(0xFFFACC15),
        secondary: Color(0xFFCA8A04),
        kind: _IllustrationKind.hammerDrill,
        specTag: 'BRUSHLESS KIT',
      );
    }
    if (t.contains('dewalt') || t.contains('dca1820') || t.contains('dcb205')) {
      return const _ProductVisualTheme(
        brand: 'DEWALT 20V MAX',
        accent: Color(0xFFFACC15),
        secondary: Color(0xFFA16207),
        kind: _IllustrationKind.batteryAdapter,
        specTag: '10Ah + ADAPTER',
      );
    }
    if (t.contains('dyson')) {
      final isCarBoat = t.contains('car+boat') || t.contains('car_boat');
      final isV12 = t.contains('v12');
      return _ProductVisualTheme(
        brand: isCarBoat
            ? 'DYSON CAR+BOAT'
            : (isV12 ? 'DYSON V12 SLIM' : 'DYSON V8 CYCLONE'),
        accent: isV12 ? const Color(0xFFC084FC) : const Color(0xFF818CF8),
        secondary: const Color(0xFF4F46E5),
        kind: isCarBoat ? _IllustrationKind.dysonHandheld : _IllustrationKind.dysonStick,
        specTag: isCarBoat ? '50-MIN HANDHELD' : (isV12 ? '2.2 LB PUSH-BUTTON' : '2-IN-1 STICK+HAND'),
      );
    }
    if (t.contains('metamucil') || t.contains('collagen') || t.contains('vital')) {
      final isDiy = t.contains('vital') || t.contains('diy');
      return _ProductVisualTheme(
        brand: isDiy ? 'METAMUCIL + VITAL' : 'METAMUCIL BLEND',
        accent: isDiy ? const Color(0xFF38BDF8) : const Color(0xFFFB923C),
        secondary: isDiy ? const Color(0xFF0369A1) : const Color(0xFFEA580C),
        kind: _IllustrationKind.supplementTub,
        specTag: isDiy ? '150 SERVINGS STACK' : '52 SERVINGS 2-IN-1',
      );
    }
    if (t.contains('bounty') || t.contains('charmin') || t.contains('cascade') || t.contains('glad')) {
      String brand = 'HOUSEHOLD S&S';
      Color accent = const Color(0xFF34D399);
      if (t.contains('bounty')) {
        brand = 'BOUNTY SELECT-A-SIZE';
        accent = const Color(0xFF22C55E);
      } else if (t.contains('charmin')) {
        brand = 'CHARMIN ULTRA SOFT';
        accent = const Color(0xFF38BDF8);
      } else if (t.contains('cascade')) {
        brand = 'CASCADE PLATINUM+';
        accent = const Color(0xFF2DD4BF);
      } else if (t.contains('glad')) {
        brand = 'GLAD FORCEFLEX+';
        accent = const Color(0xFFFBBF24);
      }
      return _ProductVisualTheme(
        brand: brand,
        accent: accent,
        secondary: const Color(0xFF059669),
        kind: _IllustrationKind.consumableBox,
        specTag: option.pgStockupEligible ? 'P&G \$25 + 15% S&S' : '15% S&S FILLER',
      );
    }
    if (t.contains('cascadia') ||
        t.contains('ticket to ride') ||
        t.contains('gravitrax') ||
        t.contains('gravity maze') ||
        categoryTag == 'games') {
      final isMarble = t.contains('gravitrax') || t.contains('gravity');
      return _ProductVisualTheme(
        brand: t.contains('cascadia')
            ? 'AEG • CASCADIA'
            : (t.contains('ticket')
                ? 'DAYS OF WONDER'
                : (t.contains('gravitrax') ? 'RAVENSBURGER STEM' : 'THINKFUN LOGIC')),
        accent: isMarble ? const Color(0xFF34D399) : const Color(0xFFF472B6),
        secondary: isMarble ? const Color(0xFF059669) : const Color(0xFFDB2777),
        kind: isMarble ? _IllustrationKind.marblePuzzle : _IllustrationKind.boardGame,
        specTag: '3-FOR-2 ELIGIBLE • 8+',
      );
    }

    return const _ProductVisualTheme(
      brand: 'AMAZON BLACK FRIDAY',
      accent: Color(0xFF38BDF8),
      secondary: Color(0xFF0284C7),
      kind: _IllustrationKind.genericProduct,
      specTag: 'VERIFIED SKU',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _resolveTheme();

    return Container(
      height: height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        gradient: RadialGradient(
          center: const Alignment(0.0, -0.1),
          radius: 1.05,
          colors: [
            theme.accent.withValues(alpha: 0.24),
            theme.secondary.withValues(alpha: 0.10),
            const Color(0xFF0D1119),
          ],
        ),
        border: Border.all(
          color: theme.accent.withValues(alpha: 0.28),
        ),
      ),
      child: Stack(
        children: [
          // Subtle studio grid & product illustration canvas
          Positioned.fill(
            child: CustomPaint(
              painter: _ProductIllustrationPainter(
                kind: theme.kind,
                accent: theme.accent,
                secondary: theme.secondary,
              ),
            ),
          ),

          // Top-left Brand Pill
          if (!compact)
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF090C10).withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.accent.withValues(alpha: 0.45)),
                ),
                child: Text(
                  theme.brand,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: theme.accent,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),

          // Top-right Discount Badge
          if (option.discountPctOffMsrp > 0 && !option.isTrapWarning)
            Positioned(
              top: compact ? 6 : 10,
              right: compact ? 6 : 10,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 6 : 8,
                  vertical: compact ? 2 : 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '-${option.discountPctOffMsrp}%',
                  style: TextStyle(
                    fontSize: compact ? 10 : 11.5,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF052E16),
                  ),
                ),
              ),
            ),

          // Bottom-left Spec Tag & Unit Price Pill
          if (!compact)
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090C10).withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      theme.specTag,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  if (option.isRecommendedBranch && !option.isTrapWarning)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, size: 12, color: Color(0xFF451A03)),
                          SizedBox(width: 3),
                          Text(
                            'BEST PICK',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF451A03),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

enum _IllustrationKind {
  spatula,
  riceBasin,
  knifeSharpener,
  hammerDrill,
  batteryAdapter,
  trapBattery,
  dysonHandheld,
  dysonStick,
  supplementTub,
  consumableBox,
  boardGame,
  marblePuzzle,
  genericProduct,
}

class _ProductVisualTheme {
  final String brand;
  final Color accent;
  final Color secondary;
  final _IllustrationKind kind;
  final String specTag;

  const _ProductVisualTheme({
    required this.brand,
    required this.accent,
    required this.secondary,
    required this.kind,
    required this.specTag,
  });
}

class _ProductIllustrationPainter extends CustomPainter {
  final _IllustrationKind kind;
  final Color accent;
  final Color secondary;

  const _ProductIllustrationPainter({
    required this.kind,
    required this.accent,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Studio floor shadow ellipse
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 34), width: 110, height: 18),
      shadowPaint,
    );

    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillAccent = Paint()
      ..color = accent.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final fillSoft = Paint()
      ..color = accent.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final fillDark = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;

    switch (kind) {
      case _IllustrationKind.spatula:
        // Slotted stainless turner blade + handle
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(-0.38);
        final blade = RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(-22, 0), width: 62, height: 34),
          const Radius.circular(6),
        );
        canvas.drawRRect(blade, Paint()..color = const Color(0xFFCBD5E1));
        canvas.drawRRect(blade, strokePaint);
        // Slots inside blade
        for (double dx = -42; dx <= -6; dx += 12) {
          canvas.drawLine(
            Offset(dx, -9),
            Offset(dx, 9),
            Paint()
              ..color = const Color(0xFF0F172A)
              ..strokeWidth = 3.2
              ..strokeCap = StrokeCap.round,
          );
        }
        // Neck & Handle
        canvas.drawLine(const Offset(9, 0), const Offset(24, 0), strokePaint..strokeWidth = 4);
        final handle = RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(46, 0), width: 42, height: 14),
          const Radius.circular(7),
        );
        canvas.drawRRect(handle, fillAccent);
        canvas.drawRRect(handle, strokePaint..strokeWidth = 1.8);
        canvas.restore();
        break;

      case _IllustrationKind.riceBasin:
        // 304 Stainless perforated bowl
        final bowlPath = Path()
          ..moveTo(cx - 52, cy - 14)
          ..quadraticBezierTo(cx - 46, cy + 32, cx, cy + 32)
          ..quadraticBezierTo(cx + 46, cy + 32, cx + 52, cy - 14)
          ..close();
        canvas.drawPath(bowlPath, Paint()..color = const Color(0xFF94A3B8).withValues(alpha: 0.45));
        canvas.drawPath(bowlPath, strokePaint);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy - 14), width: 104, height: 20),
          Paint()..color = const Color(0xFFE2E8F0).withValues(alpha: 0.25),
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy - 14), width: 104, height: 20),
          strokePaint,
        );
        // Microporous laser perforations on side
        final dotPaint = Paint()..color = accent;
        for (double y = cy - 2; y <= cy + 18; y += 6) {
          for (double x = cx + 6; x <= cx + 34; x += 7) {
            canvas.drawCircle(Offset(x, y), 1.6, dotPaint);
          }
        }
        break;

      case _IllustrationKind.knifeSharpener:
        // Fixed-angle V-clamp + sharpening rod + strop
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy + 16), width: 84, height: 16),
            const Radius.circular(5),
          ),
          fillDark,
        );
        canvas.drawLine(Offset(cx - 28, cy + 12), Offset(cx - 28, cy - 26), strokePaint);
        canvas.drawLine(Offset(cx - 28, cy - 20), Offset(cx + 38, cy + 6), Paint()
          ..color = accent
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx + 8, cy - 6), width: 32, height: 11),
            const Radius.circular(4),
          ),
          fillAccent,
        );
        break;

      case _IllustrationKind.hammerDrill:
        // DeWalt yellow/black cordless hammer drill silhouette
        final body = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx - 4, cy - 14), width: 64, height: 26),
          const Radius.circular(7),
        );
        canvas.drawRRect(body, fillAccent);
        canvas.drawRRect(body, strokePaint);
        // Chuck + bit
        canvas.drawRect(
          Rect.fromCenter(center: Offset(cx + 34, cy - 14), width: 14, height: 16),
          fillDark,
        );
        canvas.drawLine(Offset(cx + 41, cy - 14), Offset(cx + 56, cy - 14), strokePaint);
        // Grip + 20V battery base
        final grip = Path()
          ..moveTo(cx - 14, cy - 1)
          ..lineTo(cx - 22, cy + 20)
          ..lineTo(cx - 6, cy + 20)
          ..lineTo(cx + 2, cy - 1)
          ..close();
        canvas.drawPath(grip, fillDark);
        canvas.drawPath(grip, strokePaint);
        final battery = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx - 14, cy + 25), width: 38, height: 14),
          const Radius.circular(4),
        );
        canvas.drawRRect(battery, fillAccent);
        canvas.drawRRect(battery, strokePaint);
        break;

      case _IllustrationKind.batteryAdapter:
      case _IllustrationKind.trapBattery:
        // Twin 5.0Ah XR Battery Packs + Adapter
        for (final dx in [-24.0, 24.0]) {
          final pack = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx + dx, cy + 4), width: 40, height: 38),
            const Radius.circular(6),
          );
          canvas.drawRRect(pack, fillDark);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(cx + dx, cy - 8), width: 40, height: 14),
              const Radius.circular(4),
            ),
            fillAccent,
          );
          canvas.drawRRect(pack, strokePaint);
        }
        if (kind == _IllustrationKind.trapBattery) {
          final warnPaint = Paint()
            ..color = const Color(0xFFEF4444)
            ..strokeWidth = 3.5;
          canvas.drawLine(Offset(cx - 45, cy - 22), Offset(cx + 45, cy + 26), warnPaint);
        }
        break;

      case _IllustrationKind.dysonHandheld:
      case _IllustrationKind.dysonStick:
        // Dyson Cyclone body + wand + cleaner head
        final cyclone = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx - 18, cy - 6), width: 44, height: 28),
          const Radius.circular(10),
        );
        canvas.drawRRect(cyclone, fillAccent);
        canvas.drawRRect(cyclone, strokePaint);
        // Wand
        final wandEnd = kind == _IllustrationKind.dysonStick ? cx + 48 : cx + 28;
        canvas.drawLine(
          Offset(cx + 4, cy - 6),
          Offset(wandEnd, cy + 12),
          Paint()
            ..color = accent
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round,
        );
        // Motorized head
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(wandEnd, cy + 18), width: 26, height: 12),
            const Radius.circular(4),
          ),
          fillDark,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(wandEnd, cy + 18), width: 26, height: 12),
            const Radius.circular(4),
          ),
          strokePaint,
        );
        break;

      case _IllustrationKind.supplementTub:
        // Canister tub + lid + label
        final tub = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy + 4), width: 52, height: 54),
          const Radius.circular(10),
        );
        canvas.drawRRect(tub, fillSoft);
        canvas.drawRRect(tub, strokePaint);
        // Lid
        final lid = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy - 24), width: 56, height: 12),
          const Radius.circular(4),
        );
        canvas.drawRRect(lid, fillAccent);
        canvas.drawRRect(lid, strokePaint);
        // Label stripe
        canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, cy + 4), width: 48, height: 20),
          fillAccent,
        );
        break;

      case _IllustrationKind.consumableBox:
        // Twin household rolls / package
        for (final dx in [-18.0, 18.0]) {
          final roll = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx + dx, cy + 2), width: 32, height: 48),
            const Radius.circular(7),
          );
          canvas.drawRRect(roll, fillSoft);
          canvas.drawRRect(roll, strokePaint);
          canvas.drawCircle(Offset(cx + dx, cy + 2), 9, fillAccent);
        }
        break;

      case _IllustrationKind.boardGame:
      case _IllustrationKind.marblePuzzle:
        // 3D Isometric Board Game Box + Hex / Marble accents
        final box = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx - 6, cy + 2), width: 56, height: 54),
          const Radius.circular(8),
        );
        canvas.drawRRect(box, fillSoft);
        canvas.drawRRect(box, strokePaint);
        // Hex / Marble graphic inside box
        if (kind == _IllustrationKind.marblePuzzle) {
          canvas.drawCircle(Offset(cx - 6, cy - 4), 11, fillAccent);
          canvas.drawArc(
            Rect.fromCenter(center: Offset(cx - 6, cy + 2), width: 40, height: 40),
            0,
            math.pi,
            false,
            strokePaint,
          );
        } else {
          canvas.drawCircle(Offset(cx - 6, cy + 2), 15, fillAccent);
        }
        // Second offset card/tile
        final tile = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx + 28, cy + 10), width: 26, height: 34),
          const Radius.circular(5),
        );
        canvas.drawRRect(tile, fillAccent);
        canvas.drawRRect(tile, strokePaint);
        break;

      case _IllustrationKind.genericProduct:
        final card = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: 58, height: 50),
          const Radius.circular(10),
        );
        canvas.drawRRect(card, fillSoft);
        canvas.drawRRect(card, strokePaint);
        canvas.drawCircle(Offset(cx, cy), 12, fillAccent);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ProductIllustrationPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.accent != accent;
  }
}
