import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;
import 'package:unused_code_cleaner/src/cleaner.dart';
import 'package:unused_code_cleaner/src/models/cleanup_options.dart';
import 'package:unused_code_cleaner/src/exceptions.dart';
import 'package:unused_code_cleaner/src/utils/pattern_matcher.dart';

void main() {
  group('Critical Safety Tests', () {
    late Directory tempDir;
    late String tempPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('safety_test_');
      tempPath = tempDir.path;
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('prevents self-analysis', () async {
      // Create a mock unused_code_cleaner project
      final pubspecFile = File(path.join(tempPath, 'pubspec.yaml'));
      await pubspecFile.writeAsString('''
name: unused_code_cleaner
description: Test package
version: 1.0.0
environment:
  sdk: ^3.0.0
''');

      final libDir = Directory(path.join(tempPath, 'lib'));
      await libDir.create();

      final cleaner = UnusedCodeCleaner();
      final options = CleanupOptions(
        interactive: false,
        removeUnusedAssets: false,
        removeUnusedFiles: false,
        removeUnusedFunctions: false,
        removeUnusedPackages: false,
      );

      expect(
        () => cleaner.analyze(tempPath, options),
        throwsA(isA<ProjectValidationException>()),
      );
    });

    test('excludes dangerous patterns by default', () {
      final dangerousPaths = [
        '.git/config',
        '.dart_tool/package_config.json',
        'build/app.js',
        'test.g.dart',
      ];

      for (final path in dangerousPaths) {
        expect(
          PatternMatcher.isExcluded(path, []),
          isTrue,
          reason: 'Should exclude: $path',
        );
      }
    });

    test('allows normal project files', () {
      final normalPaths = [
        'lib/main.dart',
        'lib/src/utils.dart',
        'test/widget_test.dart',
        'pubspec.yaml',
      ];

      for (final path in normalPaths) {
        expect(
          PatternMatcher.isExcluded(path, []),
          isFalse,
          reason: 'Should NOT exclude: $path',
        );
      }
    });
  });
}
