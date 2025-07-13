import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/file_utils.dart';
import '../utils/pattern_matcher.dart';
import '../models/cleanup_options.dart';

/// Analyzes asset files to identify unused assets within a Flutter/Dart project.
///
/// This analyzer examines asset declarations in pubspec.yaml, scans for asset
/// references in Dart code, and identifies assets that are declared but never used.
///
/// CRITICAL SAFETY FEATURES:
/// - Protects assets declared in pubspec.yaml
/// - Comprehensive reference detection (constants, variables, package: URLs)
/// - Path normalization for cross-platform compatibility
/// - Detailed logging for debugging
class AssetAnalyzer {
  /// Analyzes the project to find unused asset files.
  ///
  /// [projectPath] - Root path of the project
  /// [dartFiles] - List of Dart files to scan for asset references
  /// [options] - Cleanup options including exclude patterns
  /// Returns a list of unused items representing unused assets.
  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedAssets = <UnusedItem>[];

    try {
      Logger.info('🔍 Starting asset analysis...');

      // Get declared assets from pubspec.yaml (CRITICAL: These should NEVER be deleted)
      final declaredAssets = await _getDeclaredAssets(projectPath);
      Logger.debug(
          'Found ${declaredAssets.length} declared assets in pubspec.yaml');
      if (declaredAssets.isNotEmpty) {
        Logger.debug('Declared assets: ${declaredAssets.join(', ')}');
      }

      // Get all asset files from project
      final assetFiles = await _getProjectAssets(projectPath);
      Logger.debug(
          'Found ${assetFiles.length} asset files in project directories');

      // Find referenced assets in Dart files and other config files
      final referencedAssets =
          await _findReferencedAssets(dartFiles, projectPath);
      Logger.debug(
          'Found ${referencedAssets.length} referenced assets in code');
      if (options.verbose && referencedAssets.isNotEmpty) {
        Logger.debug('Referenced assets: ${referencedAssets.join(', ')}');
      }

      // Find unused assets with comprehensive safety checks
      for (final assetFile in assetFiles) {
        final relativePath = path.relative(assetFile.path, from: projectPath);
        final normalizedPath = PatternMatcher.normalizePath(relativePath);

        Logger.debug('Analyzing asset: $normalizedPath');

        // SAFETY CHECK 1: Skip excluded patterns
        if (PatternMatcher.isExcluded(
            normalizedPath, options.excludePatterns)) {
          Logger.debug('✅ Skipping excluded asset: $normalizedPath');
          continue;
        }

        // SAFETY CHECK 2: NEVER delete assets declared in pubspec.yaml
        if (_isAssetDeclared(normalizedPath, declaredAssets)) {
          Logger.debug(
              '✅ Protecting declared asset in pubspec.yaml: $normalizedPath');
          continue;
        }

        // SAFETY CHECK 3: Check if asset is referenced in code
        if (_isAssetReferenced(normalizedPath, referencedAssets)) {
          Logger.debug('✅ Asset is referenced in code: $normalizedPath');
          continue;
        }

        // If we reach here, the asset appears to be unused
        final size = await FileUtils.getFileSize(assetFile.path);

        Logger.debug('❌ Marking as unused: $normalizedPath');
        unusedAssets.add(UnusedItem(
          name: path.basename(assetFile.path),
          path: assetFile.path,
          type: UnusedItemType.asset,
          size: size,
          description:
              'Unused asset file (not referenced in code or pubspec.yaml)',
        ));
      }

      // SAFETY WARNING: Alert if too many assets are marked as unused
      if (unusedAssets.length > 10 ||
          (assetFiles.isNotEmpty &&
              unusedAssets.length / assetFiles.length > 0.5)) {
        Logger.warning(
            '⚠️  WARNING: ${unusedAssets.length} out of ${assetFiles.length} assets marked as unused!');
        Logger.warning(
            'This seems unusually high. Please review the analysis carefully.');
        Logger.warning(
            'Consider running with --dry-run first to verify results.');
      }

      Logger.info(
          'Asset analysis complete: ${unusedAssets.length} unused assets found');
      return unusedAssets;
    } catch (e) {
      Logger.error('Asset analysis failed: $e');
      return [];
    }
  }

  /// Gets asset declarations from pubspec.yaml file.
  ///
  /// [projectPath] - Root path of the project
  /// Returns a list of declared asset paths from the pubspec.yaml file.
  Future<List<String>> _getDeclaredAssets(String projectPath) async {
    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));

    if (!await pubspecFile.exists()) {
      Logger.debug('No pubspec.yaml found');
      return [];
    }

    try {
      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content);

      final assets = <String>[];

      if (yaml['flutter'] != null && yaml['flutter']['assets'] != null) {
        final assetList = yaml['flutter']['assets'] as List;
        for (final asset in assetList) {
          final normalizedAsset =
              PatternMatcher.normalizePath(asset.toString());
          assets.add(normalizedAsset);
        }
      }

      return assets;
    } catch (e) {
      Logger.error('Error reading pubspec.yaml: $e');
      return [];
    }
  }

  /// Checks if an asset is declared in pubspec.yaml
  bool _isAssetDeclared(String assetPath, List<String> declaredAssets) {
    final normalizedAssetPath = PatternMatcher.normalizePath(assetPath);

    for (final declared in declaredAssets) {
      final normalizedDeclared = PatternMatcher.normalizePath(declared);

      // Exact match
      if (normalizedAssetPath == normalizedDeclared) {
        return true;
      }

      // Check if the asset is within a declared directory
      if (normalizedDeclared.endsWith('/') &&
          normalizedAssetPath.startsWith(normalizedDeclared)) {
        return true;
      }

      // Check if declared asset is a directory containing this file
      if (!normalizedDeclared.endsWith('/') &&
          normalizedAssetPath.startsWith('$normalizedDeclared/')) {
        return true;
      }
    }

    return false;
  }

  /// Finds all asset files in common asset directories within the project.
  ///
  /// Searches in standard asset directories: assets, images, fonts, data, lib/assets.
  ///
  /// [projectPath] - Root path of the project
  /// Returns a list of all asset files found in the project.
  Future<List<File>> _getProjectAssets(String projectPath) async {
    final assets = <File>[];

    // Common asset directories
    final assetDirs = [
      'assets',
      'images',
      'fonts',
      'data',
      'lib/assets',
    ];

    for (final dirName in assetDirs) {
      final dir = Directory(path.join(projectPath, dirName));
      if (await dir.exists()) {
        final files = await FileUtils.findAssetFiles(dir.path);
        assets.addAll(files);
      }
    }

    return assets;
  }

  /// Scans Dart files to find references to asset files.
  ///
  /// Looks for asset references in various forms: direct paths, AssetImage, Image.asset,
  /// constants, variables, package: URLs, and configuration files.
  ///
  /// [dartFiles] - List of Dart files to scan
  /// [projectPath] - Root path of the project for package name resolution
  /// Returns a set of referenced asset paths found in the code.
  Future<Set<String>> _findReferencedAssets(
      List<File> dartFiles, String projectPath) async {
    final referenced = <String>{};

    // Get package name for package: URL detection
    final packageName = await _getPackageName(projectPath);
    Logger.debug('Project package name: $packageName');

    for (final file in dartFiles) {
      try {
        final content = await file.readAsString();

        // Look for asset references in various forms
        _findAssetReferences(content, referenced, 'assets/');
        _findAssetReferences(content, referenced, 'images/');
        _findAssetReferences(content, referenced, 'fonts/');
        _findAssetReferences(content, referenced, 'data/');

        _findAssetImageReferences(content, referenced);
        _findImageAssetReferences(content, referenced);
        _findPackageReferences(content, referenced, packageName);
        _findConstantReferences(content, referenced);
        _findVariableReferences(content, referenced);
      } catch (e) {
        Logger.debug('Error reading file ${file.path}: $e');
      }
    }

    // Also scan JSON/YAML configuration files for asset references
    await _findConfigFileReferences(projectPath, referenced);

    return referenced;
  }

  /// Gets the package name from pubspec.yaml
  Future<String> _getPackageName(String projectPath) async {
    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
    if (await pubspecFile.exists()) {
      try {
        final content = await pubspecFile.readAsString();
        final yaml = loadYaml(content);
        return yaml['name']?.toString() ?? 'unknown_package';
      } catch (e) {
        Logger.debug('Error reading package name: $e');
      }
    }
    return 'unknown_package';
  }

  /// Scans configuration files (JSON, YAML) for asset references
  Future<void> _findConfigFileReferences(
      String projectPath, Set<String> referenced) async {
    try {
      final configFiles = await FileUtils.findAssetFiles(projectPath);
      for (final configFile in configFiles) {
        if (configFile.path.endsWith('.json') ||
            configFile.path.endsWith('.yaml') ||
            configFile.path.endsWith('.yml')) {
          try {
            final content = await configFile.readAsString();
            _findAssetReferences(content, referenced, 'assets/');
            _findAssetReferences(content, referenced, 'images/');
            _findAssetReferences(content, referenced, 'fonts/');
            _findAssetReferences(content, referenced, 'data/');
          } catch (e) {
            Logger.debug('Error reading config file ${configFile.path}: $e');
          }
        }
      }
    } catch (e) {
      Logger.debug('Error scanning config files: $e');
    }
  }

  /// Helper method to find asset references with a specific prefix.
  /// Enhanced to properly normalize paths and handle various quote types.
  void _findAssetReferences(
      String content, Set<String> referenced, String prefix) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains(prefix)) {
        // Find quoted strings containing the prefix
        for (var quote in ['"', "'"]) {
          final parts = trimmed.split(quote);
          for (int i = 1; i < parts.length; i += 2) {
            if (parts[i].contains(prefix)) {
              referenced.add(PatternMatcher.normalizePath(parts[i]));
            }
          }
        }
      }
    }
  }

  /// Helper method to find AssetImage references.
  /// Enhanced with better parsing and normalization.
  void _findAssetImageReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');
    for (final line in lines) {
      if (line.contains('AssetImage(')) {
        final startIndex = line.indexOf('AssetImage(') + 11;
        final remaining = line.substring(startIndex);
        final firstQuote = remaining.contains('"')
            ? remaining.indexOf('"')
            : remaining.indexOf("'");
        if (firstQuote != -1) {
          final quote = remaining[firstQuote];
          final endQuote = remaining.indexOf(quote, firstQuote + 1);
          if (endQuote != -1) {
            final assetPath = remaining.substring(firstQuote + 1, endQuote);
            referenced.add(PatternMatcher.normalizePath(assetPath));
          }
        }
      }
    }
  }

  /// Helper method to find Image.asset references.
  /// Enhanced with better parsing and normalization.
  void _findImageAssetReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');
    for (final line in lines) {
      if (line.contains('Image.asset(')) {
        final startIndex = line.indexOf('Image.asset(') + 12;
        final remaining = line.substring(startIndex);
        final firstQuote = remaining.contains('"')
            ? remaining.indexOf('"')
            : remaining.indexOf("'");
        if (firstQuote != -1) {
          final quote = remaining[firstQuote];
          final endQuote = remaining.indexOf(quote, firstQuote + 1);
          if (endQuote != -1) {
            final assetPath = remaining.substring(firstQuote + 1, endQuote);
            referenced.add(PatternMatcher.normalizePath(assetPath));
          }
        }
      }
    }
  }

  /// Finds package: URL references (e.g., package:my_app/assets/image.png)
  void _findPackageReferences(
      String content, Set<String> referenced, String packageName) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains('package:$packageName/')) {
        for (var quote in ['"', "'"]) {
          final parts = trimmed.split(quote);
          for (int i = 1; i < parts.length; i += 2) {
            if (parts[i].contains('package:$packageName/')) {
              final assetPath =
                  parts[i].replaceFirst('package:$packageName/', '');
              referenced.add(PatternMatcher.normalizePath(assetPath));
            }
          }
        }
      }
    }
  }

  /// Finds asset references in constant declarations
  void _findConstantReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();

      // Look for constant declarations like: static const String kImage = 'assets/image.png';
      if ((trimmed.startsWith('static const String') ||
              trimmed.startsWith('const String') ||
              trimmed.startsWith('final String')) &&
          trimmed.contains('=')) {
        final parts = trimmed.split('=');
        if (parts.length > 1) {
          final valuePart = parts[1].trim();
          for (var quote in ['"', "'"]) {
            if (valuePart.contains(quote)) {
              final startQuote = valuePart.indexOf(quote) + 1;
              final endQuote = valuePart.indexOf(quote, startQuote);
              if (endQuote != -1) {
                final assetPath = valuePart.substring(startQuote, endQuote);
                if (assetPath.contains('assets/') ||
                    assetPath.contains('images/') ||
                    assetPath.contains('fonts/') ||
                    assetPath.contains('data/')) {
                  referenced.add(PatternMatcher.normalizePath(assetPath));
                }
              }
            }
          }
        }
      }
    }
  }

  /// Finds asset references in variable declarations and assignments
  void _findVariableReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();

      // Look for variable assignments like: String imagePath = 'assets/image.png';
      if ((trimmed.contains('String ') || trimmed.contains('var ')) &&
          trimmed.contains('=')) {
        final parts = trimmed.split('=');
        if (parts.length > 1) {
          final valuePart = parts[1].trim();
          for (var quote in ['"', "'"]) {
            if (valuePart.contains(quote)) {
              final startQuote = valuePart.indexOf(quote) + 1;
              final endQuote = valuePart.indexOf(quote, startQuote);
              if (endQuote != -1) {
                final assetPath = valuePart.substring(startQuote, endQuote);
                if (assetPath.contains('assets/') ||
                    assetPath.contains('images/') ||
                    assetPath.contains('fonts/') ||
                    assetPath.contains('data/')) {
                  referenced.add(PatternMatcher.normalizePath(assetPath));
                }
              }
            }
          }
        }
      }
    }
  }

  /// Checks if an asset file is referenced in the codebase.
  ///
  /// Performs both direct matching and partial matching for folder references.
  /// Enhanced with proper path normalization and comprehensive matching.
  ///
  /// [assetPath] - Path to the asset file to check
  /// [referencedAssets] - Set of all referenced asset paths
  /// Returns true if the asset is referenced, false otherwise.
  bool _isAssetReferenced(String assetPath, Set<String> referencedAssets) {
    final normalizedAssetPath = PatternMatcher.normalizePath(assetPath);

    // Direct match
    if (referencedAssets.contains(normalizedAssetPath)) {
      return true;
    }

    // Check for partial matches with proper normalization
    for (final ref in referencedAssets) {
      final normalizedRef = PatternMatcher.normalizePath(ref);

      // Exact match
      if (normalizedAssetPath == normalizedRef) {
        return true;
      }

      // Check if asset is within a referenced directory
      if (normalizedRef.endsWith('/') &&
          normalizedAssetPath.startsWith(normalizedRef)) {
        return true;
      }

      // Check if reference is a directory containing this asset
      if (!normalizedRef.endsWith('/') &&
          normalizedAssetPath.startsWith('$normalizedRef/')) {
        return true;
      }

      // Check for parent directory references
      if (normalizedAssetPath.startsWith(normalizedRef) &&
          normalizedAssetPath.length > normalizedRef.length) {
        final remaining = normalizedAssetPath.substring(normalizedRef.length);
        if (remaining.startsWith('/')) {
          return true;
        }
      }
    }

    return false;
  }
}
