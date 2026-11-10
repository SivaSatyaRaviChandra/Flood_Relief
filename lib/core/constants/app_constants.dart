/// Application-wide constants: box names, storage keys, BLE identifiers and
/// protocol limits.
library;

/// Hive box names. Kept in one place so repositories and wiring agree.
class Boxes {
  Boxes._();

  static const String device = 'device';
  static const String user = 'user';
  static const String sos = 'sos';
  static const String packets = 'packets';
  static const String outbox = 'outbox';
  static const String dupCache = 'dupCache';
  static const String teams = 'teams';
  static const String settings = 'settings';

  // Field-reporting boxes.
  static const String floodReports = 'floodReports';
  static const String helpRequests = 'helpRequests';
  static const String shelters = 'shelters';
  static const String contacts = 'contacts';
  static const String alerts = 'alerts';
}

/// Keys used inside the settings box.
class SettingsKeys {
  SettingsKeys._();

  static const String demoMode = 'demoMode';
  static const String speechProvider = 'speechProvider';
  static const String onboardingComplete = 'onboardingComplete';
  static const String role = 'role';

  /// Start the peer-to-peer link automatically right after an SOS is saved.
  /// When false the user presses "Search for relay / rescue now" instead.
  static const String autoStartLinkAfterSos = 'autoStartLinkAfterSos';

  /// Show the newest alerts as a banner on the dashboard.
  static const String showAlertBanner = 'showAlertBanner';

  /// Last successfully captured position, kept so the dashboard can show a
  /// position even before a fresh GPS fix arrives.
  static const String lastLatitude = 'lastLatitude';
  static const String lastLongitude = 'lastLongitude';
  static const String lastAccuracy = 'lastAccuracy';
}

/// Keys used for the persisted device identity.
class DeviceKeys {
  DeviceKeys._();

  static const String deviceId = 'deviceId';
  static const String createdAt = 'createdAt';
}

/// BLE protocol constants.
class BleConstants {
  BleConstants._();

  /// 128-bit service UUID identifying a FloodRelief peer-to-peer node.
  static const String serviceUuid = 'c6b1f0fe-4f4a-4f3a-b1a2-0f1e2d3c4b5a';

  /// Characteristic used to exchange raw SOS/ACK packets.
  static const String characteristicUuid =
      'c6b1f0fe-4f4a-4f3a-b1a2-0f1e2d3c4b5b';

  /// Stable prefix used when advertising as a peripheral.
  static const String deviceNamePrefix = 'FloodReliefNode-';

  /// Maximum number of hops a packet may travel.
  static const int maxHops = 8;

  /// Default TTL assigned to outgoing packets.
  static const int defaultTtl = 8;

  /// Packets older than this are treated as stale/replayed.
  static const Duration replayWindow = Duration(hours: 6);

  /// A packet whose timestamp is more than this far in the future is rejected.
  static const Duration futureSkew = Duration(minutes: 5);

  /// Bounded duplicate cache limits.
  static const int dupCacheCapacity = 1000;
  static const Duration dupCacheRetention = Duration(days: 1);

  /// Transmission queue retry behaviour.
  static const int maxTransmissionAttempts = 5;
  static const Duration retryDelay = Duration(seconds: 15);
}

/// General limits.
class Limits {
  Limits._();

  static const int maxDescriptionLength = 600;

  /// Field reports and help requests use a shorter free-text budget so a
  /// single packet-sized record stays readable in the list screens.
  static const int maxFieldNoteLength = 280;

  static const int minTotalPeople = 1;

  /// Maximum number of people a single report may reference.
  static const int maxPeopleCount = 5000;

  /// Shelters may list at most this many facilities.
  static const int maxShelterFacilities = 12;

  /// Retention bounds so local storage cannot grow without limit.
  static const int maxStoredAlerts = 250;
  static const int maxStoredReports = 400;
  static const int maxStoredHelpRequests = 300;

  /// How far back a flood report is still considered "current".
  static const Duration floodReportFreshness = Duration(hours: 24);

  /// Default radius used by the "nearby" filters.
  static const double nearbyRadiusMetres = 5000;

  /// A report/request is never treated as fresh beyond this age.
  static const Duration maxRecordAge = Duration(days: 30);

  /// Cap on the in-memory framework error log surfaced in Settings.
  static const int maxErrorLogEntries = 40;
}
