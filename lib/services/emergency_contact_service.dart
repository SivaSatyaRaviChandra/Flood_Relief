/// Emergency contact application service.
///
/// Validation and primary-contact handling for the user-managed contact list.
/// The list ships empty on purpose — see
/// `models/emergency_contact.dart` for why no default hotline numbers are
/// invented.
library;

import '../core/errors/app_error.dart';
import '../core/utils/id_generator.dart';
import '../models/emergency_contact.dart';
import '../repositories/emergency_contact_repository.dart';

class EmergencyContactService {
  EmergencyContactService({
    required this.repository,
    required this.idGenerator,
  });

  final EmergencyContactRepository repository;
  final IdGenerator idGenerator;

  /// Digits, spaces and the common separators are allowed; anything else is
  /// rejected so a mistyped number cannot be saved silently.
  static final RegExp _phonePattern = RegExp(r'^[0-9+][0-9\s\-().]{4,24}$');

  static final RegExp _digitsOnly = RegExp(r'[0-9]');

  List<String> validateDraft({
    required String name,
    required String phone,
    required ContactKind kind,
    String? notes,
  }) {
    final errors = <String>[];
    if (name.trim().isEmpty) errors.add('Enter a name.');
    final trimmedPhone = phone.trim();
    if (trimmedPhone.isEmpty) {
      errors.add('Enter a phone number.');
    } else if (!_phonePattern.hasMatch(trimmedPhone)) {
      errors.add('That phone number contains unsupported characters.');
    } else if (_digitsOnly.allMatches(trimmedPhone).length < 5) {
      errors.add('That phone number is too short.');
    }
    if ((notes ?? '').trim().length > 200) {
      errors.add('Notes must be at most 200 characters.');
    }
    return errors;
  }

  Future<EmergencyContact> saveContact({
    String? contactId,
    required String name,
    required String phone,
    required ContactKind kind,
    String? notes,
    bool isPrimary = false,
  }) async {
    final errors = validateDraft(
      name: name,
      phone: phone,
      kind: kind,
      notes: notes,
    );
    if (errors.isNotEmpty) throw InvalidFormError(errors);

    final contact = EmergencyContact(
      contactId: contactId ?? idGenerator.contactId(),
      name: name.trim(),
      phone: phone.trim(),
      kind: kind,
      notes: (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      isPrimary: isPrimary,
    );
    await repository.save(contact);
    return contact;
  }

  Future<EmergencyContact> require(String contactId) async {
    final existing = await repository.getById(contactId);
    if (existing == null) {
      throw const AppError(
        AppErrorKind.notFound,
        'That contact is no longer stored on this device.',
      );
    }
    return existing;
  }

  /// Makes [contactId] the single primary contact. Passing null clears the
  /// primary flag on every contact.
  Future<void> setPrimary(String? contactId) async {
    if (contactId == null) {
      final all = await repository.getAll();
      for (final contact in all) {
        if (contact.isPrimary) {
          await repository.save(contact.copyWith(isPrimary: false));
        }
      }
      return;
    }
    final target = await require(contactId);
    // `save` demotes every other contact first (repository contract), so this
    // can never leave two primaries behind.
    await repository.save(target.copyWith(isPrimary: true));
  }

  Future<void> delete(String contactId) => repository.delete(contactId);

  /// The contact dialled first, or null when the list is empty.
  Future<EmergencyContact?> primary() async {
    final all = await repository.getAll();
    for (final contact in all) {
      if (contact.isPrimary) return contact;
    }
    return null;
  }

  /// True when the user has not added anybody yet.
  Future<bool> isEmpty() async => (await repository.getAll()).isEmpty;
}
