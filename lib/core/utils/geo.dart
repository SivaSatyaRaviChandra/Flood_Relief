/// Geodesic helpers used for "how far is it" questions.
///
/// Deliberately dependency-free (haversine) so the app never needs a map SDK
/// or a network tile service to answer distance questions offline.
library;

import 'dart:math' as math;

const double _earthRadiusMetres = 6371008.8;

/// Great-circle distance between two coordinates, in metres.
double distanceBetween(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  final dLat = _toRadians(latitudeB - latitudeA);
  final dLng = _toRadians(longitudeB - longitudeA);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(latitudeA)) *
          math.cos(_toRadians(latitudeB)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusMetres * c;
}

/// Human readable distance: metres below 1 km, kilometres above.
String formatDistance(double metres) {
  if (metres.isNaN || metres.isInfinite) return '—';
  if (metres < 1000) return '${metres.round()} m';
  final km = metres / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}

/// Whether two coordinates are valid WGS84 degrees.
bool isValidCoordinate(double latitude, double longitude) =>
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180 &&
    !latitude.isNaN &&
    !longitude.isNaN;

double _toRadians(double degrees) => degrees * math.pi / 180.0;
