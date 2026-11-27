import 'package:geolocator/geolocator.dart';

class LocationFixResult {
  final double? latitude;
  final double? longitude;
  final String? errorMessage;

  const LocationFixResult({
    this.latitude,
    this.longitude,
    this.errorMessage,
  });

  bool get hasLocation => latitude != null && longitude != null;
}

class LocationService {
  /// Returns current GPS coordinates along with a user-friendly error message on failure.
  static Future<LocationFixResult> getCurrentLocationWithStatus() async {
    try {
      bool serviceEnabled = true;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      } catch (_) {
        // Some web browsers throw or don't support isLocationServiceEnabled; continue to permission check.
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return const LocationFixResult(
            errorMessage: 'Location permission denied. Please allow location access.',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationFixResult(
          errorMessage: 'Location permission permanently denied. Enable it in browser/device settings.',
        );
      }

      if (!serviceEnabled) {
        return const LocationFixResult(
          errorMessage: 'Device GPS / Location service is turned off. Please turn on GPS.',
        );
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        // Fallback to balanced/medium accuracy when indoors or under weak sky view
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          );
        } catch (_) {
          try {
            position = await Geolocator.getLastKnownPosition();
          } catch (_) {}
        }
      }

      if (position == null) {
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      if (position != null) {
        return LocationFixResult(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }
      return const LocationFixResult(
        errorMessage: 'Could not lock GPS signal right now. Try again outdoors or paste a Google Maps link.',
      );
    } catch (e) {
      return LocationFixResult(
        errorMessage: 'Location error: $e',
      );
    }
  }

  /// Tries to get the current GPS coordinates.
  /// Returns a record with (latitude, longitude) or null if permission was denied or disabled.
  static Future<({double latitude, double longitude})?> getCurrentLocation() async {
    final res = await getCurrentLocationWithStatus();
    if (res.hasLocation) {
      return (latitude: res.latitude!, longitude: res.longitude!);
    }
    return null;
  }

  /// Builds a Google Maps search/pin URL from coordinates
  static String buildMapsUrl(double latitude, double longitude) {
    return 'https://maps.google.com/?q=$latitude,$longitude';
  }
}
