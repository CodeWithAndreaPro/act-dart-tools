import 'dart:io' as io;

enum FileSkipReason {
  generatedFile('generatedFile'),
  nestedPackage('nestedPackage'),
  excludedDirectory('excludedDirectory'),
  nestedRepository('nestedRepository');

  const FileSkipReason(this.code);

  final String code;
}

class TargetPackageFiles {
  const TargetPackageFiles({
    required this.dartFiles,
    required this.skippedFiles,
    required this.skippedDirectories,
  });

  final List<TargetDartFile> dartFiles;
  final List<SkippedDartFile> skippedFiles;
  final List<SkippedDirectory> skippedDirectories;
}

class TargetDartFile {
  const TargetDartFile({required this.relativePath, required this.path});

  final String relativePath;
  final String path;
}

class SkippedDartFile {
  const SkippedDartFile({required this.relativePath, required this.reason});

  final String relativePath;
  final FileSkipReason reason;
}

class SkippedDirectory {
  const SkippedDirectory({required this.relativePath, required this.reason});

  final String relativePath;
  final FileSkipReason reason;
}

TargetPackageFiles discoverTargetPackageFiles(io.Directory root) {
  final rootDirectory = root.absolute;
  final rootPath = _directoryPath(rootDirectory);
  final dartFiles = <TargetDartFile>[];
  final skippedFiles = <SkippedDartFile>[];
  final skippedDirectories = <SkippedDirectory>[];

  void walk(io.Directory directory) {
    final entries = directory.listSync(followLinks: false)
      ..sort(
        (a, b) =>
            _relativePath(rootPath, a).compareTo(_relativePath(rootPath, b)),
      );

    for (final entry in entries) {
      if (entry is io.Directory) {
        final skipReason = _directorySkipReason(rootDirectory, entry);
        if (skipReason == null) {
          walk(entry);
        } else {
          skippedDirectories.add(
            SkippedDirectory(
              relativePath: _relativeDirectoryPath(rootPath, entry),
              reason: skipReason,
            ),
          );
        }
      } else if (entry is io.File && _isDartFile(entry)) {
        final relativePath = _relativePath(rootPath, entry);
        if (_isGeneratedDartFile(entry, relativePath)) {
          skippedFiles.add(
            SkippedDartFile(
              relativePath: relativePath,
              reason: FileSkipReason.generatedFile,
            ),
          );
        } else {
          dartFiles.add(
            TargetDartFile(relativePath: relativePath, path: entry.path),
          );
        }
      }
    }
  }

  walk(rootDirectory);
  dartFiles.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  skippedFiles.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  skippedDirectories.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return TargetPackageFiles(
    dartFiles: dartFiles,
    skippedFiles: skippedFiles,
    skippedDirectories: skippedDirectories,
  );
}

FileSkipReason? _directorySkipReason(
  io.Directory rootDirectory,
  io.Directory directory,
) {
  if (!_samePath(rootDirectory, directory) && _isGitRepository(directory)) {
    return FileSkipReason.nestedRepository;
  }
  final name = _basename(directory.path);
  if (name.startsWith('.') || _excludedDirectoryNames.contains(name)) {
    return FileSkipReason.excludedDirectory;
  }
  if (!_samePath(rootDirectory, directory) &&
      io.File(
        '${directory.path}${io.Platform.pathSeparator}pubspec.yaml',
      ).existsSync()) {
    return FileSkipReason.nestedPackage;
  }
  return null;
}

bool _isGitRepository(io.Directory directory) {
  final gitPath = '${directory.path}${io.Platform.pathSeparator}.git';
  final type = io.FileSystemEntity.typeSync(gitPath, followLinks: false);
  return type == io.FileSystemEntityType.directory ||
      type == io.FileSystemEntityType.file;
}

bool _isDartFile(io.File file) => file.path.endsWith('.dart');

bool _isGeneratedDartFile(io.File file, String relativePath) {
  final fileName = _basename(relativePath);
  if (_generatedSuffixes.any(fileName.endsWith)) {
    return true;
  }
  if (_isGeneratedLocalizationFile(fileName)) {
    return true;
  }
  final contents = file.readAsStringSync();
  return _strongGeneratedMarkers.any(contents.contains);
}

bool _isGeneratedLocalizationFile(String fileName) {
  return fileName == 'app_localizations.dart' ||
      RegExp(r'^app_localizations_[A-Za-z_]+\.dart$').hasMatch(fileName) ||
      RegExp(r'^messages_(all|[A-Za-z_]+)\.dart$').hasMatch(fileName);
}

String _directoryPath(io.Directory directory) {
  final path = directory.absolute.uri.normalizePath().toFilePath();
  final separator = io.Platform.pathSeparator;
  if (path.length > separator.length && path.endsWith(separator)) {
    return path.substring(0, path.length - separator.length);
  }
  return path;
}

String _relativePath(String rootPath, io.FileSystemEntity entity) {
  final separator = io.Platform.pathSeparator;
  final path = entity.absolute.uri.normalizePath().toFilePath();
  final prefix = rootPath.endsWith(separator)
      ? rootPath
      : '$rootPath$separator';
  final relativePath = path.startsWith(prefix)
      ? path.substring(prefix.length)
      : path;
  return relativePath.replaceAll(separator, '/');
}

String _relativeDirectoryPath(String rootPath, io.Directory directory) {
  final relativePath = _relativePath(rootPath, directory);
  if (relativePath.endsWith('/')) {
    return relativePath.substring(0, relativePath.length - 1);
  }
  return relativePath;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  if (index == -1) {
    return normalized;
  }
  return normalized.substring(index + 1);
}

bool _samePath(io.Directory first, io.Directory second) {
  return first.absolute.uri.normalizePath() ==
      second.absolute.uri.normalizePath();
}

const _excludedDirectoryNames = {'build', 'coverage'};

const _generatedSuffixes = {
  '.chopper.dart',
  '.drift.dart',
  '.freezed.dart',
  '.g.dart',
  '.gen.dart',
  '.gr.dart',
  '.mapper.dart',
  '.mock.dart',
  '.mocks.dart',
  '.pb.dart',
  '.pbenum.dart',
  '.pbgrpc.dart',
  '.pbjson.dart',
};

const _strongGeneratedMarkers = {
  'GENERATED CODE - DO NOT MODIFY BY HAND',
  'Generated code. Do not modify.',
  '<auto-generated>',
};
