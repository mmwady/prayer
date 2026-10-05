"""Physical vocabulary and contextual stations are deliberately separate."""
COUNTS = dict(fajr=2, dhuhr=4, asr=4, maghrib=3, isha=4, demo=1)
CORE = ['standing', 'ruku', 'standing_after_ruku', 'sujood_first', 'sitting', 'sujood_second']
STATION_POSES = dict(standing='standing', ruku='ruku', standing_after_ruku='standing',
                     sujood_first='sujood', sitting='sitting', sujood_second='sujood',
                     intermediate_sitting='sitting', final_sitting='sitting',
                     takbir='takbir', salam_right='salam_right', salam_left='salam_left')
LABELS = dict(standing='القيام', ruku='الركوع', standing_after_ruku='الاعتدال بعد الركوع',
              sujood_first='السجود الأول', sitting='الجلوس بين السجدتين',
              sujood_second='السجود الثاني', intermediate_sitting='الجلوس الأوسط',
              final_sitting='الجلوس الأخير', takbir='تكبيرة الإحرام',
              salam_right='السلام يمينًا', salam_left='السلام يسارًا')
DEFAULT_POSE_MAP = {
    **{p: p for p in ['standing', 'ruku', 'sujood', 'sitting', 'unknown',
                      'takbir', 'salam_right', 'salam_left']},
    '1_Qiyam': 'standing', '2_Takbir': 'takbir', '3_Qiyam_Recitation': 'standing',
    '4_Ruku': 'ruku', '5_Sujud': 'sujood', '6_Jalsa': 'sitting',
    '7_Salam_Right': 'salam_right', '8_Salam_Left': 'salam_left',
}


def stations(prayer: str) -> list[list[str]]:
    """Recorded analysis includes opening takbir and terminal right/left salam."""
    count = COUNTS[prayer]
    return [(['takbir'] if i == 0 else []) + CORE
            + (['intermediate_sitting'] if i == 1 and count > 2 else [])
            + (['final_sitting', 'salam_right', 'salam_left'] if i == count - 1 else [])
            for i in range(count)]
