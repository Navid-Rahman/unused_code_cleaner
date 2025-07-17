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

      // Print debug information if verbose
      if (options.verbose) {
        dependencyGraph.printGraph();
      }

      // Find entry points
      final entryPoints = await _findEntryPoints();
      Logger.info(
          'Found ${entryPoints.length} entry points: ${entryPoints.map((e) => path.basename(e)).join(', ')}');

      if (entryPoints.isEmpty) {
        Logger.error(
            '❌ No entry points found! All files will be marked as unused.');
        Logger.info(
            '💡 Make sure your project has a main.dart file in the root or lib/ directory.');
        return _markAllFilesAsUnused(dartFiles, projectPath, options);
      }

      // Find reachable files
      final reachableFiles = dependencyGraph.findReachableFiles(entryPoints);
      Logger.info(
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

      // Print summary if verbose
      if (options.verbose) {
        _printAnalysisSummary(
            dartFiles, reachableFiles, unusedFiles, entryPoints);
      }

      return unusedFiles;
    } catch (e) {
      Logger.error('File analysis failed: $e');
      return [];
    }
  }

  /// Mark all files as unused when no entry points are found
  List<UnusedItem> _markAllFilesAsUnused(
      List<File> dartFiles, String projectPath, CleanupOptions options) {
    final unusedFiles = <UnusedItem>[];

    final libDartFiles = dartFiles
        .where((file) =>
            file.path.contains('${path.separator}lib${path.separator}') ||
            file.path.endsWith('${path.separator}lib'))
        .toList();

    for (final file in libDartFiles) {
      final relativePath = path.relative(file.path, from: projectPath);

      if (PatternMatcher.isExcluded(relativePath, options.excludePatterns) ||
          _isSpecialFile(relativePath)) {
        continue;
      }

      unusedFiles.add(UnusedItem(
        name: path.basename(file.path),
        path: file.path,
        type: UnusedItemType.file,
        size: 0,
        description: 'Marked as unused (no entry points found)',
      ));
    }

    return unusedFiles;
  }

  /// Print detailed analysis summary
  void _printAnalysisSummary(List<File> allFiles, Set<String> reachableFiles,
      List<UnusedItem> unusedFiles, List<String> entryPoints) {
    Logger.section('📊 ANALYSIS SUMMARY');

    final stats = dependencyGraph.getStatistics();
    Logger.info('Total Dart files: ${allFiles.length}');
    Logger.info('Entry points: ${entryPoints.length}');
    Logger.info('Reachable files: ${reachableFiles.length}');
    Logger.info('Unused files: ${unusedFiles.length}');
    Logger.info('Files in dependency graph: ${stats['totalFiles']}');
    Logger.info('Total dependencies: ${stats['totalDependencies']}');
    Logger.info(
        'Average dependencies per file: ${stats['averageDependenciesPerFile'].toStringAsFixed(1)}');

    if (stats['circularDependencies'] > 0) {
      Logger.warning(
          '⚠️ Found ${stats['circularDependencies']} circular dependencies');
    }

    if (unusedFiles.isNotEmpty) {
      Logger.section('📝 UNUSED FILES DETAILS');
      for (final unused in unusedFiles.take(10)) {
        // Show first 10
        Logger.info('• ${unused.name} (${unused.description})');
      }
      if (unusedFiles.length > 10) {
        Logger.info('... and ${unusedFiles.length - 10} more files');
      }
    }
  }

  Future<void> _buildDependencyGraph(
      List<File> dartFiles, CleanupOptions options) async {
    Logger.debug('Building dependency graph for ${dartFiles.length} files...');

    int processedFiles = 0;
    int skippedFiles = 0;
    int filesWithImports = 0;

    for (final file in dartFiles) {
      if (PatternMatcher.isExcluded(file.path, options.excludePatterns)) {
        skippedFiles++;
        continue;
      }

      try {
        final imports = await _findImportedFiles(file, projectPath);
        dependencyGraph.addFile(file.path, imports);
        processedFiles++;

        if (imports.isNotEmpty) {
          filesWithImports++;
          if (options.verbose) {
            Logger.debug(
                'File ${path.relative(file.path, from: projectPath)} imports: ${imports.map((i) => path.relative(i, from: projectPath)).join(', ')}');
          }
        }
      } catch (e) {
        Logger.debug('Error processing file ${file.path}: $e');
        skippedFiles++;
      }
    }

    Logger.info(
        'Dependency graph built: $processedFiles processed, $filesWithImports with imports, $skippedFiles skipped');
  }

  Future<Set<String>> _findImportedFiles(File file, String projectPath) async {
    final imported = <String>{};
    try {
      final content = await file.readAsString();
      final lines = content.split('\n');

      // Track imports to later check for widget usage
      final Map<String, String> importedClasses = {};

      for (final line in lines) {
        final trimmed = line.trim();

        // Handle relative imports with both single and double quotes
        final relativePattern = RegExp(r'''import\s+['"](\.\.?/[^'"]+)['"]''');
        final relativeMatch = relativePattern.firstMatch(trimmed);
        if (relativeMatch != null && !trimmed.contains('package:')) {
          String importPath = relativeMatch.group(1)!;

          // Resolve relative path
          final dir = path.dirname(file.path);
          final resolvedPath = path.normalize(path.join(dir, importPath));

          // Ensure .dart extension
          final dartPath = resolvedPath.endsWith('.dart')
              ? resolvedPath
              : '$resolvedPath.dart';

          if (await File(dartPath).exists()) {
            final normalizedPath = PatternMatcher.normalizePath(dartPath);
            imported.add(normalizedPath);

            // Extract class names for widget usage detection
            final className = _extractClassNameFromPath(dartPath);
            if (className != null) {
              importedClasses[className] = normalizedPath;
            }
          }
        }

        // Handle package imports from same project with both quotes
        final packagePattern =
            RegExp(r'''import\s+['"]package:([^/]+)/([^'"]+)['"]''');
        final packageMatch = packagePattern.firstMatch(trimmed);
        if (packageMatch != null) {
          final packageName = packageMatch.group(1)!;
          final filePath = packageMatch.group(2)!;

          // Check if it's importing from the same project
          final projectPackageName = await _getProjectPackageName(projectPath);
          if (packageName == projectPackageName) {
            final fullPath = path.join(projectPath, 'lib', filePath);
            final dartPath =
                fullPath.endsWith('.dart') ? fullPath : '$fullPath.dart';

            if (await File(dartPath).exists()) {
              final normalizedPath = PatternMatcher.normalizePath(dartPath);
              imported.add(normalizedPath);

              // Extract class names for widget usage detection
              final className = _extractClassNameFromPath(dartPath);
              if (className != null) {
                importedClasses[className] = normalizedPath;
              }
            }
          }
        }

        // Handle part files with both quotes
        final partPattern = RegExp(r'''part\s+['"]([^'"]+)['"]''');
        final partMatch = partPattern.firstMatch(trimmed);
        if (partMatch != null) {
          String partPath = partMatch.group(1)!;
          final dir = path.dirname(file.path);
          final resolvedPath = path.normalize(path.join(dir, partPath));
          final dartPath = resolvedPath.endsWith('.dart')
              ? resolvedPath
              : '$resolvedPath.dart';

          if (await File(dartPath).exists()) {
            imported.add(PatternMatcher.normalizePath(dartPath));
          }
        }

        // Handle export statements
        final exportPattern = RegExp(r'''export\s+['"]([^'"]+)['"]''');
        final exportMatch = exportPattern.firstMatch(trimmed);
        if (exportMatch != null && !trimmed.contains('package:')) {
          String exportPath = exportMatch.group(1)!;
          final dir = path.dirname(file.path);
          final resolvedPath = path.normalize(path.join(dir, exportPath));
          final dartPath = resolvedPath.endsWith('.dart')
              ? resolvedPath
              : '$resolvedPath.dart';

          if (await File(dartPath).exists()) {
            imported.add(PatternMatcher.normalizePath(dartPath));
          }
        }
      }

      // Phase 2: Detect widget/class usage in the file content
      final usedFiles =
          await _detectClassUsage(content, importedClasses, projectPath);
      imported.addAll(usedFiles);
    } catch (e) {
      Logger.debug('Error reading file ${file.path}: $e');
    }
    return imported;
  }

  /// Extracts the likely class name from a file path
  String? _extractClassNameFromPath(String filePath) {
    final fileName = path.basenameWithoutExtension(filePath);
    if (fileName.isEmpty) return null;

    // Convert snake_case or kebab-case to PascalCase
    final parts = fileName.split(RegExp(r'[_-]'));
    final className = parts
        .map((part) => part.isNotEmpty
            ? part[0].toUpperCase() + part.substring(1).toLowerCase()
            : '')
        .join('');

    return className.isNotEmpty ? className : null;
  }

  /// Detects actual usage of imported classes/widgets in the file content
  Future<Set<String>> _detectClassUsage(String content,
      Map<String, String> importedClasses, String projectPath) async {
    final usedFiles = <String>{};

    for (final entry in importedClasses.entries) {
      final className = entry.key;
      final filePath = entry.value;

      // Common usage patterns for Flutter widgets and Dart classes
      final usagePatterns = [
        RegExp(r'\b' + className + r'\s*\('), // Constructor call: ClassName()
        RegExp(r'\b' + className + r'\s*\.'), // Static access: ClassName.method
        RegExp(r':\s*' +
            className +
            r'\s*[,\)\s]'), // Type annotation: Type className
        RegExp(r'<' + className + r'>'), // Generic type: List<ClassName>
        RegExp(r'\b' +
            className +
            r'\s+\w+'), // Variable declaration: ClassName variable
        RegExp(r'extends\s+' +
            className +
            r'\b'), // Inheritance: extends ClassName
        RegExp(r'implements\s+' +
            className +
            r'\b'), // Interface: implements ClassName
        RegExp(r'with\s+' + className + r'\b'), // Mixin: with ClassName
        RegExp(r'case\s+' +
            className +
            r'\.'), // Enum access: case ClassName.value
        RegExp(r'home:\s*' +
            className +
            r'\s*\('), // Flutter route: home: ClassName()
        RegExp(r'builder:\s*.*' + className + r'\s*\('), // Builder pattern
      ];

      // Check if any pattern matches
      for (final pattern in usagePatterns) {
        if (pattern.hasMatch(content)) {
          usedFiles.add(filePath);
          Logger.debug(
              'Detected usage of $className in ${path.basename(filePath)}');
          break; // Found usage, no need to check other patterns
        }
      }
    }

    return usedFiles;
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

    // Primary Flutter app entry point (project root)
    final rootMainFile = path.join(projectPath, 'main.dart');
    if (await File(rootMainFile).exists()) {
      entryPoints.add(PatternMatcher.normalizePath(rootMainFile));
      Logger.debug('Found Flutter app entry point: $rootMainFile');
    }

    // Package main entry point (lib/main.dart)
    final libMainFile = path.join(projectPath, 'lib', 'main.dart');
    if (await File(libMainFile).exists()) {
      entryPoints.add(PatternMatcher.normalizePath(libMainFile));
      Logger.debug('Found package main entry point: $libMainFile');
    }

    // Look for any main.dart files in subdirectories
    final libDir = Directory(path.join(projectPath, 'lib'));
    if (await libDir.exists()) {
      await for (final file in libDir.list(recursive: true)) {
        if (file is File && path.basename(file.path) == 'main.dart') {
          final normalizedPath = PatternMatcher.normalizePath(file.path);
          if (!entryPoints.contains(normalizedPath)) {
            entryPoints.add(normalizedPath);
            Logger.debug('Found additional main entry point: ${file.path}');
          }
        }
      }
    }

    // Bin directory executables
    final binDir = Directory(path.join(projectPath, 'bin'));
    if (await binDir.exists()) {
      await for (final file in binDir.list(recursive: true)) {
        if (file.path.endsWith('.dart')) {
          entryPoints.add(PatternMatcher.normalizePath(file.path));
          Logger.debug('Found bin entry point: ${file.path}');
        }
      }
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
        if (file.path.endsWith('.dart') &&
            (path.basename(file.path) == 'main.dart' ||
                file.path.contains('${path.separator}lib${path.separator}'))) {
          entryPoints.add(PatternMatcher.normalizePath(file.path));
          Logger.debug('Found example entry point: ${file.path}');
        }
      }
    }

    if (entryPoints.isEmpty) {
      Logger.warning(
          '⚠️ No entry points found! This might cause all files to be marked as unused.');
    } else {
      Logger.info('✅ Found ${entryPoints.length} entry points');
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
