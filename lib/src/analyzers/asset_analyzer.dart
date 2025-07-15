import 'dart:io';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/file_utils.dart';
import '../utils/pattern_matcher.dart';
import '../utils/ast_utils.dart';
import '../models/cleanup_options.dart';

class AssetAnalyzer {
  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedAssets = <UnusedItem>[];

    try {
      Logger.info('🔍 Starting asset analysis...');

      final declaredAssets = await _getDeclaredAssets(projectPath);
      Logger.debug(
          'Found ${declaredAssets.length} declared assets in pubspec.yaml');
      if (declaredAssets.isNotEmpty) {
        Logger.debug('Declared assets: ${declaredAssets.join(', ')}');
      }

      final assetFiles = await _getProjectAssets(projectPath);
      Logger.debug(
          'Found ${assetFiles.length} asset files in project directories');

      final referencedAssets =
          await _findReferencedAssets(dartFiles, projectPath);
      Logger.debug(
          'Found ${referencedAssets.length} referenced assets in code');
      if (options.verbose && referencedAssets.isNotEmpty) {
        Logger.debug('Referenced assets: ${referencedAssets.join(', ')}');
      }

      for (final assetFile in assetFiles) {
        final relativePath = path.relative(assetFile.path, from: projectPath);
        final normalizedPath = PatternMatcher.normalizePath(relativePath);

        Logger.debug('Analyzing asset: $normalizedPath');

        if (PatternMatcher.isExcluded(
            normalizedPath, options.excludePatterns)) {
          Logger.debug('✅ Skipping excluded asset: $normalizedPath');
          continue;
        }

        if (_isAssetDeclared(normalizedPath, declaredAssets)) {
          Logger.debug(
              '✅ Protecting declared asset in pubspec.yaml: $normalizedPath');
          continue;
        }

        if (_isAssetReferenced(normalizedPath, referencedAssets)) {
          Logger.debug('✅ Asset is referenced in code: $normalizedPath');
          continue;
        }

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

      // CRITICAL SAFETY CHECK: Prevent mass deletion
      await _performSafetyValidation(
          assetFiles, unusedAssets, declaredAssets, referencedAssets);

      Logger.info(
          'Asset analysis complete: ${unusedAssets.length} unused assets found');
      return unusedAssets;
    } catch (e) {
      Logger.error('Asset analysis failed: $e');
      return [];
    }
  }

