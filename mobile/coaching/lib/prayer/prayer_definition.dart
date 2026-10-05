enum PrayerType { fajr, dhuhr, asr, maghrib, isha, demo }

enum PrayerPose { standing, ruku, sujood, sitting, unknown }

enum PrayerStation {
  standing,
  ruku,
  standingAfterRuku,
  sujood1,
  sittingBetweenSujood,
  sujood2,
  intermediateSitting,
  finalSitting;

  PrayerPose get pose => switch (this) {
        standing || standingAfterRuku => PrayerPose.standing,
        ruku => PrayerPose.ruku,
        sujood1 || sujood2 => PrayerPose.sujood,
        _ => PrayerPose.sitting,
      };

  bool get isCore => index <= PrayerStation.sujood2.index;
}

class RakahDefinition {
  RakahDefinition({
    required this.index,
    this.hasIntermediateSitting = false,
    this.hasFinalSitting = false,
  }) : stations = List.unmodifiable([
          PrayerStation.standing,
          PrayerStation.ruku,
          PrayerStation.standingAfterRuku,
          PrayerStation.sujood1,
          PrayerStation.sittingBetweenSujood,
          PrayerStation.sujood2,
          if (hasIntermediateSitting) PrayerStation.intermediateSitting,
          if (hasFinalSitting) PrayerStation.finalSitting,
        ]);

  final int index;
  final bool hasIntermediateSitting;
  final bool hasFinalSitting;
  final List<PrayerStation> stations;
}

class PrayerDefinition {
  PrayerDefinition({
    required this.prayerType,
    required this.arabicName,
    required int rakahCount,
  }) : rakahs = List.unmodifiable(List.generate(
          rakahCount,
          (i) => RakahDefinition(
            index: i + 1,
            hasIntermediateSitting: i == 1 && rakahCount > 2,
            hasFinalSitting:
                i == rakahCount - 1 && prayerType != PrayerType.demo,
          ),
        ));

  final PrayerType prayerType;
  final String arabicName;
  final List<RakahDefinition> rakahs;
  int get rakahCount => rakahs.length;
  int get coreMovementCount => rakahCount * 6;
  int get stationCount => rakahs.fold(0, (n, r) => n + r.stations.length);
}

class PrayerCatalog {
  static final definitions = List<PrayerDefinition>.unmodifiable([
    PrayerDefinition(
        prayerType: PrayerType.fajr, arabicName: 'صلاة الفجر', rakahCount: 2),
    PrayerDefinition(
        prayerType: PrayerType.dhuhr, arabicName: 'صلاة الظهر', rakahCount: 4),
    PrayerDefinition(
        prayerType: PrayerType.asr, arabicName: 'صلاة العصر', rakahCount: 4),
    PrayerDefinition(
        prayerType: PrayerType.maghrib,
        arabicName: 'صلاة المغرب',
        rakahCount: 3),
    PrayerDefinition(
        prayerType: PrayerType.isha, arabicName: 'صلاة العشاء', rakahCount: 4),
    PrayerDefinition(
        prayerType: PrayerType.demo, arabicName: 'ركعة تجريبية', rakahCount: 1),
  ]);

  static PrayerDefinition of(PrayerType type) =>
      definitions.firstWhere((p) => p.prayerType == type);
}
