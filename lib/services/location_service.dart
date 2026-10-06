import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Tries to get the current GPS coordinates.
  /// Returns a record with (latitude, longitude) or null if permission was denied or disabled.
  static Future<({double latitude, double longitude})?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return (latitude: position.latitude, longitude: position.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Builds a Google Maps search/pin URL from coordinates
  static String buildMapsUrl(double latitude, double longitude) {
    return 'https://maps.google.com/?q=$latitude,$longitude';
  }
}
