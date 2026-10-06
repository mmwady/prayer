import 'package:flutter/material.dart';
import '../ui/ui_kit.dart';
import '../ui/app_theme.dart';
import 'contracts.dart';

class LocalPredictionCards extends StatelessWidget {
  const LocalPredictionCards(
      {super.key, required this.result, this.expandable = false});
  final Map<String, dynamic>? result;
  final bool expandable;
  String label(Object? action) {
    final index = actionClasses.indexOf(action is String ? action : '');
    return index < 0 ? 'وضعية غير متاحة' : actionArabic[index];
  }

  String confidence(Object? value) =>
      value is num ? '${(value * 100).toStringAsFixed(1)}٪' : '—';
  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return const AppNote(
          'تحذير تشخيصي: قرارات النماذج الثلاثة غير متاحة لهذه النتيجة.',
          icon: Icons.warning_amber);
    }
    final models = r['individual_models'];
    Widget decisions() {
      if (models is! List || models.length != 3) {
        return const AppNote(
            'تحذير تشخيصي: النتيجة لا تحتوي على قرارات النماذج الثلاثة.',
            icon: Icons.warning_amber);
      }
      return LayoutBuilder(builder: (context, c) {
        final three = c.maxWidth >= 600;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final m in models)
            SizedBox(
                width: three ? (c.maxWidth - 20) / 3 : c.maxWidth,
                child: AppCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Model seed ${m['seed']}',
                              textDirection: TextDirection.ltr),
                          Text((m['predicted_action'] ?? 'غير متاح').toString(),
                              textDirection: TextDirection.ltr,
                              style: Theme.of(context).textTheme.titleSmall),
                          Text(label(m['predicted_action'])),
                          Text('ثقة التصنيف ${confidence(m['confidence'])}'),
                          Text(
                              m['available'] == false
                                  ? 'لا توجد وضعية صالحة'
                                  : m['class_index'] == r['class_index']
                                      ? 'يتفق مع القرار المجمع'
                                      : 'يختلف عن القرار المجمع — عدم يقين',
                              style: TextStyle(
                                  color: m['class_index'] == r['class_index']
                                      ? AppColors.accent
                                      : AppColors.warning))
                        ])))
        ]);
      });
    }

    final body = <Widget>[
      Text('القرار المجمع: ${label(r['predicted_action'])}',
          style: Theme.of(context).textTheme.titleMedium),
      Text((r['predicted_action'] ?? 'غير متاح').toString(),
          textDirection: TextDirection.ltr),
      Text('ثقة التصنيف ${confidence(r['confidence'])}',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (expandable)
        ExpansionTile(
            title: const Text('قرارات النماذج الثلاثة'),
            children: [decisions()])
      else
        decisions(),
      if (r['classifier_disagreement'] == true)
        const AppNote(
            'تختلف قرارات المصنفات؛ راجع النتائج الثلاثة. الثقة لا تقيس صحة الصلاة.',
            icon: Icons.help_outline),
      if (r['warning'] != null) AppNote(r['warning'].toString()),
      Text(
          'وضوح الجسم: ${r['mean_visibility'] is num ? (r['mean_visibility'] as num).toStringAsFixed(3) : '—'} • الاستعادة: ${r['recovery_method']} • ${(r['inference_ms'] as num? ?? 0).toStringAsFixed(0)} ms'),
      if (!expandable)
        for (final item in r['top3'] as List? ?? const [])
          Text('${label(item['action'])} • ${confidence(item['probability'])}'),
    ];
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: body));
  }
}
