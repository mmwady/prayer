// UI copy for the integrated account, family and mosque workflows.
const integratedEnglishStrings = <String, String>{
  'الأسماء الحقيقية لا تظهر للمجموعة.':
      'Real names are not shown to the group.',
  'الأسماء الحقيقية وبيانات الاتصال والوسائط لا تظهر للمجموعة.':
      'Real names, contact information and media are not shown to the group.',
  'عضو الأسرة': 'Family member',
  'مفتاح خدمة البريد غير صالح. يحتاج مسؤول المنصة إلى تحديث إعداد Resend.':
      'The email service key is invalid. The platform administrator must update the Resend configuration.',
  'عنوان المرسل غير موثّق لدى Resend. يجب توثيق نطاق البريد أولًا.':
      'The sender address is not verified with Resend. Verify the email domain first.',
  'Resend في وضع الاختبار ويسمح بالإرسال إلى بريد مالك الحساب فقط. وثّق نطاقًا في Resend ثم استخدم بريدًا من ذلك النطاق.':
      'Resend is in test mode and only allows delivery to the account owner\'s email. Verify a domain in Resend, then use an address on that domain.',
  'رفضت خدمة Resend المستلم أو المرسل. عنوان الاختبار يسمح عادة ببريد مالك حساب Resend فقط.':
      'Resend rejected the recipient or sender. Test delivery usually only allows the Resend account owner\'s email.',
  'وصلت خدمة البريد إلى حد الإرسال المؤقت؛ حاول بعد قليل.':
      'The email service has reached its temporary sending limit; try again shortly.',
  'هذه مجموعة أطفال؛ استخدم خيار «ضم طفل بموافقتي».':
      'This is a children\'s group; use “Join a child with my consent”.',
  'هذه المجموعة لا تناسب فئة عمر الطفل. اختر مجموعة الأطفال المطابقة لعمره.':
      'This group does not match the child\'s age. Choose the appropriate children\'s group.',
  'هذا البريد مسجل ومفعّل بالفعل. استخدم «لدي حساب بالفعل» لتسجيل الدخول.':
      'This email is already registered and verified. Use “I already have an account” to sign in.',
  'فصل ولي الأمر هذا الجهاز.': 'The guardian disconnected this device.',
  'لم يُرسل بريد في وضع التطوير؛ حُفظ رابط التفعيل في صندوق البريد المحلي على الكمبيوتر.':
      'No email was sent in development mode; the activation link was saved in the local outbox on the computer.',
  'تم حفظ الحساب؛ طلب إرسال رابط التفعيل معلّق وسيُعاد تلقائيًا. {0}':
      'Your account was saved; activation email delivery is queued and will retry automatically. {0}',
  'تم قبول طلب إرسال رابط التفعيل. تحقق من بريدك والبريد غير المرغوب؛ بعد التفعيل سجّل الدخول.':
      'The activation email request was accepted. Check your inbox and spam folder, then sign in after activation.',
  'إذا كان البريد مسجلًا ولم يُفعّل، سيحاول الخادم إرسال رابط التفعيل. تحقق من بريدك والبريد غير المرغوب.':
      'If this email is registered but unverified, the server will try to send an activation link. Check your inbox and spam folder.',
  'وضع محلي: حُفظ رابط الاستعادة في مجلد البريد التجريبي على الكمبيوتر؛ لم يُرسل بريد.':
      'Local mode: the recovery link was saved in the development outbox on the computer; no email was sent.',
  'إذا كان البريد مسجلًا، سيحاول الخادم إرسال رابط استعادة كلمة المرور. تحقق من بريدك والبريد غير المرغوب.':
      'If this email is registered, the server will try to send a password recovery link. Check your inbox and spam folder.',
  'تعذر تحميل بيانات الأسرة. حاول مجددًا.':
      'Could not load family information. Try again.',
  'إنشاء أسرة': 'Create a family',
  'اسم الأسرة': 'Family name',
  'إنشاء': 'Create',
  'إضافة طفل إلى الأسرة': 'Add a child to the family',
  'الاسم الحقيقي': 'Real name',
  'الاسم المستعار للمجموعات — اختياري': 'Group nickname — optional',
  'الفئة العمرية': 'Age group',
  '5–9 سنوات': 'Ages 5–9',
  '10–13 سنة': 'Ages 10–13',
  '14–17 سنة': 'Ages 14–17',
  'إضافة': 'Add',
  'دعوة فرد إلى الأسرة': 'Invite a family member',
  'مستوى الصلاحية': 'Permission level',
  'ولي أمر — إدارة الأطفال والموافقات':
      'Guardian — manage children and consent',
  'بالغ — تقدمه الشخصي فقط': 'Adult — personal progress only',
  'داعم — متابعة محدودة': 'Supporter — limited monitoring',
  'إنشاء الدعوة': 'Create invitation',
  'دعوة الأسرة': 'Family invitation',
  'صلاحيات {0}': 'Permissions for {0}',
  'الدور داخل هذه الأسرة فقط': 'Role within this family only',
  'بالغ — ملفه الشخصي فقط': 'Adult — own profile only',
  'داعم — مشاهدة محدودة': 'Supporter — limited viewing',
  'إزالة من الأسرة': 'Remove from family',
  'حفظ الصلاحية': 'Save permission',
  'افتح كاميرا هاتف الطفل وامسح الرمز. سيتم الربط مباشرة دون بريد أو كلمة مرور، ويبقى الجهاز مرتبطًا حتى تفصله من هنا. ينتهي الرمز خلال 5 دقائق ويُستخدم مرة واحدة.':
      'Open the child\'s phone camera and scan the code. Pairing needs no email or password, and the device stays paired until you disconnect it here. The code expires in 5 minutes and can be used once.',
  'تم': 'Done',
  'لا يوجد جهاز مرتبط الآن. إذا مسح الطفل QR للتو، انتظر لحظة ثم افتح إدارة الأجهزة مجددًا.':
      'No device is paired yet. If the child just scanned the QR code, wait a moment and reopen device management.',
  'الجهاز المرتبط {0}': 'Paired device {0}',
  'هاتف أو متصفح ويب': 'Phone or web browser',
  'تطبيق الهاتف': 'Mobile app',
  'فصل': 'Disconnect',
  'فصل جهاز الطفل؟': 'Disconnect the child\'s device?',
  'سيتوقف جهاز {0} عن المزامنة، ويمكن ربطه لاحقًا برمز جديد.':
      '{0}\'s device will stop syncing and can be paired again using a new code.',
  'فصل الجهاز': 'Disconnect device',
  'مالك الأسرة': 'Family owner',
  'بالغ': 'Adult',
  'داعم': 'Supporter',
  'إدارة الأسرة': 'Family management',
  'الأسرة مساحة خاصة. الأسماء الحقيقية تظهر لأولياء الأمر فقط، وصلاحية ولي الأمر لا تُمنح لمعلم المسجد تلقائيًا.':
      'A family is a private space. Real names appear only to guardians; mosque teachers do not automatically receive guardian permissions.',
  'العائلات': 'Families',
  'أسرة جديدة': 'New family',
  'ابدأ مساحة أسرتك': 'Start your family space',
  'أنشئ أسرة ثم أضف الأطفال أو ادعُ ولي أمر آخر.':
      'Create a family, then add children or invite another guardian.',
  'الأسرة الحالية': 'Current family',
  'الأسرة': 'Family',
  'مستواك: {0}': 'Your role: {0}',
  'دعوة فرد': 'Invite a member',
  'الأطفال والملفات التابعة': 'Children and dependent profiles',
  'يربط ولي الأمر كل طفل بجهاز التدريب عند الحاجة.':
      'Guardians can pair each child with a training device when needed.',
  'إضافة طفل': 'Add a child',
  'تشجيع الأسرة': 'Family encouragement',
  'هذه النقاط من ملخصات التدريب بالكاميرا، وليست حضور المسجد.':
      'These points come from camera training summaries and are separate from mosque attendance.',
  'لا توجد ملفات أطفال في هذه الأسرة بعد.':
      'This family has no child profiles yet.',
  'بلا اسم مستعار': 'No nickname',
  'غير مرتبط بجهاز': 'No paired device',
  'مرتبط • {0}': 'Paired • {0}',
  'ربط هاتف الطفل': 'Pair the child\'s phone',
  'إدارة/فصل الأجهزة{0}': 'Manage / disconnect devices{0}',
  'ستظهر النتائج بعد أول تدريب صالح.':
      'Results will appear after the first qualifying training session.',
  '{0} صلوات مكتملة': '{0} complete prayers',
  'العمر غير محدد': 'Age not specified',
  'طلب صلاحية قائد مسجد': 'Request mosque leader permission',
  'اسم المسجد': 'Mosque name',
  'المدينة': 'City',
  'المهمة': 'Role',
  'شيخ أو معلم مجموعة': 'Group imam or teacher',
  'مسؤول إدارة المسجد': 'Mosque administrator',
  'معلومات تساعد على التحقق': 'Information to support verification',
  'إرسال الطلب': 'Submit request',
  'صلاحيات المسجد': 'Mosque permissions',
  'صلاحياتي المعتمدة': 'My approved permissions',
  'لا توجد لك صلاحية قائد مسجد حاليًا.':
      'You currently have no mosque leader permission.',
  'مسؤول المسجد': 'Mosque administrator',
  'قائد': 'Leader',
  'طلباتي': 'My requests',
  'بانتظار التحقق': 'Awaiting verification',
  'طلب إدارة مسجد': 'Request mosque administration',
  'إدارة طلبات القادة': 'Manage leader requests',
  'لا توجد طلبات معلقة.': 'No pending requests.',
  'اعتماد': 'Approve',
  'تعذر تحميل مجموعات المسجد. حاول مجددًا.':
      'Could not load mosque groups. Try again.',
  'مغادرة المجموعة؟': 'Leave this group?',
  'سيغادر {0} هذه المجموعة، ويمكن الانضمام لاحقًا بدعوة جديدة.':
      '{0} will leave this group and can join again with a new invitation.',
  'مغادرة': 'Leave',
  'رسالة إلى المجموعة': 'Message to the group',
  'رد على {0}': 'Reply to {0}',
  'مثال: أنا في الطريق إلى المسجد، من سينضم إليّ؟':
      'Example: I\'m on my way to the mosque. Who will join me?',
  'إرسال': 'Send',
  'إنشاء مجموعة مسجد': 'Create a mosque group',
  'المسجد': 'Mosque',
  'اسم المجموعة': 'Group name',
  'الفئة': 'Category',
  'بالغون': 'Adults',
  'دعوة الانضمام إلى المجموعة': 'Group invitation',
  'يمسح الشخص الرمز للانضمام بنفسه، أو يمسحه ولي الأمر من خيار ضم طفل. طلب الطفل يحتاج قبول قائد المسجد.':
      'Scan the code to join personally, or have a guardian scan it to join a child. A child\'s request needs approval from the mosque leader.',
  'فتح حضور الصلاة': 'Open prayer attendance',
  'فتح لمدة 30 دقيقة': 'Open for 30 minutes',
  'رمز حضور {0}': '{0} attendance code',
  'هذا الرمز للحضور فقط، ولا يضيف أي نقاط إلى تقييم التدريب بالكاميرا.':
      'This code records attendance only and adds no points to camera training assessment.',
  'مجموعات المسجد': 'Mosque groups',
  'وضعي الشخصي': 'Personal mode',
  'وضع قائد المسجد': 'Mosque leader mode',
  'الانضمام للأطفال يتم بموافقة ولي الأمر. تعرض المجموعة أسماء مستعارة فقط، ويظل الحضور منفصلًا عن تقييم التدريب.':
      'Children join with guardian consent. Groups show nicknames only; attendance remains separate from training assessment.',
  'لوحة قائد المسجد': 'Mosque leader dashboard',
  'يمكنك إنشاء المجموعات، إصدار QR لأولياء الأمور، وفتح حضور الصلاة. صلاحية القائد منفصلة عن وصاية الأسرة.':
      'Create groups, issue QR codes for guardians and open prayer attendance. Leader permissions are separate from family guardianship.',
  'المجموعات التي أديرها': 'Groups I manage',
  'عضوياتي في المسجد': 'My mosque memberships',
  'انضم بنفسي': 'Join personally',
  'ضم طفل بموافقتي': 'Join a child with my consent',
  'لا توجد مجموعات بعد': 'No groups yet',
  'استخدم دعوة المسجد للانضمام، أو أنشئ مجموعة إن كنت قائدًا معتمدًا.':
      'Use a mosque invitation to join, or create a group if you are an approved leader.',
  'المجموعة الحالية': 'Current group',
  'لوحة الحضور': 'Attendance dashboard',
  'حضور المسجد — مستقل عن نقاط التدريب بالكاميرا.':
      'Mosque attendance — separate from camera training points.',
  'لوحة التدريب': 'Training dashboard',
  'ملخصات التدريب بالكاميرا فقط — لا صور ولا فيديو.':
      'Camera training summaries only — no images or video.',
  'منافسة مجموعات المسجد': 'Mosque group competition',
  'إجماليات المجموعات فقط؛ لا تظهر أسماء الأطفال.':
      'Group totals only; children\'s names are not shown.',
  '{0} • بانتظار قبول قائد المسجد': '{0} • Awaiting mosque leader approval',
  '{0} • عضوية نشطة': '{0} • Active membership',
  'مجلس المجموعة': 'Group conversation',
  'رسائل تشجيعية قصيرة لأعضاء مجموعة البالغين فقط.':
      'Short encouragement messages for adult group members only.',
  'تحديث الرسائل': 'Refresh messages',
  'إرسال رسالة للمجموعة': 'Send a group message',
  'لا توجد رسائل بعد. ابدأ برسالة تشجيع للذهاب إلى المسجد.':
      'No messages yet. Start with encouragement to visit the mosque.',
  'رد': 'Reply',
  'طلبات انضمام الأطفال': 'Children\'s join requests',
  'وافق على الطلب بعد تحقق المسجد من ولي الأمر.':
      'Approve the request after the mosque verifies the guardian.',
  'طلب موثق بموافقة ولي الأمر • بانتظار القرار':
      'Verified guardian consent • Awaiting decision',
  'رفض الطلب': 'Reject request',
  'قبول الطفل': 'Accept child',
  'عرض QR للانضمام': 'Show joining QR',
  'فتح حضور صلاة': 'Open prayer attendance',
  'لا توجد بيانات حضور مشاركة بعد.': 'No shared attendance information yet.',
  '{0} من {1} • {2}%': '{0} of {1} • {2}%',
  'تسجيل حاضر': 'Mark present',
  'لا توجد نتائج تدريب مشاركة بعد.': 'No shared training results yet.',
  'لا توجد إجماليات للمسجد بعد.': 'No mosque totals yet.',
  '{0} أعضاء': '{0} members',
  '{0}% حضور': '{0}% attendance',
  'ملفي الشخصي': 'My profile',
  'طفل في {0}': 'Child in {0}',
  'تعذر تحميل ملفات الأسرة.': 'Could not load family profiles.',
  'أُرسل طلب الطفل إلى قائد المسجد للموافقة.':
      'The child\'s request was sent to the mosque leader for approval.',
  'تم انضمامك إلى المجموعة.': 'You joined the group.',
  'تعذر إكمال الانضمام. حاول مجددًا.': 'Could not complete joining. Try again.',
  'ضم طفل إلى مجموعة مسجد': 'Join a child to a mosque group',
  'الانضمام بنفسي إلى مجموعة مسجد': 'Join a mosque group personally',
  'موافقة ولي الأمر ثم قبول المسجد': 'Guardian consent, then mosque approval',
  'عضوية شخصية مستقلة': 'Independent personal membership',
  'اختر طفلك ووافق على البيانات المختصرة. قائد المسجد يقبل الطلب، لكنه لا يصبح ولي أمر.':
      'Choose your child and approve the summary sharing. The mosque leader approves the request but does not become a guardian.',
  'هذا الانضمام يخصك أنت، سواء كنت مسلمًا جديدًا أو كبير سن أو عضوًا عاديًا، ولا يرتبط بالأطفال.':
      'This membership is yours, whether you are a new Muslim, older adult or regular member. It is separate from children\'s memberships.',
  'رمز دعوة المجموعة': 'Group invitation code',
  'مسح QR دعوة المسجد': 'Scan mosque invitation QR',
  'من سينضم؟': 'Who will join?',
  'لا يوجد طفل مسجل': 'No registered child',
  'أضف الطفل أولًا من إدارة الأسرة، ثم ارجع لمسح دعوة المجموعة.':
      'Add the child in family management first, then return to scan the group invitation.',
  'الاسم المستعار الظاهر للمجموعة': 'Nickname shown to the group',
  'الموافقة': 'Consent',
  'مشاركة ملخص التدريب': 'Share training summary',
  'النقاط والصلوات المكتملة فقط؛ لا صور أو فيديو.':
      'Points and complete prayers only; no images or video.',
  'مشاركة حضور المسجد': 'Share mosque attendance',
  'سجل مستقل لا يغير تقييم التدريب.':
      'A separate record that does not change training assessment.',
  'الظهور في لوحة التشجيع': 'Appear on the encouragement board',
  'بالاسم المستعار فقط.': 'Nickname only.',
  'لن نشارك الاسم الحقيقي أو البريد أو الموقع أو أي وسائط من الكاميرا.':
      'We will not share real names, emails, locations or any camera media.',
  'أوافق وأرسل طلب الطفل': 'I consent — submit the child\'s request',
  'أوافق وأنضم بنفسي': 'I consent — join personally',
  'مسح دعوة مجموعة المسجد': 'Scan mosque group invitation',
  'امسح QR الذي يعرضه قائد المسجد، ثم اختر الطفل وراجع الموافقة.':
      'Scan the mosque leader\'s QR code, then choose the child and review consent.',
  'تعذر فتح الكاميرا. أدخل رمز الدعوة يدويًا.':
      'Could not open the camera. Enter the invitation code manually.',
  'درجة الحركات غير متاحة للنتائج القديمة':
      'Movement score is unavailable for older results',
  '{0}٪ • {1}/{2} حركة': '{0}% • {1}/{2} movements',
  'اكتمال الحركات المرصودة': 'Observed movement coverage',
  'الأسبوع: {0}': 'This week: {0}',
  'اليوم': 'Today',
  'نسبة رصد الحركات مستقلة عن النقاط، ولا تعني صحة الصلاة أو قبولها.':
      'Movement coverage is separate from points and does not judge prayer validity or acceptance.',
  'جهاز {0}': '{0}\'s device',
  'الحساب — اختياري': 'Account — optional',
  'تقدمي • أسرتي • مجموعات المسجد': 'My progress • My family • Mosque groups',
  'التدريب المحلي مرتبط بهذا الملف': 'Local training is linked to this profile',
  'تسجيل موحّد للجميع دون اختيار دور دائم':
      'One sign-in for everyone, with no permanent role selection',
  'الحساب': 'Account',
  'التدريب وتحليل الصلاة يعملان محليًا دون حساب. عند تسجيل الدخول لا تُرسل صور أو فيديو أو بيانات حركة؛ تُزامن ملخصات النتيجة فقط.':
      'Prayer training and analysis work locally without an account. Sign-in syncs result summaries only; no images, video or movement data are sent.',
  'كلمة المرور (8 أحرف على الأقل)': 'Password (at least 8 characters)',
  '8 أحرف على الأقل': 'At least 8 characters',
  'مسار التعلّم — اختياري': 'Learning path — optional',
  'تعلّم عام': 'General learning',
  'مسلم جديد': 'New Muslim',
  'طريقة العرض — اختيارية': 'Display preference — optional',
  'العرض القياسي': 'Standard display',
  'واجهة مبسطة': 'Simplified interface',
  'نص أكبر': 'Larger text',
  'إنشاء الحساب': 'Create account',
  'لدي رمز دعوة أو ربط جهاز': 'I have an invitation or device pairing code',
  'جهاز المتعلم': 'Learner\'s device',
  'تم ربط الجهاز بـ {0}': 'Device paired with {0}',
  'يمكن بدء التدريب بالكاميرا الآن. يستطيع الطفل تسجيل الخروج من الجهاز، وتسجيل الدخول مرة أخرى يتم فقط بربط جديد من ولي الأمر.':
      'Camera training can start now. A child can sign out of the device, but signing in again requires a new guardian pairing.',
  'نتيجتي': 'My result',
  'مراكزي في مجموعات المسجد': 'My positions in mosque groups',
  'العودة إلى التدريب': 'Return to training',
  'تسجيل خروج الطفل من هذا الجهاز': 'Sign the child out of this device',
  'بعد الخروج لا يستطيع الطفل الدخول بكلمة مرور؛ يعيد ولي الأمر ربط الجهاز من إدارة الأسرة.':
      'After sign-out the child cannot use a password to sign in; the guardian must pair the device again in family management.',
  'جارٍ تحميل النتيجة': 'Loading result',
  'تحديث النتيجة': 'Refresh result',
  '{0} نقطة هذا الأسبوع': '{0} points this week',
  '{0} صلاة مكتملة • {1} أيام متتالية':
      '{0} complete prayers • {1} consecutive days',
  'اليوم: {0} من 5 صلوات مكتملة': 'Today: {0} of 5 prayers complete',
  'لست عضوًا في مجموعة مسجد بعد.': 'You have not joined a mosque group yet.',
  'الاسم: {0} • {1} نقطة': 'Name: {0} • {1} points',
  'ولي الأمر عطّل الظهور في لوحة الترتيب.':
      'The guardian disabled appearance on the leaderboard.',
  'السلام عليكم، {0}': 'Assalamu alaykum, {0}',
  'دعوة مسجد بانتظار الإكمال': 'Mosque invitation awaiting completion',
  'اختر ملفك أو طفلك ثم وافق على المشاركة.':
      'Choose your profile or child, then consent to sharing.',
  'إكمال': 'Continue',
  'تقدمي الشخصي': 'My personal progress',
  'نتائج التدريب بالكاميرا مرتبطة بحسابك':
      'Camera training results are linked to your account',
  'اختر ملفك الشخصي لمزامنة ملخصات التدريب':
      'Choose your personal profile to sync training summaries',
  'أسرتي': 'My family',
  'أفراد الأسرة • الأطفال • الأجهزة • الموافقات':
      'Family members • Children • Devices • Consent',
  'الانضمام بموافقة ولي الأمر • الحضور • التشجيع':
      'Joining with guardian consent • Attendance • Encouragement',
  'صلاحيات وإدارة المسجد': 'Mosque permissions and management',
  'طلب صلاحية قائد • متابعة التحقق • إدارة الطلبات للمسؤول العام':
      'Request leader permission • Track verification • Platform administrator requests',
  'مسح QR والانضمام بنفسي': 'Scan QR and join personally',
  'مسح QR وضم طفل بموافقتي': 'Scan QR and join a child with my consent',
  'استخدام رمز دعوة أو حضور أو جهاز':
      'Use an invitation, attendance or device code',
  'ملف التدريب: {0}': 'Training profile: {0}',
  '{0} نتيجة تنتظر المزامنة': '{0} results waiting to sync',
  'مزامنة': 'Sync',
  'سجّل الدخول أو أنشئ حسابًا لإكمال الدعوة.':
      'Sign in or create an account to complete the invitation.',
  'استخدام رمز': 'Use a code',
  'نوع الرمز': 'Code type',
  'ربط جهاز طفل': 'Pair a child\'s device',
  'دعوة مجموعة مسجد': 'Mosque group invitation',
  'دعوة أسرة': 'Family invitation',
  'تسجيل حضور في المسجد': 'Record mosque attendance',
  'الرمز': 'Code',
  'متابعة': 'Continue',
  'مسح الرمز': 'Scan code',
  'اسمح بالكاميرا لمسح QR فقط. يمكنك دائمًا إدخال الرمز يدويًا.':
      'Allow the camera to scan the QR code only. You can always enter the code manually.',
  'تعذر فتح الكاميرا. أدخل الرمز يدويًا.':
      'Could not open the camera. Enter the code manually.',
  'جاهز للتدريب دون اتصال': 'Ready to train offline',
  'جارٍ تجهيز التدريب دون إنترنت': 'Preparing offline training',
  'حُفظ {0} من {1} ملفًا': 'Saved {0} of {1} files',
  'تحليل الصور والكاميرا على جهازك': 'Image and camera analysis on your device',
  'ثلاثة نماذج محلية • الصور لا تُرسل إلى خادم':
      'Three local models • Images are never sent to a server',
  'المراجع المحلية': 'Local references',
  'إدارة ملفات المعايرة المراجعة على هذا الجهاز':
      'Manage reviewed calibration files on this device',
};
