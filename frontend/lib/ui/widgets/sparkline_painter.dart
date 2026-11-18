import 'dart:math' as math;
import 'package:flutter/material.dart';

class SparklineWidget extends StatelessWidget {
  final List<double> history;
  final double strikePrice;
  final double msrp;
  final double allTimeLow;
  final bool isBelowStrike;
  final bool isTrap;

  const SparklineWidget({
    super.key,
    required this.history,
    required this.strikePrice,
    required this.msrp,
    required this.allTimeLow,
    required this.isBelowStrike,
    required this.isTrap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          history: history.isEmpty ? [msrp, strikePrice] : history,
          strikePrice: strikePrice,
          msrp: msrp,
          allTimeLow: allTimeLow,
          isBelowStrike: isBelowStrike,
          isTrap: isTrap,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> history;
  final double strikePrice;
  final double msrp;
  final double allTimeLow;
  final bool isBelowStrike;
  final bool isTrap;

  _SparklinePainter({
    required this.history,
    required this.strikePrice,
    required this.msrp,
    required this.allTimeLow,
    required this.isBelowStrike,
    required this.isTrap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final allVals = [...history, strikePrice, msrp, allTimeLow];
    final minVal = allVals.reduce(math.min) * 0.92;
    final maxVal = allVals.reduce(math.max) * 1.06;
    final range = math.max(1.0, maxVal - minVal);

    const padX = 6.0;
    const padY = 8.0;
    final usableW = math.max(10.0, size.width - padX * 2);
    final usableH = math.max(10.0, size.height - padY * 2);

    double toX(int i) =>
        padX + (history.length <= 1 ? usableW : (i / (history.length - 1)) * usableW);
    double toY(double v) =>
        size.height - padY - ((v - minVal) / range) * usableH;

    // Draw dashed strike price line
    final strikeY = toY(strikePrice).clamp(padY, size.height - padY);
    final strikePaint = Paint()
      ..color = const Color(0xFF22C55E).withValues(alpha: 0.65)
      ..strokeWidth = 1.2;

    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double startX = padX;
    while (startX < size.width - padX) {
      canvas.drawLine(
        Offset(startX, strikeY),
        Offset(math.min(startX + dashWidth, size.width - padX), strikeY),
        strikePaint,
      );
      startX += dashWidth + dashSpace;
    }

    // Draw trajectory path
    final lineColor = isTrap
        ? const Color(0xFFEF4444)
        : (isBelowStrike ? const Color(0xFF22C55E) : const Color(0xFF38BDF8));

    final path = Path();
    for (int i = 0; i < history.length; i++) {
      final pt = Offset(toX(i), toY(history[i]).clamp(padY, size.height - padY));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);

    // Draw endpoint circle
    final lastPt = Offset(
      toX(history.length - 1),
      toY(history.last).clamp(padY, size.height - padY),
    );
    canvas.drawCircle(lastPt, 4.0, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.history != history ||
        oldDelegate.strikePrice != strikePrice ||
        oldDelegate.isBelowStrike != isBelowStrike;
  }
}
