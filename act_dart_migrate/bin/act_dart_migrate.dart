import 'dart:io' as io;

import 'package:act_dart_migrate/act_dart_migrate.dart';

Future<void> main(List<String> arguments) async {
  io.exitCode = await runActDartMigrate(arguments);
}
