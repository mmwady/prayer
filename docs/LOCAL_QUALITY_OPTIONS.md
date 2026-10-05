# Local prayer analysis quality options

The Flutter recorded-video and live-camera screens expose **تحسين قراءة الحركات**.
Expand it and press **استخدام إعدادات التحسين المقترحة** before starting analysis.
This enables sequence normalization and visible-leg Ruku gating, matching the two
currently enabled backend correction settings. Each can be disabled separately.
All switches are off initially to preserve explicitly optional raw model behavior.
The settings apply to this screen/session; they are frozen at session creation.

**ترجيح وضع الجلوس — تجريبي** remains off in the recommended preset. It combines
Jalsa/right-Salam/left-Salam probabilities only when the raw top-class confidence
is below 0.65 and the sum is at least 0.65. This is a broader posture assessment,
not a replacement for any individual classifier's decision.

## Report transparency

- `predictions` retains every original ensemble and all three individual decisions.
- `assessment_options` records the effective options.
- `corrections` records affected frames, timestamps, raw action/confidence,
  assessed posture/confidence, and independently applied correction reasons.
- `raw_assessment` retains the original conservative station/event assignment.
- Normalized station assignments carry `assignment_method=normalized_sequence`.
- **أثر التحسينات والنتائج الأصلية** shows raw coverage and station statuses,
  correction reasons and raw decisions. All corrections are retained in JSON export.
- Raw report uncertainty still leaves the final result `REVIEW_REQUIRED`; optional
  alignment cannot erase that requirement or assert religious validity.
- Missing/weak/nonfinite leg landmarks leave gated Ruku unconfirmed. Models,
  preprocessing, detector, confidence threshold and CPU provider are unchanged.

Android and Flutter Web now use the same Dart report implementation. Web image
inference remains in the existing local WASM worker. The separate standalone browser
recognizer keeps its original raw JavaScript report; it is not the Flutter prayer flow.

## Verification

`test/fixtures/local_quality_videos.json` contains 457 measured 4-fps observations
from both user videos, actual prepared-image landmarks and the three separately
measured Python classifier distributions. Every combination of the three switches
matches Python station status/event/timestamp assignment and unexpected events.
The tests also check unchanged source predictions, geometric visibility/degeneracy,
default-off switches, preset behavior, raw disclosure and frozen save/export options.

All 131 Flutter tests pass. `flutter analyze --no-pub` has zero errors/warnings and
six existing infos outside the change. These are report parity tests on measured
Python outputs, not new full-video Android inference accuracy or human annotations.

Release ARM64 APK and release Web build pass. The new offline Web cache manifest
was generated. APK model/preprocessing hashes match the original asset manifest;
test fixtures are absent. APK SHA-256:
`698513832584980021e86f16d233c42abab3ebc84dfe76697787d88eb278c08b`.
The update was installed on the connected Samsung M52 without clearing app data.
Actual Arabic UI and the recommended preset were verified: normalization/Ruku on,
experimental seated projection off. Screenshot: `output/iqtadi-quality-options.png`.
The new APK has not been used to replay either complete source video on the phone.

### Subsequent actual phone acceptance — 2026-10-05

The paragraph above describes the initial quality release. The current repaired
APK SHA-256 is `4f4e3df755ae2bb9640335b021bb90adb1f53eb12804c60b45b4132f230e3b6c`.
Reviewing the user's current phone report revealed an older installed APK, then
physical replay revealed premature floor Standing rakah boundaries and early
false Salam truncation. Normalization now requires a witnessed standing/ruku/standing
anchor after floor/seated observations and uses the last witnessed left Salam.
Both Dart and Python use these rules. Native busy release now precedes reply delivery.

Actual Samsung M52 Fajr replay (256 frames): 3/16 raw stations and 58 unexpected
events -> **16/16 stations, 2/2 rakahs and 20 unexpected events** with the recommended
preset. All 256 original probability distributions remain exactly unchanged.
Result stays `REVIEW_REQUIRED`; residual classifier errors remain visible.
42 focused Flutter and 37 backend video tests pass, including the actual phone
event regression. See `output/mobile-current-review.md` and `mobile-final-report.json`.
The WhatsApp video has not been replayed on the final APK.

Reproduce fixture preparation locally using `output/diagnose_local_quality.py` then
`output/prepare_local_quality_fixtures.py`; fixtures are not packaged into the app.

For live camera, these options do not increase capture rate. Keep the existing
buffered/adaptive limitations in mind when interpreting short gestures.
