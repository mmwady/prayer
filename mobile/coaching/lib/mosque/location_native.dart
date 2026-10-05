import 'package:flutter/services.dart';

abstract interface class LocationService {
  Future<Map<String, dynamic>> current();
}

class DeviceLocation implements LocationService {
  static const channel = MethodChannel('iqtadi/mosque_location');
  @override
  Future<Map<String, dynamic>> current() async {
    final point = await channel.invokeMapMethod<String, dynamic>('current');
    if (point == null) {
      throw Exception('تعذر الموقع؛ استخدم التحديد اليدوي');
    }
    return point;
  }
}

Future<void> navigateTo(double lat, double lng) async {
  await DeviceLocation.channel
      .invokeMethod('navigate', {'lat': lat, 'lng': lng});
}
