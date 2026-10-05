import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'platform.dart';

class AccountError implements Exception {
  AccountError(this.code, [this.status = 0]);
  final String code;
  final int status;
  @override
  String toString() => switch (code) {
        'EMAIL_VERIFICATION_REQUIRED' =>
          'فعّل بريدك الإلكتروني ثم سجّل الدخول.',
        'PAIRING_INVALID_OR_EXPIRED' =>
          'رمز الربط غير صالح أو انتهى. اطلب رمزًا جديدًا.',
        'DEVICE_DISCONNECTED' => 'تم فصل الجهاز أو انتهت جلسته. أعد الربط.',
        'SIGN_IN_REQUIRED' => 'سجّل الدخول لعرض لوحة المتابعة.',
        'EMAIL_SERVICE_NOT_CONFIGURED' =>
          'خدمة البريد غير مهيأة على الخادم بعد.',
        'EMAIL_SERVICE_UNAVAILABLE' => 'تعذر إرسال البريد؛ حاول مجددًا.',
        'ORIGIN_NOT_ALLOWED' =>
          'عنوان تطبيق الويب غير مسموح في إعدادات الخادم.',
        'TRY_AGAIN_LATER' => 'محاولات كثيرة؛ حاول مجددًا بعد دقائق.',
        'INVALID_LOGIN_CREDENTIALS' => 'تحقق من البريد وكلمة المرور.',
        _ => 'تعذر إتمام الطلب. تحقق من الاتصال والإعدادات ($code).',
      };
}

class AccountClient {
  AccountClient(this.base, {http.Client? client})
      : client = client ?? accountHttpClient();
  final String base;
  final http.Client client;
  String? guardianToken, deviceToken;
  String get platform => kIsWeb ? 'web' : 'android';

  Future<dynamic> call(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      bool child = false}) async {
    final credential = child ? deviceToken : guardianToken;
    final request =
        http.Request(method, Uri.parse('$base/api/v1/accounts$path'))
          ..headers.addAll({
            'Content-Type': 'application/json',
            'X-Iqtadi-Account': '1',
            'X-Iqtadi-Platform': platform,
            if (credential != null) 'Authorization': 'Bearer $credential',
          });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 12)));
    final data = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw AccountError(
          data is Map && data['detail'] is String
              ? data['detail'] as String
              : 'INVALID_REQUEST',
          response.statusCode);
    }
    return data;
  }

  void close() => client.close();
}
