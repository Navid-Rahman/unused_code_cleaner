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

/// Enhanced asset analyzer using semantic AST analysis
class AssetAnalyzer {
  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedAssets = <UnusedItem>[];

    try {
      Logger.info('🔍 Starting enhanced asset analysis (semantic-based)...');

      final declaredAssets = await _getDeclaredAssets(projectPath);
      Logger.debug(
          'Found ${declaredAssets.length} declared assets in pubspec.yaml');

      final assetFiles = await _getProjectAssets(projectPath);
      Logger.debug(
          'Found ${assetFiles.length} asset files in project directories');

      final referencedAssets =
          await _findReferencedAssets(dartFiles, projectPath);
      Logger.debug(
          'Found ${referencedAssets.length} referenced assets in code');

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

        // Additional safety check: look for the asset filename in references
        final fileName = path.basename(normalizedPath);
        final fileNameReferenced = referencedAssets.any(
            (ref) => path.basename(ref) == fileName || ref.contains(fileName));

        if (fileNameReferenced) {
          Logger.debug(
              '✅ Asset filename found in references: $normalizedPath (filename: $fileName)');
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

      Logger.info(
          'Enhanced asset analysis complete: ${unusedAssets.length} unused assets found');
      return unusedAssets;
    } catch (e) {
      Logger.error('Enhanced asset analysis failed: $e');
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
      if (normalizedAssetPath == normalizedDeclared) {
        return true;
      }
      if (normalizedDeclared.endsWith('/') &&
          normalizedAssetPath.startsWith(normalizedDeclared)) {
        return true;
      }
      if (!normalizedDeclared.endsWith('/') &&
          normalizedAssetPath.startsWith('$normalizedDeclared/')) {
        return true;
      }
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

    AstUtils.initializeAnalysisContext(projectPath);

    try {
      int processedFiles = 0;
      int filesWithAssets = 0;

      for (final file in dartFiles) {
        try {
          final initialCount = referenced.length;

          // Use semantic AST analysis for accurate asset detection
          final resolvedUnit = await AstUtils.getResolvedUnit(file.path);
          if (resolvedUnit != null) {
            final visitor = SemanticAssetVisitor(referenced, packageName);
            resolvedUnit.unit.accept(visitor);
          }

          processedFiles++;
          final newAssets = referenced.length - initialCount;
          if (newAssets > 0) {
            filesWithAssets++;
            Logger.debug(
                'Found $newAssets new asset references in ${path.basename(file.path)}');
          }
        } catch (e) {
          Logger.debug('Error analyzing file ${file.path}: $e');
        }
      }

      // Also check configuration files
      await _findConfigFileReferences(projectPath, referenced);

      Logger.info(
          'Semantic asset analysis: $processedFiles files processed, $filesWithAssets files with assets, ${referenced.length} total references');
      return referenced;
    } finally {
      AstUtils.disposeAnalysisContext();
    }
  }

  bool _isAssetReferenced(String assetPath, Set<String> referencedAssets) {
    final normalizedAssetPath = PatternMatcher.normalizePath(assetPath);

    for (final ref in referencedAssets) {
      final normalizedRef = PatternMatcher.normalizePath(ref);

      // Exact match
      if (normalizedAssetPath == normalizedRef) {
        return true;
      }

      // Fuzzy matching for different path formats
      if (_fuzzyPathMatch(normalizedAssetPath, normalizedRef)) {
        return true;
      }
    }

    return false;
  }

  bool _fuzzyPathMatch(String assetPath, String referencePath) {
    // Remove common prefixes
    final assetSegments = assetPath.split('/');
    final refSegments = referencePath.split('/');

    // Check if the filename matches
    if (assetSegments.last == refSegments.last) {
      return true;
    }

    // Check if one path contains the other
    if (assetPath.contains(referencePath) ||
        referencePath.contains(assetPath)) {
      return true;
    }

    // Check for package: prefix variations
    if (referencePath.startsWith('packages/') &&
        assetPath
            .endsWith(referencePath.substring(referencePath.indexOf('/', 9)))) {
      return true;
    }

    return false;
  }

  Future<String> _getPackageName(String projectPath) async {
    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) return '';

    try {
      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content);
      return yaml['name'] ?? '';
    } catch (e) {
      Logger.debug('Error reading package name: $e');
      return '';
    }
  }

  Future<void> _findConfigFileReferences(
      String projectPath, Set<String> referenced) async {
    // Check common configuration files for asset references
    final configFiles = [
      'lib/generated/assets.dart',
      'lib/gen/assets.gen.dart',
      'assets.json',
      'asset_manifest.json',
    ];

    for (final configFile in configFiles) {
      final file = File(path.join(projectPath, configFile));
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          final matches =
              RegExp(r'''['"]([^'"]*\.[a-zA-Z0-9]+)['"]''').allMatches(content);
          for (final match in matches) {
            final assetPath = match.group(1);
            if (assetPath != null && _isValidAssetPath(assetPath)) {
              referenced.add(PatternMatcher.normalizePath(assetPath));
            }
          }
        } catch (e) {
          Logger.debug('Error reading config file $configFile: $e');
        }
      }
    }
  }

  bool _isValidAssetPath(String path) {
    if (path.isEmpty) return false;

    // Check for common asset file extensions
    final assetExtensions = {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.svg',
      '.json',
      '.txt',
      '.xml',
      '.csv',
      '.ttf',
      '.otf',
      '.woff',
      '.woff2',
      '.mp3',
      '.wav',
      '.mp4',
      '.mov',
      '.pdf',
      '.zip',
      '.gz'
    };

    final hasValidExtension =
        assetExtensions.any((ext) => path.toLowerCase().endsWith(ext));

    // Check for asset-like paths
    final hasAssetPath = path.contains('asset') ||
        path.contains('image') ||
        path.contains('font') ||
        path.contains('data');

    return hasValidExtension && hasAssetPath;
  }
}

