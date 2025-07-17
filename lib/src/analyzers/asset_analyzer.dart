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

      // CRITICAL SAFETY CHECK: Prevent mass deletion
      await _performSafetyValidation(
          assetFiles, unusedAssets, declaredAssets, referencedAssets);

      // Enhanced logging summary
      _printAssetAnalysisSummary(
          assetFiles, declaredAssets, referencedAssets, unusedAssets, options);

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

    // Initialize AST analysis context
    AstUtils.initializeAnalysisContext(projectPath);

    try {
      int processedFiles = 0;
      int filesWithAssets = 0;

      for (final file in dartFiles) {
        try {
          final content = await file.readAsString();
          final initialCount = referenced.length;

          // Use AST-based analysis for better accuracy
          final resolvedUnit = await AstUtils.getResolvedUnit(file.path);
          if (resolvedUnit != null) {
            final visitor = AssetVariableVisitor(referenced);
            resolvedUnit.unit.accept(visitor);

            // Log AST analysis summary if verbose
            final summary = visitor.getSummary();
            if (summary['assetVariables'] > 0) {
              Logger.debug(
                  'AST analysis for ${path.basename(file.path)}: ${summary['assetVariables']} asset variables, ${summary['usedVariables']} used');
            }
          }

          // Enhanced string-based detection as fallback and complement
          _findDirectAssetReferences(content, referenced);
          _findVariableReferences(content, referenced);
          _findPackageReferences(content, referenced, packageName);
          _findWidgetPropertyReferences(content, referenced);
          _findConstantReferences(content, referenced);

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
          'Asset reference analysis: $processedFiles files processed, $filesWithAssets files with assets, ${referenced.length} total references');
      return referenced;
    } finally {
      AstUtils.disposeAnalysisContext();
    }
  }

  /// Enhanced method to find direct asset references using multiple patterns
  void _findDirectAssetReferences(String content, Set<String> referenced) {
    // Enhanced patterns for asset detection
    final directPatterns = [
      // Method calls
      RegExp(r'''AssetImage\s*\(\s*['"]([^'"]+)['"]''', multiLine: true),
      RegExp(r'''Image\.asset\s*\(\s*['"]([^'"]+)['"]''', multiLine: true),
      RegExp(r'''rootBundle\.load(?:String)?\s*\(\s*['"]([^'"]+)['"]''',
          multiLine: true),
      RegExp(
          r'''DefaultAssetBundle\.of.*?\.load(?:String)?\s*\(\s*['"]([^'"]+)['"]''',
          multiLine: true),

      // Direct asset path references
      RegExp(
          r'''['"]([^'"]*(?:assets|images|fonts|data)[^'"]*\.[a-zA-Z0-9]+)['"]''',
          multiLine: true),

      // Flutter specific patterns
      RegExp(
          r'''decoration:\s*BoxDecoration\s*\([^)]*image:\s*AssetImage\s*\(\s*['"]([^'"]+)['"]''',
          multiLine: true, dotAll: true),
      RegExp(r'''backgroundImage:\s*AssetImage\s*\(\s*['"]([^'"]+)['"]''',
          multiLine: true),
    ];

    for (final pattern in directPatterns) {
      final matches = pattern.allMatches(content);
      for (final match in matches) {
        final assetPath = match.group(1);
        if (assetPath != null && _isValidAssetPath(assetPath)) {
          referenced.add(PatternMatcher.normalizePath(assetPath));
          Logger.debug('Direct pattern match: "$assetPath"');
        }
      }
    }
  }

  /// Find variable references and their usage
  void _findVariableReferences(String content, Set<String> referenced) {
    final lines = content.split('\n');
    final variableMap = <String, String>{};

    // First pass: Find variable declarations
    for (final line in lines) {
      // Match const declarations: const kAsset = "path";
      final constMatch =
          RegExp(r'''(?:static\s+)?const\s+(\w+)\s*=\s*['"]([^'"]+)['"]''')
              .firstMatch(line);
      if (constMatch != null) {
        final varName = constMatch.group(1)!;
        final varValue = constMatch.group(2)!;
        if (_isValidAssetPath(varValue)) {
          variableMap[varName] = varValue;
          referenced.add(PatternMatcher.normalizePath(varValue));
          Logger.debug('Found const variable: $varName = "$varValue"');
        }
      }

      // Match final/var declarations: final String asset = "path";
      final finalMatch =
          RegExp(r'''(?:final|var|String)\s+(\w+)\s*=\s*['"]([^'"]+)['"]''')
              .firstMatch(line);
      if (finalMatch != null) {
        final varName = finalMatch.group(1)!;
        final varValue = finalMatch.group(2)!;
        if (_isValidAssetPath(varValue)) {
          variableMap[varName] = varValue;
          referenced.add(PatternMatcher.normalizePath(varValue));
          Logger.debug('Found variable declaration: $varName = "$varValue"');
        }
      }
    }

    // Second pass: Find variable usage
    for (final line in lines) {
      for (final varName in variableMap.keys) {
        // Look for variable usage in asset methods
        final usagePatterns = [
          RegExp(r'''AssetImage\s*\(\s*''' + varName + r'''\s*\)'''),
          RegExp(r'''Image\.asset\s*\(\s*''' + varName + r'''\s*\)'''),
          RegExp(r'''rootBundle\.load\w*\s*\(\s*''' + varName + r'''\s*\)'''),
          RegExp(
              r''':\s*''' + varName + r'''\s*[,\)]'''), // Property assignment
        ];

        for (final pattern in usagePatterns) {
          if (pattern.hasMatch(line)) {
            final assetPath = variableMap[varName]!;
            referenced.add(PatternMatcher.normalizePath(assetPath));
            Logger.debug('Found variable usage: $varName -> "$assetPath"');
            break;
          }
        }
      }
    }
  }

  /// Find constant references like MyClass.kAsset
  void _findConstantReferences(String content, Set<String> referenced) {
    // Match class constant references: MyClass.kAsset, Constants.imagePath, etc.
    final constantPattern =
        RegExp(r'(\w+)\.([kK]\w+|[A-Z_]+)', multiLine: true);
    final matches = constantPattern.allMatches(content);

    for (final match in matches) {
      final className = match.group(1)!;
      final constantName = match.group(2)!;

      // Look for the constant definition in the same file or imported files
      final constDefPattern = RegExp(
          r'''(?:static\s+)?const\s+''' +
              constantName +
              r'''\s*=\s*['"]([^'"]+)['"]''',
          multiLine: true);

      final constMatch = constDefPattern.firstMatch(content);
      if (constMatch != null) {
        final assetPath = constMatch.group(1)!;
        if (_isValidAssetPath(assetPath)) {
          referenced.add(PatternMatcher.normalizePath(assetPath));
          Logger.debug(
              'Found constant reference: $className.$constantName -> "$assetPath"');
        }
      }
    }
  }

  /// Enhanced validation for asset paths
  bool _isValidAssetPath(String path) {
    if (path.isEmpty || path.length < 3) return false;

    // Skip common non-asset strings
    final skipPatterns = [
      'http://',
      'https://',
      'file://',
      'ftp://',
      'package:',
      'dart:',
      'flutter:',
      'localhost',
      '127.0.0.1',
      '.com',
      '.org',
      '.net',
    ];

    for (final skip in skipPatterns) {
      if (path.contains(skip)) return false;
    }

    // Must contain asset directory or have asset extension
    final assetDirs = ['assets/', 'images/', 'fonts/', 'data/'];
    final hasAssetDir = assetDirs.any((dir) => path.contains(dir));

    final assetExtensions = [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.bmp',
      '.webp',
      '.svg',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.txt',
      '.md',
      '.ttf',
      '.otf',
      '.woff',
      '.woff2',
      '.mp3',
      '.wav',
      '.ogg',
      '.m4a',
      '.mp4',
      '.mov',
      '.avi',
      '.pdf',
      '.zip',
      '.tar',
      '.gz'
    ];

    final hasAssetExt =
        assetExtensions.any((ext) => path.toLowerCase().endsWith(ext));

    return hasAssetDir || hasAssetExt;
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

  /// Enhanced asset reference checking with fuzzy matching
  bool _isAssetReferenced(String assetPath, Set<String> referencedAssets) {
    final normalizedAssetPath = PatternMatcher.normalizePath(assetPath);

    // Direct match
    if (referencedAssets.contains(normalizedAssetPath)) {
      Logger.debug('Direct match found for: $normalizedAssetPath');
      return true;
    }

    // Try multiple matching strategies
    for (final ref in referencedAssets) {
      final normalizedRef = PatternMatcher.normalizePath(ref);

      // Exact match
      if (normalizedAssetPath == normalizedRef) {
        Logger.debug('Exact match: $normalizedAssetPath == $normalizedRef');
        return true;
      }

      // Directory-based match
      if (normalizedRef.endsWith('/') &&
          normalizedAssetPath.startsWith(normalizedRef)) {
        Logger.debug(
            'Directory match: $normalizedAssetPath starts with $normalizedRef');
        return true;
      }

      // Prefix match
      if (!normalizedRef.endsWith('/') &&
          normalizedAssetPath.startsWith('$normalizedRef/')) {
        Logger.debug(
            'Prefix match: $normalizedAssetPath starts with $normalizedRef/');
        return true;
      }

      // Filename-only match (for cases where path structures differ)
      final assetFileName = path.basename(normalizedAssetPath);
      final refFileName = path.basename(normalizedRef);
      if (assetFileName == refFileName && assetFileName.isNotEmpty) {
        Logger.debug(
            'Filename match: $assetFileName (paths: $normalizedAssetPath vs $normalizedRef)');
        return true;
      }

      // Fuzzy match: same filename with different directory structures
      if (assetFileName == refFileName && assetFileName.contains('.')) {
        // Additional validation: check if the directory structure is reasonable
        final assetDirs = path.dirname(normalizedAssetPath).split('/');
        final refDirs = path.dirname(normalizedRef).split('/');

        // Check if they share common directory names
        final commonDirs = assetDirs.toSet().intersection(refDirs.toSet());
        if (commonDirs.isNotEmpty || assetDirs.length == refDirs.length) {
          Logger.debug(
              'Fuzzy match with shared directories: $normalizedAssetPath ~ $normalizedRef');
          return true;
        }
      }

      // Handle relative path references
      if (normalizedRef.startsWith('./') || normalizedRef.startsWith('../')) {
        final cleanRef = normalizedRef.replaceFirst(RegExp(r'^\.\.?/'), '');
        if (normalizedAssetPath.endsWith(cleanRef)) {
          Logger.debug(
              'Relative path match: $normalizedAssetPath ends with $cleanRef');
          return true;
        }
      }

      // Handle cases where asset path is referenced without full directory structure
      if (normalizedAssetPath.contains(normalizedRef) ||
          normalizedRef.contains(normalizedAssetPath)) {
        // Be careful with substring matches to avoid false positives
        final longer = normalizedAssetPath.length > normalizedRef.length
            ? normalizedAssetPath
            : normalizedRef;
        final shorter = normalizedAssetPath.length <= normalizedRef.length
            ? normalizedAssetPath
            : normalizedRef;

        if (longer.endsWith(shorter) || longer.contains('/$shorter')) {
          Logger.debug('Substring match: $longer contains $shorter');
          return true;
        }
      }
    }

    return false;
  }

  /// Print detailed asset analysis summary
  void _printAssetAnalysisSummary(
      List<File> assetFiles,
      List<String> declaredAssets,
      Set<String> referencedAssets,
      List<UnusedItem> unusedAssets,
      CleanupOptions options) {
    if (!options.verbose) return;

    Logger.section('📊 ASSET ANALYSIS SUMMARY');

    Logger.info('Total asset files found: ${assetFiles.length}');
    Logger.info('Assets declared in pubspec.yaml: ${declaredAssets.length}');
    Logger.info('Asset references found in code: ${referencedAssets.length}');
    Logger.info('Unused assets identified: ${unusedAssets.length}');

    if (declaredAssets.isNotEmpty) {
      Logger.section('📝 DECLARED ASSETS (pubspec.yaml)');
      for (final declared in declaredAssets.take(10)) {
        Logger.info('• $declared');
      }
      if (declaredAssets.length > 10) {
        Logger.info('... and ${declaredAssets.length - 10} more');
      }
    }

    if (referencedAssets.isNotEmpty) {
      Logger.section('🔗 REFERENCED ASSETS (found in code)');
      for (final referenced in referencedAssets.take(10)) {
        Logger.info('• $referenced');
      }
      if (referencedAssets.length > 10) {
        Logger.info('... and ${referencedAssets.length - 10} more');
      }
    }

    if (unusedAssets.isNotEmpty) {
      Logger.section('❌ UNUSED ASSETS');
      for (final unused in unusedAssets.take(10)) {
        Logger.info('• ${unused.name} (${unused.path})');
      }
      if (unusedAssets.length > 10) {
        Logger.info('... and ${unusedAssets.length - 10} more');
      }
    }

    // Calculate statistics
    final totalSize =
        assetFiles.fold<int>(0, (sum, file) => sum + file.lengthSync());
    final unusedSize =
        unusedAssets.fold<int>(0, (sum, item) => sum + (item.size ?? 0));
    final usedAssets = assetFiles.length - unusedAssets.length;

    Logger.section('📈 STATISTICS');
    Logger.info(
        'Usage rate: $usedAssets/${assetFiles.length} assets (${((usedAssets / assetFiles.length) * 100).round()}%)');
    Logger.info(
        'Total size: ${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB');
    Logger.info(
        'Unused size: ${(unusedSize / 1024 / 1024).toStringAsFixed(1)} MB');

    if (unusedAssets.length / assetFiles.length > 0.5) {
      Logger.warning(
          '⚠️ More than 50% of assets are unused - please verify results!');
    }
  }

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

/// Enhanced AST visitor to detect asset references in string variables, constants, and usage
class AssetVariableVisitor extends RecursiveAstVisitor<void> {
  final Set<String> references;
  final Map<String, String> variableValues = {}; // varName -> assetPath
  final Map<String, String> fieldValues = {}; // fieldName -> assetPath
  final Set<String> assetVariables =
      {}; // Track which variables contain asset paths
  final Set<String> usedVariables =
      {}; // Track which variables are actually used

  AssetVariableVisitor(this.references);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final varName = node.name.lexeme;
    final initializer = node.initializer;

    if (initializer is SimpleStringLiteral) {
      final value = initializer.value;
      if (_isAssetPath(value)) {
        variableValues[varName] = value;
        assetVariables.add(varName);
        references.add(PatternMatcher.normalizePath(value));
        Logger.debug('Found asset variable: $varName = "$value"');
      }
    } else if (initializer is AdjacentStrings) {
      // Handle concatenated strings
      final concatenated = _getConcatenatedString(initializer);
      if (_isAssetPath(concatenated)) {
        variableValues[varName] = concatenated;
        assetVariables.add(varName);
        references.add(PatternMatcher.normalizePath(concatenated));
        Logger.debug(
            'Found asset variable (concatenated): $varName = "$concatenated"');
      }
    } else if (initializer is StringInterpolation) {
      // Handle string interpolation
      final interpolated = _getInterpolatedString(initializer);
      if (_isAssetPath(interpolated)) {
        variableValues[varName] = interpolated;
        assetVariables.add(varName);
        references.add(PatternMatcher.normalizePath(interpolated));
        Logger.debug(
            'Found asset variable (interpolated): $varName = "$interpolated"');
      }
    }

    super.visitVariableDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    // Handle class fields and static constants
    for (final variable in node.fields.variables) {
      final fieldName = variable.name.lexeme;
      final initializer = variable.initializer;

      if (initializer is SimpleStringLiteral) {
        final value = initializer.value;
        if (_isAssetPath(value)) {
          fieldValues[fieldName] = value;
          assetVariables.add(fieldName);
          references.add(PatternMatcher.normalizePath(value));
          Logger.debug('Found asset field: $fieldName = "$value"');
        }
      } else if (initializer is AdjacentStrings) {
        final concatenated = _getConcatenatedString(initializer);
        if (_isAssetPath(concatenated)) {
          fieldValues[fieldName] = concatenated;
          assetVariables.add(fieldName);
          references.add(PatternMatcher.normalizePath(concatenated));
          Logger.debug(
              'Found asset field (concatenated): $fieldName = "$concatenated"');
        }
      }
    }

    super.visitFieldDeclaration(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final varName = node.name;

    // Check if this identifier refers to an asset variable
    if (assetVariables.contains(varName)) {
      usedVariables.add(varName);

      // Add the asset path from the variable
      final assetPath = variableValues[varName] ?? fieldValues[varName];
      if (assetPath != null) {
        references.add(PatternMatcher.normalizePath(assetPath));
        Logger.debug('Used asset variable: $varName -> "$assetPath"');
      }
    }

    super.visitSimpleIdentifier(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final value = node.value;
    if (_isAssetPath(value)) {
      references.add(PatternMatcher.normalizePath(value));
      Logger.debug('Found direct asset reference: "$value"');
    }
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    final targetName = node.target?.toString();

    // Enhanced detection for asset-related method calls
    final assetMethods = [
      'AssetImage',
      'asset',
      'load',
      'loadString',
      'loadStructuredData'
    ];

    final assetTargets = [
      'Image',
      'AssetImage',
      'rootBundle',
      'DefaultAssetBundle'
    ];

    bool isAssetMethod = assetMethods.contains(methodName) ||
        (targetName != null && assetTargets.contains(targetName));

    if (isAssetMethod && node.argumentList.arguments.isNotEmpty) {
      final firstArg = node.argumentList.arguments.first;

      if (firstArg is SimpleStringLiteral) {
        final assetPath = firstArg.value;
        references.add(PatternMatcher.normalizePath(assetPath));
        Logger.debug(
            'Found asset method call: $targetName.$methodName("$assetPath")');
      } else if (firstArg is SimpleIdentifier) {
        // Handle variable references in method calls
        final varName = firstArg.name;
        usedVariables.add(varName);

        final assetPath = variableValues[varName] ?? fieldValues[varName];
        if (assetPath != null) {
          references.add(PatternMatcher.normalizePath(assetPath));
          Logger.debug(
              'Found asset method call with variable: $targetName.$methodName($varName) -> "$assetPath"');
        }
      } else if (firstArg is PropertyAccess) {
        // Handle property access like MyClass.kAssetPath
        final propertyName = firstArg.propertyName.name;
        if (assetVariables.contains(propertyName)) {
          final assetPath =
              variableValues[propertyName] ?? fieldValues[propertyName];
          if (assetPath != null) {
            references.add(PatternMatcher.normalizePath(assetPath));
            Logger.debug(
                'Found asset method call with property: $targetName.$methodName($propertyName) -> "$assetPath"');
          }
        }
      }
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    // Handle named parameters like: decoration: BoxDecoration(image: AssetImage(...))
    final paramName = node.name.label.name;
    final assetParams = ['image', 'backgroundImage', 'asset', 'src', 'source'];

    if (assetParams.contains(paramName)) {
      final expression = node.expression;
      if (expression is SimpleStringLiteral && _isAssetPath(expression.value)) {
        references.add(PatternMatcher.normalizePath(expression.value));
        Logger.debug(
            'Found asset in named parameter: $paramName = "${expression.value}"');
      } else if (expression is SimpleIdentifier) {
        final varName = expression.name;
        final assetPath = variableValues[varName] ?? fieldValues[varName];
        if (assetPath != null) {
          references.add(PatternMatcher.normalizePath(assetPath));
          Logger.debug(
              'Found asset variable in named parameter: $paramName = $varName -> "$assetPath"');
        }
      }
    }

    super.visitNamedExpression(node);
  }

  /// Extract concatenated string from AdjacentStrings
  String _getConcatenatedString(AdjacentStrings node) {
    final buffer = StringBuffer();
    for (final string in node.strings) {
      if (string is SimpleStringLiteral) {
        buffer.write(string.value);
      }
    }
    return buffer.toString();
  }

  /// Extract interpolated string (simplified - gets static parts)
  String _getInterpolatedString(StringInterpolation node) {
    final buffer = StringBuffer();
    for (final element in node.elements) {
      if (element is InterpolationString) {
        buffer.write(element.value);
      } else if (element is InterpolationExpression) {
        // For simplicity, just add placeholder - could be enhanced
        buffer.write('*');
      }
    }
    return buffer.toString();
  }

  /// Enhanced asset path detection
  bool _isAssetPath(String value) {
    if (value.isEmpty) return false;

    // Common asset directories
    final assetDirs = ['assets/', 'images/', 'fonts/', 'data/', 'lib/assets/'];
    for (final dir in assetDirs) {
      if (value.contains(dir)) return true;
    }

    // Common asset file extensions
    final assetExtensions = [
      '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', // Images
      '.svg', // Vector graphics
      '.json', '.yaml', '.yml', '.xml', // Data files
      '.ttf', '.otf', '.woff', '.woff2', // Fonts
      '.mp3', '.wav', '.ogg', '.m4a', // Audio
      '.mp4', '.mov', '.avi', '.webm', // Video
      '.pdf', '.txt', '.md' // Documents
    ];

    for (final ext in assetExtensions) {
      if (value.toLowerCase().endsWith(ext)) return true;
    }

    return false;
  }

  /// Get summary of analysis for debugging
  Map<String, dynamic> getSummary() {
    return {
      'totalVariables': variableValues.length + fieldValues.length,
      'usedVariables': usedVariables.length,
      'assetVariables': assetVariables.length,
      'directReferences': references.length,
    };
  }
}
