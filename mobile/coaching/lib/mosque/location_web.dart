import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('navigator.geolocation.getCurrentPosition')
external void _getPosition(
    JSFunction success, JSFunction failure, JSObject options);
@JS('window.open')
external JSAny? _open(JSString url, JSString target, JSString features);

abstract interface class LocationService {
  Future<Map<String, dynamic>> current();
}

class DeviceLocation implements LocationService {
  @override
  Future<Map<String, dynamic>> current() {
    final result = Completer<Map<String, dynamic>>();
    try {
      _getPosition(
          ((JSObject position) {
            if (result.isCompleted) return;
            final coords = position.getProperty<JSObject>('coords'.toJS);
            result.complete({
              'lat': coords.getProperty<JSNumber>('latitude'.toJS).toDartDouble,
              'lng':
                  coords.getProperty<JSNumber>('longitude'.toJS).toDartDouble,
              'accuracy':
                  coords.getProperty<JSNumber>('accuracy'.toJS).toDartDouble,
            });
          }).toJS,
          ((JSObject error) {
            if (!result.isCompleted) {
              result.completeError(
                  Exception('رُفض الإذن أو تعذر GPS؛ يمكنك التحديد اليدوي'));
            }
          }).toJS,
          {'enableHighAccuracy': true, 'timeout': 10000, 'maximumAge': 0}
              .jsify() as JSObject);
    } catch (_) {
      result.completeError(Exception('GPS غير متاح؛ استخدم التحديد اليدوي'));
    }
    return result.future.timeout(const Duration(seconds: 12));
  }
}

Future<void> navigateTo(double lat, double lng) async {
  _open('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'.toJS,
      '_blank'.toJS, 'noopener,noreferrer'.toJS);
}
