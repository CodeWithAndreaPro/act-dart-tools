import 'dart:io' as io;

import 'package:args/args.dart';

import 'exit_codes.dart';
import 'report.dart';
import 'target_package_run.dart';
import 'version.dart';

Future<int> runDartPrimaryConstructors(
  List<String> arguments, {
  StringSink? stdout,
  StringSink? stderr,
  TargetPackageRunner? runner,
}) async {
  final out = stdout ?? io.stdout;
  final err = stderr ?? io.stderr;

  try {
    if (arguments.length == 1 && arguments.single == '--version') {
      out.writeln(packageVersion);
      return exitSuccess;
    }

    if (arguments.isNotEmpty && arguments.first == 'migrate') {
      return await _runMigrate(
        arguments.skip(1).toList(),
        stdout: out,
        stderr: err,
        runner: runner ?? TargetPackageRunner(),
      );
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
  } catch (error, stackTrace) {
    return _writeInternalError(
      error,
      stackTrace,
      json: arguments.contains('--json'),
      stdout: out,
      stderr: err,
    );
  }
}

Future<int> _runMigrate(
  List<String> arguments, {
  required StringSink stdout,
  required StringSink stderr,
  required TargetPackageRunner runner,
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

  final outcome = runner.run(
    TargetPackageRunRequest(
      root: results.option('root'),
      mode: results.option('mode') ?? 'safe',
      dryRun: results.flag('dry-run'),
    ),
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
    );
  }
  return outcome.exitCode;
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

int _writeInternalError(
  Object error,
  StackTrace stackTrace, {
  required bool json,
  required StringSink stdout,
  required StringSink stderr,
}) {
  const report = CliErrorReport(
    code: 'internalError',
    message: 'Internal error while running migration.',
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
