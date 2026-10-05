import 'prayer_definition.dart';
import 'prayer_calibration.dart';

/// Static MVP training copy; independent of inference. Human review pending.
class PrayerContent {
  static const version = 'ar-movement-mvp-1';
  static const purpose =
      'تدريب على تسلسل حركات الصلاة فقط، دون تقييم صحتها أو قبولها.';
  static const setup =
      'ثبّت الهاتف وأظهر الجسم كاملاً. إذا استوردت مرجعًا محليًا للضبط، اتبع رسمه قبل البدء. الرسوم التعليمية لا تقيس وضعيتك.';
  static const calibrationLabels = <CalibrationIssue, String>{
    CalibrationIssue.noBody: 'قف أمام الكاميرا حتى يظهر جسمك.',
    CalibrationIssue.visibility:
        'أظهر الرأس والكتفين والوركين والركبتين والقدمين بوضوح.',
    CalibrationIssue.framing: 'الجسم قريب من حافة الصورة؛ عدّل موضع الهاتف.',
    CalibrationIssue.tooFar: 'اقترب قليلًا من الكاميرا.',
    CalibrationIssue.tooClose: 'ارجع خطوة لتترك مساحة للركوع والسجود.',
    CalibrationIssue.center: 'تحرّك لتكون في منتصف الصورة.',
    CalibrationIssue.posture: 'قف مستقيمًا وافرد الركبتين لضبط التصوير.',
    CalibrationIssue.angle:
        'استدر قليلًا حتى يقترب اتجاه الجسم من الرسم الأبيض.',
    CalibrationIssue.holding: 'الوضع مناسب مبدئيًا؛ اثبت قليلًا لتأكيد الضبط.',
    CalibrationIssue.ready: '✓ وضع التصوير مناسب تقريبًا. يمكنك بدء التدريب.',
  };
  static const unclear = 'لم أتمكن من رصد الحركة بوضوح';
  static const adjust = 'حاول تعديل موضع الهاتف أو إعادة الحركة';
  static const skipped = 'لم يتم رصد الحركة السابقة، أعد الجزء الموضح.';
  static const repeated = 'تم رصد حركة مكررة، انتقل إلى الحركة الموضحة.';
  static const unexpected = 'أعد الحركة من فضلك، واتبع الحركة الموضحة.';
  static const labels = <PrayerStation, String>{
    PrayerStation.standing: 'القيام',
    PrayerStation.ruku: 'الركوع',
    PrayerStation.standingAfterRuku: 'الاعتدال بعد الركوع',
    PrayerStation.sujood1: 'السجود الأول',
    PrayerStation.sittingBetweenSujood: 'الجلوس بين السجدتين',
    PrayerStation.sujood2: 'السجود الثاني',
    PrayerStation.intermediateSitting: 'الجلوس الأوسط',
    PrayerStation.finalSitting: 'الجلوس الأخير',
  };
  static const poseLabels = <PrayerPose, String>{
    PrayerPose.standing: 'قيام',
    PrayerPose.ruku: 'ركوع',
    PrayerPose.sujood: 'سجود',
    PrayerPose.sitting: 'جلوس',
    PrayerPose.unknown: 'غير واضحة / انتقال',
  };
}
