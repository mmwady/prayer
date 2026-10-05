# Browser inference source contract (inspected before implementation)

The requested `Deployment/` directory is absent in this checkout. Authoritative artifacts are
`model/deployment_bundle/*`; the image/camera UI and extended predictor are under
`PrayerActionRecognizer_UI/`. The extended predictor has the same mathematical feature,
recovery and ensemble operations as the compact predictor. Neither source is modified.

## Image preparation

Pillow `ImageOps.exif_transpose`, then `convert('RGB')`; `thumbnail((384,512), LANCZOS)`
preserves aspect ratio and **never enlarges** a smaller image. Pillow's thumbnail defaults
to `reducing_gap=2.0` (integer reduction may precede Lanczos for large images). Thumbnail
dimensions use Pillow's aspect-error-minimizing floor/ceil choice. Paste at
`((384-width)//2,(512-height)//2)` into an RGB black canvas.

Recovery candidates are constructed from that canvas independently, in this order:
`standard`, channel-wise `ImageOps.autocontrast(cutoff=1)` (trim 1% from each histogram
tail including black padding), `ImageEnhance.Contrast(...).enhance(1.15)` (rounded mean
8-bit L luminance is the degenerate gray image), `rotate(-5,BICUBIC)`, `rotate(5,BICUBIC)`.
Rotation is around (192,256), expand=false, black fill. Stop on the first valid pose.
Browser image decoding/ICC/JPEG may differ from Pillow; pixel and pose parity must be measured.
PNG bytes are decoded locally with fast-png, discard alpha without compositing, ignore
ICC transformations as Pillow's RGB conversion does, and apply raw eXIf orientation.
48 fixtures cover RGBA/LA/palette/L/1/I;16 and all eight orientations. Sub-8-bit
interlaced PNG is rejected explicitly because the pinned decoder does not support it
correctly; convert it to an RGB PNG/JPEG. JPEG/WebP use the browser's native oriented
decoder, so their decode rounding and color-profile differences remain a parity limit.

## Pose and float32 feature contract

MediaPipe Tasks PoseLandmarker, supplied `pose_landmarker_heavy.task`, IMAGE mode,
num_poses=1, detection/presence/tracking thresholds all 0.2; default CPU delegate.
Use normalized `pose_landmarks[0]`, **not world landmarks**. No mirroring before inference.

Verified library boundary: `@mediapipe/tasks-vision` 0.10.32's public normalized
landmark converter omits presence, even though the graph emits protobuf field 5.
`scripts/mediapipe-presence.mjs` preserves that measured raw field during bundling.
It checks the exact upstream file hash and converter occurrence, failing on upgrades.
This changes only the JS container conversion, never the graph, task model or weights.
See [upstream converter](https://github.com/google-ai-edge/mediapipe/blob/v0.10.32/mediapipe/tasks/web/components/processors/landmark_result.ts).

Let X be the 33×3 float32 XYZ array. Visibility V and presence P are 33-element float32
arrays with missing/null values replaced by zero. H=(X23+X24)/2 in all three coordinates.
S=(X11.xy+X12.xy)/2. Scale=max(sqrt(sum((S-H.xy)^2)),
sqrt(sum((X11.xy-X12.xy)^2))). Distances use XY only, with no aspect correction.
Z is nevertheless centered at H.z and divided by the same scale.
N=(X-H)/scale; raw=[N row-major flattened (99),V (33),P (33)].
features[0:165]=(raw-mean)/std; features[165]=float32(1).
NumPy float32 rounding applies to the intermediate arithmetic. Reject scale<=1e-4,
nonfinite coordinates and nonfinite features (the latter is additional defensive validation
requested by the browser specification). Do not clamp standardized features.

## Classifiers and ordering

Metadata winner `exp1_full_head_attention`, main seeds 2026,3407,8111, feature dimension 166.
Class order, zero based:
0 `1_Qiyam`; 1 `2_Takbir`; 2 `3_Qiyam_Recitation`; 3 `4_Ruku`;
4 `5_Sujud`; 5 `6_Jalsa`; 6 `7_Salam_Right`; 7 `8_Salam_Left`.
Each TorchScript model returns logits. Independently softmax each model, then arithmetic
class-wise mean. Python additionally divides the mean by its float32 sum; this differs
from the requested literal mean only by floating-point roundoff. Browser retains the
literal mean and tests the difference against Python with an explicit tolerance.
Python ranks `np.argsort(p)[::-1]`; equal values use descending class index for the small
eight-class reference fixtures. No logits averaging, voting, retraining or corrections.

## Camera rule and sequence ownership

`PrayerActionRecognizer_UI/app.py`: minimum confidence defaults to 0.70 (slider 0.50–0.95),
three consecutive confident identical actions, 3-second capture cooldown, deduplicate
held actions, retain newest 12 captures, baseline inference spacing 0.22 seconds.
An invalid/low-confidence sample resets the candidate. A different confident candidate
unlocks the previously captured action. Adaptive throttling may increase the spacing;
it must never turn one prediction into multiple matches.

Existing backend raw sequence validation uses all-optimal-path LCS alignment in
`backend/app/analysis/sequence.py`, with definitions from `domain.py`. Browser report
generation ports this raw conservative alignment; experimental normalization/geometry
corrections remain absent/disabled. Reports express observed movements and uncertainty,
never prayer validity. Existing backend recorded/live routes remain available separately.

## Three distinct parity levels

1. Identical float32 landmarks → features: atol=2e-5, rtol=2e-6.
2. Identical features → PyTorch/ONNX logits: atol=2e-5, rtol=2e-5;
   probabilities: atol=2e-6, rtol=2e-5. Check all three models and ensemble class.
3. Identical image bytes → measured pose/recovery/class agreement; no universal threshold
   is asserted before observing real results. Detection failures count explicitly.

Primary implementation references: [MediaPipe Web guide](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/web_js),
[ORT deployment](https://onnxruntime.ai/docs/tutorials/web/deploy.html),
[Pillow source](https://github.com/python-pillow/Pillow). Worker fallback remains on-device;
same-origin WASM uses one thread without requiring cross-origin isolation.
