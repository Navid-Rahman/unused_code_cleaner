import 'dart:io';
import 'package:path/path.dart' as path;

import 'models/analysis_result.dart';
import 'models/unused_item.dart';
import 'models/cleanup_options.dart';
import 'utils/logger.dart';
import 'utils/file_utils.dart';
import 'analyzers/asset_analyzer.dart';
import 'analyzers/function_analyzer.dart';
import 'analyzers/package_analyzer.dart';
import 'analyzers/file_analyzer.dart';
import 'exceptions.dart';

/// Main orchestrator class for unused code analysis and cleanup operations.
///
/// This class coordinates multiple specialized analyzers to identify unused:
/// - Assets (images, fonts, other files referenced in pubspec.yaml)
/// - Functions and methods (declared but never called)
/// - Package dependencies (imported but not used)
/// - Dart files (not imported anywhere)
///
/// Provides both analysis-only and interactive cleanup capabilities.
class UnusedCodeCleaner {
  late final AssetAnalyzer _assetAnalyzer;
  late final FunctionAnalyzer _functionAnalyzer;
  late final PackageAnalyzer _packageAnalyzer;
  late final FileAnalyzer _fileAnalyzer;

  /// Initializes all analyzer components.
  UnusedCodeCleaner() {
    _assetAnalyzer = AssetAnalyzer();
    _functionAnalyzer = FunctionAnalyzer();
    _packageAnalyzer = PackageAnalyzer();
    _fileAnalyzer = FileAnalyzer();
  }

  /// Performs comprehensive analysis of a Dart project to identify unused code.
  ///
  /// Orchestrates multiple analysis phases:
  /// 1. Project structure validation
  /// 2. Dart file discovery and indexing
  /// 3. Parallel analysis of assets, functions, packages, and files
  /// 4. Result compilation and reporting
  /// 5. Optional interactive cleanup
  ///
  /// Returns detailed [AnalysisResult] with findings and timing information.
  Future<AnalysisResult> analyze(
      String projectPath, CleanupOptions options) async {
    final stopwatch = Stopwatch()..start();

    Logger.setVerbose(options.verbose);
    Logger.title('🔍 UNUSED CODE CLEANER - ANALYSIS STARTED');

    try {
      // Validate project structure
      await _validateProject(projectPath);

      final dartFiles =
          await FileUtils.findDartFiles(path.join(projectPath, 'lib'));
      final totalFiles = dartFiles.length;

      Logger.info('Found $totalFiles Dart files to analyze');

      // Perform analysis
      final unusedAssets =
          await _analyzeAssets(projectPath, dartFiles, options);
      final unusedFunctions =
          await _analyzeFunctions(projectPath, dartFiles, options);
      final unusedPackages =
          await _analyzePackages(projectPath, dartFiles, options);
      final unusedFiles = await _analyzeFiles(projectPath, dartFiles, options);

      stopwatch.stop();

      final result = AnalysisResult(
        unusedAssets: unusedAssets,
        unusedFunctions: unusedFunctions,
        unusedPackages: unusedPackages,
        unusedFiles: unusedFiles,
        analysisTime: stopwatch.elapsed,
        totalScannedFiles: totalFiles,
      );

      _displayResults(result);

      if (options.interactive && result.hasUnusedItems) {
        await _handleInteractiveCleanup(result, options);
      }

      return result;
    } catch (e) {
      Logger.error('Analysis failed: $e');
      rethrow;
    }
  }

  /// Validates that the target directory contains a valid Dart/Flutter project.
  ///
  /// Checks for required files and directories:
  /// - pubspec.yaml (project configuration)
  /// - lib/ directory (main source code)
  Future<void> _validateProject(String projectPath) async {
    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) {
      throw ProjectValidationException(
          'pubspec.yaml not found in $projectPath');
    }

    final libDir = Directory(path.join(projectPath, 'lib'));
    if (!await libDir.exists()) {
      throw ProjectValidationException(
          'lib directory not found in $projectPath');
    }

