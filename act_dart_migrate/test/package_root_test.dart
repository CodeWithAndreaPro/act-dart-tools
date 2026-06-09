import 'dart:io';

import 'package:act_dart_migrate/src/core/package_root.dart';
import 'package:test/test.dart';

import 'src/test_support.dart';

void main() {
  group('package root validation', () {
    test('normalizes package roots for reports', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));

      expect(normalizeTargetPackageRoot(root.path), normalizedPath(root));
    });

    test(
      'rejects missing and non-package roots with stable messages',
      () async {
        final nonPackageRoot = await Directory.systemTemp.createTemp(
          'act_dart_non_package_',
        );
        addTearDown(() => nonPackageRoot.deleteSync(recursive: true));

        expect(normalizeTargetPackageRoot(null), isNull);
        expect(
          invalidTargetPackageRootMessage(null),
          'A target package root is required.',
        );
        expect(normalizeTargetPackageRoot(nonPackageRoot.path), isNull);
        expect(
          invalidTargetPackageRootMessage(nonPackageRoot.path),
          'Target package root does not exist or has no pubspec.yaml: '
          '${nonPackageRoot.path}',
        );
      },
    );
  });
}
