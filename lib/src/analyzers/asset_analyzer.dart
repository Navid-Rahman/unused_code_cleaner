import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/file_utils.dart';
import '../utils/pattern_matcher.dart';
import '../models/cleanup_options.dart';

/// Enhanced asset analyzer using Flutter-proven asset detection patterns
class AssetAnalyzer {
  late AnalysisContextCollection _analysisContextCollection;

  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedAssets = <UnusedItem>[];

    try {
      Logger.info('🔍 Starting Flutter-based asset analysis...');

      // Initialize proper analysis context like Flutter does
      _analysisContextCollection = AnalysisContextCollection(
        includedPaths: [projectPath],
      );

      final declaredAssets = await _getDeclaredAssets(projectPath);
      Logger.debug(
          'Found ${declaredAssets.length} declared assets in pubspec.yaml');

      final assetFiles = await _getProjectAssets(projectPath);
      Logger.debug(
          'Found ${assetFiles.length} asset files in project directories');

      print(
          'DEBUG: About to call _findReferencedAssets with ${dartFiles.length} files');
      final referencedAssets =
          await _findReferencedAssets(dartFiles, projectPath);
      print(
          'DEBUG: _findReferencedAssets returned ${referencedAssets.length} references');
      Logger.debug(
          'Found ${referencedAssets.length} referenced assets in code');

      // Log detailed findings for debugging
      Logger.debug('Declared assets: ${declaredAssets.take(10)}...');
      Logger.debug('Referenced assets: ${referencedAssets.take(10)}...');

      for (final assetFile in assetFiles) {
        final relativePath = path.relative(assetFile.path, from: projectPath);
        final normalizedPath = PatternMatcher.normalizePath(relativePath);

        Logger.debug('Analyzing asset: $normalizedPath');

        if (PatternMatcher.isExcluded(
            normalizedPath, options.excludePatterns)) {
          Logger.debug('✅ Skipping excluded asset: $normalizedPath');
          continue;
        }

        // Only protect assets that are actually referenced in code
        if (_isAssetReferenced(normalizedPath, referencedAssets)) {
          Logger.debug('✅ Asset is referenced in code: $normalizedPath');
          continue;
        }

        // Assets that are declared in pubspec.yaml but not referenced in code should be considered unused
        // (unless they're explicitly excluded above)

        // Enhanced safety checks using Flutter's patterns
        final fileName = path.basename(normalizedPath);
        final fileNameWithoutExt =
            path.basenameWithoutExtension(normalizedPath);

        // Check multiple reference patterns like Flutter does
        final isFileNameReferenced = referencedAssets.any((ref) {
          final refBasename = path.basename(ref);
          final refWithoutExt = path.basenameWithoutExtension(ref);

          return refBasename == fileName ||
              refWithoutExt == fileNameWithoutExt ||
              ref.contains(fileName) ||
              ref.contains(fileNameWithoutExt) ||
              _matchesAssetPathPattern(normalizedPath, ref);
        });

        if (isFileNameReferenced) {
          Logger.debug(
              '✅ Asset filename matched in references: $normalizedPath');
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
          'Flutter-based asset analysis complete: ${unusedAssets.length} unused assets found');
      return unusedAssets;
    } catch (e) {
      Logger.error('Flutter-based asset analysis failed: $e');
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

  Future<List<File>> _getProjectAssets(String projectPath) async {
    final assets = <File>[];

    // Use comprehensive asset detection like Flutter does
    final assetDirs = [
      'assets',
      'asset',
      'images',
      'image',
      'fonts',
      'font',
      'data',
      'resources',
      'static',
      'files',
      'lib/assets',
      'lib/images',
      'lib/fonts'
    ];

    print('DEBUG: Looking for assets in project: $projectPath');
    for (final dirName in assetDirs) {
      final dir = Directory(path.join(projectPath, dirName));
      print('DEBUG: Checking directory: ${dir.path}');
      if (await dir.exists()) {
        print('DEBUG: Directory exists, finding asset files...');
        final files = await FileUtils.findAssetFiles(dir.path);
        print('DEBUG: Found ${files.length} asset files in $dirName');
        for (final file in files) {
          print('DEBUG:   Asset file: ${file.path}');
        }
        assets.addAll(files);
      } else {
        print('DEBUG: Directory does not exist: ${dir.path}');
      }
    }

    // Also check root directory for asset files
    final rootDir = Directory(projectPath);
    if (await rootDir.exists()) {
      await for (final entity in rootDir.list(recursive: false)) {
        if (entity is File && _isAssetFile(entity.path)) {
          print('DEBUG: Found root asset file: ${entity.path}');
          assets.add(entity);
        }
      }
    }

    print('DEBUG: Total asset files found: ${assets.length}');
    return assets;
  }

  bool _isAssetFile(String filePath) {
    final fileName = path.basename(filePath);

    // Exclude configuration files that shouldn't be considered assets
    if (fileName == 'pubspec.yaml' ||
        fileName == 'pubspec.yml' ||
        fileName == 'analysis_options.yaml' ||
        fileName == '.packages') {
      return false;
    }

    final assetExtensions = {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.svg',
      '.bmp',
      '.ico',
      '.json',
      '.txt',
      '.xml',
      '.csv',
      '.yaml',
      '.yml',
      '.ttf',
      '.otf',
      '.woff',
      '.woff2',
      '.mp3',
      '.wav',
      '.m4a',
      '.aac',
      '.ogg',
      '.mp4',
      '.mov',
      '.avi',
      '.webm',
      '.pdf',
      '.zip',
      '.gz',
      '.tar'
    };

    final extension = path.extension(filePath).toLowerCase();
    return assetExtensions.contains(extension);
  }

  Future<Set<String>> _findReferencedAssets(
      List<File> dartFiles, String projectPath) async {
    final referenced = <String>{};
    final packageName = await _getPackageName(projectPath);

    print('DEBUG: Project package name: $packageName');
    print(
        'DEBUG: Processing ${dartFiles.length} Dart files for asset references');

    try {
      int processedFiles = 0;
      int filesWithAssets = 0;

      for (final file in dartFiles) {
        try {
          print('DEBUG: Analyzing file: ${file.path}');
          final initialCount = referenced.length;

          // Use proper Flutter-style analysis context
          final analysisContext =
              _analysisContextCollection.contextFor(file.path);
          final analysisSession = analysisContext.currentSession;
          final parseResult = await analysisSession.getParsedUnit(file.path);

          if (parseResult is ParsedUnitResult) {
            print('DEBUG: Successfully parsed ${file.path}');
            final visitor =
                FlutterAssetVisitor(referenced, packageName, projectPath);
            parseResult.unit.accept(visitor);
            print(
                'DEBUG: FlutterAssetVisitor found ${referenced.length - initialCount} asset references');
          } else {
            print(
                'DEBUG: Failed to parse ${file.path}: ${parseResult.runtimeType}');
          }

          processedFiles++;
          final newAssets = referenced.length - initialCount;
          if (newAssets > 0) {
            filesWithAssets++;
            print(
                'DEBUG: Found $newAssets new asset references in ${path.basename(file.path)}');
            for (final ref in referenced.skip(initialCount)) {
              print('DEBUG:   Reference: $ref');
            }
          }
        } catch (e) {
          print('DEBUG: Error analyzing file ${file.path}: $e');
        }
      }

      // Also check configuration files like Flutter does
      await _findConfigFileReferences(projectPath, referenced);

      Logger.info(
          'Flutter asset analysis: $processedFiles files processed, $filesWithAssets files with assets, ${referenced.length} total references');

      return referenced;
    } catch (e) {
      Logger.error('Error in asset reference analysis: $e');
      return referenced;
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

      // Enhanced fuzzy matching using Flutter patterns
      if (_matchesAssetPathPattern(normalizedAssetPath, normalizedRef)) {
        return true;
      }
    }

    return false;
  }

  bool _matchesAssetPathPattern(String assetPath, String referencePath) {
    // Remove common prefixes and normalize
    final assetSegments = assetPath.split('/');
    final refSegments = referencePath.split('/');

    // Check if the filename matches
    if (assetSegments.last == refSegments.last) {
      return true;
    }

    // Check filename without extension
    final assetBasename = path.basenameWithoutExtension(assetPath);
    final refBasename = path.basenameWithoutExtension(referencePath);
    if (assetBasename == refBasename && assetBasename.isNotEmpty) {
      return true;
    }

    // Check if one path contains the other
    if (assetPath.contains(referencePath) ||
        referencePath.contains(assetPath)) {
      return true;
    }

    // Check for package: prefix variations (like Flutter AssetBundle does)
    if (referencePath.startsWith('packages/') &&
        assetPath
            .endsWith(referencePath.substring(referencePath.indexOf('/', 9)))) {
      return true;
    }

    // Check for assets/ prefix variations
    if (referencePath.startsWith('assets/') &&
        assetPath.endsWith(referencePath.substring(7))) {
      return true;
    }

    // Check reverse: asset starts with assets/ but reference doesn't
    if (assetPath.startsWith('assets/') &&
        referencePath == assetPath.substring(7)) {
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
      'AssetManifest.json',
      'FontManifest.json',
    ];

    for (final configFile in configFiles) {
      final file = File(path.join(projectPath, configFile));
      if (await file.exists()) {
        try {
          final content = await file.readAsString();

          // Use comprehensive regex patterns like Flutter does
          final patterns = [
            RegExp(
                r'''['"]([^'"]*\.[a-zA-Z0-9]+)['"]'''), // Basic asset patterns
            RegExp(r'''assets/([^'"]*\.[a-zA-Z0-9]+)'''), // Assets directory
            RegExp(r'''images/([^'"]*\.[a-zA-Z0-9]+)'''), // Images directory
            RegExp(r'''fonts/([^'"]*\.[a-zA-Z0-9]+)'''), // Fonts directory
          ];

          for (final pattern in patterns) {
            final matches = pattern.allMatches(content);
            for (final match in matches) {
              final assetPath = match.group(1);
              if (assetPath != null && _isValidAssetPath(assetPath)) {
                referenced.add(PatternMatcher.normalizePath(assetPath));
              }
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

/// Flutter-style asset visitor using comprehensive AST analysis patterns
class FlutterAssetVisitor extends RecursiveAstVisitor<void> {
  final Set<String> referenced;
  final String packageName;
  final String projectPath;
  final Map<String, String> variableValues = {};

  FlutterAssetVisitor(this.referenced, this.packageName, this.projectPath);

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
  void visitFieldDeclaration(FieldDeclaration node) {
    // Track static field declarations that might contain asset paths
    for (final variable in node.fields.variables) {
      if (variable.initializer is StringLiteral) {
        final stringLiteral = variable.initializer as StringLiteral;
        final value = stringLiteral.stringValue;
        if (value != null && _isValidAssetPath(value)) {
          variableValues[variable.name.lexeme] = value;
          referenced.add(PatternMatcher.normalizePath(value));
        }
      }
    }
    super.visitFieldDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;

    // Handle Image.asset() calls
    if (methodName == 'asset' && _isImageAssetCall(node)) {
      _extractAssetFromArguments(node.argumentList);
    }

    // Handle AssetBundle.load() calls
    if (methodName == 'load' || methodName == 'loadString') {
      _extractAssetFromArguments(node.argumentList);
    }

    // Handle rootBundle.load() calls
    if (methodName == 'load' && node.target?.toString() == 'rootBundle') {
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

    // Handle NetworkImage with asset fallback patterns
    if (typeName == 'NetworkImage') {
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
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    // Catch any string literal that looks like an asset path
    final value = node.value;
    if (_isValidAssetPath(value)) {
      referenced.add(PatternMatcher.normalizePath(value));
    }
    super.visitSimpleStringLiteral(node);
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

  bool _isImageAssetCall(MethodInvocation node) {
    return node.target?.toString() == 'Image' ||
        (node.target is PrefixedIdentifier &&
            (node.target as PrefixedIdentifier).identifier.name == 'Image');
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
      } else if (argument is PrefixedIdentifier) {
        // Handle package prefixed identifiers
        final fullName = '${argument.prefix.name}.${argument.identifier.name}';
        if (variableValues.containsKey(fullName)) {
          final assetPath = variableValues[fullName]!;
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
      '.bmp',
      '.ico',
      '.json',
      '.txt',
      '.xml',
      '.csv',
      '.yaml',
      '.yml',
      '.ttf',
      '.otf',
      '.woff',
      '.woff2',
      '.mp3',
      '.wav',
      '.m4a',
      '.aac',
      '.ogg',
      '.mp4',
      '.mov',
      '.avi',
      '.webm',
      '.pdf',
      '.zip',
      '.gz',
      '.tar'
    };

    final hasValidExtension =
        assetExtensions.any((ext) => path.toLowerCase().endsWith(ext));

    // Check for asset-like paths (more comprehensive than before)
    final hasAssetPath = path.contains('asset') ||
        path.contains('image') ||
        path.contains('font') ||
        path.contains('data') ||
        path.contains('resource') ||
        path.contains('icon') ||
        path.contains('media') ||
        hasValidExtension; // If it has a valid extension, consider it an asset

    return hasValidExtension && hasAssetPath;
  }
}