  Future<List<String>> _getDeclaredAssets(String projectPath) async {
    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) return [];

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
          // Include subdirectories recursively if declared with trailing slash
          if (normalizedAsset.endsWith('/')) {
            final dir = Directory(path.join(projectPath, normalizedAsset));
            if (await dir.exists()) {
              await for (final entity
                  in dir.list(recursive: true, followLinks: false)) {
                if (entity is File) {
                  final relPath = path.relative(entity.path, from: projectPath);
                  assets.add(PatternMatcher.normalizePath(relPath));
                }
              }
            }
          }
        }
      }
      return assets;
    } catch (e) {
      Logger.error('Error reading pubspec.yaml: $e');
      return [];
    }
  }

  bool _isAssetDeclared(String assetPath, List<String> declaredAssets) {
    final normalizedAssetPath = PatternMatcher.normalizePath(assetPath);
    for (final declared in declaredAssets) {
      final normalizedDeclared = PatternMatcher.normalizePath(declared);
      if (normalizedAssetPath == normalizedDeclared) return true;
      if (normalizedDeclared.endsWith('/') &&
          normalizedAssetPath.startsWith(normalizedDeclared)) return true;
      if (!normalizedDeclared.endsWith('/') &&
          normalizedAssetPath.startsWith('$normalizedDeclared/')) return true;
    }
    return false;
  }

  Future<List<File>> _getProjectAssets(String projectPath) async {
    final assets = <File>[];
    final assetDirs = ['assets', 'images', 'fonts', 'data', 'lib/assets'];
    for (final dirName in assetDirs) {
      final dir = Directory(path.join(projectPath, dirName));
      if (await dir.exists()) {
        final files = await FileUtils.findAssetFiles(dir.path);
        assets.addAll(files);
      }
    }
    return assets;
  }

  Future<Set<String>> _findReferencedAssets(
      List<File> dartFiles, String projectPath) async {
    final referenced = <String>{};
    final packageName = await _getPackageName(projectPath);
    Logger.debug('Project package name: $packageName');

    // Initialize AST analysis context
    AstUtils.initializeAnalysisContext(projectPath);

    try {
      for (final file in dartFiles) {
        try {
          final content = await file.readAsString();
          
          // Use AST-based analysis for better accuracy
          final resolvedUnit = await AstUtils.getResolvedUnit(file.path);
          if (resolvedUnit != null) {
            final visitor = AssetVariableVisitor(referenced);
            resolvedUnit.unit.accept(visitor);
          }
          
          // Keep existing string-based detection as fallback
          _findDirectAssetReferences(content, referenced);
          _findPackageReferences(content, referenced, packageName);
          _findWidgetPropertyReferences(content, referenced);
        } catch (e) {
          Logger.debug('Error analyzing file ${file.path}: $e');
        }
      }
      
      // Also check configuration files
      await _findConfigFileReferences(projectPath, referenced);
      
      return referenced;
    } finally {
      AstUtils.disposeAnalysisContext();
    }
  }

  /// Enhanced method to find direct asset references using multiple patterns
  void _findDirectAssetReferences(String content, Set<String> referenced) {
    final patterns = [
      r'AssetImage\([\'"]([^\'"]+)[\'"]',
      r'Image\.asset\([\'"]([^\'"]+)[\'"]',
      r'rootBundle\.load\([\'"]([^\'"]+)[\'"]',
      r'DefaultAssetBundle\.of\([^)]+\)\.load\([\'"]([^\'"]+)[\'"]',
      r'[\'"]assets/[^\'"]+[\'"]',
      r'[\'"]images/[^\'"]+[\'"]',
      r'[\'"]fonts/[^\'"]+[\'"]',
      r'[\'"]data/[^\'"]+[\'"]',
    ];

    for (final pattern in patterns) {
      final regex = RegExp(pattern);
      final matches = regex.allMatches(content);
      for (final match in matches) {
        if (match.group(1) != null) {
          referenced.add(PatternMatcher.normalizePath(match.group(1)!));
        } else if (match.group(0) != null) {
          // For simple quoted strings, extract the path
          final quotedString = match.group(0)!;
          final cleaned = quotedString.replaceAll(RegExp(r'[\'"]'), '');
          if (cleaned.contains('/')) {
            referenced.add(PatternMatcher.normalizePath(cleaned));
          }
        }
      }
    }
  }

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

  void _findAssetReferences(
      String content, Set<String> referenced, String prefix) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains(prefix)) {
        for (var quote in ['"', "'"]) {
          final parts = trimmed.split(quote);
          for (int i = 1; i < parts.length; i += 2) {
            if (parts[i].contains(prefix)) {
              final assetPath = parts[i].split(RegExp(r'[ \t\r\n]'))[
                  0]; // Take first segment to avoid partial matches
              referenced.add(PatternMatcher.normalizePath(assetPath));
            }
          }
        }
      }
    }
  }

  void _findAssetImageReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');
    for (final line in lines) {
      if (line.contains('AssetImage(')) {
        final startIndex = line.indexOf('AssetImage(') + 11;
        final remaining = line.substring(startIndex);
        final quoteIndex = remaining.contains('"')
            ? remaining.indexOf('"')
            : remaining.indexOf("'");
        if (quoteIndex != -1) {
          final quote = remaining[quoteIndex];
          final endQuote = remaining.indexOf(quote, quoteIndex + 1);
          if (endQuote != -1) {
            final assetPath =
                remaining.substring(quoteIndex + 1, endQuote).trim();
            referenced.add(PatternMatcher.normalizePath(assetPath));
          }
        }
      }
    }
  }

  void _findImageAssetReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');
    for (final line in lines) {
      if (line.contains('Image.asset(')) {
        final startIndex = line.indexOf('Image.asset(') + 11;
        final remaining = line.substring(startIndex);
        final quoteIndex = remaining.contains('"')
            ? remaining.indexOf('"')
            : remaining.indexOf("'");
        if (quoteIndex != -1) {
          final quote = remaining[quoteIndex];
          final endQuote = remaining.indexOf(quote, quoteIndex + 1);
          if (endQuote != -1) {
            final assetPath =
                remaining.substring(quoteIndex + 1, endQuote).trim();
            referenced.add(PatternMatcher.normalizePath(assetPath));
          }
        }
      }
    }
  }

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
              final assetPath = parts[i]
                  .replaceFirst('package:$packageName/', '')
                  .split(RegExp(r'[ \t\r\n]'))[0];
              referenced.add(PatternMatcher.normalizePath(assetPath));
            }
          }
        }
      }
    }
  }

  void _findConstantReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
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
                final assetPath =
                    valuePart.substring(startQuote, endQuote).trim();
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

  void _findVariableReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
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
                final assetPath =
                    valuePart.substring(startQuote, endQuote).trim();
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

  // New method to detect asset references in widget properties
  void _findWidgetPropertyReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains('DecorationImage(') || trimmed.contains('child:')) {
        for (var quote in ['"', "'"]) {
          final parts = trimmed.split(quote);
          for (int i = 1; i < parts.length; i += 2) {
            if (parts[i].contains('assets/') ||
                parts[i].contains('images/') ||
                parts[i].contains('fonts/') ||
                parts[i].contains('data/')) {
              final assetPath = parts[i].split(RegExp(r'[ \t\r\n]'))[0];
              referenced.add(PatternMatcher.normalizePath(assetPath));
            }
          }
        }
      }
    }
  }

  bool _isAssetReferenced(String assetPath, Set<String> referencedAssets) {
    final normalizedAssetPath = PatternMatcher.normalizePath(assetPath);
    if (referencedAssets.contains(normalizedAssetPath)) return true;
    for (final ref in referencedAssets) {
      final normalizedRef = PatternMatcher.normalizePath(ref);
      if (normalizedAssetPath == normalizedRef) return true;
      if (normalizedRef.endsWith('/') &&
          normalizedAssetPath.startsWith(normalizedRef)) return true;
      if (!normalizedRef.endsWith('/') &&
          normalizedAssetPath.startsWith('$normalizedRef/')) return true;
    }
    return false;
  }

  /// CRITICAL SAFETY VALIDATION: Prevents mass deletion of assets
  Future<void> _performSafetyValidation(
      List<File> assetFiles,
      List<UnusedItem> unusedAssets,
      List<String> declaredAssets,
      Set<String> referencedAssets) async {
    final totalAssets = assetFiles.length;
    final unusedCount = unusedAssets.length;

    // If more than 75% of assets are marked as unused, this is highly suspicious
    if (totalAssets > 0 && (unusedCount / totalAssets) > 0.75) {
      Logger.warning(
          '🚨 CRITICAL WARNING: $unusedCount out of $totalAssets assets marked as unused!');
      Logger.warning(
          'This is ${((unusedCount / totalAssets) * 100).round()}% of all assets.');
      Logger.warning('');
      Logger.warning(
          'This seems EXTREMELY high and likely indicates an analysis error.');
      Logger.warning('');
      Logger.warning('📊 Analysis Summary:');
      Logger.warning('  • Total assets found: $totalAssets');
      Logger.warning(
          '  • Assets declared in pubspec.yaml: ${declaredAssets.length}');
      Logger.warning(
          '  • Asset references found in code: ${referencedAssets.length}');
      Logger.warning('  • Assets marked as unused: $unusedCount');
      Logger.warning('');
      Logger.warning('🔍 Possible causes:');
      Logger.warning(
          '  • Assets referenced through dynamic paths or variables');
      Logger.warning(
          '  • Assets used in config files, JSON, or external resources');
      Logger.warning('  • Assets referenced from packages or plugins');
      Logger.warning('  • Build-generated asset references');
      Logger.warning('');
      Logger.warning('⚠️  STRONG RECOMMENDATION: Use --dry-run mode first!');
    } else if (unusedCount > 10) {
      Logger.warning('⚠️  WARNING: $unusedCount assets marked as unused.');
      Logger.warning('Please review the list carefully before deletion.');
      Logger.warning(
          'Consider running with --dry-run first to verify results.');
    }
  }
}
