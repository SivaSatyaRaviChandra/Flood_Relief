/// Deterministic priority engine.
///
/// Scoring factors and thresholds are held in [PriorityConfig], separate from
/// the UI. Every assignment produces the priority plus a human-readable list
/// of reasons so users and rescue operators can see *why* a priority was set.
library;

import '../models/enums/emergency_type.dart';
import '../models/enums/sos_priority.dart';
import '../models/people_info.dart';

class PriorityConfig {
  const PriorityConfig({
    this.emergencyBase = const {
      EmergencyType.rescueRequired: 100,
      EmergencyType.medicalAssistance: 95,
      EmergencyType.missingPerson: 90,
      EmergencyType.evacuationRequired: 70,
      EmergencyType.shelterRequired: 50,
      EmergencyType.foodRequired: 40,
      EmergencyType.drinkingWaterRequired: 30,
      EmergencyType.other: 10,
    },
    this.peopleTotalLarge = 20,
    this.peopleTotalMedium = 12,
    this.peopleTotalHighThreshold = 10,
    this.peopleTotalMediumThreshold = 5,
    this.childrenPoint = 3,
    this.childrenCap = 15,
    this.elderlyPoint = 3,
    this.elderlyCap = 12,
    this.pregnantPoint = 8,
    this.pregnantCap = 16,
    this.specialPoint = 5,
    this.specialCap = 15,
    this.keywordBoost = 8,
    this.keywordCap = 24,
    this.criticalThreshold = 120,
    this.highThreshold = 80,
    this.mediumThreshold = 45,
  });

  /// Base score for each emergency type.
  final Map<EmergencyType, int> emergencyBase;

  /// Additional points for large groups.
  final int peopleTotalLarge;
  final int peopleTotalMedium;

  final int peopleTotalHighThreshold;
  final int peopleTotalMediumThreshold;

  final int childrenPoint;
  final int childrenCap;
  final int elderlyPoint;
  final int elderlyCap;
  final int pregnantPoint;
  final int pregnantCap;
  final int specialPoint;
  final int specialCap;

  /// Boost applied once per recognized keyword in the description.
  final int keywordBoost;
  final int keywordCap;

  final int criticalThreshold;
  final int highThreshold;
  final int mediumThreshold;

  /// Keywords that indicate an escalating situation. Kept deliberately small
  /// and documented; the description is free text and this is a heuristic.
  static const List<String> dangerKeywords = [
    'trapped',
    'trapping',
    'rising',
    'stuck',
    'flooding',
    'danger',
  ];
}

class PriorityVerdict {
  const PriorityVerdict({
    required this.priority,
    required this.score,
    required this.reasons,
  });

  final SosPriority priority;
  final int score;
  final List<String> reasons;
}

class PriorityService {
  const PriorityService(this.config);

  final PriorityConfig config;

  PriorityVerdict evaluate({
    required EmergencyType emergencyType,
    required PeopleInfo people,
    required String description,
  }) {
    final reasons = <String>[];
    var score = 0;

    final base = config.emergencyBase[emergencyType] ?? 10;
    score += base;
    reasons.add('Base score for ${emergencyType.label}: $base');

    if (people.totalPeople >= config.peopleTotalHighThreshold) {
      score += config.peopleTotalLarge;
      reasons.add(
        '${people.totalPeople} people affected: '
        '${config.peopleTotalLarge} points',
      );
    } else if (people.totalPeople >= config.peopleTotalMediumThreshold) {
      score += config.peopleTotalMedium;
      reasons.add(
        '${people.totalPeople} people affected: '
        '${config.peopleTotalMedium} points',
      );
    } else if (people.totalPeople >= 1) {
      score += 5;
      reasons.add('${people.totalPeople} person affected: 5 points');
    }

    if (people.childrenCount > 0) {
      final points = _cap(
        people.childrenCount * config.childrenPoint,
        config.childrenCap,
      );
      score += points;
      reasons.add('${people.childrenCount} children: $points points');
    }
    if (people.elderlyCount > 0) {
      final points = _cap(
        people.elderlyCount * config.elderlyPoint,
        config.elderlyCap,
      );
      score += points;
      reasons.add('${people.elderlyCount} elderly: $points points');
    }
    if (people.pregnantWomenCount > 0) {
      final points = _cap(
        people.pregnantWomenCount * config.pregnantPoint,
        config.pregnantCap,
      );
      score += points;
      reasons.add(
        '${people.pregnantWomenCount} pregnant women: $points points',
      );
    }
    if (people.specialAssistanceCount > 0) {
      final points = _cap(
        people.specialAssistanceCount * config.specialPoint,
        config.specialCap,
      );
      score += points;
      reasons.add(
        '${people.specialAssistanceCount} with special assistance needs: '
        '$points points',
      );
    }

    // The keyword boost is a documented heuristic over free-text input.
    if (PriorityConfig.dangerKeywords.any(description.toLowerCase().contains)) {
      var boosted = 0;
      for (final word in PriorityConfig.dangerKeywords) {
        if (description.toLowerCase().contains(word)) {
          boosted += config.keywordBoost;
        }
      }
      boosted = _cap(boosted, config.keywordCap);
      if (boosted > 0) {
        score += boosted;
        reasons.add('Description mentions an escalating situation: $boosted points');
      }
    }

    final priority = _fromScore(score);
    reasons.add(
      'Total score: $score — classified as ${priority.label} '
      '(critical ≥ ${config.criticalThreshold}, high ≥ ${config.highThreshold}, '
      'medium ≥ ${config.mediumThreshold}).',
    );

    return PriorityVerdict(priority: priority, score: score, reasons: reasons);
  }

  SosPriority _fromScore(int score) {
    if (score >= config.criticalThreshold) return SosPriority.critical;
    if (score >= config.highThreshold) return SosPriority.high;
    if (score >= config.mediumThreshold) return SosPriority.medium;
    return SosPriority.low;
  }

  static int _cap(int value, int cap) => value > cap ? cap : value;
}