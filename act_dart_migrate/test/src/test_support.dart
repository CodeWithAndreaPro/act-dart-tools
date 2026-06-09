import 'dart:convert';
import 'dart:io';

import 'package:act_dart_migrate/src/core/discovery.dart';
import 'package:act_dart_migrate/src/core/exit_codes.dart';
import 'package:act_dart_migrate/src/migrations/primary_constructors/primary_constructors.dart';
import 'package:test/test.dart';

Future<Directory> createPackageRoot() async {
  final root = await Directory.systemTemp.createTemp(
    'act_dart_primary_package_',
  );
  File('${root.path}${Platform.pathSeparator}pubspec.yaml').writeAsStringSync(
    '''
name: target_package
environment:
  sdk: ^3.12.0
''',
  );
  return root;
}

void writeFile(Directory root, String relativePath, String contents) {
  final file = File(
    '${root.path}${Platform.pathSeparator}${systemPath(relativePath)}',
  );
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

String systemPath(String relativePath) {
  return relativePath.replaceAll('/', Platform.pathSeparator);
}

Future<ProcessResult> runCli(List<String> arguments) {
  return Process.run(Platform.resolvedExecutable, [
    'run',
    'act_dart_migrate',
    ...arguments,
  ]);
}

Future<ProcessResult> runCliPrimaryConstructors(String targetRootPath) {
  return runCli(['primary-constructors', targetRootPath, '--json']);
}

Map<String, Object?> expectSinglePrimaryConstructorMigration(
  ProcessResult result, {
  required String path,
  required String declarationName,
  String declarationKind = 'class',
  bool reportsEmptyClassBody = false,
}) {
  expect(result.exitCode, exitSuccess);
  expect(result.stderr, isEmpty);
  final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
  expect(decoded['migration'], primaryConstructorsMigration);
  expect(decoded['changedFiles'], [path]);
  expect(decoded['migratedDeclarations'], [
    {
      'path': path,
      'declarationKind': declarationKind,
      'declarationName': declarationName,
      'transform': 'primaryConstructor',
      'offset': 0,
    },
    if (reportsEmptyClassBody)
      {
        'path': path,
        'declarationKind': 'class',
        'declarationName': declarationName,
        'transform': 'emptyClassBody',
        'offset': 0,
      },
  ]);
  expect(decoded['transformCounts'], {
    'primaryConstructor': 1,
    if (reportsEmptyClassBody) 'emptyClassBody': 1,
  });
  return decoded;
}

Future<Map<String, Object?>> expectSinglePrimaryConstructorSkip({
  required String relativePath,
  required String originalSource,
  required String declarationName,
  required String reason,
  required String message,
  String declarationKind = 'class',
}) async {
  final root = await createPackageRoot();
  addTearDown(() => root.deleteSync(recursive: true));
  writeFile(root, relativePath, originalSource);

  final result = await runCliPrimaryConstructors(root.path);

  expect(result.exitCode, exitSuccess);
  expect(result.stderr, isEmpty);
  final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
  expect(decoded['ok'], isTrue);
  expect(decoded['migration'], primaryConstructorsMigration);
  expect(decoded['changedFiles'], isEmpty);
  expect(decoded['migratedDeclarations'], isEmpty);
  expect(decoded['skippedDeclarations'], [
    {
      'path': relativePath,
      'declarationKind': declarationKind,
      'declarationName': declarationName,
      'transform': 'primaryConstructor',
      'offset': 0,
      'reason': reason,
      'message': message,
    },
  ]);
  expect(decoded['skipReasonCounts'], {reason: 1});
  expect(readFile(root, relativePath), originalSource);
  return decoded;
}

Future<String> formattedFile(Directory root, String relativePath) async {
  final file = File(
    '${root.path}${Platform.pathSeparator}${systemPath(relativePath)}',
  );
  final result = await Process.run(Platform.resolvedExecutable, [
    'format',
    '--enable-experiment=primary-constructors',
    file.path,
  ]);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return file.readAsStringSync();
}

String readFile(Directory root, String relativePath) {
  return File(
    '${root.path}${Platform.pathSeparator}${systemPath(relativePath)}',
  ).readAsStringSync();
}

String normalizedPath(Directory directory) {
  final path = directory.absolute.uri.normalizePath().toFilePath();
  final separator = Platform.pathSeparator;
  if (path.length > separator.length && path.endsWith(separator)) {
    return path.substring(0, path.length - separator.length);
  }
  return path;
}

List<String> discoveredPaths(TargetPackageFiles files) {
  return [for (final file in files.dartFiles) file.relativePath];
}

List<({String path, FileSkipReason reason})> skippedFileFacts(
  TargetPackageFiles files,
) {
  return [
    for (final file in files.skippedFiles)
      (path: file.relativePath, reason: file.reason),
  ];
}

List<({String path, FileSkipReason reason})> skippedDirectoryFacts(
  TargetPackageFiles files,
) {
  return [
    for (final directory in files.skippedDirectories)
      (path: directory.relativePath, reason: directory.reason),
  ];
}
