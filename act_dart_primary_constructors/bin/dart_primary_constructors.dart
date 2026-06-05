import 'dart:io' as io;

import 'package:dart_primary_constructors/dart_primary_constructors.dart';

Future<void> main(List<String> arguments) async {
  io.exitCode = await runDartPrimaryConstructors(arguments);
}