/// Semantic visitor for asset references using AST analysis
class SemanticAssetVisitor extends RecursiveAstVisitor<void> {
  final Set<String> referenced;
  final String packageName;
  final Map<String, String> variableValues = {};

  SemanticAssetVisitor(this.referenced, this.packageName);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    // Track string variable assignments for later resolution
    if (node.initializer is StringLiteral) {
      final stringLiteral = node.initializer as StringLiteral;
      final value = stringLiteral.stringValue;
      if (value != null && _isValidAssetPath(value)) {
        variableValues[node.name.lexeme] = value;
        referenced.add(PatternMatcher.normalizePath(value));
      }
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;

    // Handle Image.asset() calls
    if (methodName == 'asset' && node.target?.toString() == 'Image') {
      _extractAssetFromArguments(node.argumentList);
    }

    // Handle AssetImage() constructor calls
    if (methodName == 'load' || methodName == 'loadString') {
      _extractAssetFromArguments(node.argumentList);
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.name2.lexeme;

    // Handle AssetImage constructor
    if (typeName == 'AssetImage') {
      _extractAssetFromArguments(node.argumentList);
    }

    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // Resolve variable references to their string values
    final variableName = node.name;
    if (variableValues.containsKey(variableName)) {
      final assetPath = variableValues[variableName]!;
      referenced.add(PatternMatcher.normalizePath(assetPath));
    }

    super.visitSimpleIdentifier(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    // Handle string interpolations that might contain asset paths
    for (final element in node.elements) {
      if (element is InterpolationString) {
        final value = element.value;
        if (_isValidAssetPath(value)) {
          referenced.add(PatternMatcher.normalizePath(value));
        }
      }
    }
    super.visitStringInterpolation(node);
  }

  void _extractAssetFromArguments(ArgumentList argumentList) {
    for (final argument in argumentList.arguments) {
      if (argument is StringLiteral) {
        final value = argument.stringValue;
        if (value != null && _isValidAssetPath(value)) {
          referenced.add(PatternMatcher.normalizePath(value));
        }
      } else if (argument is SimpleIdentifier) {
        // Try to resolve variable reference
        final variableName = argument.name;
        if (variableValues.containsKey(variableName)) {
          final assetPath = variableValues[variableName]!;
          referenced.add(PatternMatcher.normalizePath(assetPath));
        }
      }
    }
  }

  bool _isValidAssetPath(String path) {
    if (path.isEmpty) return false;

    // Check for common asset file extensions
    final assetExtensions = {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.svg',
      '.json',
      '.txt',
      '.xml',
      '.csv',
      '.ttf',
      '.otf',
      '.woff',
      '.woff2',
      '.mp3',
      '.wav',
      '.mp4',
      '.mov',
      '.pdf',
      '.zip',
      '.gz'
    };

    final hasValidExtension =
        assetExtensions.any((ext) => path.toLowerCase().endsWith(ext));

    // Check for asset-like paths
    final hasAssetPath = path.contains('asset') ||
        path.contains('image') ||
        path.contains('font') ||
        path.contains('data');

    return hasValidExtension && hasAssetPath;
  }
}
