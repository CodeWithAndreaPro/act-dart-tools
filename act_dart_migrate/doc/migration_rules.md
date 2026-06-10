# Migration Rules

This document explains the behavior of the bundled ACT tooling for Dart
primary-constructor migrations. It is meant to help Regular ACT Users and LLM
agents predict what the migration can change, what it will skip, and how to read
the stable report vocabulary.

The migration is conservative. When it cannot prove that a rewrite preserves the
meaning of the Target Package source, it leaves the source unchanged and reports
a stable reason code.

## Supported Transforms

The public transform names are:

- `primaryConstructor`
- `constructorShorthand`
- `emptyClassBody`

`primaryConstructor` covers both class primary-constructor migration and
enhanced-enum primary-constructor migration. For eligible classes and enhanced
enums, it moves ordinary constructor boilerplate into Dart experimental
primary-constructor syntax while preserving the declaration shape that matters
to callers: modifiers, type parameters, bounds, clauses, constructor names,
parameter names, nullability, default values, `required`, private declaring
parameter names, and simple `super` parameters.

The selected primary-constructor target may be unnamed, named, or `.new` when
there is exactly one non-redirecting generative constructor that can be migrated
safely. Retained redirecting constructors can remain in the body and be rewritten
to constructor shorthand.

Supported parameter shapes include mapped field-formal parameters, typed field
formals whose explicit type matches the field type, function-typed field formals
whose explicit field declaration type can be copied to a declaring parameter,
simple pass-through parameters, simple `super` parameters, optional positional
parameters, named parameters, defaults, and `required`. Fields with implicit
types are emitted as explicit `dynamic` declaring parameters when otherwise safe.
Mutable covariant fields can become `covariant var` declaring parameters.

Class and enhanced-enum primary-constructor migration may also move safe
parameter-only field initializer assignments to field declarations. Constructor
assertions may be retained in a primary constructor body when doing so preserves
their order and meaning. Class migrations may also retain explicit super
constructor initializers such as `super(...)` and `super.named(...)`.

By default, retained explicit super constructor initializers are migrated for
maximum coverage. The opt-in `--skip-super-constructor-initializers` flag is a
temporary Dart SDK primary-constructor workaround for a stable-channel compiler
failure seen when a migrated class has both a primary constructor and an
abstract superclass whose constructor has required parameters:

```dart
abstract class Parent {
  const Parent({required this.index});
  final int index;
}

class const Child(final int value) extends Parent {
  this : super(index: value);
}
```

When enabled, the flag skips otherwise eligible class migrations whose
primary-constructor body would retain `super(...)` or `super.named(...)`. Super
parameters such as `super.key` do not trigger that flag-specific skip.

Enhanced-enum primary-constructor migration preserves enum value argument shape
and retained enum members such as methods, getters, factories, and static
members. Named enum constructors can become named enum primary constructors when
the enum has a single safe non-redirecting generative constructor target.

`constructorShorthand` covers eligible generative and factory constructors that
stay in class, enhanced-enum, or extension-type bodies but can be rewritten to
constructor declaration shorthand. Primary-constructor migration is preferred
when it is safe. Generative constructors use `new` shorthand, for example
`C.name()` becomes `new name()`. Factory constructors remove the enclosing type
name, for example `factory C.name()` becomes `factory name()` and `factory C()`
becomes `factory()`. `const`, `external`, metadata, documentation comments,
parameters, initializer lists, bodies, and redirected factory targets are
preserved.

Constructor shorthand can still run after a primary-constructor skip when the
skip is caused by constructor shape or metadata that does not make shorthand
unsafe, such as `multipleConstructors`, `externalConstructor`,
`namedConstructor`, `constructorMetadata`, `constructorComment`, or
`parameterMetadata`.

`emptyClassBody` collapses truly empty bodies to semicolon form for ordinary
classes, mixin classes, mixins, extension types, extensions, and empty enums,
including declarations made empty by primary-constructor migration. It does not
remove bodies that contain comments, and it does not collapse enums that contain
enum values or retained members.

Declarations that already use primary-constructor syntax are treated as
unchanged. They are not failures, and they are not listed as migrated or skipped
declarations.

## Safe No-Op Outcomes

