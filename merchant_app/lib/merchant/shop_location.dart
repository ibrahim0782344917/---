import 'package:geolocator/geolocator.dart';

/// Only capture coordinates when a merchant explicitly taps the action while
/// physically at the shop. No continuous or background location tracking.
Future<({double latitude, double longitude})> captureShopLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw StateError('فعّل خدمة الموقع في الهاتف.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw StateError('لم تُمنح صلاحية الموقع. يمكنك كتابة الإحداثيات يدوياً.');
  }
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    ),
  );
  final latitude = position.latitude;
  final longitude = position.longitude;
  if (!isBaghdadShopLocation(latitude, longitude)) {
    throw StateError('الإحداثيات خارج نطاق بغداد. تأكد أنك داخل المحل.');
  }
  return (latitude: latitude, longitude: longitude);
}

/// Broad Baghdad bounds; protects against accidental fake/out-of-region pins.
bool isBaghdadShopLocation(double? latitude, double? longitude) =>
    latitude != null && longitude != null &&
    latitude.isFinite && longitude.isFinite &&
    latitude >= 32.8 && latitude <= 33.9 &&
    longitude >= 43.6 && longitude <= 45.2;

bool validShopPhone(String? phone) {
  final value = phone?.trim() ?? '';
  return value.length >= 8 && value.length <= 30 &&
      RegExp(r'[0-9]').allMatches(value).length >= 7;
}
