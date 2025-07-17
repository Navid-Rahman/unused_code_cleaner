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

      // Find entry points
      final entryPoints = await _findEntryPoints();
      Logger.debug(
          'Found ${entryPoints.length} entry points: ${entryPoints.join(', ')}');

      // Find reachable files
      final reachableFiles = dependencyGraph.findReachableFiles(entryPoints);
      Logger.debug(
          'Found ${reachableFiles.length} reachable files from entry points');

      // Check each file in lib/ directory
      final libDartFiles = dartFiles
          .where((file) =>
              file.path.contains('${path.separator}lib${path.separator}') ||
              file.path.endsWith('${path.separator}lib'))
          .toList();

      Logger.debug('Analyzing ${libDartFiles.length} files in lib/ directory');

      for (final file in libDartFiles) {
        final relativePath = path.relative(file.path, from: projectPath);
        final normalizedPath = PatternMatcher.normalizePath(file.path);

        Logger.debug(
            'Checking file: $relativePath (normalized: $normalizedPath)');

        if (PatternMatcher.isExcluded(relativePath, options.excludePatterns)) {
          Logger.debug('✅ Skipping excluded file: $relativePath');
          continue;
        }

        if (reachableFiles.contains(normalizedPath) ||
            _isSpecialFile(relativePath)) {
          Logger.debug(
              '✅ Protecting file: $relativePath (reachable: ${reachableFiles.contains(normalizedPath)}, special: ${_isSpecialFile(relativePath)})');
          continue;
        }

        Logger.debug('❌ Marking as unused: $relativePath');
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
    Logger.debug('Building dependency graph for ${dartFiles.length} files...');

    for (final file in dartFiles) {
      if (PatternMatcher.isExcluded(file.path, options.excludePatterns)) {
        continue;
      }
      final imports = await _findImportedFiles(file, projectPath);
      dependencyGraph.addFile(file.path, imports);

      if (imports.isNotEmpty) {
        Logger.debug(
            'File ${path.relative(file.path, from: projectPath)} imports: ${imports.map((i) => path.relative(i, from: projectPath)).join(', ')}');
      }
    }
  }

  Future<Set<String>> _findImportedFiles(File file, String projectPath) async {
    final imported = <String>{};
    try {
      final content = await file.readAsString();
      final lines = content.split('\n');

      for (final line in lines) {
        final trimmed = line.trim();

        // Handle relative imports (import './file.dart' or import '../file.dart')
        if (trimmed.startsWith('import \'') && !trimmed.contains('package:')) {
          final match = RegExp(r"import\s+'([^']+)'").firstMatch(trimmed);
          if (match != null) {
            String importPath = match.group(1)!;

            // Resolve relative path
            final dir = path.dirname(file.path);
            final resolvedPath = path.normalize(path.join(dir, importPath));

            // Ensure .dart extension
            final dartPath = resolvedPath.endsWith('.dart')
                ? resolvedPath
                : '$resolvedPath.dart';

            if (await File(dartPath).exists()) {
              imported.add(PatternMatcher.normalizePath(dartPath));
            }
          }
        }

        // Handle package imports from same project (package:project_name/...)
        else if (trimmed.startsWith('import \'package:')) {
          final match =
              RegExp(r"import\s+'package:([^/]+)/([^']+)'").firstMatch(trimmed);
          if (match != null) {
            final packageName = match.group(1)!;
            final filePath = match.group(2)!;

            // Check if it's importing from the same project
            final projectPackageName =
                await _getProjectPackageName(projectPath);
            if (packageName == projectPackageName) {
              final fullPath = path.join(projectPath, 'lib', filePath);
              final dartPath =
                  fullPath.endsWith('.dart') ? fullPath : '$fullPath.dart';

              if (await File(dartPath).exists()) {
                imported.add(PatternMatcher.normalizePath(dartPath));
              }
            }
          }
        }

        // Handle part files
        else if (trimmed.startsWith('part \'')) {
          final match = RegExp(r"part\s+'([^']+)'").firstMatch(trimmed);
          if (match != null) {
            String partPath = match.group(1)!;
            final dir = path.dirname(file.path);
            final resolvedPath = path.normalize(path.join(dir, partPath));
            final dartPath = resolvedPath.endsWith('.dart')
                ? resolvedPath
                : '$resolvedPath.dart';

            if (await File(dartPath).exists()) {
              imported.add(PatternMatcher.normalizePath(dartPath));
            }
          }
        }
      }
    } catch (e) {
      Logger.debug('Error reading file ${file.path}: $e');
    }
    return imported;
  }

  Future<String> _getProjectPackageName(String projectPath) async {
    try {
      final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
      if (await pubspecFile.exists()) {
        final content = await pubspecFile.readAsString();
        final nameMatch =
            RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(content);
        if (nameMatch != null) {
          return nameMatch.group(1)!.trim();
        }
      }
    } catch (e) {
      Logger.debug('Error reading project package name: $e');
    }
    return 'unknown';
  }

  Future<List<String>> _findEntryPoints() async {
    final entryPoints = <String>[];

    // Main entry point
    final mainFile = path.join(projectPath, 'lib', 'main.dart');
    if (await File(mainFile).exists()) {
      entryPoints.add(PatternMatcher.normalizePath(mainFile));
      Logger.debug('Found main entry point: $mainFile');
    }

    // Test files as entry points
    final testDir = Directory(path.join(projectPath, 'test'));
    if (await testDir.exists()) {
      await for (final file in testDir.list(recursive: true)) {
        if (file.path.endsWith('.dart')) {
          entryPoints.add(PatternMatcher.normalizePath(file.path));
          Logger.debug('Found test entry point: ${file.path}');
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
          Logger.debug('Found integration test entry point: ${file.path}');
        }
      }
    }

    // Example files as entry points
    final exampleDir = Directory(path.join(projectPath, 'example'));
    if (await exampleDir.exists()) {
      await for (final file in exampleDir.list(recursive: true)) {
        if (file.path.endsWith('.dart')) {
          entryPoints.add(PatternMatcher.normalizePath(file.path));
          Logger.debug('Found example entry point: ${file.path}');
        }
      }
    }

    return entryPoints;
  }

  bool _isSpecialFile(String relativePath) {
    final normalizedPath = PatternMatcher.normalizePath(relativePath);
    final specialPatterns = [
      r'\.g\.dart$', // Generated files
      r'\.gr\.dart$', // Generated route files
      r'\.freezed\.dart$', // Freezed generated files
      r'\.part\.dart$', // Part files
      r'main\.dart$', // Main entry point
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
      r'^build/',
      r'^\.dart_tool/',
    ];

    final isSpecial = specialPatterns
        .any((pattern) => RegExp(pattern).hasMatch(normalizedPath));
    if (isSpecial) {
      Logger.debug('File marked as special: $relativePath');
    }
    return isSpecial;
  }
}
