import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;

import 'logger.dart';

/// Utility class for Dart AST analysis.
class AstUtils {
  static AnalysisContextCollection? _collection;

  /// Initializes the AnalysisContextCollection for the given project path.
  static void initializeAnalysisContext(String projectPath) {
    final normalizedPath = path.normalize(path.absolute(projectPath));
    _collection = AnalysisContextCollection(
      includedPaths: [normalizedPath],
      excludedPaths: [
        path.join(normalizedPath, '.dart_tool'),
        path.join(normalizedPath, 'build'),
        path.join(normalizedPath, '.pub'),
      ],
    );
    Logger.debug('AnalysisContextCollection initialized for $normalizedPath');
  }

  /// Disposes the AnalysisContextCollection.
  static void disposeAnalysisContext() {
    _collection = null;
    Logger.debug('AnalysisContextCollection disposed.');
  }

  /// Gets the resolved AST for a given Dart file.
  /// Returns null if the file cannot be resolved or if analysis context is not initialized.
  static Future<ResolvedUnitResult?> getResolvedUnit(String filePath) async {
    if (_collection == null) {
      Logger.warning(
          'AnalysisContextCollection not initialized. Call initializeAnalysisContext first.');
      return null;
    }
    try {
      final context = _collection!.contextFor(filePath);
      final result = await context.currentSession.getResolvedUnit(filePath);
      if (result is ResolvedUnitResult) {
        return result;
      }
      Logger.debug(
          'Failed to resolve unit for $filePath: ${result.runtimeType}');
      return null;
    } catch (e) {
      Logger.debug('Error getting resolved unit for $filePath: $e');
      return null;
    }
  }
}

/// Base visitor for collecting declarations and references.
/// This will be extended by specific analyzers.
class BaseAstVisitor extends RecursiveAstVisitor<void> {
  final Set<String> declarations = {};
  final Set<String> references = {};
  final String currentFilePath;

  BaseAstVisitor(this.currentFilePath);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // This is a very basic way to collect references. Specific analyzers
    // will need to refine this based on what they are looking for (e.g.,
    // function calls, variable usages, asset paths in string literals).
    references.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  // Add more visit methods as needed for specific types of declarations/references
}
