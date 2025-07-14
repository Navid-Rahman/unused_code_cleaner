import 'dart:io';
import 'package:path/path.dart' as path;

import 'models/analysis_result.dart';
import 'models/unused_item.dart';
import 'models/cleanup_options.dart';
import 'utils/logger.dart' as logger;
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

    logger.Logger.setVerbose(options.verbose);
    logger.Logger.title('🔍 UNUSED CODE CLEANER - ANALYSIS STARTED');

    try {
      // Validate project structure
      await _validateProject(projectPath);

      // CRITICAL FIX: Find ALL Dart files in project, not just lib/
      // This was causing files outside lib/ to be marked as unused
      final dartFiles = await FileUtils.findDartFiles(projectPath);
      final totalFiles = dartFiles.length;

      logger.Logger.info('Found $totalFiles Dart files to analyze');

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

      // CRITICAL SAFETY VALIDATION: Check if results seem suspicious
      _validateResultsSafety(result);

      // Handle dry-run mode
      if (options.dryRun) {
        logger.Logger.warning(
            '🛑 DRY RUN MODE: No files will be deleted. Review the above results.');
        logger.Logger.info(
            'To actually remove files, run without --dry-run flag.');
        return result;
      }

      if (options.interactive && result.hasUnusedItems) {
        await _handleInteractiveCleanup(result, options);
      }

      return result;
    } catch (e) {
      logger.Logger.error('Analysis failed: $e');
      rethrow;
    }
  }

  /// Validates that the target directory contains a valid Dart/Flutter project.
  ///
  /// Checks for required files and directories:
  /// - pubspec.yaml (project configuration)
  /// - lib/ directory (main source code)
  ///
  /// Safety checks:
  /// - Prevents analysis of the unused_code_cleaner package itself
  /// - Validates project structure
  Future<void> _validateProject(String projectPath) async {
    // CRITICAL SAFETY CHECK: Check system paths FIRST before checking pubspec.yaml
    final resolvedPath = path.normalize(path.absolute(projectPath));
    final systemPaths = [
      path.join(Platform.environment['USERPROFILE'] ?? '', 'Documents'),
      path.join(Platform.environment['USERPROFILE'] ?? '', 'Desktop'),
      'C:\\',
      'C:\\Windows',
      'C:\\Program Files',
      'C:\\Program Files (x86)',
      'C:\\Users',
    ];

    for (final systemPath in systemPaths) {
      if (resolvedPath == path.normalize(path.absolute(systemPath))) {
        throw ProjectValidationException(
            'Cannot analyze system directory: $resolvedPath');
      }
    }

    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) {
      throw ProjectValidationException(
          'pubspec.yaml not found in $projectPath');
    }

    // Critical safety check: prevent analyzing ourselves
    final pubspecContent = await pubspecFile.readAsString();
    if (pubspecContent.contains('name: unused_code_cleaner')) {
      throw ProjectValidationException(
          'Cannot analyze unused_code_cleaner package itself for safety reasons');
    }

    final libDir = Directory(path.join(projectPath, 'lib'));
    if (!await libDir.exists()) {
      throw ProjectValidationException(
          'lib directory not found in $projectPath');
    }

    logger.Logger.success('Project structure validated');
  }

  /// Analyzes asset files to find unused resources declared in pubspec.yaml.
  Future<List<UnusedItem>> _analyzeAssets(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    logger.Logger.section('📦 ANALYZING ASSETS');
    return await _assetAnalyzer.analyze(projectPath, dartFiles, options);
  }

  /// Analyzes function and method declarations to find unused code.
  Future<List<UnusedItem>> _analyzeFunctions(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    logger.Logger.section('⚡ ANALYZING FUNCTIONS');
    return await _functionAnalyzer.analyze(projectPath, dartFiles, options);
  }

  /// Analyzes package dependencies to find unused imports in pubspec.yaml.
  Future<List<UnusedItem>> _analyzePackages(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    logger.Logger.section('📦 ANALYZING PACKAGES');
    return await _packageAnalyzer.analyze(projectPath, dartFiles, options);
  }

  /// Analyzes Dart files to find unreferenced source files.
  Future<List<UnusedItem>> _analyzeFiles(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    logger.Logger.section('📄 ANALYZING FILES');
    return await _fileAnalyzer.analyze(projectPath, dartFiles, options);
  }

  /// Displays comprehensive analysis results in a formatted output.
  ///
  /// Shows timing information, file counts, and detailed breakdowns
  /// of each type of unused item found during analysis.
  void _displayResults(AnalysisResult result) {
    logger.Logger.title('📊 ANALYSIS RESULTS');

    logger.Logger.info(
        'Analysis completed in ${result.analysisTime.inMilliseconds}ms');
    logger.Logger.info('Total files scanned: ${result.totalScannedFiles}');
    logger.Logger.info('Total unused items found: ${result.totalUnusedItems}');

    if (!result.hasUnusedItems) {
      logger.Logger.success('🎉 No unused items found! Your project is clean.');
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

    logger.Logger.section('$title (${items.length} items)');

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

    logger.Logger.table(tableData);
  }

  /// Orchestrates interactive cleanup process for all unused item categories.
  ///
  /// Processes each category of unused items according to cleanup options,
  /// prompting user for confirmation when in interactive mode.
  /// Enhanced with additional safety warnings for assets.
  Future<void> _handleInteractiveCleanup(
      AnalysisResult result, CleanupOptions options) async {
    logger.Logger.section('🗑️ CLEANUP OPTIONS');

    if (result.unusedAssets.isNotEmpty && options.removeUnusedAssets) {
      // ENHANCED SAFETY: Warn if too many assets are marked for deletion
      if (result.unusedAssets.length > 10) {
        logger.Logger.warning(
            '⚠️  WARNING: ${result.unusedAssets.length} assets marked for deletion!');
        logger.Logger.warning(
            'This seems unusually high. Please review the list carefully.');
        logger.Logger.warning(
            'Consider running with --dry-run first to verify results.');
        logger.Logger.warning('Assets to be deleted:');
        for (int i = 0; i < result.unusedAssets.length && i < 20; i++) {
          logger.Logger.warning(
              '  ${i + 1}. ${result.unusedAssets[i].name} (${result.unusedAssets[i].path})');
        }
        if (result.unusedAssets.length > 20) {
          logger.Logger.warning(
              '  ... and ${result.unusedAssets.length - 20} more assets');
        }

        stdout.write(
            '❗ Are you SURE you want to proceed? Type "YES DELETE ALL" to confirm: ');
        final megaConfirmation = stdin.readLineSync();
        if (megaConfirmation != 'YES DELETE ALL') {
          logger.Logger.info('Asset deletion cancelled for safety');
          return;
        }
      }

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
      logger.Logger.info('Auto-removing unused $itemType...');

      // CRITICAL SAFETY: Show detailed list before automatic removal
      logger.Logger.warning('⚠️  AUTOMATIC REMOVAL - Review these items:');
      for (final item in items) {
        logger.Logger.warning('  - ${item.name} (${item.path})');
      }

      // Final safety check
      stdout.write(
          '❗ PROCEED WITH AUTOMATIC DELETION? Type "DELETE" to confirm: ');
      final confirmation = stdin.readLineSync();
      if (confirmation != 'DELETE') {
        logger.Logger.info('Automatic removal cancelled for safety');
        return;
      }

      await _removeItems(items, createBackup: options.createBackup);
    } else {
      logger.Logger.warning('Found ${items.length} unused $itemType:');

      // Show detailed list of items to be removed
      for (int i = 0; i < items.length && i < 10; i++) {
        logger.Logger.warning(
            '  ${i + 1}. ${items[i].name} (${items[i].path})');
      }
      if (items.length > 10) {
        logger.Logger.warning('  ... and ${items.length - 10} more items');
      }

      stdout.write('❗ Do you want to remove these $itemType? (y/N): ');
      final input = stdin.readLineSync()?.toLowerCase();

      if (input == 'y' || input == 'yes') {
        // Double confirmation for files/assets
        if (itemType == 'files' || itemType == 'assets') {
          stdout.write(
              '⚠️  This will permanently DELETE files. Type "DELETE" to confirm: ');
          final confirmation = stdin.readLineSync();
          if (confirmation != 'DELETE') {
            logger.Logger.info('File deletion cancelled for safety');
            return;
          }
        }
        await _removeItems(items, createBackup: options.createBackup);
      } else {
        logger.Logger.info('Skipping removal of unused $itemType');
      }
    }
  }

  /// Removes a list of unused items from the project.
  ///
  /// Dispatches to appropriate removal methods based on item type:
  /// - Assets/Files: Physical file deletion with optional backup
  /// - Functions: AST-based code removal from source files
  /// - Packages: Removal from pubspec.yaml with dependency updates
  ///
  /// Tracks removal statistics and reports freed disk space.
  /// Enhanced with backup functionality for safety.
  Future<void> _removeItems(List<UnusedItem> items,
      {bool createBackup = true}) async {
    int removedCount = 0;
    int totalSize = 0;
    Directory? backupDir;

    // Create backup directory if requested
    if (createBackup &&
        items.any((item) =>
            item.type == UnusedItemType.asset ||
            item.type == UnusedItemType.file)) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      backupDir = Directory('unused_code_cleaner_backup_$timestamp');
      await backupDir.create();
      logger.Logger.info('📦 Created backup directory: ${backupDir.path}');
    }

    for (final item in items) {
      try {
        switch (item.type) {
          case UnusedItemType.asset:
          case UnusedItemType.file:
            final file = File(item.path);
            if (await file.exists()) {
              // Create backup if requested
              if (backupDir != null) {
                final relativePath =
                    path.relative(item.path, from: Directory.current.path);
                final backupPath = path.join(backupDir.path, relativePath);
                final backupFile = File(backupPath);
                await backupFile.create(recursive: true);
                await file.copy(backupFile.path);
                logger.Logger.debug(
                    'Backed up: ${item.path} -> ${backupFile.path}');
              }

              if (await FileUtils.deleteFile(item.path)) {
                removedCount++;
                totalSize += item.size ?? 0;
                logger.Logger.debug('Removed: ${item.path}');
              }
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
        logger.Logger.error('Failed to remove ${item.name}: $e');
      }
    }

    logger.Logger.success('Removed $removedCount items');
    if (totalSize > 0) {
      logger.Logger.success(
          'Freed up ${FileUtils.formatFileSize(totalSize)} of disk space');
    }

    if (backupDir != null && removedCount > 0) {
      logger.Logger.info('📦 Backup created at: ${backupDir.path}');
      logger.Logger.info(
          '💡 You can restore deleted files from the backup if needed');
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
        logger.Logger.warning('File not found: ${item.path}');
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
        logger.Logger.success(
            'Removed function ${item.name} from ${item.path}');
      } else {
        logger.Logger.warning(
            'Could not locate function ${item.name} in ${item.path}');
      }
    } catch (e) {
      logger.Logger.error('Failed to remove function ${item.name}: $e');
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
        logger.Logger.warning('pubspec.yaml not found at: $pubspecPath');
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
            logger.Logger.debug('Found package to remove: $trimmedLine');

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
        logger.Logger.success('Removed package ${item.name} from pubspec.yaml');

        // Run pub get to update dependencies
        logger.Logger.info('Running pub get to update dependencies...');
        final result = await Process.run(
          'dart',
          ['pub', 'get'],
          workingDirectory: path.dirname(pubspecPath),
        );

        if (result.exitCode == 0) {
          logger.Logger.success('Dependencies updated successfully');
        } else {
          logger.Logger.warning('pub get failed: ${result.stderr}');
        }
      } else {
        logger.Logger.warning('Package ${item.name} not found in pubspec.yaml');
      }
    } catch (e) {
      logger.Logger.error('Failed to remove package ${item.name}: $e');
    }
  }

  /// CRITICAL SAFETY: Validates analysis results to prevent mass deletion
  void _validateResultsSafety(AnalysisResult result) {
    final totalUnused = result.totalUnusedItems;
    final totalScanned = result.totalScannedFiles;

    // Check for suspiciously high deletion rates
    bool suspicious = false;
    final warnings = <String>[];

    if (result.unusedAssets.length > 20) {
      suspicious = true;
      warnings.add('${result.unusedAssets.length} assets marked for deletion');
    }

    if (result.unusedFiles.length > 10) {
      suspicious = true;
      warnings
          .add('${result.unusedFiles.length} Dart files marked for deletion');
    }

    if (result.unusedPackages.length > 5) {
      suspicious = true;
      warnings
          .add('${result.unusedPackages.length} packages marked for deletion');
    }

    if (totalScanned > 0 && (totalUnused / totalScanned) > 0.3) {
      suspicious = true;
      warnings.add(
          '${((totalUnused / totalScanned) * 100).round()}% of all scanned items marked for deletion');
    }

    if (suspicious) {
      logger.Logger.warning('🚨 CRITICAL SAFETY WARNING:');
      logger.Logger.warning('');
      for (final warning in warnings) {
        logger.Logger.warning('  • $warning');
      }
      logger.Logger.warning('');
      logger.Logger.warning(
          'This seems EXTREMELY high and may indicate an analysis error.');
      logger.Logger.warning('');
      logger.Logger.warning('⚠️  STRONG RECOMMENDATIONS:');
      logger.Logger.warning('  1. Use --dry-run mode to preview changes');
      logger.Logger.warning('  2. Review the analysis results carefully');
      logger.Logger.warning(
          '  3. Check if assets/files are referenced dynamically');
      logger.Logger.warning('  4. Verify the project structure is correct');
      logger.Logger.warning(
          '  5. Consider using --exclude patterns for important files');
      logger.Logger.warning('');

      // EXTREME SAFETY: If results are highly suspicious, recommend immediate dry-run
      if (result.unusedAssets.length > 50 || result.unusedFiles.length > 20) {
        logger.Logger.error(
            '🛑 EXTREME CAUTION: Unusually high number of items marked for deletion!');
        logger.Logger.error(
            '🛑 This strongly suggests an analysis bug or misconfiguration.');
        logger.Logger.error(
            '🛑 PLEASE run with --dry-run first and carefully review results!');
      }
    }
  }
}
