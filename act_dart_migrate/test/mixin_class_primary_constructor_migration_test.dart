import 'dart:convert';

import 'package:act_dart_migrate/src/core/exit_codes.dart';
import 'package:act_dart_migrate/src/migrations/primary_constructors/primary_constructors.dart';
import 'package:test/test.dart';

import 'src/test_support.dart';

void main() {
  group('mixin class primary constructor migration', () {
    test(
      'migrates unnamed trivial constructors with mixinClass reports',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        writeFile(root, 'lib/empty_mixin_class.dart', '''
mixin class EmptyMixinClass {
  EmptyMixinClass();
}
''');

        final result = await runCliPrimaryConstructors(root.path);

        expect(result.exitCode, exitSuccess);
        expect(result.stderr, isEmpty);
        final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
        expect(decoded['changedFiles'], ['lib/empty_mixin_class.dart']);
        expect(decoded['migratedDeclarations'], [
          {
            'path': 'lib/empty_mixin_class.dart',
            'declarationKind': 'mixinClass',
            'declarationName': 'EmptyMixinClass',
            'transform': 'primaryConstructor',
            'offset': 0,
          },
          {
            'path': 'lib/empty_mixin_class.dart',
            'declarationKind': 'mixinClass',
            'declarationName': 'EmptyMixinClass',
            'transform': 'emptyClassBody',
            'offset': 0,
          },
        ]);
        expect(decoded['skippedDeclarations'], isEmpty);
        expect(decoded['transformCounts'], {
          'primaryConstructor': 1,
          'emptyClassBody': 1,
        });
        expect(await formattedFile(root, 'lib/empty_mixin_class.dart'), '''
mixin class EmptyMixinClass;
''');
        await expectAnalyzerClean(root);
      },
    );

    test(
      'migrates named trivial constructors when accepted by the SDK',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        writeFile(root, 'lib/named_mixin_class.dart', '''
mixin class NamedMixinClass {
  NamedMixinClass.named();
}
''');

        final result = await runCliPrimaryConstructors(root.path);

        expectSinglePrimaryConstructorMigration(
          result,
          path: 'lib/named_mixin_class.dart',
          declarationKind: 'mixinClass',
          declarationName: 'NamedMixinClass',
          reportsEmptyClassBody: true,
        );
        expect(await formattedFile(root, 'lib/named_mixin_class.dart'), '''
mixin class NamedMixinClass.named();
''');
        await expectAnalyzerClean(root);
      },
    );

    test('keeps non-trivial mixin class skip behavior unchanged', () async {
      const originalSource = '''
mixin class NonTrivialMixinClass {
  final int value;

  NonTrivialMixinClass(this.value);
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/non_trivial_mixin_class.dart',
        originalSource: originalSource,
        declarationKind: 'mixinClass',
        declarationName: 'NonTrivialMixinClass',
        reason: DeclarationSkipReason.mixinClassPrimaryConstructor.code,
        message: DeclarationSkipReason.mixinClassPrimaryConstructor.message,
      );
    });
  });
}
