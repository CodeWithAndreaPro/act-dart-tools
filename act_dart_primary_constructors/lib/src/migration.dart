import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'discovery.dart';
import 'report.dart';
import 'source_edit.dart';

part 'migration/class_primary_constructor.dart';
part 'migration/class_body_rewrite.dart';
part 'migration/constructor_initialization.dart';
part 'migration/declaration_planner.dart';
part 'migration/engine.dart';
part 'migration/enum_primary_constructor.dart';
part 'migration/field_comments.dart';
part 'migration/field_to_parameter.dart';
part 'migration/models.dart';
part 'migration/source_helpers.dart';