    Logger.success('Project structure validated');
  }

  /// Analyzes asset files to find unused resources declared in pubspec.yaml.
  Future<List<UnusedItem>> _analyzeAssets(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    Logger.section('📦 ANALYZING ASSETS');
    return await _assetAnalyzer.analyze(projectPath, dartFiles, options);
  }

  /// Analyzes function and method declarations to find unused code.
  Future<List<UnusedItem>> _analyzeFunctions(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    Logger.section('⚡ ANALYZING FUNCTIONS');
    return await _functionAnalyzer.analyze(projectPath, dartFiles, options);
  }

  /// Analyzes package dependencies to find unused imports in pubspec.yaml.
  Future<List<UnusedItem>> _analyzePackages(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    Logger.section('📦 ANALYZING PACKAGES');
    return await _packageAnalyzer.analyze(projectPath, dartFiles, options);
  }

  /// Analyzes Dart files to find unreferenced source files.
  Future<List<UnusedItem>> _analyzeFiles(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    Logger.section('📄 ANALYZING FILES');
    return await _fileAnalyzer.analyze(projectPath, dartFiles, options);
  }

  /// Displays comprehensive analysis results in a formatted output.
  ///
  /// Shows timing information, file counts, and detailed breakdowns
  /// of each type of unused item found during analysis.
  void _displayResults(AnalysisResult result) {
    Logger.title('📊 ANALYSIS RESULTS');

    Logger.info(
        'Analysis completed in ${result.analysisTime.inMilliseconds}ms');
    Logger.info('Total files scanned: ${result.totalScannedFiles}');
    Logger.info('Total unused items found: ${result.totalUnusedItems}');

    if (!result.hasUnusedItems) {
      Logger.success('🎉 No unused items found! Your project is clean.');
      return;
    }

    _displayUnusedItems('Unused Assets', result.unusedAssets);
    _displayUnusedItems('Unused Functions', result.unusedFunctions);
    _displayUnusedItems('Unused Packages', result.unusedPackages);
    _displayUnusedItems('Unused Files', result.unusedFiles);
  }

  /// Displays a formatted table of unused items for a specific category.
  ///
  /// Creates a table with columns for name, path, size, and description.
  /// Truncates long paths for better readability in terminal output.
  void _displayUnusedItems(String title, List<UnusedItem> items) {
    if (items.isEmpty) return;

    Logger.section('$title (${items.length} items)');

    final tableData = [
      ['Name', 'Path', 'Size', 'Description']
    ];

    for (final item in items) {
      tableData.add([
        item.displayName,
        item.path.length > 50
            ? '...${item.path.substring(item.path.length - 47)}'
            : item.path,
        item.size != null ? FileUtils.formatFileSize(item.size!) : 'N/A',
        item.description ?? 'No description'
      ]);
    }

    Logger.table(tableData);
  }

  /// Orchestrates interactive cleanup process for all unused item categories.
  ///
  /// Processes each category of unused items according to cleanup options,
  /// prompting user for confirmation when in interactive mode.
  Future<void> _handleInteractiveCleanup(
      AnalysisResult result, CleanupOptions options) async {
    Logger.section('🗑️ CLEANUP OPTIONS');

    if (result.unusedAssets.isNotEmpty && options.removeUnusedAssets) {
      await _handleItemCleanup('assets', result.unusedAssets, options);
    }

    if (result.unusedFunctions.isNotEmpty && options.removeUnusedFunctions) {
      await _handleItemCleanup('functions', result.unusedFunctions, options);
    }

    if (result.unusedPackages.isNotEmpty && options.removeUnusedPackages) {
      await _handleItemCleanup('packages', result.unusedPackages, options);
    }

    if (result.unusedFiles.isNotEmpty && options.removeUnusedFiles) {
      await _handleItemCleanup('files', result.unusedFiles, options);
    }
  }

  /// Handles cleanup for a specific category of unused items.
  ///
  /// In interactive mode, prompts user for confirmation before removal.
  /// In automatic mode, proceeds with removal immediately.
  /// Respects cleanup options for each item type.
  Future<void> _handleItemCleanup(
      String itemType, List<UnusedItem> items, CleanupOptions options) async {
    if (!options.interactive) {
      Logger.info('Auto-removing unused $itemType...');
      await _removeItems(items);
    } else {
      Logger.warning('Found ${items.length} unused $itemType');
      stdout.write('Do you want to remove them? (y/N): ');
      final input = stdin.readLineSync()?.toLowerCase();

      if (input == 'y' || input == 'yes') {
        await _removeItems(items);
      } else {
        Logger.info('Skipping removal of unused $itemType');
      }
    }
  }

  /// Removes a list of unused items from the project.
  ///
  /// Dispatches to appropriate removal methods based on item type:
  /// - Assets/Files: Physical file deletion
  /// - Functions: AST-based code removal from source files
  /// - Packages: Removal from pubspec.yaml with dependency updates
  ///
  /// Tracks removal statistics and reports freed disk space.
  Future<void> _removeItems(List<UnusedItem> items) async {
    int removedCount = 0;
    int totalSize = 0;

    for (final item in items) {
      try {
        switch (item.type) {
          case UnusedItemType.asset:
          case UnusedItemType.file:
            if (await FileUtils.deleteFile(item.path)) {
              removedCount++;
              totalSize += item.size ?? 0;
              Logger.debug('Removed: ${item.path}');
            }
            break;
          case UnusedItemType.function:
            await _removeFunctionFromFile(item);
            removedCount++;
            break;
          case UnusedItemType.package:
            await _removePackageFromPubspec(item);
            removedCount++;
            break;
        }
      } catch (e) {
        Logger.error('Failed to remove ${item.name}: $e');
      }
    }

    Logger.success('Removed $removedCount items');
    if (totalSize > 0) {
      Logger.success(
          'Freed up ${FileUtils.formatFileSize(totalSize)} of disk space');
    }
  }

  /// Removes an unused function or method from its source file.
  ///
  /// Uses string-based parsing to locate function boundaries:
  /// 1. Searches for function declaration by name and signature
  /// 2. Uses brace counting to determine function scope
  /// 3. Removes function code including trailing empty lines
  /// 4. Preserves file formatting and structure
  ///
  /// Handles various function types: regular, async, getters, setters.
  Future<void> _removeFunctionFromFile(UnusedItem item) async {
    try {
      final file = File(item.path);
      if (!await file.exists()) {
        Logger.warning('File not found: ${item.path}');
        return;
      }

      final content = await file.readAsString();
      final lines = content.split('\n');

      // Find the function declaration line
      int? functionStartLine;
      int? functionEndLine;
      int braceCount = 0;
      bool inFunction = false;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();

        // Look for function declaration
        if (!inFunction &&
            (line.contains('${item.name}(') ||
                line.contains('${item.name} ('))) {
          // Check if this is actually a function declaration
          if (line.contains('void ') ||
              line.contains('Future<') ||
              line.contains('String ') ||
              line.contains('int ') ||
              line.contains('bool ') ||
              line.contains('double ') ||
              line.contains('List<') ||
              line.contains('Map<') ||
              !line.contains('=')) {
            // Not a variable assignment
            functionStartLine = i;
            inFunction = true;

            // Count opening braces on the same line
            braceCount =
                '{'.allMatches(line).length - '}'.allMatches(line).length;

            // If function is on single line or ends immediately
            if (braceCount == 0 &&
                (line.endsWith(';') || line.endsWith('=>'))) {
              functionEndLine = i;
              break;
            }
          }
        }

        if (inFunction) {
          // Count braces to find function end
          braceCount +=
              '{'.allMatches(line).length - '}'.allMatches(line).length;

          if (braceCount == 0 && functionStartLine != null) {
            functionEndLine = i;
            break;
          }
        }
      }

      if (functionStartLine != null && functionEndLine != null) {
        // Remove the function lines (including empty lines before/after if present)
        final newLines = <String>[];

        // Add lines before function
        newLines.addAll(lines.sublist(0, functionStartLine));

        // Skip the function lines
        // Also skip empty lines after the function
        int skipAfter = functionEndLine + 1;
        while (skipAfter < lines.length && lines[skipAfter].trim().isEmpty) {
          skipAfter++;
        }

        // Add lines after function
        if (skipAfter < lines.length) {
          newLines.addAll(lines.sublist(skipAfter));
        }

        // Write the modified content back
        await file.writeAsString(newLines.join('\n'));
        Logger.success('Removed function ${item.name} from ${item.path}');
      } else {
        Logger.warning(
            'Could not locate function ${item.name} in ${item.path}');
      }
    } catch (e) {
      Logger.error('Failed to remove function ${item.name}: $e');
    }
  }

  /// Removes an unused package dependency from pubspec.yaml.
  ///
  /// Performs section-aware parsing to safely remove packages:
  /// 1. Identifies dependencies vs dev_dependencies sections
  /// 2. Locates target package and associated configuration
  /// 3. Handles multi-line package definitions (version constraints)
  /// 4. Updates pubspec.yaml and runs `dart pub get`
  /// 5. Provides detailed logging throughout the process
  ///
  /// Automatically updates dependency lock files after removal.
  Future<void> _removePackageFromPubspec(UnusedItem item) async {
    try {
      final pubspecPath =
          path.join(path.dirname(item.path), '..', '..', 'pubspec.yaml');
      final pubspecFile = File(pubspecPath);

      if (!await pubspecFile.exists()) {
        Logger.warning('pubspec.yaml not found at: $pubspecPath');
        return;
      }

      final content = await pubspecFile.readAsString();
      final lines = content.split('\n');
      final newLines = <String>[];

      bool inDependencies = false;
      bool inDevDependencies = false;
      bool packageRemoved = false;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmedLine = line.trim();

        // Track which section we're in
        if (trimmedLine == 'dependencies:') {
          inDependencies = true;
          inDevDependencies = false;
        } else if (trimmedLine == 'dev_dependencies:') {
          inDependencies = false;
          inDevDependencies = true;
        } else if (trimmedLine.endsWith(':') && !trimmedLine.startsWith(' ')) {
          // Entered a new top-level section
          inDependencies = false;
          inDevDependencies = false;
        }

        // Check if this line contains the package to remove
        bool shouldRemoveLine = false;
        if ((inDependencies || inDevDependencies) && trimmedLine.isNotEmpty) {
          // Check if line starts with the package name followed by ':'
          if (trimmedLine.startsWith('${item.name}:')) {
            shouldRemoveLine = true;
            packageRemoved = true;
            Logger.debug('Found package to remove: $trimmedLine');

            // Also check if the next lines are part of this package definition (multi-line)
            int j = i + 1;
            while (j < lines.length) {
              final nextLine = lines[j];
              final nextTrimmed = nextLine.trim();

              // If next line is more indented and not another package, it's part of this package
              if (nextLine.startsWith('    ') && !nextTrimmed.contains(':')) {
                j++; // Skip this line too
              } else if (nextLine.startsWith('      ')) {
                j++; // Skip even more indented lines (version constraints, etc.)
              } else {
                break;
              }
            }
            i = j - 1; // Update main loop counter
          }
        }

        if (!shouldRemoveLine) {
          newLines.add(line);
        }
      }

      if (packageRemoved) {
        await pubspecFile.writeAsString(newLines.join('\n'));
        Logger.success('Removed package ${item.name} from pubspec.yaml');

        // Run pub get to update dependencies
        Logger.info('Running pub get to update dependencies...');
        final result = await Process.run(
          'dart',
          ['pub', 'get'],
          workingDirectory: path.dirname(pubspecPath),
        );

        if (result.exitCode == 0) {
          Logger.success('Dependencies updated successfully');
        } else {
          Logger.warning('pub get failed: ${result.stderr}');
        }
      } else {
        Logger.warning('Package ${item.name} not found in pubspec.yaml');
      }
    } catch (e) {
      Logger.error('Failed to remove package ${item.name}: $e');
    }
  }
}
