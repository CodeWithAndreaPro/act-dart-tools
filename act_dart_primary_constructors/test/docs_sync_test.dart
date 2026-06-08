import 'dart:io';

import 'package:act_dart_primary_constructors/act_dart_primary_constructors.dart';
import 'package:act_dart_primary_constructors/src/discovery.dart';
import 'package:test/test.dart';

void main() {
  test('migration rules document includes public report vocabulary', () {
    final rules = File('doc/migration_rules.md').readAsStringSync();

    _expectAllPresent(rules, [
      primaryConstructorTransform,
      constructorShorthandTransform,
      emptyClassBodyTransform,
    ], 'transform names');
    _expectAllPresent(rules, [
      for (final reason in DeclarationSkipReason.values) reason.code,
    ], 'declaration skip reason codes');
    _expectAllPresent(rules, [
      for (final reason in FileSkipReason.values) reason.code,
    ], 'file and directory skip reason codes');
  });
}

void _expectAllPresent(
  String contents,
  Iterable<String> expectedValues,
  String label,
) {
  final missing = [
    for (final value in expectedValues)
      if (!contents.contains(value)) value,
  ];

  expect(missing, isEmpty, reason: 'Missing $label: ${missing.join(', ')}');
}
