/// Deterministic priority engine: scoring, thresholds and keyword boost.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flood_relief/models/enums/emergency_type.dart';
import 'package:flood_relief/models/enums/sos_priority.dart';
import 'package:flood_relief/models/people_info.dart';
import 'package:flood_relief/services/priority_service.dart';

void main() {
  const service = PriorityService(PriorityConfig());

  test('a large rescue with vulnerable people is critical', () {
    final verdict = service.evaluate(
      emergencyType: EmergencyType.rescueRequired,
      people: const PeopleInfo(
        totalPeople: 10,
        childrenCount: 3,
        elderlyCount: 1,
        pregnantWomenCount: 1,
      ),
      description: 'Urgent help needed at the community hall.',
    );
    expect(verdict.priority, SosPriority.critical);
    // 100 (rescue) + 20 (≥10 people) + 9 (children) + 3 (elderly) + 8
    // (pregnant) = 140.
    expect(verdict.score, 140);
    expect(verdict.reasons, isNotEmpty);
  });

  test('seed SOS-003 scores 91 and is HIGH (food + 12 people + vulnerable)', () {
    final verdict = service.evaluate(
      emergencyType: EmergencyType.foodRequired,
      people: const PeopleInfo(
        totalPeople: 12,
        childrenCount: 4,
        elderlyCount: 2,
        pregnantWomenCount: 1,
        specialAssistanceCount: 1,
      ),
      description:
          'Twelve people sheltering on the roof of the community hall. Food '
          'and drinking water needed; blankets for the night.',
    );
    // 40 (food) + 20 (≥10 people) + 12 (children) + 6 (elderly) + 8 (pregnant)
    // + 5 (special) = 91 → HIGH (≥80).
    expect(verdict.score, 91);
    expect(verdict.priority, SosPriority.high);
    expect(verdict.reasons.any((r) => r.contains('Total score: 91')), isTrue);
  });

  test('seed SOS-2 scores 111 and is HIGH (medical + vulnerable)', () {
    final verdict = service.evaluate(
      emergencyType: EmergencyType.medicalAssistance,
      people: const PeopleInfo(
        totalPeople: 4,
        elderlyCount: 1,
        pregnantWomenCount: 1,
      ),
      description: 'Elderly patient requires insulin and urgent transport.',
    );
    // 95 + 5 (1-4 people) + 3 (elderly) + 8 (pregnant) = 111.
    expect(verdict.score, 111);
    expect(verdict.priority, SosPriority.high);
  });

  test('threshold boundary: 45 is medium, 35 is low', () {
    final medium = service.evaluate(
      emergencyType: EmergencyType.foodRequired,
      people: const PeopleInfo(totalPeople: 1),
      description: 'Some food please.',
    );
    expect(medium.score, 45);
    expect(medium.priority, SosPriority.medium);

    final low = service.evaluate(
      emergencyType: EmergencyType.drinkingWaterRequired,
      people: const PeopleInfo(totalPeople: 1),
      description: 'Need some water.',
    );
    expect(low.score, 35);
    expect(low.priority, SosPriority.low);
  });

  test('danger keywords add a bounded boost', () {
    final boosted = service.evaluate(
      emergencyType: EmergencyType.other,
      people: const PeopleInfo(totalPeople: 1),
      description: 'trapped trapping rising stuck flooding danger',
    );
    // 10 (other) + 5 (1 person) + cap(6×8, 24) = 39.
    expect(boosted.score, 39);
    expect(boosted.priority, SosPriority.low);
    expect(
      boosted.reasons.any((r) => r.contains('24 points')),
      isTrue,
    );
  });

  test('children points are capped', () {
    final verdict = service.evaluate(
      emergencyType: EmergencyType.foodRequired,
      people: const PeopleInfo(totalPeople: 1, childrenCount: 10),
      description: '',
    );
    // 40 + 5 + cap(10×3, 15) = 60.
    expect(verdict.score, 60);
    expect(verdict.reasons.any((r) => r.contains('10 children: 15 points')),
        isTrue);
  });

  test('every verdict explains itself', () {
    final verdict = service.evaluate(
      emergencyType: EmergencyType.missingPerson,
      people: const PeopleInfo(totalPeople: 2, elderlyCount: 1),
      description: 'Grandfather missing since yesterday.',
    );
    expect(verdict.reasons, isNotEmpty);
    expect(verdict.reasons.last, contains('Total score'));
  });
}