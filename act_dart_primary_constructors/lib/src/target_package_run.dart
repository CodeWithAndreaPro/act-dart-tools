import 'dart:io' as io;

import 'discovery.dart';
import 'exit_codes.dart';
import 'migration.dart';
import 'report.dart';

class TargetPackageRunRequest {
  const TargetPackageRunRequest({
    required this.root,
    required this.mode,
    required this.dryRun,
  });

  final String? root;
  final String mode;
  final bool dryRun;
}

class TargetPackageRunOutcome {
  const TargetPackageRunOutcome._({
    required this.exitCode,
    this.report,
    this.error,
  });

  factory TargetPackageRunOutcome.success(MigrationReport report) {
    return TargetPackageRunOutcome._(exitCode: exitSuccess, report: report);
  }

  factory TargetPackageRunOutcome.failure(
    CliErrorReport error, {
    required int exitCode,
  }) {
    return TargetPackageRunOutcome._(exitCode: exitCode, error: error);
  }

  final int exitCode;
  final MigrationReport? report;
  final CliErrorReport? error;
}

abstract interface class TargetPackageRunFileSystem {
  String? normalizePackageRoot(String? root);

  TargetPackageFiles discover(String root);

  String readDartFile(TargetDartFile file);

  void writeDartFile(TargetDartFile file, String source);
}

class LocalTargetPackageRunFileSystem implements TargetPackageRunFileSystem {
  const LocalTargetPackageRunFileSystem();

  @override
  String? normalizePackageRoot(String? root) {
    if (root == null || root.isEmpty) {
      return null;
    }
    final directory = io.Directory(root);
    if (!directory.existsSync()) {
      return null;
    }
    final pubspec = io.File(
      '${directory.path}${io.Platform.pathSeparator}pubspec.yaml',
    );
    if (!pubspec.existsSync()) {
      return null;
    }
    return _reportRootPath(directory);
  }

  @override
  TargetPackageFiles discover(String root) {
    return discoverTargetPackageFiles(io.Directory(root));
  }

  @override
  String readDartFile(TargetDartFile file) {
    return io.File(file.path).readAsStringSync();
  }

  @override
  void writeDartFile(TargetDartFile file, String source) {
    io.File(file.path).writeAsStringSync(source);
  }
}

class TargetPackageRunner {
  TargetPackageRunner({
    TargetPackageRunFileSystem? fileSystem,
    ParseTargetDartSource? parseSource,
  }) : fileSystem = fileSystem ?? const LocalTargetPackageRunFileSystem(),
       parseSource = parseSource ?? parseTargetDartSource;

  final TargetPackageRunFileSystem fileSystem;
  final ParseTargetDartSource parseSource;

  TargetPackageRunOutcome run(TargetPackageRunRequest request) {
    final root = fileSystem.normalizePackageRoot(request.root);
    if (root == null) {
      return TargetPackageRunOutcome.failure(
        CliErrorReport(
          code: 'invalidRoot',
          message: _invalidRootMessage(request.root),
        ),
        exitCode: exitInvalidRoot,
      );
    }

    final discovery = fileSystem.discover(root);
    late final MigrationRunResult migration;
    try {
      migration = migrateTargetPackageFiles(
        files: discovery.dartFiles,
        dryRun: request.dryRun,
        readFile: fileSystem.readDartFile,
        writeFile: fileSystem.writeDartFile,
        parseSource: parseSource,
      );
    } on MigrationFailure catch (error) {
      return TargetPackageRunOutcome.failure(
        CliErrorReport(
          code: error.isInputParseFailure
              ? 'parseFailure'
              : 'validationFailure',
          message: error.message,
        ),
        exitCode: error.isInputParseFailure
            ? exitParseFailure
            : exitValidationFailure,
      );
    }

    return TargetPackageRunOutcome.success(
      MigrationReport.fromRun(
        root: root,
        mode: request.mode,
        dryRun: request.dryRun,
        discovery: discovery,
        migration: migration,
      ),
    );
  }
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
