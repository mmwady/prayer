// ─────────────────────────────────────────────────────────────────────────────
// workout_screen.dart
//
// Distraction-free workout view.
//
// Visual stack (bottom → top):
//   1. `CameraPreview`  — the live camera feed (or a black placeholder if
//      we're running in an environment without a real camera).
//   2. `ArOverlay`      — stick figure + faulty-joint pulse.
//   3. `RepCounter`     — small HUD in a corner.
//
// Per the UX spec, the active screen shows NO menus or buttons. A long-press
// anywhere exits — chosen because swipe-to-dismiss conflicts with some
// Android gesture navigation.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/env.dart';
import '../services/audio_player.dart';
import '../services/pose_detector.dart';
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

  // Tracks whether the user has loaded a video (or the stub is active).
  // On web, the file picker requires a real user gesture — we can't call
  // detector.start() from initState() because the browser will silently
  // block the file dialog. So we split initialisation in two:
  //   • initState()    → connects WS + loads templates
  //   • _loadDetector() → called from an explicit tap, then starts the detector
  bool _videoLoaded = false;

  @override
  void initState() {
    super.initState();
    // Retrieve the locale string from the provider
    final localeCode = context.read<LocaleProvider>().localeCode;

    _controller = WorkoutController(
      exercise: widget.exercise,
      detector: getPlatformPoseDetector(),
      ws: WsClient('${Env.wsUrl}?lang=$localeCode'),
      audio: CoachingAudioPlayer(),
    );

    // Connect WS + fetch templates immediately — these don't need a gesture.
    // The actual detector (file picker on web) is started by _loadDetector().
    _controller.startWithoutDetector();
  }

  /// Called when the user taps the "Load Video" button.
  /// Wrapped in user-gesture context so the browser allows the file picker.
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
        // Long-press exits the set — closes the screen AND the WS
        // (via the controller's dispose).
        body: GestureDetector(
          onLongPress: () async {
            await _controller.finishSet();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Layer 1: camera placeholder. A real implementation wires a
              // `CameraController` + `CameraPreview` here; we use a black
              // background so the AR overlay renders on an emulator.
              Container(color: Colors.black),

              // Layer 2: AR overlay driven by the controller's keypoints.
              Consumer<WorkoutController>(
                builder: (_, c, __) => ArOverlay(
                  keypoints: c.keypoints,
                  faultyJoints: c.faultyJoints,
                ),
              ),

              // Layer 3: HUD. Positioned deliberately off-center so the
              // subject's torso (where the AR stick figure lives) isn't
              // occluded.
              Positioned(
                top: 48,
                right: 24,
                child: Consumer<WorkoutController>(
                  builder: (_, c, __) => RepCounter(reps: c.repCount),
                ),
              ),

              // Caption: shown small at the bottom so hearing-impaired users
              // or those without sound can still read the coach's response.
              Positioned(
                left: 24,
                right: 24,
                bottom: 48,
                child: Consumer<WorkoutController>(
                  builder: (_, c, __) => AnimatedOpacity(
                    opacity: c.lastCaption == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      c.lastCaption ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Layer 4 (web only): "Load Video" prompt.
              // Shown until the user picks a file. This button MUST be the
              // source of the detector.start() call because browsers require
              // file-picker dialogs to originate from a direct user gesture.
              // Once _videoLoaded is true, this layer disappears entirely.
              if (!_videoLoaded)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 18),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                        icon: const Icon(Icons.video_file_outlined),
                        label: Text(context.watch<LocaleProvider>().t('load_video')),
                        onPressed: _loadDetector,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
