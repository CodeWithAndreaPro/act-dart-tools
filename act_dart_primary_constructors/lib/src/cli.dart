import 'dart:io' as io;

import 'package:args/args.dart';

import 'discovery.dart';
import 'exit_codes.dart';
import 'report.dart';
import 'version.dart';

Future<int> runDartPrimaryConstructors(
  List<String> arguments, {
  StringSink? stdout,
  StringSink? stderr,
}) async {
  final out = stdout ?? io.stdout;
  final err = stderr ?? io.stderr;

  if (arguments.length == 1 && arguments.single == '--version') {
    out.writeln(packageVersion);
    return exitSuccess;
  }

  if (arguments.isNotEmpty && arguments.first == 'migrate') {
    return _runMigrate(arguments.skip(1).toList(), stdout: out, stderr: err);
  }

  return _writeError(
    CliErrorReport(
      code: 'argumentError',
      message: 'Expected --version or the migrate command.',
    ),
    exitArgumentError,
    json: arguments.contains('--json'),
    stdout: out,
    stderr: err,
  );
}

Future<int> _runMigrate(
  List<String> arguments, {
  required StringSink stdout,
  required StringSink stderr,
}) async {
  final parser = ArgParser()
    ..addOption('root', help: 'Target Dart package root.')
    ..addOption('mode', defaultsTo: 'safe', allowed: const ['safe'])
    ..addFlag(
      'dry-run',
      negatable: false,
      help: 'Plan the migration without writing files.',
    )
    ..addFlag(
      'json',
      negatable: false,
      help: 'Emit a machine-readable JSON report.',
    )
    ..addFlag(
      'include-skipped',
      negatable: false,
      help: 'Include skipped declarations in text output.',
    );

  final jsonRequested = arguments.contains('--json');
  late final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    return _writeError(
      CliErrorReport(code: 'argumentError', message: error.message),
      exitArgumentError,
      json: jsonRequested,
      stdout: stdout,
      stderr: stderr,
    );
  }

  final rootOption = results.option('root');
  final rootValidation = _validateRoot(rootOption);
  if (rootValidation == null) {
    return _writeError(
      CliErrorReport(
        code: 'invalidRoot',
        message: _invalidRootMessage(rootOption),
      ),
      exitInvalidRoot,
      json: results.flag('json'),
      stdout: stdout,
      stderr: stderr,
    );
  }

  final discovery = discoverTargetPackageFiles(io.Directory(rootValidation));
  final report = MigrationReport(
    root: rootValidation,
    mode: results.option('mode') ?? 'safe',
    dryRun: results.flag('dry-run'),
    skippedFiles: discovery.skippedFileReports,
    skipReasonCounts: discovery.skipReasonCounts,
  );

  if (results.flag('json')) {
    stdout.writeln(report.toJsonString());
  } else {
    _writeTextReport(
      report,
      stdout,
      includeSkipped: results.flag('include-skipped'),
    );
  }
  return exitSuccess;
}

String? _validateRoot(String? root) {
  if (root == null || root.isEmpty) {
    return null;
  }
  final directory = io.Directory(root);
  if (!directory.existsSync()) {
    return null;
  }
  final packageConfig = io.File(
    '${directory.path}${io.Platform.pathSeparator}pubspec.yaml',
  );
  if (!packageConfig.existsSync()) {
    return null;
  }
  return _reportRootPath(directory);
}

String _reportRootPath(io.Directory directory) {
  final path = directory.absolute.uri.normalizePath().toFilePath();
  final separator = io.Platform.pathSeparator;
  if (path.length > separator.length && path.endsWith(separator)) {
    return path.substring(0, path.length - separator.length);
  }
  return path;
}

String _invalidRootMessage(String? root) {
  if (root == null || root.isEmpty) {
    return 'A target package root is required.';
  }
  return 'Target package root does not exist or has no pubspec.yaml: $root';
}

int _writeError(
  CliErrorReport report,
  int exitCode, {
  required bool json,
  required StringSink stdout,
  required StringSink stderr,
}) {
  if (json) {
    stdout.writeln(report.toJsonString());
  } else {
    stderr.writeln(report.message);
  }
  return exitCode;
}

void _writeTextReport(
  MigrationReport report,
  StringSink stdout, {
  required bool includeSkipped,
}) {
  stdout
    ..writeln('Dart primary constructors migration')
    ..writeln('Tool version: $packageVersion')
    ..writeln('Root: ${report.root}')
    ..writeln('Mode: ${report.mode}')
    ..writeln('Dry run: ${report.dryRun}')
    ..writeln('Formatted: false')
    ..writeln('Changed files: ${report.changedFiles.length}')
    ..writeln('Migrated declarations: ${report.migratedDeclarations.length}')
    ..writeln('Skipped declarations: ${report.skippedDeclarations.length}')
    ..writeln('Skipped files: ${report.skippedFiles.length}');

  if (includeSkipped && report.skippedFiles.isNotEmpty) {
    stdout.writeln('Skipped file details:');
    for (final skippedFile in report.skippedFiles) {
      if (skippedFile case {
        'path': final String path,
        'reason': final String reason,
      }) {
        stdout.writeln('- $path ($reason)');
      }
    }
  }
}
