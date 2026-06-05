import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import 'discovery.dart';
import 'source_edit.dart';

const primaryConstructorTransform = 'primaryConstructor';

class MigrationRunResult {
  const MigrationRunResult({
    required this.changedFiles,
    required this.migratedDeclarations,
    required this.transformCounts,
  });

  final List<String> changedFiles;
  final List<Map<String, Object?>> migratedDeclarations;
  final Map<String, int> transformCounts;
}

class MigrationFailure implements Exception {
  const MigrationFailure(this.message, {required this.isInputParseFailure});

  final String message;
  final bool isInputParseFailure;

  @override
  String toString() => 'MigrationFailure: $message';
}

MigrationRunResult migrateTargetPackageFiles({
  required List<TargetDartFile> files,
  required bool dryRun,
}) {
  final changedFiles = <String>[];
  final migratedDeclarations = <Map<String, Object?>>[];
  final plannedFiles = <_PlannedFileMigration>[];

  for (final targetFile in files) {
    final source = targetFile.file.readAsStringSync();
    final plan = _planFileMigration(targetFile: targetFile, source: source);
    if (plan == null) {
      continue;
    }
    changedFiles.add(targetFile.relativePath);
    migratedDeclarations.addAll(plan.migratedDeclarations);
    plannedFiles.add(plan);
  }

  for (final plan in plannedFiles) {
    _parseSource(
      plan.transformedSource,
      path: plan.targetFile.file.path,
      input: false,
    );
  }

  if (!dryRun) {
    for (final plan in plannedFiles) {
      plan.targetFile.file.writeAsStringSync(plan.transformedSource);
    }
  }

  return MigrationRunResult(
    changedFiles: changedFiles,
    migratedDeclarations: migratedDeclarations,
    transformCounts: {
      if (migratedDeclarations.isNotEmpty)
        primaryConstructorTransform: migratedDeclarations.length,
    },
  );
}

_PlannedFileMigration? _planFileMigration({
  required TargetDartFile targetFile,
  required String source,
}) {
  final unit = _parseSource(source, path: targetFile.file.path, input: true);
  final edits = <SourceEdit>[];
  final migratedDeclarations = <Map<String, Object?>>[];

  for (final declaration
      in unit.unit.declarations.whereType<ClassDeclaration>()) {
    final classPlan = _planClassMigration(
      source: source,
      targetFile: targetFile,
      declaration: declaration,
    );
    if (classPlan == null) {
      continue;
    }
    edits.addAll(classPlan.edits);
    migratedDeclarations.add(classPlan.reportEntry);
  }

  if (edits.isEmpty) {
    return null;
  }

  final transformedSource = applySourceEdits(source, edits);
  return _PlannedFileMigration(
    targetFile: targetFile,
    transformedSource: transformedSource,
    migratedDeclarations: migratedDeclarations,
  );
}

_ClassMigrationPlan? _planClassMigration({
  required String source,
  required TargetDartFile targetFile,
  required ClassDeclaration declaration,
}) {
  if (declaration.namePart is PrimaryConstructorDeclaration) {
    return null;
  }

  final constructor = _eligibleUnnamedConstructor(declaration);
  if (constructor == null) {
    return null;
  }

  final fieldParameters = constructor.parameters.parameters;
  if (fieldParameters.isEmpty ||
      fieldParameters.any((parameter) => parameter is! FieldFormalParameter)) {
    return null;
  }

  final fieldsByName = _eligibleFieldsByName(declaration, source);
  final parameterEdits = <SourceEdit>[];
  final removableMembers = <ClassMember>{constructor};
  final fieldNames = <String>{};
  final parametersOffset = constructor.parameters.offset;
  final parametersSource = _sourceFor(source, constructor.parameters);

  for (final parameter in fieldParameters.cast<FieldFormalParameter>()) {
    final fieldName = parameter.name.lexeme;
    final field = fieldsByName[fieldName];
    if (field == null || !fieldNames.add(fieldName)) {
      return null;
    }
    if (!_isSimpleFieldFormalParameter(parameter)) {
      return null;
    }
    removableMembers.add(field.declaration);
    final replacement =
        '${field.declaringKeyword} ${field.typeSource} $fieldName';
    parameterEdits.add(
      SourceEdit(
        offset: parameter.thisKeyword.offset - parametersOffset,
        length: parameter.name.end - parameter.thisKeyword.offset,
        replacement: replacement,
      ),
    );
  }

  final primaryParameters = applySourceEdits(parametersSource, parameterEdits);
  final edits = <SourceEdit>[
    if (constructor.constKeyword != null)
      SourceEdit(
        offset: declaration.classKeyword.end,
        length: 0,
        replacement: ' const',
      ),
    SourceEdit(
      offset: declaration.namePart.end,
      length: 0,
      replacement: primaryParameters,
    ),
  ];

  if (declaration.body.members.length == removableMembers.length) {
    edits.add(
      SourceEdit(
        offset: declaration.body.offset,
        length: declaration.body.length,
        replacement: ';',
      ),
    );
  } else {
    for (final member in removableMembers) {
      final range = _memberRemovalRange(source, member);
      edits.add(
        SourceEdit(offset: range.offset, length: range.length, replacement: ''),
      );
    }
  }

  return _ClassMigrationPlan(
    edits: edits,
    reportEntry: {
      'path': targetFile.relativePath,
      'declarationKind': 'class',
      'declarationName': declaration.namePart.typeName.lexeme,
      'transform': primaryConstructorTransform,
      'offset': declaration.offset,
    },
  );
}

