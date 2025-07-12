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
      // Get declared assets from pubspec.yaml
      final declaredAssets = await _getDeclaredAssets(projectPath);
      Logger.debug('Found ${declaredAssets.length} declared assets');

      // Get all asset files from project
      final assetFiles = await _getProjectAssets(projectPath);
      Logger.debug('Found ${assetFiles.length} asset files in project');

      // Find referenced assets in Dart files
      final referencedAssets = await _findReferencedAssets(dartFiles);
      Logger.debug('Found ${referencedAssets.length} referenced assets');

      // Find unused assets
      for (final assetFile in assetFiles) {
        final relativePath = path.relative(assetFile.path, from: projectPath);

        // Skip excluded patterns
        if (PatternMatcher.isExcluded(relativePath, options.excludePatterns)) {
          continue;
        }

        if (!_isAssetReferenced(relativePath, referencedAssets)) {
          final size = await FileUtils.getFileSize(assetFile.path);

          unusedAssets.add(UnusedItem(
            name: path.basename(assetFile.path),
            path: assetFile.path,
            type: UnusedItemType.asset,
            size: size,
            description: 'Unused asset file',
          ));
        }
      }

      Logger.info('Found ${unusedAssets.length} unused assets');
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
    final content = await pubspecFile.readAsString();
    final yaml = loadYaml(content);

    final assets = <String>[];

    if (yaml['flutter'] != null && yaml['flutter']['assets'] != null) {
      final assetList = yaml['flutter']['assets'] as List;
      for (final asset in assetList) {
        assets.add(asset.toString());
      }
    }

    return assets;
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
  /// Looks for asset references in various forms: direct paths, AssetImage, Image.asset.
  ///
  /// [dartFiles] - List of Dart files to scan
  /// Returns a set of referenced asset paths found in the code.
  Future<Set<String>> _findReferencedAssets(List<File> dartFiles) async {
    final referenced = <String>{};

    for (final file in dartFiles) {
      try {
        final content = await file.readAsString();

        // Look for asset references using simple string search
        _findAssetReferences(content, referenced, 'assets/');
        _findAssetReferences(content, referenced, 'images/');
        _findAssetReferences(content, referenced, 'fonts/');
        _findAssetImageReferences(content, referenced);
        _findImageAssetReferences(content, referenced);
      } catch (e) {
        Logger.debug('Error reading file ${file.path}: $e');
      }
    }

    return referenced;
  }

  /// Helper method to find asset references with a specific prefix.
  void _findAssetReferences(
      String content, Set<String> referenced, String prefix) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains(prefix)) {
        // Find quoted strings containing the prefix
        final parts = trimmed.split('"');
        for (final part in parts) {
          if (part.contains(prefix)) {
            referenced.add(part);
          }
        }
        // Also check single quotes
        final singleParts = trimmed.split("'");
        for (final part in singleParts) {
          if (part.contains(prefix)) {
            referenced.add(part);
          }
        }
      }
    }
  }

  /// Helper method to find AssetImage references.
  void _findAssetImageReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');
    for (final line in lines) {
      if (line.contains('AssetImage(')) {
        final startIndex =
            line.indexOf('AssetImage(') + 11; // Length of 'AssetImage('
        final remaining = line.substring(startIndex);
        final firstQuote = remaining.indexOf('"') == -1
            ? remaining.indexOf("'")
            : remaining.indexOf('"');
        if (firstQuote != -1) {
          final quote = remaining[firstQuote];
          final endQuote = remaining.indexOf(quote, firstQuote + 1);
          if (endQuote != -1) {
            final assetPath = remaining.substring(firstQuote + 1, endQuote);
            referenced.add(assetPath);
          }
        }
      }
    }
  }

  /// Helper method to find Image.asset references.
  void _findImageAssetReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');
    for (final line in lines) {
      if (line.contains('Image.asset(')) {
        final startIndex =
            line.indexOf('Image.asset(') + 12; // Length of 'Image.asset('
        final remaining = line.substring(startIndex);
        final firstQuote = remaining.indexOf('"') == -1
            ? remaining.indexOf("'")
            : remaining.indexOf('"');
        if (firstQuote != -1) {
          final quote = remaining[firstQuote];
          final endQuote = remaining.indexOf(quote, firstQuote + 1);
          if (endQuote != -1) {
            final assetPath = remaining.substring(firstQuote + 1, endQuote);
            referenced.add(assetPath);
          }
        }
      }
    }
  }

  /// Checks if an asset file is referenced in the codebase.
  ///
  /// Performs both direct matching and partial matching for folder references.
  ///
  /// [assetPath] - Path to the asset file to check
  /// [referencedAssets] - Set of all referenced asset paths
  /// Returns true if the asset is referenced, false otherwise.
  bool _isAssetReferenced(String assetPath, Set<String> referencedAssets) {
    // Direct match
    if (referencedAssets.contains(assetPath)) return true;

    // Check for partial matches (e.g., folder references)
    for (final ref in referencedAssets) {
      if (assetPath.startsWith(ref) || ref.startsWith(assetPath)) {
        return true;
      }
    }

    return false;
  }
}
