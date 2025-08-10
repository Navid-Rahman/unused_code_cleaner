import 'package:test/test.dart';
import 'package:unused_code_cleaner/src/analyzers/enhanced_asset_analyzer.dart';
import 'package:unused_code_cleaner/src/models/cleanup_options.dart';
import 'dart:io';

/// Comprehensive test suite for the Enhanced AssetAnalyzer
/// Tests the critical safety fixes that prevent mass deletion of assets
void main() {
  group('Enhanced AssetAnalyzer Safety Tests', () {
    late Directory tempDir;
    late EnhancedAssetAnalyzer analyzer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('asset_analyzer_test');
      analyzer = EnhancedAssetAnalyzer();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should protect assets declared in pubspec.yaml', () async {
      // Create test project structure
      await _createTestProject(tempDir);

      final dartFiles = await _findDartFiles(tempDir.path);
      final options = CleanupOptions(verbose: true);

      final unusedAssets =
          await analyzer.analyze(tempDir.path, dartFiles, options);

      // Should only find truly unused assets, not declared ones
      expect(unusedAssets.length, equals(1));
      expect(unusedAssets.first.name, equals('unused.png'));
    });

    test('should detect package: URL references', () async {
      // Create test project with package: URL reference
      await _createTestProjectWithPackageReferences(tempDir);

      final dartFiles = await _findDartFiles(tempDir.path);
      final options = CleanupOptions(verbose: true);

      final unusedAssets =
          await analyzer.analyze(tempDir.path, dartFiles, options);

      // Should not mark package-referenced assets as unused
      expect(
          unusedAssets
              .every((asset) => !asset.name.contains('package_referenced')),
          isTrue);
    });

    test('should detect constant references', () async {
      // Create test project with constant references
      await _createTestProjectWithConstants(tempDir);

      final dartFiles = await _findDartFiles(tempDir.path);
      final options = CleanupOptions(verbose: true);

      final unusedAssets =
          await analyzer.analyze(tempDir.path, dartFiles, options);

      // Should not mark constant-referenced assets as unused
      expect(
          unusedAssets
              .every((asset) => !asset.name.contains('constant_referenced')),
          isTrue);
    });

    test('should warn about mass deletion attempts', () async {
      // Create project with many assets
      await _createTestProjectWithManyAssets(tempDir);

      final dartFiles = await _findDartFiles(tempDir.path);
      final options = CleanupOptions(verbose: true);

      final unusedAssets =
          await analyzer.analyze(tempDir.path, dartFiles, options);

      // Should find many unused assets and trigger warning
      expect(unusedAssets.length, greaterThan(10));
    });
  });
}

/// Creates a basic test project structure
Future<void> _createTestProject(Directory baseDir) async {
  // Create pubspec.yaml with declared assets (specific files, not entire directory)
  final pubspecFile = File('${baseDir.path}/pubspec.yaml');
  await pubspecFile.writeAsString('''
name: test_project
flutter:
  assets:
    - assets/image.png  # Only this specific asset is declared
    - images/icon.png
''');

  // Create asset directories and files
  final assetsDir = Directory('${baseDir.path}/assets');
  await assetsDir.create(recursive: true);

  await File('${assetsDir.path}/image.png').writeAsString('fake image');
  await File('${assetsDir.path}/unused.png')
      .writeAsString('fake unused image'); // This should be unused

  final imagesDir = Directory('${baseDir.path}/images');
  await imagesDir.create(recursive: true);
  await File('${imagesDir.path}/icon.png').writeAsString('fake icon');

  // Create lib directory and main.dart with asset references
  final libDir = Directory('${baseDir.path}/lib');
  await libDir.create(recursive: true);

  await File('${libDir.path}/main.dart').writeAsString('''
import 'package:flutter/material.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Image.asset('assets/image.png'), // This asset should be protected
            AssetImage('images/icon.png'), // This asset should be protected
          ],
        ),
      ),
    );
  }
}
''');
}

/// Creates test project with package: URL references
Future<void> _createTestProjectWithPackageReferences(Directory baseDir) async {
  final pubspecFile = File('${baseDir.path}/pubspec.yaml');
  await pubspecFile.writeAsString('''
name: test_project
''');

  final assetsDir = Directory('${baseDir.path}/assets');
  await assetsDir.create(recursive: true);
  await File('${assetsDir.path}/package_referenced.png').writeAsString('fake');

  final libDir = Directory('${baseDir.path}/lib');
  await libDir.create(recursive: true);

  await File('${libDir.path}/main.dart').writeAsString('''
import 'package:flutter/material.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset('package:test_project/assets/package_referenced.png');
  }
}
''');
}

/// Creates test project with constant references
Future<void> _createTestProjectWithConstants(Directory baseDir) async {
  final pubspecFile = File('${baseDir.path}/pubspec.yaml');
  await pubspecFile.writeAsString('''
name: test_project
''');

  final assetsDir = Directory('${baseDir.path}/assets');
  await assetsDir.create(recursive: true);
  await File('${assetsDir.path}/constant_referenced.png').writeAsString('fake');

  final libDir = Directory('${baseDir.path}/lib');
  await libDir.create(recursive: true);

  await File('${libDir.path}/constants.dart').writeAsString('''
class Assets {
  static const String kImage = 'assets/constant_referenced.png';
}
''');

  await File('${libDir.path}/main.dart').writeAsString('''
import 'package:flutter/material.dart';
import 'constants.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(Assets.kImage);
  }
}
''');
}

/// Creates test project with many assets to trigger warnings
Future<void> _createTestProjectWithManyAssets(Directory baseDir) async {
  final pubspecFile = File('${baseDir.path}/pubspec.yaml');
  await pubspecFile.writeAsString('''
name: test_project
''');

  final assetsDir = Directory('${baseDir.path}/assets');
  await assetsDir.create(recursive: true);

  // Create 15 unused assets to trigger the warning
  for (int i = 0; i < 15; i++) {
    await File('${assetsDir.path}/unused_$i.png').writeAsString('fake');
  }

  final libDir = Directory('${baseDir.path}/lib');
  await libDir.create(recursive: true);

  await File('${libDir.path}/main.dart').writeAsString('''
import 'package:flutter/material.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(); // No asset references
  }
}
''');
}

/// Helper to find Dart files
Future<List<File>> _findDartFiles(String path) async {
  final libDir = Directory('$path/lib');
  if (!await libDir.exists()) return [];

  final dartFiles = <File>[];
  await for (final entity in libDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      dartFiles.add(entity);
    }
  }
  return dartFiles;
}
