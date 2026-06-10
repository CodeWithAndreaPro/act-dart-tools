import 'dart:convert';
import 'dart:io';

import 'package:act_dart_migrate/src/core/exit_codes.dart';
import 'package:act_dart_migrate/src/migrations/primary_constructors/primary_constructors.dart';
import 'package:test/test.dart';

import 'src/test_support.dart';

void main() {
  group('extension type primary constructor migration', () {
    test('keeps supported primary constructors idempotent', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      const source = '''
extension type UserId(String value);

extension type NamedId.name(int value);

extension type const ConstNamedId.name(int value);
''';
      writeFile(root, 'lib/ids.dart', source);

      final firstResult = await runCliPrimaryConstructors(root.path);
      final firstReport = _expectCleanNoOp(firstResult);
      expect(firstReport['migration'], primaryConstructorsMigration);
      expect(readFile(root, 'lib/ids.dart'), source);

      final secondResult = await runCliPrimaryConstructors(root.path);
      _expectCleanNoOp(secondResult);
      expect(readFile(root, 'lib/ids.dart'), source);
      await expectAnalyzerClean(root);
    });

    test(
      'collapses empty bodies without changing representation parameters',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        const originalSource = '''
extension type OmittedFinal(int value) {}

extension type ExplicitFinal(final int value) {}
''';
        writeFile(root, 'lib/representations.dart', originalSource);

        final result = await runCliPrimaryConstructors(root.path);

        expect(result.exitCode, exitSuccess);
        expect(result.stderr, isEmpty);
        final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
        expect(decoded['changedFiles'], ['lib/representations.dart']);
        expect(decoded['migratedDeclarations'], [
          {
            'path': 'lib/representations.dart',
            'declarationKind': 'extensionType',
            'declarationName': 'OmittedFinal',
            'transform': 'emptyClassBody',
            'offset': originalSource.indexOf('extension type OmittedFinal'),
          },
          {
            'path': 'lib/representations.dart',
            'declarationKind': 'extensionType',
            'declarationName': 'ExplicitFinal',
            'transform': 'emptyClassBody',
            'offset': originalSource.indexOf('extension type ExplicitFinal'),
          },
        ]);
        expect(decoded['skippedDeclarations'], isEmpty);
        expect(decoded['transformCounts'], {'emptyClassBody': 2});
        expect(await formattedFile(root, 'lib/representations.dart'), '''
extension type OmittedFinal(int value);

extension type ExplicitFinal(final int value);
''');
        await expectAnalyzerClean(root);
      },
    );

    test(
      'rewrites safe body constructors after representation validation',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        const originalSource = '''
extension type Identifier(String value) {
  external Identifier.named(String value);

  Identifier.redirected(String value) : this(value);
}
''';
        writeFile(root, 'lib/identifier.dart', originalSource);

        final result = await runCliPrimaryConstructors(root.path);

        expect(result.exitCode, exitSuccess);
        expect(result.stderr, isEmpty);
        final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
        expect(decoded['changedFiles'], ['lib/identifier.dart']);
        expect(decoded['migratedDeclarations'], [
          {
            'path': 'lib/identifier.dart',
            'declarationKind': 'constructor',
            'declarationName': 'Identifier.named',
            'transform': 'constructorShorthand',
            'offset': originalSource.indexOf('external Identifier.named'),
          },
          {
            'path': 'lib/identifier.dart',
            'declarationKind': 'constructor',
            'declarationName': 'Identifier.redirected',
            'transform': 'constructorShorthand',
            'offset': originalSource.indexOf('Identifier.redirected'),
          },
        ]);
        expect(decoded['skippedDeclarations'], isEmpty);
        expect(decoded['transformCounts'], {'constructorShorthand': 2});
        expect(await formattedFile(root, 'lib/identifier.dart'), '''
extension type Identifier(String value) {
  external new named(String value);

  new redirected(String value) : this(value);
}
''');
        await expectAnalyzerClean(root);
      },
    );

    test('skips var representation parameters without other edits', () async {
      const originalSource = '''
extension type Invalid(var value) {
  Invalid.named(String value) : this(value);
}
''';

      await _expectSingleExtensionTypeRepresentationSkip(
        relativePath: 'lib/invalid.dart',
        originalSource: originalSource,
        declarationName: 'Invalid',
      );
    });

    test('skips multi-parameter representation shapes without edits', () async {
      const originalSource = '''
extension type Pair(int x, int y) {}
''';

      await _expectSingleExtensionTypeRepresentationSkip(
        relativePath: 'lib/pair.dart',
        originalSource: originalSource,
        declarationName: 'Pair',
      );
    });
  });
}

Map<String, Object?> _expectCleanNoOp(ProcessResult result) {
  expect(result.exitCode, exitSuccess);
  expect(result.stderr, isEmpty);
  final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
  expect(decoded['ok'], isTrue);
  expect(decoded['changedFiles'], isEmpty);
  expect(decoded['migratedDeclarations'], isEmpty);
  expect(decoded['skippedDeclarations'], isEmpty);
  expect(decoded['transformCounts'], isEmpty);
  expect(decoded['skipReasonCounts'], isEmpty);
  return decoded;
}

Future<void> _expectSingleExtensionTypeRepresentationSkip({
  required String relativePath,
  required String originalSource,
  required String declarationName,
}) async {
  final root = await createPackageRoot();
  addTearDown(() => root.deleteSync(recursive: true));
  writeFile(root, relativePath, originalSource);

  final result = await runCliPrimaryConstructors(root.path);

  expect(result.exitCode, exitSuccess);
  expect(result.stderr, isEmpty);
  final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
  expect(decoded['changedFiles'], isEmpty);
  expect(decoded['migratedDeclarations'], isEmpty);
  expect(decoded['skippedDeclarations'], [
    {
      'path': relativePath,
      'declarationKind': 'extensionType',
      'declarationName': declarationName,
      'transform': 'primaryConstructor',
      'offset': 0,
      'reason': DeclarationSkipReason.extensionTypeRepresentationParameter.code,
      'message':
          DeclarationSkipReason.extensionTypeRepresentationParameter.message,
    },
  ]);
  expect(decoded['skipReasonCounts'], {
    DeclarationSkipReason.extensionTypeRepresentationParameter.code: 1,
  });
  expect(readFile(root, relativePath), originalSource);
}
