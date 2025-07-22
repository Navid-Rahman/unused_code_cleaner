import 'dart:io';
import 'package:path/path.dart' as path;

import 'models/analysis_result.dart';
import 'models/unused_item.dart';
import 'models/cleanup_options.dart';
import 'utils/logger.dart' as logger;
import 'utils/file_utils.dart';
import 'utils/safe_removal.dart';
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
  AssetAnalyzer? _assetAnalyzer;
  FunctionAnalyzer? _functionAnalyzer;
  PackageAnalyzer? _packageAnalyzer;
  FileAnalyzer? _fileAnalyzer;

  /// Initializes all analyzer components.
  UnusedCodeCleaner();

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

    // Initialize analyzers with project path
    _assetAnalyzer = AssetAnalyzer();
    _functionAnalyzer = FunctionAnalyzer();
    _packageAnalyzer = PackageAnalyzer(projectPath);
    _fileAnalyzer = FileAnalyzer(projectPath);

    try {
      // Validate project structure
      await _validateProject(projectPath);

      // Find ALL Dart files in project
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
        await _handleInteractiveCleanup(result, options, projectPath);
      }

      return result;
    } catch (e) {
      logger.Logger.error('Analysis failed: $e');
      rethrow;
    }
  }

  /// Validates that the target directory contains a valid Dart/Flutter project.
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
    return await _assetAnalyzer!.analyze(projectPath, dartFiles, options);
  }

  /// Analyzes function and method declarations to find unused code.
  Future<List<UnusedItem>> _analyzeFunctions(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    logger.Logger.section('⚡ ANALYZING FUNCTIONS');
    return await _functionAnalyzer!.analyze(projectPath, dartFiles, options);
  }

  /// Analyzes package dependencies to find unused imports in pubspec.yaml.
  Future<List<UnusedItem>> _analyzePackages(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    logger.Logger.section('📦 ANALYZING PACKAGES');
    return await _packageAnalyzer!.analyze(projectPath, dartFiles, options);
  }

  /// Analyzes Dart files to find unreferenced source files.
  Future<List<UnusedItem>> _analyzeFiles(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    logger.Logger.section('📄 ANALYZING FILES');
    return await _fileAnalyzer!.analyze(projectPath, dartFiles, options);
  }

  /// Displays comprehensive analysis results in a formatted output.
  void _displayResults(AnalysisResult result) {
    logger.Logger.title('📊 ANALYSIS RESULTS');

    logger.Logger.info(
        'Analysis completed in ${result.analysisTime.inMilliseconds}ms');
    logger.Logger.info('Total files scanned: ${result.totalScannedFiles}');
    logger.Logger.info('Total unused items found: ${result.totalUnusedItems}');

    if (result.unusedAssets.isNotEmpty) {
      logger.Logger.section(
          'Unused Assets (${result.unusedAssets.length} items)');
      logger.Logger.table([
        ['Name', 'Path', 'Size', 'Description'],
        ...result.unusedAssets.map((item) => [
              item.name,
              item.path,
              item.formattedSize,
              item.safeDescription,
            ]),
      ]);
    }

    if (result.unusedFunctions.isNotEmpty) {
      logger.Logger.section(
          'Unused Functions (${result.unusedFunctions.length} items)');
      logger.Logger.table([
        ['Name', 'Path', 'Line', 'Description'],
        ...result.unusedFunctions.map((item) => [
              item.name,
              item.path,
              item.lineNumber?.toString() ?? 'N/A',
              item.safeDescription,
            ]),
      ]);
    }

    if (result.unusedPackages.isNotEmpty) {
      logger.Logger.section(
          'Unused Packages (${result.unusedPackages.length} items)');
      logger.Logger.table([
        ['Name', 'Path', 'Description'],
        ...result.unusedPackages.map((item) => [
              item.name,
              item.path,
              item.safeDescription,
            ]),
      ]);
    }

    if (result.unusedFiles.isNotEmpty) {
      logger.Logger.section(
          'Unused Files (${result.unusedFiles.length} items)');
      logger.Logger.table([
        ['Name', 'Path', 'Size', 'Description'],
        ...result.unusedFiles.map((item) => [
              item.name,
              item.path,
              item.formattedSize,
              item.safeDescription,
            ]),
      ]);
    }

    // Enhanced comprehensive summary
    _displayComprehensiveSummary(result);

    if (result.totalUnusedItems == 0) {
      logger.Logger.success('🎉 No unused items found! Your project is clean.');
    }
  }

  /// CRITICAL SAFETY VALIDATION: Prevents mass deletion
  void _validateResultsSafety(AnalysisResult result) {
    // ENHANCED SAFETY: If more than 30% of scanned files are marked as unused, warn user
    if (result.totalScannedFiles > 0 &&
        (result.totalUnusedItems / result.totalScannedFiles) > 0.30) {
      logger.Logger.warning(
          '🚨 CRITICAL WARNING: ${result.totalUnusedItems} out of ${result.totalScannedFiles} items marked as unused!');
      logger.Logger.warning(
          'This is ${((result.totalUnusedItems / result.totalScannedFiles) * 100).round()}% of all scanned items.');
      logger.Logger.warning('');
      logger.Logger.warning(
          'This seems EXTREMELY high and likely indicates an analysis error.');
      logger.Logger.warning('');
      logger.Logger.warning('🔍 Analysis Summary:');
      logger.Logger.warning(
          '  • Total files scanned: ${result.totalScannedFiles}');
      logger.Logger.warning('  • Unused assets: ${result.unusedAssets.length}');
      logger.Logger.warning(
          '  • Unused functions: ${result.unusedFunctions.length}');
      logger.Logger.warning(
          '  • Unused packages: ${result.unusedPackages.length}');
      logger.Logger.warning('  • Unused files: ${result.unusedFiles.length}');
      logger.Logger.warning('');
      logger.Logger.warning('🔍 Possible causes:');
      logger.Logger.warning(
          '  • Dynamic references not detected by static analysis');
      logger.Logger.warning(
          '  • Configuration files or build scripts using resources');
      logger.Logger.warning('  • Generated code or external tool dependencies');
      logger.Logger.warning('  • Plugin/platform-specific code not detected');
      logger.Logger.warning('');
      logger.Logger.warning(
          '⚠️  STRONG RECOMMENDATION: Use --dry-run mode first!');
    }
  }

  /// Handles interactive cleanup with enhanced safety using SafeRemoval.
  Future<void> _handleInteractiveCleanup(
      AnalysisResult result, CleanupOptions options, String projectPath) async {
    logger.Logger.section('🗑️ CLEANUP OPTIONS');

    // Use SafeRemoval for enhanced safety
    final safeRemoval = SafeRemoval(projectPath);
    final allUnusedItems = <UnusedItem>[];

    // Collect all items to be removed
    if (result.unusedAssets.isNotEmpty && options.removeUnusedAssets) {
      allUnusedItems.addAll(result.unusedAssets);
    }
    if (result.unusedFunctions.isNotEmpty && options.removeUnusedFunctions) {
      allUnusedItems.addAll(result.unusedFunctions);
    }
    if (result.unusedPackages.isNotEmpty && options.removeUnusedPackages) {
      allUnusedItems.addAll(result.unusedPackages);
    }
    if (result.unusedFiles.isNotEmpty && options.removeUnusedFiles) {
      allUnusedItems.addAll(result.unusedFiles);
    }

    if (allUnusedItems.isEmpty) {
      logger.Logger.info('No unused items to remove');
      return;
    }

    // Enhanced safety warning for large removals
    if (allUnusedItems.length > 10) {
      logger.Logger.warning(
          '⚠️  WARNING: ${allUnusedItems.length} items marked for deletion!');
      logger.Logger.warning(
          'This seems unusually high. Please review the list carefully.');
      logger.Logger.warning(
          'Consider running with --dry-run first to verify results.');

      stdout.write(
          '❗ Are you SURE you want to proceed? Type "YES DELETE ALL" to confirm: ');
      final megaConfirmation = stdin.readLineSync();
      if (megaConfirmation != 'YES DELETE ALL') {
        logger.Logger.info('Cleanup cancelled for safety');
        return;
      }
    } else if (options.interactive) {
      stdout.write(
          'Do you want to remove these ${allUnusedItems.length} unused items? (y/N): ');
      final confirmation = stdin.readLineSync()?.toLowerCase();
      if (confirmation != 'y' && confirmation != 'yes') {
        logger.Logger.info('Cleanup cancelled by user');
        return;
      }
    }

    // Perform safe removal
    try {
      await safeRemoval.removeUnusedItems(allUnusedItems, dryRun: false);
      logger.Logger.success('✅ Cleanup completed successfully');
    } catch (e) {
      logger.Logger.error('Cleanup failed: $e');
      logger.Logger.info('Backup created at: ${safeRemoval.backupPath}');
    }
  }

  /// Displays a comprehensive overview of all 4 core functionality results
  void _displayComprehensiveSummary(AnalysisResult result) {
    logger.Logger.title('📋 COMPREHENSIVE ANALYSIS SUMMARY');

    // Calculate total potential savings
    double totalAssetSize = 0;
    double totalFileSize = 0;

    for (final asset in result.unusedAssets) {
      totalAssetSize += asset.size ?? 0;
    }

    for (final file in result.unusedFiles) {
      totalFileSize += file.size ?? 0;
    }

    final totalSizeBytes = totalAssetSize + totalFileSize;
    final totalSizeMB = totalSizeBytes / (1024 * 1024);

    // Create comprehensive summary table
    final summaryData = [
      ['Category', 'Items Found', 'Status', 'Impact'],
      [
        '📁 Assets',
        '${result.unusedAssets.length}',
        result.unusedAssets.isEmpty ? '✅ Clean' : '⚠️  Issues Found',
        result.unusedAssets.isEmpty
            ? 'No wasted space'
            : '${(totalAssetSize / (1024 * 1024)).toStringAsFixed(2)} MB unused'
      ],
      [
        '⚡ Functions',
        '${result.unusedFunctions.length}',
        result.unusedFunctions.isEmpty ? '✅ Clean' : '⚠️  Issues Found',
        result.unusedFunctions.isEmpty
            ? 'No dead code'
            : '${result.unusedFunctions.length} unused functions'
      ],
      [
        '📦 Packages',
        '${result.unusedPackages.length}',
        result.unusedPackages.isEmpty ? '✅ Clean' : '⚠️  Issues Found',
        result.unusedPackages.isEmpty
            ? 'Dependencies optimized'
            : '${result.unusedPackages.length} unnecessary deps'
      ],
      [
        '🗃️  Files',
        '${result.unusedFiles.length}',
        result.unusedFiles.isEmpty ? '✅ Clean' : '⚠️  Issues Found',
        result.unusedFiles.isEmpty
            ? 'No orphaned files'
            : '${(totalFileSize / (1024 * 1024)).toStringAsFixed(2)} MB orphaned'
      ],
    ];

    logger.Logger.table(summaryData);

    // Overall project health assessment
    final totalIssues = result.totalUnusedItems;
    final healthScore = _calculateHealthScore(result);

    logger.Logger.section('🏥 PROJECT HEALTH ASSESSMENT');

    if (totalIssues == 0) {
      logger.Logger.success('🌟 EXCELLENT: Your project is perfectly clean!');
    } else if (healthScore >= 90) {
      logger.Logger.success(
          '🎯 GREAT: Minimal cleanup needed (Health Score: ${healthScore.toStringAsFixed(1)}%)');
    } else if (healthScore >= 70) {
      logger.Logger.warning(
          '💡 GOOD: Some optimization opportunities (Health Score: ${healthScore.toStringAsFixed(1)}%)');
    } else if (healthScore >= 50) {
      logger.Logger.warning(
          '⚠️  NEEDS ATTENTION: Notable cleanup required (Health Score: ${healthScore.toStringAsFixed(1)}%)');
    } else {
      logger.Logger.error(
          '🚨 CRITICAL: Significant cleanup needed (Health Score: ${healthScore.toStringAsFixed(1)}%)');
    }

    // Potential improvements summary
    if (totalIssues > 0) {
      logger.Logger.section('💰 POTENTIAL IMPROVEMENTS');
      final improvements = <String>[];

      if (result.unusedAssets.isNotEmpty) {
        improvements.add(
            '🗂️  Remove ${result.unusedAssets.length} unused assets → Save ${(totalAssetSize / (1024 * 1024)).toStringAsFixed(2)} MB');
      }

      if (result.unusedFunctions.isNotEmpty) {
        improvements.add(
            '🧹 Clean ${result.unusedFunctions.length} unused functions → Reduce code complexity');
      }

      if (result.unusedPackages.isNotEmpty) {
        improvements.add(
            '📉 Remove ${result.unusedPackages.length} unused packages → Faster builds & smaller app');
      }

      if (result.unusedFiles.isNotEmpty) {
        improvements.add(
            '🗃️  Delete ${result.unusedFiles.length} orphaned files → Save ${(totalFileSize / (1024 * 1024)).toStringAsFixed(2)} MB');
      }

      for (final improvement in improvements) {
        logger.Logger.info('  • $improvement');
      }

      if (totalSizeBytes > 0) {
        logger.Logger.info('');
        logger.Logger.info(
            '💾 Total potential space savings: ${totalSizeMB.toStringAsFixed(2)} MB');
      }
    }

    // Analysis performance summary
    logger.Logger.section('⏱️  ANALYSIS PERFORMANCE');
    logger.Logger.info(
        '📊 Total analysis time: ${result.analysisTime.inMilliseconds}ms');
    logger.Logger.info('📄 Files scanned: ${result.totalScannedFiles}');
    if (result.analysisTime.inSeconds > 0) {
      logger.Logger.info(
          '⚡ Performance: ${(result.totalScannedFiles / result.analysisTime.inSeconds).toStringAsFixed(1)} files/second');
    }

    logger.Logger.info('');
    logger.Logger.info('─' * 50);
  }

  /// Calculates a health score (0-100) based on the analysis results
  double _calculateHealthScore(AnalysisResult result) {
    final totalFiles = result.totalScannedFiles;
    if (totalFiles == 0) return 100.0;

    // Weight different issues differently
    final assetWeight = 0.3;
    final functionWeight = 0.4;
    final packageWeight = 0.2;
    final fileWeight = 0.1;

    // Calculate penalties (normalized by total files to make it relative)
    final assetPenalty =
        (result.unusedAssets.length / totalFiles) * assetWeight * 100;
    final functionPenalty =
        (result.unusedFunctions.length / totalFiles) * functionWeight * 100;
    final packagePenalty = (result.unusedPackages.length / 10) *
        packageWeight *
        100; // Assuming max 10 packages is reasonable
    final filePenalty =
        (result.unusedFiles.length / totalFiles) * fileWeight * 100;

    final totalPenalty =
        assetPenalty + functionPenalty + packagePenalty + filePenalty;
    final healthScore = (100 - totalPenalty).clamp(0.0, 100.0);

    return healthScore;
  }
}
