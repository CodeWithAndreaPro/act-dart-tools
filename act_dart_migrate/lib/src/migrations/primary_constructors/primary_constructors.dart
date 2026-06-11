import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../core/discovery.dart';
import '../../core/command_discovery.dart';
import '../../core/report_contract.dart';
import '../../core/source_edit.dart';
import '../../core/target_package_run.dart';

part 'class_primary_constructor.dart';
part 'class_body_rewrite.dart';
part 'constructor_initialization.dart';
part 'declaration_planner.dart';
part 'empty_class_body.dart';
part 'engine.dart';
part 'enum_primary_constructor.dart';
part 'extension_type_primary_constructor.dart';
part 'field_comments.dart';
part 'field_to_parameter.dart';
part 'models.dart';
part 'source_helpers.dart';

const primaryConstructorsMigration = 'primary-constructors';
const primaryConstructorsSkipSuperConstructorInitializersFlag =
    'skip-super-constructor-initializers';
const primaryConstructorsCommandMetadata = MigrationCommandMetadata(
  id: primaryConstructorsMigration,
  displayName: 'Primary Constructors',
  status: 'stable',
  targetPackageMinimumDartSdk: '3.12.0',
  targetPackageRequiredExperiments: ['primary-constructors'],
  supportedCommandSyntax: [
    'dart run act_dart_migrate primary-constructors <target-package> --json',
    'dart run act_dart_migrate primary-constructors <target-package> --dry-run',
    'dart run act_dart_migrate primary-constructors <target-package> --include-skipped',
    'dart run act_dart_migrate primary-constructors <target-package> --skip-super-constructor-initializers',
  ],
  description:
      'Migrate eligible classes and enhanced enums to Dart primary-constructor syntax, with extension type support for representation validation and safe body transforms.',
);
const primaryConstructorTransform = 'primaryConstructor';
const constructorShorthandTransform = 'constructorShorthand';
const emptyClassBodyTransform = 'emptyClassBody';

const primaryConstructorTransformOrder = [
  primaryConstructorTransform,
  constructorShorthandTransform,
  emptyClassBodyTransform,
];

final primaryConstructorSkipReasonOrder = [
  for (final reason in DeclarationSkipReason.values) reason.code,
];

enum DeclarationSkipReason {
  multipleConstructors(
    'multipleConstructors',
    'Multiple generative constructors are not supported.',
  ),
  namedConstructor(
    'namedConstructor',
    'Named generative constructors are not supported in this shape.',
  ),
  mixinClassPrimaryConstructor(
    'mixinClassPrimaryConstructor',
    'Non-trivial mixin class primary constructors are not supported.',
  ),
  primaryConstructorConflict(
    'primaryConstructorConflict',
    'The primary constructor name conflicts with a retained body member.',
  ),
  extensionTypeRepresentationParameter(
    'extensionTypeRepresentationParameter',
    'Extension type primary constructors must have one non-var representation parameter.',
  ),
  externalConstructor(
    'externalConstructor',
    'External constructors are not supported.',
  ),
  redirectingConstructor(
    'redirectingConstructor',
    'Redirecting constructors are not supported.',
  ),
  nonEmptyConstructorBody(
    'nonEmptyConstructorBody',
    'Non-empty constructor bodies are not supported.',
  ),
  fieldInitializingConstructorBody(
    'fieldInitializingConstructorBody',
    'Constructor bodies that initialize instance fields are not supported.',
  ),
  unsupportedConstructorBody(
    'unsupportedConstructorBody',
    'This constructor body shape is not supported.',
  ),
  emptyNonConstConstructorWithMembers(
    'emptyNonConstConstructorWithMembers',
    'Empty non-const constructors without parameters are only supported when '
        'the class body can collapse.',
  ),
  classBodyComment(
    'classBodyComment',
    'Empty class bodies with comments are not collapsed.',
  ),
  constructorMetadata(
    'constructorMetadata',
    'Constructor metadata is not moved to primary constructors.',
  ),
  constructorComment(
    'constructorComment',
    'Constructor comments are not moved to primary constructors.',
  ),
  parameterMetadata(
    'parameterMetadata',
    'Parameter metadata is not moved to declaring parameters.',
  ),
  fieldMetadata(
    'fieldMetadata',
    'Field metadata is not moved to declaring parameters.',
  ),
  fieldComment(
    'fieldComment',
    'Ambiguous field comments are not moved to declaring parameters.',
  ),
  missingField(
    'missingField',
    'A constructor parameter maps to a missing field.',
  ),
  staticField(
    'staticField',
    'Static fields cannot become declaring parameters.',
  ),
  lateField('lateField', 'Late fields cannot become declaring parameters.'),
  externalField(
    'externalField',
    'External fields cannot become declaring parameters.',
  ),
  initializedField(
    'initializedField',
    'Initialized fields cannot become declaring parameters.',
  ),
  implicitFieldType(
    'implicitFieldType',
    'Fields with implicit types cannot become declaring parameters.',
  ),
  multipleFieldVariables(
    'multipleFieldVariables',
    'Multi-variable field declarations cannot become declaring parameters.',
  ),
  unsupportedFieldModifier(
    'unsupportedFieldModifier',
    'This field modifier is not supported for declaring parameters.',
  ),
  unsupportedParameterShape(
    'unsupportedParameterShape',
    'This constructor parameter shape is not supported.',
  ),
  unsafeInitializerDependency(
    'unsafeInitializerDependency',
    'Initializer field assignments must depend only on constructor parameters.',
  ),
  unsafeInitializerOrder(
    'unsafeInitializerOrder',
    'Moving initializer field assignments would change initializer evaluation order.',
  ),
  unsupportedInitializer(
    'unsupportedInitializer',
    'This constructor initializer is not supported.',
  ),
  superConstructorInitializer(
    'superConstructorInitializer',
    'Super constructor initializers are skipped by '
        '--skip-super-constructor-initializers as a Dart SDK '
        'primary-constructor workaround.',
  ),
  namedSuperInitializer(
    'namedSuperInitializer',
    'Named super constructor initializers are not supported.',
  );

  const DeclarationSkipReason(this.code, this.message);

  final String code;
  final String message;
}

final class PrimaryConstructorMigration implements TargetPackageMigration {
  const PrimaryConstructorMigration({
    this.skipSuperConstructorInitializers = false,
    ParseTargetDartSource? parseSource,
  }) : _customParseSource = parseSource;

  final bool skipSuperConstructorInitializers;

  final ParseTargetDartSource? _customParseSource;

  @override
  String get identifier => primaryConstructorsMigration;

  @override
  List<String> get transformOrder => primaryConstructorTransformOrder;

  @override
  List<String> get skipReasonOrder => primaryConstructorSkipReasonOrder;

  @override
  MigrationRunResult run({
    required List<TargetDartFile> files,
    required bool dryRun,
    required ReadTargetDartFile readFile,
    required WriteTargetDartFile writeFile,
  }) {
    return migrateTargetPackageFiles(
      files: files,
      dryRun: dryRun,
      readFile: readFile,
      writeFile: writeFile,
      skipSuperConstructorInitializers: skipSuperConstructorInitializers,
      parseSource: _customParseSource,
    );
  }
}
