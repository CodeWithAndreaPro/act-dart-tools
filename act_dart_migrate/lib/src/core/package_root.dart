import 'dart:io' as io;

String? normalizeTargetPackageRoot(String? root) {
  if (root == null || root.isEmpty) {
    return null;
  }
  final directory = io.Directory(root);
  if (!directory.existsSync()) {
    return null;
  }
  final pubspec = io.File(
    '${directory.path}${io.Platform.pathSeparator}pubspec.yaml',
  );
  if (!pubspec.existsSync()) {
    return null;
  }
  return _reportRootPath(directory);
}

String invalidTargetPackageRootMessage(String? root) {
  if (root == null || root.isEmpty) {
    return 'A target package root is required.';
  }
  return 'Target package root does not exist or has no pubspec.yaml: $root';
}

String _reportRootPath(io.Directory directory) {
  final path = directory.absolute.uri.normalizePath().toFilePath();
  final separator = io.Platform.pathSeparator;
  if (path.length > separator.length && path.endsWith(separator)) {
    return path.substring(0, path.length - separator.length);
  }
  return path;
}
