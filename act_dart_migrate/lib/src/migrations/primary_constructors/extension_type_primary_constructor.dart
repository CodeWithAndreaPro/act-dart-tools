part of 'primary_constructors.dart';

final class _ExtensionTypePrimaryConstructorPlanner {
  const _ExtensionTypePrimaryConstructorPlanner({required this.declaration});

  final ExtensionTypeDeclaration declaration;

  _ExtensionTypePrimaryConstructorDecision decide() {
    final namePart = declaration.namePart;
    if (namePart is! PrimaryConstructorDeclaration) {
      return const _SkippedExtensionTypePrimaryConstructor(
        DeclarationSkipReason.extensionTypeRepresentationParameter,
      );
    }

    final parameters = namePart.formalParameters.parameters;
    if (parameters.length != 1) {
      return const _SkippedExtensionTypePrimaryConstructor(
        DeclarationSkipReason.extensionTypeRepresentationParameter,
      );
    }

    final parameter = parameters.single;
    if (!_isSupportedRepresentationParameter(parameter)) {
      return const _SkippedExtensionTypePrimaryConstructor(
        DeclarationSkipReason.extensionTypeRepresentationParameter,
      );
    }

    return const _NoOpExtensionTypePrimaryConstructor();
  }

  bool _isSupportedRepresentationParameter(FormalParameter parameter) {
    return parameter is RegularFormalParameter &&
        parameter.isRequiredPositional &&
        parameter.name != null &&
        parameter.varKeyword == null &&
        parameter.constKeyword == null &&
        parameter.covariantKeyword == null &&
        parameter.functionTypedSuffix == null;
  }
}

sealed class _ExtensionTypePrimaryConstructorDecision {
  const _ExtensionTypePrimaryConstructorDecision();
}

final class _SkippedExtensionTypePrimaryConstructor
    extends _ExtensionTypePrimaryConstructorDecision {
  const _SkippedExtensionTypePrimaryConstructor(this.reason);

  final DeclarationSkipReason reason;
}

final class _NoOpExtensionTypePrimaryConstructor
    extends _ExtensionTypePrimaryConstructorDecision {
  const _NoOpExtensionTypePrimaryConstructor();
}
