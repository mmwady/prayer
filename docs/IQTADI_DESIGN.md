# Iqtadi visual redesign

Mobile-first Flutter presentation; recorded-video analysis remains backend-owned.

## Identity and assets

- Emerald `#073E30`, action green `#126B4D`, ivory `#F6F0E5`, muted gold `#C5A264`.
- `mobile/coaching/lib/ui/app_theme.dart`: semantic colors, Arabic typography, spacing, radii, Material controls.
- `mobile/coaching/lib/ui/ui_kit.dart`: shared cards, semantic status, metrics and trackers.
- `mobile/coaching/lib/ui/brand_header.dart`: architectural header and original scalable Canvas arch motif.
- `mobile/coaching/assets/branding/architecture.png`: original generated background, built-in image generation tool.
- `mobile/coaching/assets/fonts/NotoSansArabic.ttf`: bundled Arabic font; SIL OFL license beside it.
- Existing Material vector icons and educational prayer-position assets retained.

Final image prompt: Create an original wide premium Islamic architectural background illustration for a Flutter app header. Deep emerald green shadows, muted antique gold outlines, warm ivory light through a pointed mosque arch, subtle distant domes, calm refined atmospheric painterly rendering. Composition: architecture toward left third, dark emerald negative space across right two thirds for Arabic text overlay. No people, no text, no letters, no logos, no UI, no phone frames.

## Layout and behavior

Phone layouts use a single scrolling surface, two prayer columns, large touch controls and stacked movement comparisons below 540px. Web uses a centered maximum width of 880px and three prayer columns above 650px. Material route, expansion, ripple and progress animations remain enabled. Arabic RTL and local typography apply across shared themes, including the preserved isolated training screen.

Consent remains mandatory before uploading sampled JPEGs. The source video stays local. Processing displays actual controller counters and cancellation. Reports display backend results and counts derived from station statuses; model confidence remains explicitly confidence, with no invented accuracy or religious-validity assessment. Ownership headers, retention and delete workflows are unchanged. Synthetic notices remain visible.

## Verification

Actual browser home/upload screenshots are under `output/redesign/`. `processing-qa.png` and `report-qa.png` render actual Flutter widgets with explicitly synthetic test fixtures; they do not represent live model acceptance. The visual test checks 320px, 390px and 820px layouts. Production app contains no added mock data.

Flutter existing tests plus visual test: 57 passed. Backend existing suite: 100 passed. Analyzer has six existing informational findings outside redesigned files. Web release builds succeeded; Android debug APK built successfully with bounded Gradle memory after host memory exhaustion. Physical Android device runtime and live end-to-end model accuracy are not claimed by this redesign.
