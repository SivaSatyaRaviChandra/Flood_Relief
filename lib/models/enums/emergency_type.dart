/// Emergency types selectable when composing an SOS.
library;

enum EmergencyType {
  rescueRequired('RESCUE_REQUIRED', 'Rescue Required'),
  evacuationRequired('EVACUATION_REQUIRED', 'Evacuation Required'),
  medicalAssistance('MEDICAL_ASSISTANCE', 'Medical Assistance'),
  foodRequired('FOOD_REQUIRED', 'Food Required'),
  drinkingWaterRequired('DRINKING_WATER_REQUIRED', 'Drinking Water Required'),
  shelterRequired('SHELTER_REQUIRED', 'Shelter Required'),
  missingPerson('MISSING_PERSON', 'Missing Person'),
  other('OTHER', 'Other');

  const EmergencyType(this.code, this.label);

  final String code;
  final String label;

  static EmergencyType? fromCode(String? code) {
    if (code == null) return null;
    for (final type in EmergencyType.values) {
      if (type.code == code) return type;
    }
    return null;
  }
}