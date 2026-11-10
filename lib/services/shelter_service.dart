/// Shelter application service.
///
/// Shelters are designated safe locations with a capacity and an occupancy.
/// The occupancy *is* the source of truth: [Shelter.status] is derived from
/// it, so a stored record can never disagree with what the user is shown.
library;

import '../core/constants/app_constants.dart';
import '../core/errors/app_error.dart';
import '../core/utils/geo.dart';
import '../core/utils/id_generator.dart';
import '../models/shelter.dart';
import '../repositories/shelter_repository.dart';

class ShelterService {
  ShelterService({required this.repository, required this.idGenerator});

  final ShelterRepository repository;
  final IdGenerator idGenerator;

  List<String> validateDraft({
    required String name,
    required int capacity,
    required int occupied,
    required double? latitude,
    required double? longitude,
    required List<String> facilities,
    String? contactPhone,
  }) {
    final errors = <String>[];
    if (name.trim().isEmpty) errors.add('Enter a name for this location.');
    if (capacity < 0) errors.add('Capacity cannot be negative.');
    if (occupied < 0) errors.add('Occupancy cannot be negative.');
    if (capacity > 0 && occupied > capacity) {
      errors.add('Occupancy cannot be larger than capacity.');
    }
    if (facilities.length > Limits.maxShelterFacilities) {
      errors.add(
        'List at most ${Limits.maxShelterFacilities} facilities.',
      );
    }
    final hasLat = latitude != null;
    final hasLng = longitude != null;
    if (hasLat != hasLng) {
      errors.add('Provide both latitude and longitude, or neither.');
    }
    if (hasLat &&
        hasLng &&
        !isValidCoordinate(latitude, longitude)) {
      errors.add('The shelter location is out of range.');
    }
    if (contactPhone != null && contactPhone.trim().isEmpty) {
      errors.add('Contact number cannot be blank.');
    }
    return errors;
  }

  /// Creates or updates a shelter. When [shelterId] is null a new id is
  /// minted.
  Future<Shelter> saveShelter({
    String? shelterId,
    required String name,
    required int capacity,
    required int occupied,
    String? address,
    double? latitude,
    double? longitude,
    String? contactPhone,
    List<String> facilities = const [],
    String? notes,
    bool open = true,
  }) async {
    final errors = validateDraft(
      name: name,
      capacity: capacity,
      occupied: occupied,
      latitude: latitude,
      longitude: longitude,
      facilities: facilities,
      contactPhone: contactPhone,
    );
    if (errors.isNotEmpty) throw InvalidFormError(errors);

    final shelter = Shelter(
      shelterId: shelterId ?? idGenerator.shelterId(),
      name: name.trim(),
      address: (address == null || address.trim().isEmpty)
          ? null
          : address.trim(),
      latitude: latitude,
      longitude: longitude,
      capacity: capacity,
      occupied: occupied,
      contactPhone:
          (contactPhone == null || contactPhone.trim().isEmpty)
              ? null
              : contactPhone.trim(),
      facilities: facilities.where((f) => f.trim().isNotEmpty).toList(),
      notes: (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      open: open,
    );
    await repository.save(shelter);
    return shelter;
  }

  Future<Shelter> require(String shelterId) async {
    final existing = await repository.getById(shelterId);
    if (existing == null) {
      throw const AppError(
        AppErrorKind.notFound,
        'That shelter is no longer stored on this device.',
      );
    }
    return existing;
  }

  /// Records [count] people arriving. Occupancy is clamped to capacity so the
  /// derived status stays truthful ("Full") instead of going negative.
  Future<Shelter> recordArrival(String shelterId, int count) async {
    final existing = await require(shelterId);
    if (count <= 0) return existing;
    final capacity = existing.capacity;
    final occupied = capacity <= 0
        ? existing.occupied + count
        : (existing.occupied + count).clamp(0, capacity);
    final updated = existing.copyWith(occupied: occupied);
    await repository.save(updated);
    return updated;
  }

  /// Records [count] people leaving.
  Future<Shelter> recordDeparture(String shelterId, int count) async {
    final existing = await require(shelterId);
    if (count <= 0) return existing;
    final occupied = (existing.occupied - count).clamp(0, existing.occupied);
    final updated = existing.copyWith(occupied: occupied);
    await repository.save(updated);
    return updated;
  }

  Future<Shelter> setOccupancy(String shelterId, int occupied) async {
    final existing = await require(shelterId);
    final capacity = existing.capacity;
    final clamped = capacity <= 0
        ? (occupied < 0 ? 0 : occupied)
        : occupied.clamp(0, capacity);
    final updated = existing.copyWith(occupied: clamped);
    await repository.save(updated);
    return updated;
  }

  Future<Shelter> setOpen(String shelterId, bool open) async {
    final existing = await require(shelterId);
    final updated = existing.copyWith(open: open);
    await repository.save(updated);
    return updated;
  }

  Future<void> delete(String shelterId) => repository.delete(shelterId);

  /// Shelters sorted by distance from the supplied position; shelters without
  /// coordinates are listed last rather than hidden.
  Future<List<({Shelter shelter, double? distanceMetres})>> nearby({
    double? latitude,
    double? longitude,
  }) {
    return repository.sortedByDistance(
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// How many shelters currently have space.
  int countWithSpace(List<Shelter> shelters) => shelters
      .where((s) => s.open && s.availableCapacity > 0)
      .length;
}
