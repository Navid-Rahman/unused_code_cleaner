/// Comprehensive test suite for the Unused Code Cleaner package.
///
/// Tests all major functionality including:
/// - Asset analysis and detection
/// - Function analysis and detection
/// - Package dependency analysis
/// - File usage analysis
/// - Model behavior and calculations
/// - Utility functions

import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;
import 'package:unused_code_cleaner/src/utils/file_utils.dart';
import 'package:unused_code_cleaner/unused_code_cleaner.dart';

void main() {
  /// Main test group for UnusedCodeCleaner functionality.
  /// Creates a temporary test project and validates all analysis capabilities.
  group('UnusedCodeCleaner', () {
    late Directory testDir;
    late UnusedCodeCleaner cleaner;

    setUp(() async {
      // Create temporary test directory with realistic project structure
      testDir = await Directory.systemTemp.createTemp('test_project');
      cleaner = UnusedCodeCleaner();

      // Set up complete test project with used and unused items
      await _createTestProject(testDir);
    });

    tearDown(() async {
      // Clean up temporary test directory and all created files
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    /// Verifies that the cleaner can be instantiated without errors.
    test('should initialize correctly', () {
      expect(cleaner, isNotNull);
    });

    /// Tests project structure validation for valid Dart projects.
    test('should validate project structure', () async {
      final options = CleanupOptions(verbose: true);

      expect(() => cleaner.analyze(testDir.path, options), returnsNormally);
    });

    /// Validates unused asset detection functionality.
    /// Should find unused_image.png and unused_data.json.
    test('should detect unused assets', () async {
      final options = CleanupOptions(
        removeUnusedAssets: false,
        verbose: true,
        interactive: false,
      );

      final result = await cleaner.analyze(testDir.path, options);

      expect(result, isNotNull);
      expect(result.unusedAssets, isNotEmpty);
      expect(result.unusedAssets.any((item) => item.name == 'unused_image.png'),
          isTrue);
    });

    /// Validates unused function detection using AST analysis.
    /// Should find the unusedFunction() that's declared but never called.
    test('should detect unused functions', () async {
      final options = CleanupOptions(
        removeUnusedFunctions: false,
        verbose: true,
        interactive: false,
      );

      final result = await cleaner.analyze(testDir.path, options);

      expect(result, isNotNull);
      expect(result.unusedFunctions, isNotEmpty);
      expect(
          result.unusedFunctions.any((item) => item.name == 'unusedFunction'),
          isTrue);
    });

    /// Validates unused package dependency detection.
    /// Should find unused_package that's in pubspec.yaml but never imported.
    test('should detect unused packages', () async {
      final options = CleanupOptions(
        removeUnusedPackages: false,
        verbose: true,
        interactive: false,
      );

      final result = await cleaner.analyze(testDir.path, options);

      expect(result, isNotNull);
      expect(result.unusedPackages, isNotEmpty);
      expect(result.unusedPackages.any((item) => item.name == 'unused_package'),
          isTrue);
    });

    /// Validates unused file detection by analyzing import statements.
    /// Should find unused_file.dart that's never imported anywhere.
    test('should detect unused files', () async {
      final options = CleanupOptions(
        removeUnusedFiles: false,
        verbose: true,
        interactive: false,
      );

      final result = await cleaner.analyze(testDir.path, options);

      expect(result, isNotNull);
      expect(result.unusedFiles, isNotEmpty);
      expect(result.unusedFiles.any((item) => item.name == 'unused_file.dart'),
          isTrue);
    });

    /// Tests error handling for invalid project structures.
    /// Should throw ProjectValidationException for non-existent directories.
    test('should handle analysis errors gracefully', () async {
      final invalidDir = Directory(path.join(testDir.path, 'invalid'));
      final options = CleanupOptions(verbose: true);

      expect(() => cleaner.analyze(invalidDir.path, options),
          throwsA(isA<ProjectValidationException>()));
    });

    /// Verifies that analysis timing is properly measured and reported.
    test('should measure analysis time', () async {
      final options = CleanupOptions(
        verbose: true,
        interactive: false,
      );

      final result = await cleaner.analyze(testDir.path, options);

      expect(result.analysisTime, greaterThan(Duration.zero));
    });

    /// Validates that the total number of scanned files is correctly counted.
    test('should count scanned files', () async {
      final options = CleanupOptions(
        verbose: true,
        interactive: false,
      );

      final result = await cleaner.analyze(testDir.path, options);

      expect(result.totalScannedFiles, greaterThan(0));
    });
  });

  /// Test group for data model classes and their behavior.
  group('Models', () {
    /// Tests AnalysisResult calculations and aggregation logic.
    test('AnalysisResult should calculate totals correctly', () {
      final result = AnalysisResult(
        unusedAssets: [
          UnusedItem(name: 'asset1', path: 'path1', type: UnusedItemType.asset),
          UnusedItem(name: 'asset2', path: 'path2', type: UnusedItemType.asset),
        ],
        unusedFunctions: [
          UnusedItem(
              name: 'func1', path: 'path3', type: UnusedItemType.function),
        ],
        unusedPackages: [],
        unusedFiles: [],
        analysisTime: Duration(milliseconds: 100),
        totalScannedFiles: 5,
      );

      expect(result.totalUnusedItems, equals(3));
      expect(result.hasUnusedItems, isTrue);
    });

    /// Tests UnusedItem display formatting with proper icons.
    test('UnusedItem should display correct icons', () {
      final assetItem = UnusedItem(
        name: 'test.png',
        path: 'assets/test.png',
        type: UnusedItemType.asset,
      );

      final functionItem = UnusedItem(
        name: 'unusedFunction',
        path: 'lib/test.dart',
        type: UnusedItemType.function,
      );

      expect(assetItem.displayName, contains('🖼️'));
      expect(functionItem.displayName, contains('⚡'));
    });

    /// Validates CleanupOptions default values and initialization.
    test('CleanupOptions should have correct defaults', () {
      const options = CleanupOptions();

      expect(options.removeUnusedAssets, isFalse);
      expect(options.removeUnusedFunctions, isFalse);
      expect(options.removeUnusedPackages, isFalse);
      expect(options.removeUnusedFiles, isFalse);
      expect(options.interactive, isTrue);
      expect(options.verbose, isFalse);
      expect(options.excludePatterns, isEmpty);
      expect(options.includePaths, isEmpty);
    });
  });

  /// Test group for utility functions and helper methods.
  group('FileUtils', () {
    /// Tests file size formatting with various byte values.
    test('should format file sizes correctly', () {
      expect(FileUtils.formatFileSize(500), equals('500B'));
      expect(FileUtils.formatFileSize(1536), equals('1.5KB'));
      expect(FileUtils.formatFileSize(1048576), equals('1.0MB'));
      expect(FileUtils.formatFileSize(1073741824), equals('1.0GB'));
    });
  });
}

/// Creates a realistic test project structure with both used and unused items.
///
/// Sets up:
/// - pubspec.yaml with dependencies (some used, some unused)
/// - Dart files with functions (some called, some not)
/// - Asset files (some referenced, some not)
/// - Directory structure mimicking real Flutter projects
///
/// This creates a controlled environment for testing all analyzer functionality.
Future<void> _createTestProject(Directory testDir) async {
  // Create pubspec.yaml with mixed used/unused dependencies
  final pubspecContent = '''
name: test_project
description: Test project for unused code cleaner
version: 1.0.0

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  http: ^1.0.0           # Used package (imported in main.dart)
  unused_package: ^1.0.0 # Unused package (never imported)

dev_dependencies:
  test: ^1.24.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/used_image.png  # Only specific used asset declared
    - assets/data/used_data.json    # Only specific used data declared
''';

  await File(path.join(testDir.path, 'pubspec.yaml'))
      .writeAsString(pubspecContent);

  // Create lib directory structure
  final libDir = Directory(path.join(testDir.path, 'lib'));
  await libDir.create(recursive: true);

  // Create main.dart with mixed used/unused functions
  final mainContent = '''
import 'package:http/http.dart' as http; // Used import
import 'used_file.dart';                      // Used import

void main() {
  print('Test app');
  usedFunction(); // Function call - marks usedFunction as used
}

void usedFunction() {
  print('This function is used');
}

void unusedFunction() {
  // This function is declared but never called - should be detected as unused
  print('This function is not used');
}
''';

  await File(path.join(libDir.path, 'main.dart')).writeAsString(mainContent);

  // Create used_file.dart (imported and therefore used)
  final usedFileContent = '''
class UsedClass {
  void usedMethod() {
    print('This method is used');
  }
}
''';

  await File(path.join(libDir.path, 'used_file.dart'))
      .writeAsString(usedFileContent);

  // Create unused_file.dart (never imported - should be detected as unused)
  final unusedFileContent = '''
class UnusedClass {
  void unusedMethod() {
    print('This method is not used');
  }
}
''';

  await File(path.join(libDir.path, 'unused_file.dart'))
      .writeAsString(unusedFileContent);

  // Create assets directory structure and files
  final assetsDir = Directory(path.join(testDir.path, 'assets', 'images'));
  await assetsDir.create(recursive: true);

  // Create used image (declared in pubspec.yaml, should not be marked as unused)
  await File(path.join(assetsDir.path, 'used_image.png'))
      .writeAsBytes([1, 2, 3, 4]);

  // Create unused image (not declared in pubspec.yaml, should be detected as unused)
  await File(path.join(assetsDir.path, 'unused_image.png'))
      .writeAsBytes([5, 6, 7, 8]);

  // Create data directory for additional asset types
  final dataDir = Directory(path.join(testDir.path, 'assets', 'data'));
  await dataDir.create(recursive: true);

  // Create used data file (declared in pubspec.yaml)
  await File(path.join(dataDir.path, 'used_data.json'))
      .writeAsString('{"used": "data"}');

  // Create unused data file (not declared in pubspec.yaml, should be detected as unused)
  await File(path.join(dataDir.path, 'unused_data.json'))
      .writeAsString('{"test": "data"}');
}
