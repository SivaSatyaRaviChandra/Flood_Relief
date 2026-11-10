/// A shelter, camp or other designated safe location.
library;

import '../core/utils/cast.dart';
import 'enums/shelter_status.dart';

class Shelter {
  const Shelter({
    required this.shelterId,
    required this.name,
    required this.capacity,
    required this.occupied,
    required this.contactPhone,
    required this.facilities,
    this.latitude,
    this.longitude,
    this.address,
    this.notes,
    this.open = true,
  });

  final String shelterId;
  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;

  /// Total places. Zero means "capacity unknown".
  final int capacity;

  /// Places already taken.
  final int occupied;

  final String? contactPhone;
  final List<String> facilities;
  final String? notes;

  /// False when the shelter is no longer accepting people.
  final bool open;

  int get availableCapacity =>
      capacity <= 0 ? 0 : (capacity - occupied).clamp(0, capacity);

  /// Derived so the stored [capacity]/[occupied] can never disagree with the
  /// status shown to the user.
  ShelterStatus get status =>
      ShelterStatus.fromCapacity(capacity: capacity, occupied: occupied);

  bool get hasCoordinates => latitude != null && longitude != null;

  Shelter copyWith({
    int? capacity,
    int? occupied,
    String? contactPhone,
    bool clearContact = false,
    List<String>? facilities,
    String? notes,
    bool? open,
  }) {
    return Shelter(
      shelterId: shelterId,
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
      capacity: capacity ?? this.capacity,
      occupied: occupied ?? this.occupied,
      contactPhone: clearContact ? null : (contactPhone ?? this.contactPhone),
      facilities: facilities ?? this.facilities,
      notes: notes ?? this.notes,
      open: open ?? this.open,
    );
  }

  Map<String, dynamic> toMap() => {
        'shelterId': shelterId,
        'name': name,
        if (address != null) 'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'capacity': capacity,
        'occupied': occupied,
        if (contactPhone != null) 'contactPhone': contactPhone,
        'facilities': facilities,
        if (notes != null) 'notes': notes,
        'open': open,
      };

  static Shelter fromMap(dynamic map) {
    final m = map is Map ? Map<String, dynamic>.from(map) : const <String, dynamic>{};
    final rawFacilities = m['facilities'];
    final facilities = <String>[
      if (rawFacilities is List)
        for (final f in rawFacilities) asString(f)
    ];
    return Shelter(
      shelterId: asString(m['shelterId']),
      name: asString(m['name'], fallback: 'Unnamed shelter'),
      address: _emptyToNull(m['address']),
      latitude: asDouble(m['latitude']),
      longitude: asDouble(m['longitude']),
      capacity: asInt(m['capacity']) ?? 0,
      occupied: asInt(m['occupied']) ?? 0,
      contactPhone: _emptyToNull(m['contactPhone']),
      facilities: facilities,
      notes: _emptyToNull(m['notes']),
      open: asBool(m['open'], fallback: true),
    );
  }

  static String? _emptyToNull(dynamic value) {
    final text = asString(value);
    return text.isEmpty ? null : text;
  }
}
