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

/// Enhanced package analyzer using dart-code-metrics patterns
/// for detecting unused dependencies in pubspec.yaml
class EnhancedPackageAnalyzer {
  late AnalysisContextCollection _analysisContextCollection;

  /// Track used packages similar to dart-code-metrics approach
  final Set<String> _referencedPackages = <String>{};
  final Map<String, dynamic> _pubspecDependencies = <String, dynamic>{};
  final Map<String, dynamic> _pubspecDevDependencies = <String, dynamic>{};

  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedPackages = <UnusedItem>[];

    try {
      Logger.info('📦 Starting enhanced package analysis...');

      // Initialize analysis context
      final absoluteProjectPath = path.normalize(path.absolute(projectPath));
      _analysisContextCollection = AnalysisContextCollection(
        includedPaths: [absoluteProjectPath],
        excludedPaths: _getExcludedPaths(absoluteProjectPath),
      );

      // Step 1: Parse pubspec.yaml
      if (!await _parsePubspec(projectPath)) {
        Logger.error('Failed to parse pubspec.yaml');
        return [];
      }

      // Step 2: Analyze all Dart files for package usage
      await _analyzePackageUsage(dartFiles);
      Logger.debug('Found ${_referencedPackages.length} referenced packages');

      // Step 3: Find unused dependencies
      final unusedDeps = _findUnusedDependencies();
      for (final dep in unusedDeps) {
        unusedPackages.add(UnusedItem(
          name: dep,
          path: path.join(projectPath, 'pubspec.yaml'),
          type: UnusedItemType.package,
          description:
              'Package declared in pubspec.yaml but not imported in any Dart file',
        ));
      }

      // Step 4: Find unused dev dependencies (more conservative approach)
      final unusedDevDeps = _findUnusedDevDependencies();
      for (final dep in unusedDevDeps) {
        unusedPackages.add(UnusedItem(
          name: dep,
          path: path.join(projectPath, 'pubspec.yaml'),
          type: UnusedItemType.package,
          description:
              'Dev dependency declared in pubspec.yaml but not imported in any Dart file',
        ));
      }

      Logger.info(
          'Enhanced package analysis complete: ${unusedPackages.length} unused dependencies found');
      return unusedPackages;
    } catch (e) {
      Logger.error('Enhanced package analysis failed: $e');
      return [];
    }
  }

  Future<bool> _parsePubspec(String projectPath) async {
    try {
      final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
      if (!await pubspecFile.exists()) {
        Logger.error('pubspec.yaml not found');
        return false;
      }

      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content) as Map<dynamic, dynamic>;

      // Extract dependencies
      if (yaml['dependencies'] is Map) {
        _pubspecDependencies
            .addAll(Map<String, dynamic>.from(yaml['dependencies']));
      }

      // Extract dev dependencies
      if (yaml['dev_dependencies'] is Map) {
        _pubspecDevDependencies
            .addAll(Map<String, dynamic>.from(yaml['dev_dependencies']));
      }

      Logger.debug(
          'Parsed ${_pubspecDependencies.length} dependencies and ${_pubspecDevDependencies.length} dev dependencies');
      return true;
    } catch (e) {
      Logger.error('Error parsing pubspec.yaml: $e');
      return false;
    }
  }

  Future<void> _analyzePackageUsage(List<File> dartFiles) async {
    for (final dartFile in dartFiles) {
      try {
        await _analyzeFileForPackages(dartFile);
      } catch (e) {
        Logger.error('Error analyzing ${dartFile.path} for package usage: $e');
      }
    }
  }

  Future<void> _analyzeFileForPackages(File dartFile) async {
    try {
      final absoluteFilePath = path.normalize(path.absolute(dartFile.path));
      final context = _analysisContextCollection.contextFor(absoluteFilePath);
      final session = context.currentSession;
      final result = await session.getResolvedUnit(absoluteFilePath);

      if (result is ResolvedUnitResult) {
        final visitor = _PackageUsageVisitor(_referencedPackages);
        result.unit.visitChildren(visitor);
      }
    } catch (e) {
      Logger.error('Error getting AST for ${dartFile.path}: $e');
    }
  }

  List<String> _findUnusedDependencies() {
    final unused = <String>[];

    for (final dependency in _pubspecDependencies.keys) {
      // Skip Flutter SDK and some essential packages that might not be directly imported
      if (_isEssentialPackage(dependency)) {
        continue;
      }

      // Check if package is referenced
      if (!_referencedPackages.contains(dependency)) {
        unused.add(dependency);
      }
    }

    return unused;
  }

  List<String> _findUnusedDevDependencies() {
    final unused = <String>[];

    for (final dependency in _pubspecDevDependencies.keys) {
      // Skip build tools and common dev dependencies that might not be directly imported
      if (_isEssentialDevPackage(dependency)) {
        continue;
      }

      // Check if package is referenced
      if (!_referencedPackages.contains(dependency)) {
        unused.add(dependency);
      }
    }

    return unused;
  }

  bool _isEssentialPackage(String packageName) {
    // Packages that are essential but might not be directly imported
    final essentialPackages = [
      'flutter',
      'cupertino_icons',
      'meta',
    ];

    return essentialPackages.contains(packageName);
  }

  bool _isEssentialDevPackage(String packageName) {
    // Dev packages that are essential but might not be directly imported
    final essentialDevPackages = [
      'flutter_test',
      'flutter_lints',
      'build_runner',
      'json_annotation',
      'json_serializable',
      'freezed',
      'build_verify',
      'test',
      'mockito',
      'build_test',
      'source_gen_test',
    ];

    return essentialDevPackages.contains(packageName);
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

/// Enhanced AST visitor for package usage analysis
/// Based on dart-code-metrics ImportVisitor patterns
class _PackageUsageVisitor extends RecursiveAstVisitor<void> {
  final Set<String> referencedPackages;

  _PackageUsageVisitor(this.referencedPackages);

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null) {
      final packageName = _extractPackageName(uri);
      if (packageName != null) {
        referencedPackages.add(packageName);
      }
    }
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null) {
      final packageName = _extractPackageName(uri);
      if (packageName != null) {
        referencedPackages.add(packageName);
      }
    }
    super.visitExportDirective(node);
  }

  String? _extractPackageName(String uri) {
    // Extract package name from package: URIs
    if (uri.startsWith('package:')) {
      final parts = uri.split('/');
      if (parts.isNotEmpty) {
        final packagePart = parts[0];
        return packagePart.substring('package:'.length);
      }
    }
    return null;
  }
}
