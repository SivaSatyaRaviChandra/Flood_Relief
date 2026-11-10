/// Demo data: fictional rescue teams and seed SOS requests.
///
/// All coordinates are real-world-plausible but fictional incident locations
/// near a generic coastal city. No real personal information is used.
library;

import '../../models/enums/emergency_type.dart';
import '../../models/enums/sos_priority.dart';
import '../../models/enums/sos_status.dart';
import '../../models/enums/team_status.dart';
import '../../models/people_info.dart';
import '../../models/rescue_team.dart';
import '../../models/sos_request.dart';
import '../../models/status_history.dart';

class DemoData {
  DemoData._();

  static const String demoUserId = 'USER-DEMO01';

  static List<RescueTeam> rescueTeams() => const [
        RescueTeam(
          teamId: 'TEAM-001',
          teamName: 'River Rescue Alpha',
          teamLeader: 'Asha Rao',
          contact: '9000000001',
          status: TeamStatus.available,
          latitude: 17.6868,
          longitude: 83.2185,
          baseLocation: 'Central Relief Camp',
        ),
        RescueTeam(
          teamId: 'TEAM-002',
          teamName: 'Flood Response Bravo',
          teamLeader: 'Vikram Nair',
          contact: '9000000002',
          status: TeamStatus.available,
          latitude: 17.7200,
          longitude: 83.2600,
          baseLocation: 'North Ward Hall',
        ),
        RescueTeam(
          teamId: 'TEAM-003',
          teamName: 'Medical Rapid Charlie',
          teamLeader: 'Meera Iyer',
          contact: '9000000003',
          status: TeamStatus.responding,
          latitude: 17.7000,
          longitude: 83.3000,
          baseLocation: 'District Hospital Annex',
        ),
      ];

  /// Demo SOS-1..3 fixtures used to seed the rescue dashboard. Each carries a
  /// fixed [sosId]/[timestamp] combination for deterministic display in the
  /// seeded state; priority is computed by the real priority engine at seed
  /// time (tests assert the same engine output).
  static List<SosRequest> seedSos({
    required DateTime Function() now,
    required String originDeviceId,
    required SosPriority Function({
      required EmergencyType emergencyType,
      required PeopleInfo people,
      required String description,
    })
        priorityOf,
  }) {
    final at = now().toUtc();

    SosRequest build({
      required int n,
      required PeopleInfo people,
      required EmergencyType type,
      required String description,
      required double lat,
      required double lng,
      required SosStatus status,
      required bool acknowledged,
      required Duration age,
      String? assignedTeamId,
    }) {
      final ts = at.subtract(age);
      final priority =
          priorityOf(emergencyType: type, people: people, description: description);
      final history = <StatusHistoryEntry>[
        StatusHistoryEntry(
          previousStatus: null,
          newStatus: SosStatus.pending,
          timestamp: ts,
          actorId: 'USER-SEED$n',
          note: 'SOS created and stored on device.',
        ),
        if (acknowledged || status != SosStatus.pending)
          StatusHistoryEntry(
            previousStatus: SosStatus.pending,
            newStatus: SosStatus.acknowledged,
            timestamp: ts.add(const Duration(minutes: 2)),
            teamId: 'RESCUE-NODE',
            note: 'ACK received: SOS received by rescue/relay node.',
          ),
        if (status == SosStatus.inProgress || status == SosStatus.resolved)
          StatusHistoryEntry(
            previousStatus: SosStatus.acknowledged,
            newStatus: status == SosStatus.resolved
                ? SosStatus.resolved
                : SosStatus.inProgress,
            timestamp: ts.add(const Duration(minutes: 6)),
            teamId: assignedTeamId ?? 'TEAM-001',
            note: status == SosStatus.resolved
                ? 'SOS resolved.'
                : 'Rescue in progress.',
          ),
      ];
      return SosRequest(
        sosId: 'SOS-20260922-00000$n',
        userId: 'USER-SEED$n',
        timestamp: ts,
        latitude: lat,
        longitude: lng,
        accuracy: 15.0 + n,
        people: people,
        emergencyType: type,
        description: description,
        priority: priority,
        status: status,
        assignedTeamId: assignedTeamId,
        originDeviceId: originDeviceId,
        hopCount: n == 1 ? 3 : n == 2 ? 2 : 4,
        acknowledged: acknowledged,
        acknowledgedAt: acknowledged
            ? ts.add(const Duration(minutes: 2))
            : null,
        statusHistory: history,
      );
    }

    return [
      build(
        n: 1,
        people: const PeopleInfo(
          totalPeople: 8,
          childrenCount: 2,
          elderlyCount: 1,
          pregnantWomenCount: 0,
          specialAssistanceCount: 0,
        ),
        type: EmergencyType.rescueRequired,
        description:
            'Water level is rising and people are trapped inside the building '
            'on 4th street. Two children and one elderly person need rescue.',
        lat: 17.7000,
        lng: 83.3000,
        status: SosStatus.pending,
        acknowledged: false,
        age: const Duration(minutes: 25),
      ),
      build(
        n: 2,
        people: const PeopleInfo(
          totalPeople: 4,
          childrenCount: 0,
          elderlyCount: 1,
          pregnantWomenCount: 1,
          specialAssistanceCount: 0,
        ),
        type: EmergencyType.medicalAssistance,
        description:
            'Medical assistance needed: elderly patient requires insulin and '
            'urgent transport to higher ground.',
        lat: 17.7100,
        lng: 83.3100,
        status: SosStatus.acknowledged,
        acknowledged: true,
        age: const Duration(minutes: 40),
      ),
      build(
        n: 3,
        people: const PeopleInfo(
          totalPeople: 12,
          childrenCount: 4,
          elderlyCount: 2,
          pregnantWomenCount: 1,
          specialAssistanceCount: 1,
        ),
        type: EmergencyType.foodRequired,
        description:
            'Twelve people sheltering on the roof of the community hall. Food '
            'and drinking water needed; blankets for the night.',
        lat: 17.7150,
        lng: 83.2950,
        status: SosStatus.inProgress,
        acknowledged: true,
        assignedTeamId: 'TEAM-001',
        age: const Duration(hours: 2),
      ),
    ];
  }

  /// A fictional incoming SOS used by the demo controls to simulate a packet
  /// received from another device.
  static SosRequest externalSos({
    required String sosId,
    required String originDeviceId,
    required DateTime at,
    required SosPriority priority,
  }) {
    return SosRequest(
      sosId: sosId,
      userId: 'USER-EXT01',
      timestamp: at,
      latitude: 17.7210,
      longitude: 83.3050,
      accuracy: 18.0,
      people: const PeopleInfo(
        totalPeople: 6,
        childrenCount: 2,
        elderlyCount: 0,
        pregnantWomenCount: 0,
        specialAssistanceCount: 0,
      ),
      emergencyType: EmergencyType.evacuationRequired,
      description:
          'Evacuation needed: ground floor flooded, six people stranded on '
          'the first floor of an apartment block.',
      priority: priority,
      status: SosStatus.pending,
      originDeviceId: originDeviceId,
      acknowledged: false,
      statusHistory: [
        StatusHistoryEntry(
          previousStatus: null,
          newStatus: SosStatus.pending,
          timestamp: at,
          note: 'SOS received from another device and stored locally.',
        ),
      ],
    );
  }
}