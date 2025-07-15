import 'dart:io';
import 'package:path/path.dart' as path;

import '../models/unused_item.dart';
import '../models/dependency_graph.dart';
import '../utils/logger.dart';
import '../utils/file_utils.dart';
import '../utils/pattern_matcher.dart';
import '../models/cleanup_options.dart';

class FileAnalyzer {
  final String projectPath;
  final DependencyGraph dependencyGraph = DependencyGraph();

  FileAnalyzer(this.projectPath);

  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedFiles = <UnusedItem>[];

    try {
      Logger.info('🔍 Starting file analysis...');

      // Build dependency graph
      await _buildDependencyGraph(dartFiles, options);
      Logger.debug(
          'Built dependency graph with ${dependencyGraph.fileCount} files');

      // Find entry points
      final entryPoints = await _findEntryPoints();
      Logger.debug('Found ${entryPoints.length} entry points');

      // Find reachable files
      final reachableFiles = dependencyGraph.findReachableFiles(entryPoints);
      Logger.debug('Found ${reachableFiles.length} reachable files');

      // Check each file in lib/ directory
      final libDartFiles = dartFiles
          .where((file) =>
              file.path.contains('${path.separator}lib${path.separator}') ||
              file.path.endsWith('${path.separator}lib'))
          .toList();

      for (final file in libDartFiles) {
        final relativePath = path.relative(file.path, from: projectPath);
        final normalizedPath = PatternMatcher.normalizePath(file.path);

        if (PatternMatcher.isExcluded(relativePath, options.excludePatterns)) {
          Logger.debug('✅ Skipping excluded file: $relativePath');
          continue;
        }

        if (reachableFiles.contains(normalizedPath) ||
            _isSpecialFile(relativePath)) {
          Logger.debug('✅ Protecting file: $relativePath');
          continue;
        }

        final size = await FileUtils.getFileSize(file.path);
        unusedFiles.add(UnusedItem(
          name: path.basename(file.path),
          path: file.path,
          type: UnusedItemType.file,
          size: size,
          description: 'Unused Dart file',
        ));
      }

      Logger.info('Found ${unusedFiles.length} unused files');
      return unusedFiles;
    } catch (e) {
      Logger.error('File analysis failed: $e');
      return [];
    }
  }

  Future<void> _buildDependencyGraph(
      List<File> dartFiles, CleanupOptions options) async {
    for (final file in dartFiles) {
      if (PatternMatcher.isExcluded(file.path, options.excludePatterns)) {
        continue;
      }
      final imports = await _findImportedFiles(file, projectPath);
      dependencyGraph.addFile(file.path, imports);
    }
  }

  Future<Set<String>> _findImportedFiles(File file, String projectPath) async {
    final imported = <String>{};
    try {
      final content = await file.readAsString();
      final lines = content.split('\n');

      for (final line in lines) {
        final trimmed = line.trim();

        // Handle relative imports
        if (trimmed.startsWith('import \'') && !trimmed.contains('package:')) {
          final startQuote = trimmed.indexOf('\'', 7);
          final endQuote = trimmed.indexOf('\'', startQuote + 1);
          if (startQuote != -1 && endQuote != -1) {
            String importPath = trimmed.substring(startQuote + 1, endQuote);
            if (importPath.startsWith('../') ||
                importPath.startsWith('./') ||
                !importPath.contains('/')) {
              final dir = path.dirname(file.path);
              importPath = path.normalize(path.join(dir, importPath));
            } else {
              importPath = path.join(projectPath, 'lib', importPath);
            }
            if (!importPath.endsWith('.dart')) importPath += '.dart';
            imported.add(PatternMatcher.normalizePath(importPath));
          }
        }

        // Handle part files
        if (trimmed.startsWith('part ')) {
          final startQuote = trimmed.indexOf('\'');
          final endQuote = trimmed.indexOf('\'', startQuote + 1);
          if (startQuote != -1 && endQuote != -1) {
            String partPath = trimmed.substring(startQuote + 1, endQuote);
            if (!partPath.endsWith('.dart')) partPath += '.dart';
            final dir = path.dirname(file.path);
            final fullPath = path.normalize(path.join(dir, partPath));
            imported.add(PatternMatcher.normalizePath(fullPath));
          }
        }
      }
    } catch (e) {
      Logger.debug('Error reading file ${file.path}: $e');
    }
    return imported;
  }

  Future<List<String>> _findEntryPoints() async {
    final entryPoints = <String>[];

    // Main entry point
    final mainFile = path.join(projectPath, 'lib', 'main.dart');
    if (await File(mainFile).exists()) {
      entryPoints.add(PatternMatcher.normalizePath(mainFile));
    }

    // Test files are entry points
    final testDir = Directory(path.join(projectPath, 'test'));
    if (await testDir.exists()) {
      await for (final file in testDir.list(recursive: true)) {
        if (file.path.endsWith('_test.dart')) {
          entryPoints.add(PatternMatcher.normalizePath(file.path));
        }
      }
    }

    // Integration test files
    final integrationTestDir =
        Directory(path.join(projectPath, 'integration_test'));
    if (await integrationTestDir.exists()) {
      await for (final file in integrationTestDir.list(recursive: true)) {
        if (file.path.endsWith('.dart')) {
          entryPoints.add(PatternMatcher.normalizePath(file.path));
        }
      }
    }

    // Example files
    final exampleDir = Directory(path.join(projectPath, 'example'));
    if (await exampleDir.exists()) {
      await for (final file in exampleDir.list(recursive: true)) {
        if (file.path.endsWith('.dart')) {
          entryPoints.add(PatternMatcher.normalizePath(file.path));
        }
      }
    }

    return entryPoints;
  }

  bool _isSpecialFile(String relativePath) {
    final normalizedPath = PatternMatcher.normalizePath(relativePath);
    final specialPatterns = [
      r'\.g\.dart$',
      r'\.gr\.dart$',
      r'\.freezed\.dart$',
      r'\.part\.dart$',
      r'main\.dart$',
      r'firebase_options\.dart$',
      r'generated_plugin_registrant\.dart$',
      r'^test/',
      r'^integration_test/',
      r'^lib/generated/',
      r'^example/',
      r'^tool/',
      r'^scripts/',
      r'^android/',
      r'^ios/',
      r'^web/',
      r'^windows/',
      r'^macos/',
      r'^linux/',
    ];

    return specialPatterns
        .any((pattern) => RegExp(pattern).hasMatch(normalizedPath));
  }
}
