import 'dart:io' as io;

enum FileSkipReason {
  generatedFile('generatedFile'),
  nestedPackage('nestedPackage'),
  excludedDirectory('excludedDirectory');

  const FileSkipReason(this.code);

  final String code;
}

class TargetPackageFiles {
  const TargetPackageFiles({
    required this.dartFiles,
    required this.skippedFiles,
  });

  final List<TargetDartFile> dartFiles;
  final List<SkippedDartFile> skippedFiles;

  List<Map<String, Object?>> get skippedFileReports {
    return [for (final file in skippedFiles) file.toJson()];
  }

  Map<String, int> get skipReasonCounts {
    final counts = {for (final reason in FileSkipReason.values) reason: 0};
    for (final file in skippedFiles) {
      counts[file.reason] = counts[file.reason]! + 1;
    }
    return {
      for (final reason in FileSkipReason.values)
        if (counts[reason] != 0) reason.code: counts[reason]!,
    };
  }
}

class TargetDartFile {
  const TargetDartFile({required this.relativePath, required this.file});

  final String relativePath;
  final io.File file;
}

class SkippedDartFile {
  const SkippedDartFile({required this.relativePath, required this.reason});

  final String relativePath;
  final FileSkipReason reason;

  Map<String, Object?> toJson() {
    return {'path': relativePath, 'reason': reason.code};
  }
}

TargetPackageFiles discoverTargetPackageFiles(io.Directory root) {
  final rootDirectory = root.absolute;
  final rootPath = _directoryPath(rootDirectory);
  final dartFiles = <TargetDartFile>[];
  final skippedFiles = <SkippedDartFile>[];

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
          _collectSkippedDartFiles(rootPath, entry, skipReason, skippedFiles);
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
            TargetDartFile(relativePath: relativePath, file: entry),
          );
        }
      }
    }
  }

  walk(rootDirectory);
  dartFiles.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  skippedFiles.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return TargetPackageFiles(dartFiles: dartFiles, skippedFiles: skippedFiles);
}

FileSkipReason? _directorySkipReason(
  io.Directory rootDirectory,
  io.Directory directory,
) {
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

void _collectSkippedDartFiles(
  String rootPath,
  io.Directory directory,
  FileSkipReason reason,
  List<SkippedDartFile> skippedFiles,
) {
  final entries = directory.listSync(recursive: true, followLinks: false)
    ..sort(
      (a, b) =>
          _relativePath(rootPath, a).compareTo(_relativePath(rootPath, b)),
    );
  for (final entry in entries) {
    if (entry is io.File && _isDartFile(entry)) {
      skippedFiles.add(
        SkippedDartFile(
          relativePath: _relativePath(rootPath, entry),
          reason: reason,
        ),
      );
    }
  }
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
