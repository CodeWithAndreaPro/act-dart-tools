import 'dart:io' as io;

import 'package:args/args.dart';

import 'core/command_discovery.dart';
import 'core/exit_codes.dart';
import 'core/report_contract.dart';
import 'core/target_package_run.dart';
import 'migrations/primary_constructors/primary_constructors.dart';
import 'version.dart';

Future<int> runActDartMigrate(
  List<String> arguments, {
  StringSink? stdout,
  StringSink? stderr,
  TargetPackageRunner? runner,
}) async {
  final out = stdout ?? io.stdout;
  final err = stderr ?? io.stderr;

  try {
    if (arguments.isEmpty) {
      out.write(_rootHelpOutput);
      return exitSuccess;
    }

    if (arguments.length == 1 && arguments.single == '--version') {
      out.writeln(packageVersion);
      return exitSuccess;
    }

    if (arguments.isNotEmpty && arguments.first == 'list') {
      return _runList(arguments.skip(1).toList(), stdout: out, stderr: err);
    }

    if (arguments.isNotEmpty &&
        arguments.first == primaryConstructorsMigration) {
      return await _runPrimaryConstructors(
        arguments.skip(1).toList(),
        stdout: out,
        stderr: err,
        runner: runner,
      );
    }

    return _writeError(
      CliErrorReport(
        code: 'argumentError',
        message: _unknownSubcommandMessage(arguments.first),
      ),
      exitArgumentError,
      json: arguments.contains('--json'),
      stdout: out,
      stderr: err,
    );
  } catch (error, stackTrace) {
    return _writeInternalError(
      error,
      stackTrace,
      migration: _selectedMigration(arguments),
      json: arguments.contains('--json'),
      stdout: out,
      stderr: err,
    );
  }
}

Future<int> _runPrimaryConstructors(
  List<String> arguments, {
  required StringSink stdout,
  required StringSink stderr,
  required TargetPackageRunner? runner,
}) async {
  final parser = ArgParser()
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
      CliErrorReport(
        code: 'argumentError',
        message: error.message,
        migration: primaryConstructorsMigration,
      ),
      exitArgumentError,
      json: jsonRequested,
      stdout: stdout,
      stderr: stderr,
    );
  }

  if (results.rest.length != 1) {
    return _writeError(
      const CliErrorReport(
        code: 'argumentError',
        message: 'Expected exactly one target package path.',
        migration: primaryConstructorsMigration,
      ),
      exitArgumentError,
      json: results.flag('json'),
      stdout: stdout,
      stderr: stderr,
    );
  }

  final root = results.rest.single;
  final targetPackageRunner =
      runner ??
      TargetPackageRunner(migration: const PrimaryConstructorMigration());

  final outcome = targetPackageRunner.run(
    TargetPackageRunRequest(root: root, dryRun: results.flag('dry-run')),
  );
  if (outcome.report case final report?) {
    if (results.flag('json')) {
      stdout.writeln(report.toJsonString());
    } else {
      stdout.write(
        report.toTextString(includeSkipped: results.flag('include-skipped')),
      );
    }
  } else if (outcome.error case final error?) {
    return _writeError(
      error,
      outcome.exitCode,
      json: results.flag('json'),
      stdout: stdout,
      stderr: stderr,
      migration: primaryConstructorsMigration,
    );
  }
  return outcome.exitCode;
}

int _runList(
  List<String> arguments, {
  required StringSink stdout,
  required StringSink stderr,
}) {
  final parser = ArgParser()
    ..addFlag(
      'json',
      negatable: false,
      help: 'Emit machine-readable command discovery JSON.',
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

  if (results.rest.isNotEmpty) {
    return _writeError(
      const CliErrorReport(
        code: 'argumentError',
        message: 'The list command does not accept positional arguments.',
      ),
      exitArgumentError,
      json: results.flag('json'),
      stdout: stdout,
      stderr: stderr,
    );
  }

  if (!results.flag('json')) {
    return _writeError(
      const CliErrorReport(
        code: 'argumentError',
        message: 'The list command only supports --json.',
      ),
      exitArgumentError,
      json: false,
      stdout: stdout,
      stderr: stderr,
    );
  }

  stdout.writeln(
    const CommandDiscoveryReport(
      migrations: [primaryConstructorsCommandMetadata],
    ).toJsonString(),
  );
  return exitSuccess;
}

const _rootHelpOutput = '''ACT Dart Migrate runs Dart migration subcommands.

Usage:
  dart run act_dart_migrate
  dart run act_dart_migrate --version
  dart run act_dart_migrate list --json
  dart run act_dart_migrate primary-constructors <target-package> [options]

Utility Commands:
  list --json        List supported Migration Subcommands.

Migration Subcommands:
  primary-constructors   Migrate Dart declarations to primary-constructor syntax.

Arguments:
  target-package     Package root to migrate. Use . for the current directory.

Options:
  --dry-run           Preview the migration without writing files.
  --json              Emit a machine-readable JSON report.
  --include-skipped   Include skipped declarations in text output.
''';

String _unknownSubcommandMessage(String subcommand) {
  return 'Unknown Migration Subcommand "$subcommand". Run dart run '
      'act_dart_migrate for usage. Available Migration Subcommands: '
      '$primaryConstructorsMigration.';
}

String? _selectedMigration(List<String> arguments) {
  if (arguments.isNotEmpty && arguments.first == primaryConstructorsMigration) {
    return primaryConstructorsMigration;
  }
  return null;
}

int _writeError(
  CliErrorReport report,
  int exitCode, {
  required bool json,
  required StringSink stdout,
  required StringSink stderr,
  String? migration,
}) {
  final outputReport = switch (migration) {
    final migration? => report.withMigration(migration),
    null => report,
  };
  if (json) {
    stdout.writeln(outputReport.toJsonString());
  } else {
    stderr.writeln(outputReport.message);
  }
  return exitCode;
}

int _writeInternalError(
  Object error,
  StackTrace stackTrace, {
  String? migration,
  required bool json,
  required StringSink stdout,
  required StringSink stderr,
}) {
  final report = CliErrorReport(
    code: 'internalError',
    message: 'Internal error while running migration.',
    migration: migration,
  );
  if (json) {
    stdout.writeln(report.toJsonString());
  } else {
    stderr.writeln(report.message);
  }
  stderr.writeln('Unexpected internal error: $error');
  stderr.writeln(stackTrace);
  return exitInternalError;
}
