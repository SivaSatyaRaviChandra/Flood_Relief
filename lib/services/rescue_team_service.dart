/// Rescue team application service.
///
/// Teams are registered locally on the device (there is no auth/ops server in
/// this offline build). The service owns validation and the create/update
/// rules, so the screens never construct or persist a team directly.
library;

import '../core/errors/app_error.dart';
import '../core/utils/geo.dart';
import '../core/utils/id_generator.dart';
import '../models/enums/team_status.dart';
import '../models/rescue_team.dart';
import '../repositories/rescue_repository.dart';

class RescueTeamService {
  RescueTeamService({
    required this.repository,
    required this.idGenerator,
  });

  final RescueRepository repository;
  final IdGenerator idGenerator;

  List<String> validateDraft({
    required String teamName,
    required String teamLeader,
    required String contact,
    required double? latitude,
    required double? longitude,
  }) {
    final errors = <String>[];
    if (teamName.trim().isEmpty) errors.add('Enter a team name.');
    if (teamLeader.trim().isEmpty) errors.add('Enter the team leader name.');
    final digits = contact.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      errors.add('Enter a contact number for the team.');
    } else if (digits.length < 7) {
      errors.add('The contact number looks too short.');
    }
    final hasLat = latitude != null;
    final hasLng = longitude != null;
    if (hasLat != hasLng) {
      errors.add('Provide both latitude and longitude, or neither.');
    }
    if (hasLat && hasLng && !isValidCoordinate(latitude, longitude)) {
      errors.add('The team base location is out of range.');
    }
    return errors;
  }

  /// Creates a team when [teamId] is null, otherwise updates that team.
  Future<RescueTeam> saveTeam({
    String? teamId,
    required String teamName,
    required String teamLeader,
    required String contact,
    required TeamStatus status,
    double? latitude,
    double? longitude,
    String? baseLocation,
  }) async {
    final errors = validateDraft(
      teamName: teamName,
      teamLeader: teamLeader,
      contact: contact,
      latitude: latitude,
      longitude: longitude,
    );
    if (errors.isNotEmpty) throw InvalidFormError(errors);

    if (teamId != null && await repository.getById(teamId) == null) {
      throw const AppError(
        AppErrorKind.notFound,
        'That rescue team is no longer stored on this device.',
      );
    }

    final team = RescueTeam(
      teamId: teamId ?? idGenerator.teamId(),
      teamName: teamName.trim(),
      teamLeader: teamLeader.trim(),
      contact: contact.trim(),
      status: status,
      latitude: latitude,
      longitude: longitude,
      baseLocation: (baseLocation == null || baseLocation.trim().isEmpty)
          ? null
          : baseLocation.trim(),
    );
    await repository.saveTeam(team);
    return team;
  }

  Future<RescueTeam> setStatus(String teamId, TeamStatus status) async {
    final existing = await repository.getById(teamId);
    if (existing == null) {
      throw const AppError(
        AppErrorKind.notFound,
        'That rescue team is no longer stored on this device.',
      );
    }
    final updated = existing.copyWith(status: status);
    await repository.saveTeam(updated);
    return updated;
  }
}
