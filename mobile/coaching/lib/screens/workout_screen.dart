// ─────────────────────────────────────────────────────────────────────────────
// workout_screen.dart
//
// Split workout view:
//   top half    → skeleton / joints overlay
//   bottom half → real uploaded video or live camera preview
//
// This is better for demos because reviewers can compare the AI skeleton against
// the original movement instead of seeing only floating joints.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/env.dart';
import '../services/audio_player.dart';
import '../services/pose_detector_provider.dart';
import '../services/ws_client.dart';
import '../state/locale_provider.dart';
import '../state/workout_controller.dart';
import '../widgets/ar_overlay.dart';
import '../widgets/rep_counter.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key, required this.exercise});

  final String exercise;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  late final WorkoutController _controller;
  bool _videoLoaded = false;

  @override
  void initState() {
    super.initState();
    final localeCode = context.read<LocaleProvider>().localeCode;

    _controller = WorkoutController(
      exercise: widget.exercise,
      detector: getPlatformPoseDetector(),
      ws: WsClient('${Env.wsUrl}?lang=$localeCode'),
      audio: CoachingAudioPlayer(),
    );

    _controller.startWithoutDetector();
  }

  Future<void> _loadDetector() async {
    await _controller.startDetector();
    if (mounted) setState(() => _videoLoaded = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onLongPress: () async {
            await _controller.finishSet();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: _Panel(
                        title: 'AI skeleton',
                        child: Consumer<WorkoutController>(
                          builder: (_, c, __) => Stack(
                            fit: StackFit.expand,
                            children: [
                              const ColoredBox(color: Colors.black),
                              ArOverlay(
                                keypoints: c.keypoints,
                                faultyJoints: c.faultyJoints,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white24),
                    Expanded(
                      child: _Panel(
                        title: 'Original video',
                        child: _videoLoaded
                            ? _controller.detector.buildPreview()
                            : _LoadVideoPrompt(onPressed: _loadDetector),
                      ),
                    ),
                  ],
                ),

                Positioned(
                  top: 20,
                  right: 20,
                  child: Consumer<WorkoutController>(
                    builder: (_, c, __) => RepCounter(reps: c.repCount),
                  ),
                ),

                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: Consumer<WorkoutController>(
                    builder: (_, c, __) => AnimatedOpacity(
                      opacity: c.lastCaption == null ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Text(
                            c.lastCaption ?? '',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
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
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 12,
          top: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadVideoPrompt extends StatelessWidget {
  const _LoadVideoPrompt({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
            textStyle: const TextStyle(fontSize: 18),
          ),
          icon: const Icon(Icons.video_file_outlined),
          label: Text(context.watch<LocaleProvider>().t('load_video')),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
