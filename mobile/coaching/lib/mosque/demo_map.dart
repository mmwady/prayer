import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../ui/app_theme.dart';
import 'client.dart';

/// Coordinate plot of the demo, with an explicitly synthetic route overlay.
/// No fabricated roads/tiles are represented as a real basemap.
class DemoMap extends StatelessWidget {
  const DemoMap(
      {super.key, required this.points, this.path = const [], this.onPoint});
  final List<Json> points;
  final List<Json> path;
  final void Function(double lat, double lng)? onPoint;
  List<Json> get displayPoints {
    final unique = <String, Json>{};
    for (final point in points) {
      final key =
          '${(point['lat'] as num).toDouble().toStringAsFixed(6)},${(point['lng'] as num).toDouble().toStringAsFixed(6)}';
      if (unique.containsKey(key)) {
        unique[key]!['label'] =
            '${unique[key]!['label'] ?? unique[key]!['name']} / ${point['label'] ?? point['name']}';
      } else {
        unique[key] = {...point};
      }
    }
    return unique.values.toList();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(localized(context, 'خريطة تخطيطية للديمو • المسارات محاكاة'),
            style: const TextStyle(color: AppColors.warning)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final plotted = displayPoints
              .map((point) => <String, dynamic>{
                    ...point,
                    'label': localized(
                        context, point['label'] ?? point['name'] ?? 'نقطة'),
                  })
              .toList();
          final geometry = MapGeometry([...plotted, ...path]);
          return Semantics(
              label: localized(context, 'خريطة تخطيطية: {0}', [
                localized(context, points.map((p) => localized(context, p['label'] ?? p['name'] ?? 'نقطة')).join(localized(context, '، ')))
              ]),
              child: GestureDetector(
                onTapUp: onPoint == null
                    ? null
                    : (tap) {
                        final p = geometry.unproject(
                            tap.localPosition, Size(c.maxWidth, 220));
                        onPoint!(p['lat'] as double, p['lng'] as double);
                      },
                child: SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: CustomPaint(
                        painter: _MapPainter(plotted, path, geometry,
                            Directionality.of(context)))),
              ));
        }),
        Text(
            localized(context,
                'أخضر: البداية • ذهبي: الوجهة • أزرق: نقطة لقاء مقترحة'),
            style: const TextStyle(fontSize: 11)),
      ]);
}

class MapGeometry {
  MapGeometry(List<Json> points) {
    final lat = points.map((p) => (p['lat'] as num).toDouble()).toList();
    final lng = points.map((p) => (p['lng'] as num).toDouble()).toList();
    minLat = lat.isEmpty ? 24.43 : lat.reduce((a, b) => a < b ? a : b) - .002;
    maxLat = lat.isEmpty ? 24.49 : lat.reduce((a, b) => a > b ? a : b) + .002;
    minLng = lng.isEmpty ? 39.57 : lng.reduce((a, b) => a < b ? a : b) - .002;
    maxLng = lng.isEmpty ? 39.63 : lng.reduce((a, b) => a > b ? a : b) + .002;
  }
  late double minLat, maxLat, minLng, maxLng;
  Offset project(Json p, Size s) => Offset(
      20 + ((p['lng'] as num) - minLng) / (maxLng - minLng) * (s.width - 40),
      20 + (maxLat - (p['lat'] as num)) / (maxLat - minLat) * (s.height - 40));
  Json unproject(Offset p, Size s) => {
        'lat': maxLat -
            ((p.dy - 20) / (s.height - 40)).clamp(0, 1) * (maxLat - minLat),
        'lng': minLng +
            ((p.dx - 20) / (s.width - 40)).clamp(0, 1) * (maxLng - minLng)
      };
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.points, this.path, this.geometry, this.textDirection);
  final List<Json> points, path;
  final MapGeometry geometry;
  final TextDirection textDirection;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
        Paint()..color = AppColors.surfaceHigh);
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (double x = 20; x < size.width; x += 35) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 20; y < size.height; y += 35) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (path.length > 1) {
      final line = Path()
        ..moveTo(geometry.project(path.first, size).dx,
            geometry.project(path.first, size).dy);
      for (final p in path.skip(1)) {
        final o = geometry.project(p, size);
        line.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
          line,
          Paint()
            ..color = AppColors.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    for (var i = 0; i < points.length; i++) {
      final p = points[i], o = geometry.project(p, size);
      canvas.drawCircle(
          o,
          7,
          Paint()
            ..color = i == 0
                ? AppColors.accent
                : i == 1
                    ? AppColors.gold
                    : AppColors.info);
      final text = TextPainter(
          text: TextSpan(
              text: p['label'] ?? p['name'] ?? 'نقطة',
              style: const TextStyle(
                  fontFamily: 'IqtadiArabic',
                  fontSize: 10,
                  color: AppColors.textPrimary)),
          textDirection: textDirection,
          maxLines: 2)
        ..layout(maxWidth: 130);
      text.paint(
          canvas,
          Offset((o.dx - 65).clamp(4, size.width - 134),
              o.dy > size.height - 55 ? o.dy - 40 : o.dy + 10));
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}
