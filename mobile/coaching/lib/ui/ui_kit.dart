import '../l10n/app_localizations.dart';
// ─────────────────────────────────────────────────────────────────────────────
// ui_kit.dart
//
// The handful of presentation widgets every Iqtadi screen shares: cards,
// section headers, status banners, pills, metric tiles, summary lines and the
// step/station tracker.
//
// These widgets are intentionally dumb: they render text, icons and tone. No
// prayer logic, no thresholds, no network. Screens own the wording.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Visual tone for cards, banners and pills — one color per meaning.
enum Tone {
  neutral(AppColors.textSecondary),
  info(AppColors.info),
  ready(AppColors.accent),
  attention(AppColors.warning),
  danger(AppColors.danger);

  const Tone(this.color);

  final Color color;

  /// Default icon for the tone. Callers may override with a more specific one.
  IconData get icon => switch (this) {
        Tone.neutral => Icons.info_outline,
        Tone.info => Icons.lightbulb_outline,
        Tone.ready => Icons.check_circle_outline,
        Tone.attention => Icons.error_outline,
        Tone.danger => Icons.warning_amber_rounded,
      };
}

/// Blends a tone color into the card fill so tinted cards stay readable.
Color _tintedFill(Color tone, Color base) =>
    Color.alphaBlend(tone.withValues(alpha: .10), base);

/// Rounded, hairline-bordered surface used for every block on every screen.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin = const EdgeInsets.only(bottom: AppSpacing.md),
    this.tone,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  /// Optional semantic tint. `null` renders a plain neutral card.
  final Tone? tone;

  /// When set the whole card becomes tappable with an ink ripple.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = this.tone;
    final content = Padding(padding: padding, child: child);
    return Padding(
      padding: margin,
      child: Material(
        elevation: 2,
        shadowColor: AppColors.emerald.withValues(alpha: .09),
        color: tone == null
            ? AppColors.surface
            : _tintedFill(tone.color, AppColors.surface),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(
            color: tone == null
                ? AppColors.border
                : tone.color.withValues(alpha: .40),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Section heading with an optional accent icon, subtitle and trailing widget.
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = this.icon;
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                  child: Text(localized(context, title),
                      style: theme.textTheme.titleLarge)),
              if (trailing != null) trailing,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(localized(context, subtitle),
                  style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// Tinted card carrying one status message — the app's standard way to say
/// "this worked", "watch out" or "this failed".
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.text,
    this.title,
    this.tone = Tone.neutral,
    this.icon,
    this.trailing,
    this.margin = const EdgeInsets.only(bottom: AppSpacing.md),
  });

  final String text;
  final String? title;
  final Tone tone;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = this.title;
    final trailing = this.trailing;
    return AppCard(
      tone: tone,
      margin: margin,
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? tone.icon, color: tone.color, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    localized(context, title),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: tone.color),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(localized(context, text),
                    style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing,
          ],
        ],
      ),
    );
  }
}

/// Small secondary footnote with a leading icon.
class AppNote extends StatelessWidget {
  const AppNote(this.text, {super.key, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(localized(context, text),
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      );
}

/// Compact rounded label: legends, counts, mode badges.
class PillTag extends StatelessWidget {
  const PillTag(this.text, {super.key, this.icon, this.tone = Tone.neutral});

  final String text;
  final IconData? icon;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.color.withValues(alpha: .14),
        borderRadius: AppRadius.pill,
        border: Border.all(color: tone.color.withValues(alpha: .45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone.color),
            const SizedBox(width: 5),
          ],
          Text(
            localized(context, text),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tone.color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// Label + value tile. Two of them side by side form the session metric row.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone = Tone.neutral,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = this.icon;
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: tone.color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  localized(context, label),
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            localized(context, value),
            style: theme.textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// One icon + one full sentence. Unlike [MetricTile] the whole line is a single
/// [Text], which keeps the summary copy greppable and testable verbatim.
class StatLine extends StatelessWidget {
  const StatLine({
    super.key,
    required this.text,
    this.icon = Icons.check_circle_outline,
    this.tone = Tone.neutral,
  });

  final String text;
  final IconData icon;
  final Tone tone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: tone.color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(localized(context, text),
                  style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      );
}

/// State of one entry in a [StepTracker].
enum StepMark { done, current, pending }

/// One line of a [StepTracker].
class TrackerStep {
  const TrackerStep(this.label, {this.mark = StepMark.pending});

  final String label;
  final StepMark mark;
}

/// Vertical numbered stepper with a connector line. Used for the "how to use"
/// guide and for the current rakah's station list.
class StepTracker extends StatelessWidget {
  const StepTracker(this.steps, {super.key});

  final List<TrackerStep> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 26,
                  child: Column(
                    children: [
                      _StepDot(index: i, mark: steps[i].mark),
                      if (i != steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: steps[i].mark == StepMark.done
                                ? AppColors.accent.withValues(alpha: .5)
                                : AppColors.border,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        bottom: i == steps.length - 1 ? 0 : AppSpacing.lg),
                    child: Text(
                      localized(context, steps[i].label),
                      style: steps[i].mark == StepMark.current
                          ? theme.textTheme.titleMedium
                              ?.copyWith(color: AppColors.accent)
                          : theme.textTheme.titleMedium?.copyWith(
                              color: steps[i].mark == StepMark.done
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.index, required this.mark});

  final int index;
  final StepMark mark;

  @override
  Widget build(BuildContext context) {
    final done = mark == StepMark.done;
    final current = mark == StepMark.current;
    final color = done
        ? AppColors.accent
        : current
            ? AppColors.accent
            : AppColors.border;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.accent : Colors.transparent,
        border: Border.all(color: color, width: current ? 2 : 1.2),
      ),
      child: done
          ? const Icon(Icons.check, size: 16, color: AppColors.onAccent)
          : Text(
              localized(context, '{0}', [index + 1]),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: current ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
    );
  }
}
