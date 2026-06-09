import 'dart:io' as io;

import 'discovery.dart';
import 'exit_codes.dart';
import 'package_root.dart';
import 'report_contract.dart';

class TargetPackageRunRequest {
  const TargetPackageRunRequest({required this.root, required this.dryRun});

  final String? root;
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

typedef ReadTargetDartFile = String Function(TargetDartFile file);

typedef WriteTargetDartFile = void Function(TargetDartFile file, String source);

abstract interface class TargetPackageMigration {
  String get identifier;

  List<String> get transformOrder;

  List<String> get skipReasonOrder;

  MigrationRunResult run({
    required List<TargetDartFile> files,
    required bool dryRun,
    required ReadTargetDartFile readFile,
    required WriteTargetDartFile writeFile,
  });
}

class MigrationFailure implements Exception {
  const MigrationFailure(this.message, {required this.isInputParseFailure});

  final String message;
  final bool isInputParseFailure;

  @override
  String toString() => 'MigrationFailure: $message';
}

class LocalTargetPackageRunFileSystem implements TargetPackageRunFileSystem {
  const LocalTargetPackageRunFileSystem();

  @override
  String? normalizePackageRoot(String? root) {
    return normalizeTargetPackageRoot(root);
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
    required this.migration,
    TargetPackageRunFileSystem? fileSystem,
  }) : fileSystem = fileSystem ?? const LocalTargetPackageRunFileSystem();

  final TargetPackageMigration migration;
  final TargetPackageRunFileSystem fileSystem;

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
    late final MigrationRunResult runResult;
    try {
      runResult = migration.run(
        files: discovery.dartFiles,
        dryRun: request.dryRun,
        readFile: fileSystem.readDartFile,
        writeFile: fileSystem.writeDartFile,
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
        migrationId: migration.identifier,
        dryRun: request.dryRun,
        discovery: discovery,
        runResult: runResult,
        transformOrder: migration.transformOrder,
        skipReasonOrder: migration.skipReasonOrder,
      ),
    );
  }
}

String _invalidRootMessage(String? root) {
  return invalidTargetPackageRootMessage(root);
}
