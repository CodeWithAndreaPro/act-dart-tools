import 'dart:io' as io;

import 'package:act_dart_primary_constructors/act_dart_primary_constructors.dart';

Future<void> main(List<String> arguments) async {
  io.exitCode = await runDartPrimaryConstructors(arguments);
}
