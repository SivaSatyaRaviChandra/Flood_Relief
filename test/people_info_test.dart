/// Validation rules for the people-counts value object.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flood_relief/models/people_info.dart';

void main() {
  test('defaults are all zero', () {
    const info = PeopleInfo();
    expect(info.totalPeople, 0);
    expect(info.categorizedSum, 0);
    expect(info.validate(), isEmpty);
  });

  test('negative counts are rejected', () {
    const info = PeopleInfo(
      totalPeople: -1,
      childrenCount: -2,
      elderlyCount: -1,
      pregnantWomenCount: -1,
    );
    final errors = info.validate();
    expect(errors, hasLength(4));
    expect(errors.join('\n'), contains('Total people cannot be negative.'));
    expect(errors.join('\n'), contains('Children count cannot be negative.'));
    expect(errors.join('\n'), contains('Elderly count cannot be negative.'));
    expect(errors.join('\n'), contains('Pregnant women count cannot be negative.'));
  });

  test('categorized counts may not exceed the total', () {
    const info = PeopleInfo(
      totalPeople: 4,
      childrenCount: 3,
      elderlyCount: 2,
    );
    final errors = info.validate();
    expect(errors, hasLength(1));
    expect(errors.single, contains('cannot exceed the total'));
  });

  test('categories smaller than the total are valid', () {
    const info = PeopleInfo(
      totalPeople: 10,
      childrenCount: 4,
      elderlyCount: 2,
      pregnantWomenCount: 1,
      specialAssistanceCount: 1,
    );
    expect(info.validate(), isEmpty);
  });

  test('copyWith only replaces the supplied fields', () {
    const info = PeopleInfo(totalPeople: 3, childrenCount: 1);
    final next = info.copyWith(totalPeople: 5);
    expect(next.totalPeople, 5);
    expect(next.childrenCount, 1);
    expect(next.elderlyCount, 0);
  });

  test('toMap/fromMap round-trips every field', () {
    const info = PeopleInfo(
      totalPeople: 8,
      childrenCount: 2,
      elderlyCount: 1,
      pregnantWomenCount: 1,
      specialAssistanceCount: 1,
    );
    final restored = PeopleInfo.fromMap(info.toMap());
    expect(restored.totalPeople, 8);
    expect(restored.childrenCount, 2);
    expect(restored.elderlyCount, 1);
    expect(restored.pregnantWomenCount, 1);
    expect(restored.specialAssistanceCount, 1);
  });

  test('fromMap tolerates missing keys', () {
    final restored = PeopleInfo.fromMap(const {});
    expect(restored.totalPeople, 0);
    expect(restored.validate(), isEmpty);
  });
}