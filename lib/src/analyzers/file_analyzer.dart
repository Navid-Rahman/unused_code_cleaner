import 'dart:io';
import 'package:path/path.dart' as path;

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/file_utils.dart';
import '../models/cleanup_options.dart';

/// Analyzes Dart files to identify unused files within a project.
///
/// This analyzer examines import statements to determine which files are
/// actually being used and marks files without any imports as potentially unused.
class FileAnalyzer {
  /// Analyzes the project to find unused Dart files.
  ///
  /// [projectPath] - Root path of the project
  /// [dartFiles] - List of Dart files to analyze
  /// [options] - Cleanup options including exclude patterns
  /// Returns a list of unused items representing unused files.
  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedFiles = <UnusedItem>[];

    try {
      // Get all Dart files in the project
      final allDartFiles = await FileUtils.findDartFiles(projectPath);
      Logger.debug('Found ${allDartFiles.length} total Dart files');

      // Find imported files
      final importedFiles =
          await _findImportedFiles(dartFiles, projectPath, options);
      Logger.debug('Found ${importedFiles.length} imported files');

      // Find unused files
      for (final file in allDartFiles) {
        final relativePath = path.relative(file.path, from: projectPath);

        // Skip excluded files
        if (options.excludePatterns
            .any((pattern) => relativePath.contains(pattern))) {
          continue;
        }

        if (!_isFileImported(file.path, importedFiles) &&
            !_isSpecialFile(relativePath)) {
          final size = await FileUtils.getFileSize(file.path);

          unusedFiles.add(UnusedItem(
            name: path.basename(file.path),
            path: file.path,
            type: UnusedItemType.file,
            size: size,
            description: 'Unused Dart file',
          ));
        }
      }

      Logger.info('Found ${unusedFiles.length} unused files');
      return unusedFiles;
    } catch (e) {
      Logger.error('File analysis failed: $e');
      return [];
    }
  }

  /// Finds all files that are imported by other Dart files in the project.
  ///
  /// [dartFiles] - List of Dart files to scan for imports
  /// [projectPath] - Root path of the project
  /// [options] - Cleanup options including exclude patterns
  /// Returns a set of file paths that are imported somewhere.
  Future<Set<String>> _findImportedFiles(
      List<File> dartFiles, String projectPath, CleanupOptions options) async {
    final imported = <String>{};

    for (final file in dartFiles) {
      // Skip excluded files
      if (options.excludePatterns
          .any((pattern) => file.path.contains(pattern))) {
        continue;
      }

      try {
        final content = await file.readAsString();
        final lines = content.split('\n');

        for (final line in lines) {
          final trimmed = line.trim();
          // Look for local imports (not package imports)
          if (trimmed.startsWith('import \'') &&
              !trimmed.contains('package:')) {
            // Simple string parsing instead of regex to avoid syntax issues
            final startQuote = trimmed.indexOf('\'', 7); // Skip "import "
            final endQuote = trimmed.indexOf('\'', startQuote + 1);
            if (startQuote != -1 && endQuote != -1) {
              String importPath = trimmed.substring(startQuote + 1, endQuote);
              // Resolve relative paths
              if (importPath.startsWith('../') ||
                  importPath.startsWith('./') ||
                  !importPath.contains('/')) {
                final dir = path.dirname(file.path);
                importPath = path.normalize(path.join(dir, importPath));
              } else {
                importPath = path.join(projectPath, 'lib', importPath);
              }
              imported.add(importPath);
            }
          }
        }
      } catch (e) {
        Logger.debug('Error reading file ${file.path}: $e');
      }
    }

    return imported;
  }

  /// Checks if a file is imported by any other file in the project.
  ///
  /// [filePath] - Path to the file to check
  /// [importedFiles] - Set of all imported file paths
  /// Returns true if the file is imported, false otherwise.
  bool _isFileImported(String filePath, Set<String> importedFiles) {
    // Check direct import
    if (importedFiles.contains(filePath)) return true;

    // Check for files that might be imported without extension
    final withoutExtension = filePath.replaceAll('.dart', '');
    return importedFiles.any(
        (imported) => imported.replaceAll('.dart', '') == withoutExtension);
  }

  /// Determines if a file is a special file that should not be marked as unused.
  ///
  /// Special files include main.dart, test files, generated files, etc.
  ///
  /// [relativePath] - Relative path of the file from project root
  /// Returns true if the file is special and should be kept, false otherwise.
  bool _isSpecialFile(String relativePath) {
    // Don't mark these as unused
    final specialFiles = {
      'lib/main.dart',
      'test/',
      '.g.dart',
      '.freezed.dart',
      '.gr.dart',
      'generated_plugin_registrant.dart',
    };

    return specialFiles.any((special) => relativePath.contains(special));
  }
}