ConstructorDeclaration? _eligibleUnnamedConstructor(
  ClassDeclaration declaration,
) {
  final constructors = declaration.body.members
      .whereType<ConstructorDeclaration>();
  ConstructorDeclaration? unnamed;
  for (final constructor in constructors) {
    if (constructor.factoryKeyword != null ||
        constructor.externalKeyword != null) {
      continue;
    }
    if (constructor.name != null || constructor.period != null) {
      return null;
    }
    if (unnamed != null ||
        constructor.redirectedConstructor != null ||
        constructor.initializers.isNotEmpty ||
        constructor.body is! EmptyFunctionBody) {
      return null;
    }
    unnamed = constructor;
  }
  return unnamed;
}

Map<String, _EligibleField> _eligibleFieldsByName(
  ClassDeclaration declaration,
  String source,
) {
  final fields = <String, _EligibleField>{};
  for (final member in declaration.body.members.whereType<FieldDeclaration>()) {
    final fieldList = member.fields;
    if (member.isStatic ||
        member.externalKeyword != null ||
        member.abstractKeyword != null ||
        member.covariantKeyword != null ||
        fieldList.isLate ||
        fieldList.isConst ||
        fieldList.type == null ||
        fieldList.metadata.isNotEmpty ||
        member.metadata.isNotEmpty ||
        fieldList.documentationComment != null ||
        member.documentationComment != null ||
        fieldList.variables.length != 1) {
      continue;
    }
    final variable = fieldList.variables.single;
    if (variable.initializer != null) {
      continue;
    }
    fields[variable.name.lexeme] = _EligibleField(
      declaration: member,
      typeSource: _sourceFor(source, fieldList.type!),
      declaringKeyword: fieldList.isFinal ? 'final' : 'var',
    );
  }
  return fields;
}

bool _isSimpleFieldFormalParameter(FieldFormalParameter parameter) {
  return parameter.metadata.isEmpty &&
      parameter.documentationComment == null &&
      parameter.constFinalOrVarKeyword == null &&
      parameter.covariantKeyword == null &&
      parameter.type == null &&
      parameter.functionTypedSuffix == null;
}

ParseStringResult _parseSource(
  String source, {
  required String path,
  required bool input,
}) {
  final result = parseString(
    content: source,
    path: path,
    featureSet: FeatureSet.latestLanguageVersion(
      flags: const ['primary-constructors'],
    ),
    throwIfDiagnostics: false,
  );
  if (result.errors.isNotEmpty) {
    final diagnostics = result.errors.map((error) => error.message).join('; ');
    throw MigrationFailure(
      'Failed to parse $path: $diagnostics',
      isInputParseFailure: input,
    );
  }
  return result;
}

String _sourceFor(String source, AstNode node) {
  return source.substring(node.offset, node.end);
}

_SourceRange _memberRemovalRange(String source, ClassMember member) {
  var start = member.offset;
  while (start > 0 && source.codeUnitAt(start - 1) != 10) {
    start--;
  }

  var end = member.end;
  while (end < source.length && source.codeUnitAt(end) != 10) {
    end++;
  }
  if (end < source.length) {
    end++;
  }
  while (end < source.length) {
    final nextLineEnd = source.indexOf('\n', end);
    final lineEnd = nextLineEnd == -1 ? source.length : nextLineEnd;
    if (source.substring(end, lineEnd).trim().isNotEmpty) {
      break;
    }
    end = lineEnd == source.length ? lineEnd : lineEnd + 1;
  }
  return _SourceRange(start, end - start);
}

class _ClassMigrationPlan {
  const _ClassMigrationPlan({required this.edits, required this.reportEntry});

  final List<SourceEdit> edits;
  final Map<String, Object?> reportEntry;
}

class _EligibleField {
  const _EligibleField({
    required this.declaration,
    required this.typeSource,
    required this.declaringKeyword,
  });

  final FieldDeclaration declaration;
  final String typeSource;
  final String declaringKeyword;
}

class _PlannedFileMigration {
  const _PlannedFileMigration({
    required this.targetFile,
    required this.transformedSource,
    required this.migratedDeclarations,
  });

  final TargetDartFile targetFile;
  final String transformedSource;
  final List<Map<String, Object?>> migratedDeclarations;
}

class _SourceRange {
  const _SourceRange(this.offset, this.length);

  final int offset;
  final int length;
}
