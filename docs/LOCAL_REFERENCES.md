# Local reference and movement guidance

All prayer training guidance and reference setup now run on the device. The
default training screen constructs `LocalPrayerGuidanceSource` and
`LocalPrayerReferenceRepository`, never the HTTP implementations. The original
HTTP classes remain explicit compatibility tools and tests; the app does not
instantiate them for training.

## Reference management

Open **المراجع والإرشادات المحلية**. Import a measured reference JSON on Web or
paste its JSON on any platform, review/edit it, confirm its suitability, then
save. Web exports a JSON download; native export copies JSON for local saving.
Delete removes the device's active reference. Browser storage is per origin,
and native storage is per app installation; neither is synchronized.

The repository accepts the original activated reference schema version 2, with
six complete stations in the original order. It validates metadata, finite
sample/preview coordinates, confidence, image aspect ratio, enough samples and
usable standing calibration. The JSON editor preserves original authoring
metadata. Size is limited to 2 MiB. Saved references have an independent local
schema and an explicit user review flag; incompatible/corrupt entries are
invalidated. No approved active reference is bundled or invented.

This manager edits/imports existing measured JSON; it does not extract a new
calibration reference from a video. The existing operator reference extraction
tool remains in the backend source for compatibility, but prayer inference and
local training never call it. Local reference video extraction/annotation is a
separate future authoring enhancement and must use measured MediaPipe evidence.

Bundled prayer illustrations, including Takbir and both Salam directions, are
shown as educational content only. They are not activated calibration data and
are never used to judge a user's posture. A review checkbox records the user's
confirmation; it does not assert religious, medical or expert approval.

## Classification provenance

The primary home prayer cards use the supplied three-model local inference
pipeline for video/live recognition. That pipeline does not need calibration
reference JSON and preserves all eight model classes.

The isolated legacy `PrayerTrainingScreen` remains a geometric trainer using
the existing reduced keypoint contract and deterministic station engine. Its
setup/session visibly say **تدريب هندسي محلي**, and explicitly distinguish it
from the supplied ensemble. It can start without a reference; there is then no
reference-matching or calibrated posture assessment. Importing a usable local
reference enables the previous explicit calibration/matcher flow. Missing,
uncertain or invalid observations never advance progression. ML Kit keypoints
are not converted into 166-feature classifier inputs.

Web's legacy pose wrapper now uses the same-origin on-device bridge rather
than a CDN. World-coordinate fields must be omitted when not measured; no
normalized coordinates are relabelled as world meters.

## Guidance

`LocalPrayerGuidanceSource` maps start, retry, uncertain, completed and stopped
events to bundled Arabic movement text. It does not call an LLM, send facts to
a provider or change progression. Text reiterates training purpose and does not
claim prayer validity. The static content version remains explicit; human
review of the movement copy remains pending.

## Focused checks

From `mobile/coaching`:

```powershell
flutter analyze --no-pub
flutter test --no-pub test/local_training_sources_test.dart test/prayer_calibration_widget_test.dart test/prayer_guidance_test.dart test/prayer_guidance_controller_test.dart test/prayer_calibration_test.dart --concurrency=1
```

These exercise local guidance, no fabricated reference, import/review/persistence/
export/delete, invalid evidence and schema invalidation, optional reference-free
training, and preserved calibration/HTTP compatibility behavior. Runtime Web
file download/import and physical native clipboard behavior need separate
device acceptance; a Flutter unit test does not establish them.
