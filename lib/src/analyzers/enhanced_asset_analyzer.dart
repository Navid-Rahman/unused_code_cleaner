import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../models/unused_item.dart';
import '../models/cleanup_options.dart';
import '../utils/logger.dart';

/// Enhanced asset analyzer using proven Flutter asset detection patterns
/// Based on flutter/flutter asset.dart and dart-code-metrics approaches
class EnhancedAssetAnalyzer {
  late AnalysisContextCollection _analysisContextCollection;

  /// Asset usage tracking similar to dart-code-metrics FileElementsUsage
  final Set<String> _referencedAssets = <String>{};
  final Set<String> _conditionallyReferencedAssets = <String>{};

  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedAssets = <UnusedItem>[];

    try {
      Logger.info('🔍 Starting enhanced asset analysis...');

      // Initialize analysis context collection like Flutter does
      final absoluteProjectPath = path.normalize(path.absolute(projectPath));
      _analysisContextCollection = AnalysisContextCollection(
        includedPaths: [absoluteProjectPath],
        excludedPaths: _getExcludedPaths(absoluteProjectPath),
      );

      // Step 1: Get all declared assets from pubspec.yaml (like Flutter's ManifestAssetBundle)
      final declaredAssets = await _parseAssetManifest(projectPath);
      Logger.debug('Found ${declaredAssets.length} declared assets');

      // Step 2: Find all potential asset files in the project
      final allAssetFiles = await _discoverAssetFiles(projectPath);
      Logger.debug('Found ${allAssetFiles.length} potential asset files');

      // Step 3: Analyze Dart code for asset references using advanced AST analysis
      await _analyzeAssetUsage(dartFiles, projectPath);
      Logger.debug('Found ${_referencedAssets.length} referenced assets');

      // Step 4: Check for unused assets
      for (final assetFile in allAssetFiles) {
        final relativePath = path.relative(assetFile.path, from: projectPath);
        final normalizedPath = _normalizePath(relativePath);

        if (!_isAssetUsed(normalizedPath)) {
          final fileName = path.basename(relativePath);
          unusedAssets.add(UnusedItem(
            name: fileName,
            path: assetFile.path,
            type: UnusedItemType.asset,
            description: 'Asset not referenced in code or pubspec.yaml',
          ));
        }
      }

      Logger.info(
          'Enhanced asset analysis complete: ${unusedAssets.length} unused assets found');
      return unusedAssets;
    } catch (e) {
      Logger.error('Enhanced asset analysis failed: $e');
      return [];
    }
  }

  /// Parse asset manifest similar to Flutter's _parseAssets method
  Future<List<String>> _parseAssetManifest(String projectPath) async {
    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) return [];

    try {
      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content);
      final assets = <String>[];

      // Parse flutter assets section
      if (yaml['flutter'] != null && yaml['flutter']['assets'] != null) {
        final assetList = yaml['flutter']['assets'] as List;
        for (final asset in assetList) {
          final assetPath = asset.toString();
          final normalizedAsset = _normalizePath(assetPath);
          assets.add(normalizedAsset);

          // Handle directory assets (with trailing slash) like Flutter does
          if (normalizedAsset.endsWith('/')) {
            final assetDir = Directory(path.join(projectPath, normalizedAsset));
            if (await assetDir.exists()) {
              await _addDirectoryAssets(assetDir, projectPath, assets);
            }
          }
        }
      }

      // Parse font assets
      if (yaml['flutter'] != null && yaml['flutter']['fonts'] != null) {
        final fontList = yaml['flutter']['fonts'] as List;
        for (final font in fontList) {
          if (font['fonts'] != null) {
            final fontFiles = font['fonts'] as List;
            for (final fontFile in fontFiles) {
              if (fontFile['asset'] != null) {
                assets.add(_normalizePath(fontFile['asset'].toString()));
              }
            }
          }
        }
      }

      return assets;
    } catch (e) {
      Logger.error('Error parsing pubspec.yaml: $e');
      return [];
    }
  }

  Future<void> _addDirectoryAssets(
      Directory dir, String projectPath, List<String> assets) async {
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && _isAssetFile(entity.path)) {
        final relativePath = path.relative(entity.path, from: projectPath);
        assets.add(_normalizePath(relativePath));
      }
    }
  }

  /// Discover asset files in the project similar to Flutter's asset discovery
  Future<List<File>> _discoverAssetFiles(String projectPath) async {
    final assetFiles = <File>[];

    // Common asset directories in Flutter projects
    final assetDirs = [
      'assets',
      'images',
      'fonts',
      'icons',
      'data',
      'config',
      'resources',
    ];

    for (final dirName in assetDirs) {
      final assetDir = Directory(path.join(projectPath, dirName));
      if (await assetDir.exists()) {
        await _scanDirectoryForAssets(assetDir, assetFiles);
      }
    }

    // Also check lib directory for embedded assets
    final libDir = Directory(path.join(projectPath, 'lib'));
    if (await libDir.exists()) {
      await _scanDirectoryForAssets(libDir, assetFiles);
    }

    return assetFiles;
  }

  Future<void> _scanDirectoryForAssets(
      Directory dir, List<File> assetFiles) async {
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && _isAssetFile(entity.path)) {
        assetFiles.add(entity);
      }
    }
  }

  bool _isAssetFile(String filePath) {
    final fileName = path.basename(filePath);

    // Exclude Dart and configuration files
    if (fileName.endsWith('.dart') ||
        fileName == 'pubspec.yaml' ||
        fileName == 'pubspec.yml' ||
        fileName == 'analysis_options.yaml' ||
        fileName == '.packages' ||
        fileName == 'pubspec.lock') {
      return false;
    }

    // Include common asset file types
    final assetExtensions = {
      // Images
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.bmp', '.ico',
      // Fonts
      '.ttf', '.otf', '.woff', '.woff2',
      // Audio
      '.mp3', '.wav', '.m4a', '.aac', '.ogg',
      // Video
      '.mp4', '.mov', '.avi', '.webm',
      // Data
      '.json', '.txt', '.xml', '.csv', '.yaml', '.yml',
      // Documents
      '.pdf',
      // Archives (less common but possible)
      '.zip', '.gz', '.tar'
    };

    final extension = path.extension(filePath).toLowerCase();
    return assetExtensions.contains(extension);
  }

  /// Analyze asset usage in Dart code using advanced AST analysis
  /// Based on dart-code-metrics UsedCodeVisitor patterns
  Future<void> _analyzeAssetUsage(
      List<File> dartFiles, String projectPath) async {
    for (final dartFile in dartFiles) {
      try {
        final absoluteFilePath = path.normalize(path.absolute(dartFile.path));
        final context = _analysisContextCollection.contextFor(absoluteFilePath);
        final session = context.currentSession;
        final result = await session.getResolvedUnit(absoluteFilePath);

        if (result is ResolvedUnitResult) {
          final visitor = _AssetUsageVisitor(projectPath, this);
          result.unit.visitChildren(visitor);
        }
      } catch (e) {
        Logger.error('Error analyzing ${dartFile.path}: $e');
      }
    }
  }

  /// Record asset usage (similar to dart-code-metrics _recordUsedElement)
  void _recordAssetUsage(String assetPath, {bool conditional = false}) {
    final normalizedPath = _normalizePath(assetPath);
    if (conditional) {
      _conditionallyReferencedAssets.add(normalizedPath);
    } else {
      _referencedAssets.add(normalizedPath);
    }
  }

  /// Check if an asset is used (similar to dart-code-metrics _isUsed)
  bool _isAssetUsed(String assetPath) {
    final normalizedPath = _normalizePath(assetPath);

    // Direct reference
    if (_referencedAssets.contains(normalizedPath)) return true;

    // Conditional reference
    if (_conditionallyReferencedAssets.contains(normalizedPath)) return true;

    // Fuzzy matching for asset variants (2x, 3x, etc.)
    return _hasAssetVariantMatch(normalizedPath);
  }

  bool _hasAssetVariantMatch(String assetPath) {
    final basename = path.basenameWithoutExtension(assetPath);
    final extension = path.extension(assetPath);
    final dirname = path.dirname(assetPath);

    // Check for density variants (1.5x, 2.0x, 3.0x, etc.)
    for (final ref in _referencedAssets) {
      final refBasename = path.basenameWithoutExtension(ref);
      final refExtension = path.extension(ref);
      final refDirname = path.dirname(ref);

      if (extension == refExtension && basename == refBasename) {
        // Check if this is a density variant
        if (_isDensityVariant(dirname, refDirname)) {
          return true;
        }
      }
    }

    return false;
  }

  bool _isDensityVariant(String assetDir, String refDir) {
    final densityPattern = RegExp(r'\d+(\.\d+)?x');
    return densityPattern.hasMatch(assetDir) || densityPattern.hasMatch(refDir);
  }

  String _normalizePath(String path) {
    return path.replaceAll('\\', '/').replaceAll('//', '/');
  }

  List<String> _getExcludedPaths(String projectPath) {
    return [
      path.join(projectPath, '.dart_tool'),
      path.join(projectPath, 'build'),
      path.join(projectPath, '.git'),
      path.join(projectPath, 'node_modules'),
    ];
  }
}

