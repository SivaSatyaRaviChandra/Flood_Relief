/// Location acquisition service.
///
/// Interfaces over `geolocator` so the UI never sees platform exceptions —
/// instead it receives a sealed [LocationResult].
library;

import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationPermissionState {
  granted,
  denied,
  permanentlyDenied,
  unavailable,
}

sealed class LocationResult {
  const LocationResult();
}

class LocationSuccess extends LocationResult {
  const LocationSuccess({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime timestamp;
}

class LocationUnavailable extends LocationResult {
  const LocationUnavailable({required this.message, required this.retriable});

  final String message;
  final bool retriable;
}

abstract class LocationService {
  Future<LocationPermissionState> checkPermission();

  /// Requests the location permission. Returns the resulting state.
  Future<LocationPermissionState> requestPermission();

  /// Tries to obtain the current position.
  Future<LocationResult> getCurrentLocation({Duration timeout = const Duration(seconds: 20)});

  Future<bool> openAppSettings();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationPermissionState> checkPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      return _mapPermission(permission);
    } catch (_) {
      return LocationPermissionState.unavailable;
    }
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    try {
      final permission =
          await Geolocator.requestPermission().timeout(const Duration(seconds: 45));
      return _mapPermission(permission);
    } on TimeoutException {
      return LocationPermissionState.unavailable;
    } catch (_) {
      return LocationPermissionState.unavailable;
    }
  }

  LocationPermissionState _mapPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return LocationPermissionState.granted;
      case LocationPermission.denied:
        return LocationPermissionState.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionState.permanentlyDenied;
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.unavailable;
    }
  }

  @override
  Future<LocationResult> getCurrentLocation({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      bool serviceEnabled;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      } catch (_) {
        serviceEnabled = true;
      }
      if (!serviceEnabled) {
        return const LocationUnavailable(
          message: 'GPS is disabled. Enable location services to send your SOS '
              'with your position.',
          retriable: true,
        );
      }

      final permission = await checkPermission();
      switch (permission) {
        case LocationPermissionState.granted:
          break;
        case LocationPermissionState.denied:
          final after = await requestPermission();
          if (after != LocationPermissionState.granted) {
            return const LocationUnavailable(
              message: 'Location permission is required to attach your position '
                  'to the SOS.',
              retriable: true,
            );
          }
          break;
        case LocationPermissionState.permanentlyDenied:
          return const LocationUnavailable(
            message: 'Location permission is permanently denied. Enable it in '
                'system settings and try again.',
            retriable: true,
          );
        case LocationPermissionState.unavailable:
          return const LocationUnavailable(
            message: 'Location services are unavailable on this device.',
            retriable: false,
          );
      }

      // Try a cached position first so the user sees a result quickly.
      Position? cached;
      try {
        cached = await Geolocator.getLastKnownPosition();
      } catch (_) {
        cached = null;
      }

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: timeout,
          ),
        );
      } on TimeoutException {
        if (cached != null) {
          position = cached;
        } else {
          return const LocationUnavailable(
            message: 'The location request timed out. Try again.',
            retriable: true,
          );
        }
      } on LocationServiceDisabledException {
        return const LocationUnavailable(
          message: 'GPS is disabled. Enable location services to send your SOS '
              'with your position.',
          retriable: true,
        );
      } catch (_) {
        if (cached != null) {
          position = cached;
        } else {
          return const LocationUnavailable(
            message: 'Could not determine your location. Try again.',
            retriable: true,
          );
        }
      }

      return LocationSuccess(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.hasAccuracy ? position.accuracy : null,
        timestamp: position.timestamp.toUtc(),
      );
    } catch (_) {
      return const LocationUnavailable(
        message: 'Could not determine your location. Try again.',
        retriable: true,
      );
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }
}

/// Deterministic fake used in widget tests.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.permission = LocationPermissionState.granted,
    this.result,
  });

  final LocationPermissionState permission;
  final LocationResult? result;

  @override
  Future<LocationPermissionState> checkPermission() async => permission;

  @override
  Future<LocationPermissionState> requestPermission() async => permission;

  @override
  Future<LocationResult> getCurrentLocation({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    return result ??
        LocationSuccess(
          latitude: 17.7,
          longitude: 83.3,
          accuracy: 12.0,
          timestamp: _fixedTime,
        );
  }

  @override
  Future<bool> openAppSettings() async => true;

  static final DateTime _fixedTime = DateTime.utc(2026, 9, 22, 12, 0, 0);
}