A successful run can change no files. That can happen when all declarations are
already in their fixed-point form, when the Target Package contains no eligible
Dart declarations, or when every inspected declaration is conservatively
skipped.

A skip-only result is also a successful run. It means the tool inspected source
that was valid enough to analyze for migration planning, found only unsupported
or unsafe shapes, and left the source unchanged on purpose.

## Declaration Skip Reasons

Declaration skip reasons are reported on skipped declaration records. They are
grouped below by the cause users can act on.

Constructor shape:

- `multipleConstructors`: multiple non-redirecting generative constructors make
  one primary-constructor target ambiguous.
- `namedConstructor`: a named generative constructor shape is not supported as a
  primary-constructor target.
- `mixinClassPrimaryConstructor`: non-trivial mixin class primary constructors
  are not migrated.
- `primaryConstructorConflict`: the generated primary constructor name would
  conflict with a retained body member.
- `externalConstructor`: external constructors have no body that can be safely
  rewritten.
- `redirectingConstructor`: redirecting constructors are not migrated.
- `emptyNonConstConstructorWithMembers`: empty non-const constructors without
  parameters are only removed when the class body can safely collapse.

Constructor body and initializer safety:

- `nonEmptyConstructorBody`: the constructor body contains executable code that
  is not supported for movement.
- `fieldInitializingConstructorBody`: the constructor body initializes instance
  fields.
- `unsupportedConstructorBody`: the constructor body shape is not one of the
  supported shapes.
- `unsafeInitializerDependency`: moving a field initializer would require a
  value other than constructor parameters.
- `unsafeInitializerOrder`: moving field initializer assignments would change
  initializer evaluation order.
- `unsupportedInitializer`: an initializer entry is not supported.
- `superConstructorInitializer`: `--skip-super-constructor-initializers` skipped
  an otherwise eligible migration that would retain an explicit super
  constructor initializer as a Dart SDK primary-constructor workaround.
- `namedSuperInitializer`: stable reserved reason code for named `super`
  constructor initializer skips.

Metadata and comments that would move or disappear:

- `constructorMetadata`: constructor metadata is not moved to primary
  constructors.
- `constructorComment`: constructor comments are not moved to primary
  constructors.
- `parameterMetadata`: parameter metadata is not moved to declaring parameters.
- `fieldMetadata`: field metadata is not moved to declaring parameters.
- `fieldComment`: ambiguous field comments are not moved to declaring
  parameters.
- `classBodyComment`: empty declaration bodies with comments are not collapsed
  away.

Field mapping and field declaration shape:

- `missingField`: a constructor parameter maps to no matching field.
- `staticField`: static fields cannot become declaring parameters.
- `lateField`: `late` fields cannot become declaring parameters.
- `externalField`: external fields cannot become declaring parameters.
- `initializedField`: fields that already have initializers are not converted to
  declaring parameters.
- `implicitFieldType`: stable reserved reason code for implicit field-type
  cases. Current safe implicit fields are emitted as explicit `dynamic`
  declaring parameters.
- `multipleFieldVariables`: multi-variable field declarations are not converted
  to declaring parameters.
- `unsupportedFieldModifier`: a field modifier is not supported for declaring
  parameters.
- `unsupportedParameterShape`: a constructor parameter shape is not supported.

## File And Directory Skip Reasons

Generated Dart files and skipped directory subtrees are reported separately from
declaration skips.

- `generatedFile`: a Dart file is treated as generated source and is not
  inspected for declaration migration.
- `nestedPackage`: a subdirectory contains its own `pubspec.yaml`, so it is a
  separate package boundary when the parent package is the target.
- `nestedRepository`: a subdirectory is a nested repository or worktree boundary.
- `excludedDirectory`: a transient, hidden, or build-output directory is skipped
  as a whole.

The migration does not inspect Dart files inside skipped directories. Directory
skips are reported once for the skipped subtree instead of once per file inside
that subtree.

## Failure Versus Skip

Skips are expected conservative outcomes. They do not mean the tool crashed or
that the Target Package is invalid.

A run fails only when the CLI cannot complete its migration pipeline, such as an
invalid package root, parse failure in an inspected non-generated Dart file,
transformed-source validation failure, bad arguments, or an unexpected internal
error. In successful runs, unchanged files, no-op runs, and skip-only runs are
all valid outcomes.
