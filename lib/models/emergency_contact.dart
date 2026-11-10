/// A contactable person or organisation the user trusts in an emergency.
///
/// The contact list is **user managed**: it starts empty (plus nothing), which
/// is deliberate. Shipping invented government hotline numbers would be unsafe
/// — a wrong number in a flood is worse than no number — so the user adds the
/// contacts for their own district.
library;

import '../core/utils/cast.dart';

/// What kind of contact this is.
enum ContactKind {
  family('FAMILY', 'Family'),
  friend('FRIEND', 'Friend'),
  neighbour('NEIGHBOUR', 'Neighbour'),
  authority('LOCAL_AUTHORITY', 'Local authority'),
  medical('MEDICAL', 'Medical'),
  rescue('RESCUE', 'Rescue team'),
  other('OTHER', 'Other');

  const ContactKind(this.code, this.label);

  final String code;
  final String label;

  static ContactKind? fromCode(String? code) {
    if (code == null) return null;
    for (final k in ContactKind.values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

class EmergencyContact {
  const EmergencyContact({
    required this.contactId,
    required this.name,
    required this.phone,
    required this.kind,
    this.notes,
    this.isPrimary = false,
  });

  final String contactId;
  final String name;
  final String phone;
  final ContactKind kind;
  final String? notes;

  /// The contact dialled first from the emergency contacts screen.
  final bool isPrimary;

  EmergencyContact copyWith({
    String? name,
    String? phone,
    ContactKind? kind,
    String? notes,
    bool clearNotes = false,
    bool? isPrimary,
  }) {
    return EmergencyContact(
      contactId: contactId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      kind: kind ?? this.kind,
      notes: clearNotes ? null : (notes ?? this.notes),
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  Map<String, dynamic> toMap() => {
        'contactId': contactId,
        'name': name,
        'phone': phone,
        'kind': kind.code,
        if (notes != null) 'notes': notes,
        'isPrimary': isPrimary,
      };

  static EmergencyContact fromMap(dynamic map) {
    final m = map is Map ? Map<String, dynamic>.from(map) : const <String, dynamic>{};
    return EmergencyContact(
      contactId: asString(m['contactId']),
      name: asString(m['name'], fallback: 'Contact'),
      phone: asString(m['phone']),
      kind: ContactKind.fromCode(asString(m['kind'])) ?? ContactKind.other,
      notes: asString(m['notes'], fallback: '') == ''
          ? null
          : asString(m['notes']),
      isPrimary: asBool(m['isPrimary']),
    );
  }
}