/// Advanced AST visitor for detecting asset usage patterns
/// Based on Flutter's asset analysis and dart-code-metrics visitor patterns
class _AssetUsageVisitor extends RecursiveAstVisitor<void> {
  final String projectPath;
  final EnhancedAssetAnalyzer analyzer;

  _AssetUsageVisitor(this.projectPath, this.analyzer);

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final value = node.value;
    if (_looksLikeAssetPath(value)) {
      analyzer._recordAssetUsage(value);
    }
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    // Handle string interpolation that might contain asset paths
    final text = node.toString();
    if (_looksLikeAssetPath(text)) {
      analyzer._recordAssetUsage(text);
    }
    super.visitStringInterpolation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Check for Asset.* calls like AssetImage, Image.asset, etc.
    if (_isAssetMethod(node)) {
      _extractAssetFromMethodCall(node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Check for AssetImage(), Image.asset(), etc.
    if (_isAssetConstructor(node)) {
      _extractAssetFromConstructor(node);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    // Check for generated asset references like Assets.images.logo
    if (_isGeneratedAssetReference(node)) {
      _extractGeneratedAssetReference(node);
    }
    super.visitPrefixedIdentifier(node);
  }

  bool _isAssetMethod(MethodInvocation node) {
    final methodName = node.methodName.name;
    final targetType =
        node.target?.staticType?.getDisplayString(withNullability: false);

    return (methodName == 'asset' && targetType == 'Image') ||
        (methodName == 'loadString' && targetType == 'rootBundle') ||
        (methodName == 'load' && targetType == 'rootBundle') ||
        methodName == 'loadStructuredData';
  }

  bool _isAssetConstructor(InstanceCreationExpression node) {
    final typeName = node.staticType?.getDisplayString(withNullability: false);
    return typeName == 'AssetImage' ||
        typeName == 'ExactAssetImage' ||
        typeName?.contains('AssetBundle') == true;
  }

  bool _isGeneratedAssetReference(PrefixedIdentifier node) {
    final prefix = node.prefix.name;
    return prefix == 'Assets' ||
        prefix.endsWith('Assets') ||
        prefix.startsWith('Assets');
  }

  void _extractAssetFromMethodCall(MethodInvocation node) {
    if (node.argumentList.arguments.isNotEmpty) {
      final firstArg = node.argumentList.arguments.first;
      if (firstArg is StringLiteral && firstArg.stringValue != null) {
        analyzer._recordAssetUsage(firstArg.stringValue!);
      }
    }
  }

  void _extractAssetFromConstructor(InstanceCreationExpression node) {
    if (node.argumentList.arguments.isNotEmpty) {
      final firstArg = node.argumentList.arguments.first;
      if (firstArg is StringLiteral && firstArg.stringValue != null) {
        analyzer._recordAssetUsage(firstArg.stringValue!);
      }
    }
  }

  void _extractGeneratedAssetReference(PrefixedIdentifier node) {
    // Try to resolve the generated asset path
    // This is more complex and would require analyzing the generator
    final fullPath = node.toString();
    analyzer._recordAssetUsage(fullPath);
  }

  bool _looksLikeAssetPath(String value) {
    // Check if string looks like an asset path
    return (value.contains('assets/') ||
            value.contains('images/') ||
            value.contains('fonts/') ||
            value.contains('.png') ||
            value.contains('.jpg') ||
            value.contains('.json') ||
            value.contains('.svg')) &&
        !value.contains('http') &&
        !value.contains('package:');
  }
}
