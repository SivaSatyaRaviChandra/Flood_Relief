/// Rescue team registration rules and persistence.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flood_relief/core/errors/app_error.dart';
import 'package:flood_relief/core/utils/id_generator.dart';
import 'package:flood_relief/models/enums/team_status.dart';
import 'package:flood_relief/services/rescue_team_service.dart';

import 'helpers/fakes.dart';

void main() {
  late MemoryRescueRepository repository;
  late RescueTeamService service;

  setUp(() {
    repository = MemoryRescueRepository();
    service = RescueTeamService(
      repository: repository,
      idGenerator: IdGenerator(),
    );
  });

  tearDown(() => repository.dispose());

  group('validateDraft', () {
    test('flags missing name, leader and contact', () {
      final errors = service.validateDraft(
        teamName: '  ',
        teamLeader: '',
        contact: '',
        latitude: null,
        longitude: null,
      );
      expect(errors, hasLength(3));
    });

    test('requires coordinates to be supplied as a pair', () {
      final errors = service.validateDraft(
        teamName: 'Alpha',
        teamLeader: 'Asha',
        contact: '9000000001',
        latitude: 17.7,
        longitude: null,
      );
      expect(errors, contains('Provide both latitude and longitude, or neither.'));
    });

    test('rejects out-of-range coordinates', () {
      final errors = service.validateDraft(
        teamName: 'Alpha',
        teamLeader: 'Asha',
        contact: '9000000001',
        latitude: 91,
        longitude: 83.3,
      );
      expect(errors, contains('The team base location is out of range.'));
    });

    test('accepts a complete valid draft', () {
      expect(
        service.validateDraft(
          teamName: 'Alpha',
          teamLeader: 'Asha',
          contact: '9000000001',
          latitude: 17.7,
          longitude: 83.3,
        ),
        isEmpty,
      );
    });
  });

  group('saveTeam', () {
    test('mints a team id and persists the trimmed values', () async {
      final team = await service.saveTeam(
        teamName: '  River Rescue Alpha  ',
        teamLeader: ' Asha Rao ',
        contact: ' 9000000001 ',
        status: TeamStatus.available,
        latitude: 17.6868,
        longitude: 83.2185,
        baseLocation: ' Central Camp ',
      );

      expect(team.teamId, matches(IdGenerator.teamIdPattern));
      expect(team.teamName, 'River Rescue Alpha');
      expect(team.teamLeader, 'Asha Rao');
      expect(team.contact, '9000000001');
      expect(team.baseLocation, 'Central Camp');
      expect((await repository.getTeams()), hasLength(1));
    });

    test('updates an existing team instead of duplicating it', () async {
      final created = await service.saveTeam(
        teamName: 'Bravo',
        teamLeader: 'Vikram',
        contact: '9000000002',
        status: TeamStatus.available,
      );
      final updated = await service.saveTeam(
        teamId: created.teamId,
        teamName: 'Flood Response Bravo',
        teamLeader: 'Vikram Nair',
        contact: '9000000002',
        status: TeamStatus.responding,
        baseLocation: 'North Ward Hall',
      );

      expect(updated.teamId, created.teamId);
      expect(updated.teamName, 'Flood Response Bravo');
      expect(updated.status, TeamStatus.responding);
      final all = await repository.getTeams();
      expect(all, hasLength(1));
      expect(all.single.baseLocation, 'North Ward Hall');
    });

    test('refuses to update a team that is not stored', () async {
      expect(
        () => service.saveTeam(
          teamId: 'TEAM-MISSING',
          teamName: 'Ghost',
          teamLeader: 'Nobody',
          contact: '9000000009',
          status: TeamStatus.available,
        ),
        throwsA(isA<AppError>()),
      );
    });

    test('throws InvalidFormError instead of persisting bad input', () async {
      expect(
        () => service.saveTeam(
          teamName: '',
          teamLeader: '',
          contact: '',
          status: TeamStatus.available,
        ),
        throwsA(isA<InvalidFormError>()),
      );
      expect(await repository.getTeams(), isEmpty);
    });
  });

  test('setStatus updates only the availability', () async {
    final team = await service.saveTeam(
      teamName: 'Charlie',
      teamLeader: 'Meera',
      contact: '9000000003',
      status: TeamStatus.available,
    );
    final updated = await service.setStatus(team.teamId, TeamStatus.inField);
    expect(updated.status, TeamStatus.inField);
    expect(updated.teamName, 'Charlie');
  });
}
