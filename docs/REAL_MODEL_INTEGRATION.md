# Prayer action model integration

Recorded-video real inference uses the self-contained `backend/models/prayer_action` bundle copied from `PrayerActionRecognizer_UI/deployment_bundle`.
`app/analysis/prayer_action_predictor.py` preserves the supplied UI predictor preprocessing:
EXIF transpose, RGB letterbox 384x512, ordered recovery attempts, all 33 MediaPipe landmarks,
hip/torso normalization, 166 features and the three-seed TorchScript probability average.
TorchScript weights load on CPU. The UI folder remains unchanged.

## Run

From `backend/`, install `requirements.txt` and configure `backend/.env`:

```dotenv
INFERENCE_PROVIDER=real
ANALYSIS_ALLOW_MOCK=false
PRAYER_MODEL_BUNDLE_DIR=models/prayer_action
```

Docker copies `backend/models/` into the image; no external model mount is required. Rebuild the backend image after
installing the new Torch dependency. A missing/unloadable bundle fails explicitly with
`MODEL_NOT_CONFIGURED`; inference failure never falls back to mock.

## Vocabulary and sequence

- `1_Qiyam` and `3_Qiyam_Recitation` -> standing.
- `2_Takbir` -> takbir; opening station once before first-rakah standing.
- `4_Ruku` -> ruku; `5_Sujud` -> sujood; `6_Jalsa` -> sitting.
- `7_Salam_Right` -> salam_right; `8_Salam_Left` -> salam_left, after final sitting.
- Recorded Demo is one full rakah including opening takbir, final sitting and both salam directions.

Qiyam and recitation share a physical posture for sequence assessment; the actual predictor
retains all eight class probabilities. Takbir is counted only as an opening station;
stable transition takbir gestures do not introduce another opening station.
Flutter renders the backend's Arabic station labels without a vocabulary change.
Temporal confidence/duration and conservative sequence alignment remain unchanged;
short/occluded actions stay UNCONFIRMED. No religious validity judgement is made.

## Boundary and lifecycle

The bundled end-to-end predictor bypasses the legacy opaque 32-slot model interface.
No MediaPipe point is dropped or coerced to that contract. Those interfaces remain available
for independent future models. Predictor resources are released in `finally` after each job,
including cancellation/errors. Weights are loaded per job; workers bound concurrency.

Validate on consented real videos before making any accuracy claim. Blank-image smoke tests
check runtime/no-body behavior only. Unit tests use fake outputs and do not measure accuracy.

## Local verification (2026-10-03)

- 66 backend tests passed, including eight label mappings, no-body handling and sequence changes.
- Actual `IMCSPD-MLP-Attention-Hierarchy-v1` weights loaded: 3 ensemble models, 8 finite normalized class probabilities.
- Actual MediaPipe detection on a blank JPEG returned unknown/no body; all resources closed.
- Reproduce with `python tools/smoke_prayer_model.py` from `backend/`.
- Local `backend/.env` selects real mode and disables mock. No paid provider was used.
- Real-prayer video accuracy and rebuilt Docker image remain unverified.


## Supplied-video diagnosis and verification (2026-10-03)

- Evaluated the supplied 50-second video locally and through the real HTTP JPEG pipeline at 4 FPS.
- Original outputs confused prostration/folded-knee transitions with bowing; seated probability was split between Jalsa and directional Salam.
- Backend-only postprocessing preserves weights and raw probability outputs. Visible head-down torso geometry permits a mirrored recovery pass for Sujud; only a confident Sujud result is accepted. Directional Salam is never inferred from mirrored images.
- Ruku requires at least one visible straight projected knee (160 degrees, visibility >=0.5); missing/folded legs produce unknown. This is an evidence gate, not a posture-quality score.
- When no seated subclass meets the configured confidence threshold, their sum can confirm the physical sitting posture; it cannot confirm a salam direction. Aggregated posture confidence is not an individual subclass confidence.
- Sequence assessment anchors at the first stable opening gesture, ignores transitional takbir, consolidates repeated observations within 1 second or across a witnessed takbir, and stops after terminal left salam following right salam. Sitting between salam gestures is supported.
- Unknown transition samples alone do not reject an otherwise fully evidenced sequence. Missing mandatory stations and ambiguous assignments still require review.
- HTTP verification: 200 uploaded JPEG frames, real mode, 1 observed rakah, all 10 stations DETECTED, OBSERVED_COMPLETE. Test job deleted after reading its report; no paid provider calls.
- 74 backend tests passed, including absent sitting, folded/occluded knees and directional ambiguity. Other camera angles and videos remain unvalidated; no general model accuracy claim.
- Local diagnostics: `tools/diagnose_prayer_video.py` and `tools/verify_prayer_video_api.py`; reports under `../output/video_diagnosis/`. These tools process user-authorized local footage only.


## Optional experimental postprocessing

All four corrections are OFF by default and OFF in the local `.env`.
Set any option to `true` independently in `backend/.env`, then restart the backend:

```dotenv
PRAYER_MIRROR_SUJOOD_RECOVERY=false
PRAYER_RUKU_GEOMETRY_GATE=false
PRAYER_SEATED_PROBABILITY_PROJECTION=false
PRAYER_SEQUENCE_NORMALIZATION=false
```

The first three govern mirrored Sujud recovery, the straight-knee Ruku gate and seated probability aggregation.
The fourth governs trimming, transitional takbir filtering, same-posture consolidation and tolerance of uncertain transition samples.
With all disabled, original model labels/confidence are preserved (apart from the existing canonical label mapping),
and strict conservative alignment handles the report. Recorded demo still includes final sitting and salam as requested.
The earlier successful supplied-video evaluation used all corrections enabled; it does not describe the new default raw mode.
The public `/api/v1/prayer-analyses/config` exposes active switches under `experimental_postprocessing`.
`PRAYER_RAKAH_TRANSITION_ANCHORS=false` is an additional independent, opt-in partial-recording
aid: a witnessed standing → ruku → standing triplet after floor observations can anchor the
next rakah. Missing stations stay unconfirmed. For confirmed complete rakahs, sequence
normalization now uses the final event's end as a hard boundary and reserves the first
subsequent standing episode for the next rakah's opening standing. Review placement uses
the same boundary. Restart the backend after changing switches.

Browser verification after the boundary correction: the user-provided
`20261003_121030.mp4` (63.8 seconds) was selected in the existing localhost:55368 tab,
256 sampled JPEGs uploaded, and real inference completed. First rakah remained complete;
second-rakah standing was assigned at 30.8 seconds with 100% frame confidence and a visible
image. Remaining ambiguous/missing stations stayed unconfirmed (overall 1/2 complete).
Review events appeared under rakah 2. No browser console errors were recorded. The optional
transition heuristic remained disabled; this verifies the confirmed-boundary path.
91 backend tests and 9 Flutter report tests passed; analyzer reported only six existing infos.
82 tests verify defaults, disabled behavior and opt-in behavior. No general video-accuracy claim.
