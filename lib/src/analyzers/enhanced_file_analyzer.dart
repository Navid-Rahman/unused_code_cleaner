import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;

import '../models/unused_item.dart';
import '../models/cleanup_options.dart';
import '../utils/logger.dart';

/// Enhanced file analyzer using dart-code-metrics proven patterns
/// for detecting unused Dart files through comprehensive dependency analysis
class EnhancedFileAnalyzer {
  late AnalysisContextCollection _analysisContextCollection;

  /// Track used files similar to dart-code-metrics approach
  final Set<String> _referencedFiles = <String>{};
  final Set<String> _entryPoints = <String>{};
  final Map<String, Set<String>> _fileDependencies = <String, Set<String>>{};

  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedFiles = <UnusedItem>[];

    try {
      Logger.info('🔍 Starting enhanced file analysis...');

      // Initialize analysis context
      final absoluteProjectPath = path.normalize(path.absolute(projectPath));
      _analysisContextCollection = AnalysisContextCollection(
        includedPaths: [absoluteProjectPath],
        excludedPaths: _getExcludedPaths(absoluteProjectPath),
      );

      // Step 1: Identify entry points (similar to dart-code-metrics)
      await _identifyEntryPoints(projectPath, dartFiles);
      Logger.debug('Found ${_entryPoints.length} entry points');

      // Step 2: Build dependency graph
      await _buildDependencyGraph(dartFiles);
      Logger.debug('Built dependency graph for ${dartFiles.length} files');

      // Step 3: Mark files reachable from entry points
      await _markReachableFiles();
      Logger.debug('Found ${_referencedFiles.length} reachable files');

      // Step 4: Identify unused files
      for (final dartFile in dartFiles) {
        final filePath = dartFile.path;
        final relativePath = path.relative(filePath, from: projectPath);

        if (!_isFileUsed(filePath) && !_isSpecialFile(relativePath)) {
          final fileName = path.basename(filePath);
          unusedFiles.add(UnusedItem(
            name: fileName,
            path: filePath,
            type: UnusedItemType.file,
            description: 'Dart file not imported by any other file',
          ));
        }
      }

      Logger.info(
          'Enhanced file analysis complete: ${unusedFiles.length} unused files found');
      return unusedFiles;
    } catch (e) {
      Logger.error('Enhanced file analysis failed: $e');
      return [];
    }
  }

  /// Identify entry points similar to dart-code-metrics approach
  Future<void> _identifyEntryPoints(
      String projectPath, List<File> dartFiles) async {
    // Main entry points
    final mainFiles = [
      'lib/main.dart',
      'bin/main.dart',
      'web/main.dart',
      'test/main.dart',
    ];

    for (final mainFile in mainFiles) {
      final file = File(path.join(projectPath, mainFile));
      if (await file.exists()) {
        _entryPoints.add(file.path);
      }
    }

    // Find all files that could be entry points (exported, main functions, etc.)
    for (final dartFile in dartFiles) {
      if (await _isEntryPoint(dartFile)) {
        _entryPoints.add(dartFile.path);
      }
    }

    // Test files are entry points
    for (final dartFile in dartFiles) {
      if (dartFile.path.contains('/test/') ||
          dartFile.path.endsWith('_test.dart')) {
        _entryPoints.add(dartFile.path);
      }
    }
  }

  Future<bool> _isEntryPoint(File dartFile) async {
    try {
      final content = await dartFile.readAsString();

      // Check for main function
      if (content.contains('void main(') ||
          content.contains('Future<void> main(')) {
        return true;
      }

      // Check for exports that make this a library entry point
      if (content.contains('export ') && !content.contains('// export')) {
        return true;
      }

      // Check for part of directives (these are not entry points)
      if (content.contains('part of ')) {
        return false;
      }

      return false;
    } catch (e) {
      Logger.error('Error checking if ${dartFile.path} is entry point: $e');
      return false;
    }
  }

  /// Build comprehensive dependency graph using AST analysis
  Future<void> _buildDependencyGraph(List<File> dartFiles) async {
    for (final dartFile in dartFiles) {
      try {
        final dependencies = await _analyzeDependencies(dartFile);
        _fileDependencies[dartFile.path] = dependencies;
      } catch (e) {
        Logger.error('Error analyzing dependencies for ${dartFile.path}: $e');
        _fileDependencies[dartFile.path] = <String>{};
      }
    }
  }

  /// Analyze dependencies using advanced AST patterns
  Future<Set<String>> _analyzeDependencies(File dartFile) async {
    final dependencies = <String>{};

    try {
      final absoluteFilePath = path.normalize(path.absolute(dartFile.path));
      final context = _analysisContextCollection.contextFor(absoluteFilePath);
      final session = context.currentSession;
      final result = await session.getResolvedUnit(absoluteFilePath);

      if (result is ResolvedUnitResult) {
        final visitor = _DependencyVisitor(dartFile.path, dependencies);
        result.unit.visitChildren(visitor);
      }
    } catch (e) {
      Logger.error('Error getting AST for ${dartFile.path}: $e');
    }

    return dependencies;
  }

  /// Mark all files reachable from entry points (similar to graph traversal in dart-code-metrics)
  Future<void> _markReachableFiles() async {
    final visited = <String>{};
    final queue = <String>[];

    // Start with all entry points
    queue.addAll(_entryPoints);
    _referencedFiles.addAll(_entryPoints);

    while (queue.isNotEmpty) {
      final currentFile = queue.removeAt(0);
      if (visited.contains(currentFile)) continue;
      visited.add(currentFile);

      final dependencies = _fileDependencies[currentFile] ?? <String>{};
      for (final dependency in dependencies) {
        if (!_referencedFiles.contains(dependency)) {
          _referencedFiles.add(dependency);
          queue.add(dependency);
        }
      }
    }
  }

  bool _isFileUsed(String filePath) {
    return _referencedFiles.contains(filePath) ||
        _entryPoints.contains(filePath);
  }

  bool _isSpecialFile(String relativePath) {
    // Files that should never be marked as unused
    final specialPatterns = [
      'lib/main.dart',
      'bin/main.dart',
      'web/main.dart',
      'test/main.dart',
      r'.*\.g\.dart$', // Generated files
      r'.*\.freezed\.dart$', // Freezed files
      r'.*\.gr\.dart$', // Auto route files
      r'.*\.config\.dart$', // Config files
    ];

    for (final pattern in specialPatterns) {
      if (RegExp(pattern).hasMatch(relativePath)) {
        return true;
      }
    }

    return false;
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

/// Advanced AST visitor for dependency analysis
/// Based on dart-code-metrics UsedCodeVisitor patterns
class _DependencyVisitor extends RecursiveAstVisitor<void> {
  final String currentFilePath;
  final Set<String> dependencies;
  final String projectRoot;

  _DependencyVisitor(this.currentFilePath, this.dependencies)
      : projectRoot = _findProjectRoot(currentFilePath);

  static String _findProjectRoot(String filePath) {
    var directory = Directory(path.dirname(filePath));
    while (directory.path != directory.parent.path) {
      if (File(path.join(directory.path, 'pubspec.yaml')).existsSync()) {
        return directory.path;
      }
      directory = directory.parent;
    }
    return path.dirname(filePath);
  }

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null &&
        !uri.startsWith('dart:') &&
        !uri.startsWith('package:')) {
      final resolvedPath = _resolveRelativeImport(uri);
      if (resolvedPath != null) {
        dependencies.add(resolvedPath);
      }
    }
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null &&
        !uri.startsWith('dart:') &&
        !uri.startsWith('package:')) {
      final resolvedPath = _resolveRelativeImport(uri);
      if (resolvedPath != null) {
        dependencies.add(resolvedPath);
      }
    }
    super.visitExportDirective(node);
  }

  @override
  void visitPartDirective(PartDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null) {
      final resolvedPath = _resolveRelativeImport(uri);
      if (resolvedPath != null) {
        dependencies.add(resolvedPath);
      }
    }
    super.visitPartDirective(node);
  }

  @override
  void visitPartOfDirective(PartOfDirective node) {
    // Part of files depend on their library
    if (node.uri != null) {
      final uri = node.uri!.stringValue;
      if (uri != null) {
        final resolvedPath = _resolveRelativeImport(uri);
        if (resolvedPath != null) {
          dependencies.add(resolvedPath);
        }
      }
    }
    super.visitPartOfDirective(node);
  }

  String? _resolveRelativeImport(String uri) {
    try {
      final currentDir = path.dirname(currentFilePath);
      var resolvedPath = path.normalize(path.join(currentDir, uri));

      // Add .dart extension if not present
      if (!resolvedPath.endsWith('.dart')) {
        resolvedPath += '.dart';
      }

      // Check if file exists
      if (File(resolvedPath).existsSync()) {
        return resolvedPath;
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
