import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Original vector architecture shared by the recorded-video screens.
class BrandHeader extends StatelessWidget {
  const BrandHeader(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.caption});
  final String title, subtitle, caption;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: AppRadius.card,
        child: Container(
          constraints: const BoxConstraints(minHeight: 200),
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [AppColors.emerald, Color(0xFF185B46)])),
          child: Stack(children: [
            Positioned.fill(
                child: Image.asset('assets/branding/architecture.png',
                    fit: BoxFit.cover, excludeFromSemantics: true)),
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
              AppColors.emerald.withValues(alpha: .55),
              AppColors.emerald.withValues(alpha: .93)
            ])))),
            const Positioned.fill(child: CustomPaint(painter: _ArchPainter())),
            Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.nights_stay_outlined,
                            color: AppColors.gold, size: 21),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(caption,
                                style: const TextStyle(
                                    fontFamily: 'IqtadiArabic',
                                    color: Color(0xFFE1C994),
                                    fontSize: 12)))
                      ]),
                      const SizedBox(height: 20),
                      Text(title,
                          style: const TextStyle(
                              fontFamily: 'IqtadiArabic',
                              color: Color(0xFFFFF8E9),
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              height: 1.5)),
                      const SizedBox(height: 8),
                      Text(subtitle,
                          style: const TextStyle(
                              fontFamily: 'IqtadiArabic',
                              color: Color(0xFFF1E6CD),
                              fontSize: 15,
                              height: 1.7)),
                    ])),
          ]),
        ),
      );
}

class _ArchPainter extends CustomPainter {
  const _ArchPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final x = size.width * .18;
      final w = 70.0 + i * 18;
      final y = 20.0 - i * 13;
      final path = Path()
        ..moveTo(x - w, size.height)
        ..lineTo(x - w, y + 100)
        ..cubicTo(x - w, y + 50, x - 20, y + 30, x, y)
        ..cubicTo(x + 20, y + 30, x + w, y + 50, x + w, y + 100)
        ..lineTo(x + w, size.height);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ArchPainter oldDelegate) => false;
}
