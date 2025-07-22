import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
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

/// Enhanced semantic-aware element usage tracker
class ElementUsageTracker {
  final Set<Element> usedElements = {};
  final Set<Element> declaredElements = {};
  final Set<String> conditionalImports = {};
  final Map<String, Set<Element>> fileElements = {};

  void recordUsedElement(Element element) {
    final containingLibrary = element.library;
    if (containingLibrary == null) return;
    usedElements.add(element);
  }

  void recordDeclaredElement(Element element) {
    final containingLibrary = element.library;
    if (containingLibrary == null) return;
    declaredElements.add(element);
  }

  void recordConditionalImport(String importPath) {
    conditionalImports.add(importPath);
  }

  bool isElementUsed(Element element) {
    return usedElements
            .any((usedElement) => _isEqualElements(usedElement, element)) ||
        _isConditionallyUsed(element);
  }

  bool _isEqualElements(Element left, Element right) {
    if (left == right) return true;

    final leftLibrary = left.library;
    final rightSource = right.librarySource;

    // Handle library resolution issues
    return leftLibrary != null &&
        rightSource != null &&
        left.name == right.name &&
        leftLibrary.units
            .map((unit) => unit.source.fullName)
            .contains(rightSource.fullName);
  }

  bool _isConditionallyUsed(Element element) {
    final elementPath = element.source?.fullName;
    if (elementPath == null) return false;

    return conditionalImports.any((importPath) =>
        elementPath.contains(importPath) || importPath.contains(elementPath));
  }
}

/// Enhanced AST visitor for semantic element tracking
class SemanticElementVisitor extends RecursiveAstVisitor<void> {
  final ElementUsageTracker tracker;
  final String currentFilePath;

  SemanticElementVisitor(this.tracker, this.currentFilePath);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.staticElement;
    if (element != null) {
      // Check if this is a declaration or usage
      if (_isDeclaration(node)) {
        tracker.recordDeclaredElement(element);
      } else {
        tracker.recordUsedElement(element);
      }
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.staticElement;
    if (element != null) {
      tracker.recordUsedElement(element);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final element = node.constructorName.staticElement;
    if (element != null) {
      tracker.recordUsedElement(element);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitImportDirective(ImportDirective node) {
    // Handle conditional imports
    if (node.configurations.isNotEmpty) {
      for (final config in node.configurations) {
        tracker.recordConditionalImport(config.uri.stringValue ?? '');
      }
    }
    super.visitImportDirective(node);
  }

  bool _isDeclaration(SimpleIdentifier node) {
    final parent = node.parent;
    return parent is Declaration ||
        parent is VariableDeclaration ||
        parent is FormalParameter ||
        parent is CatchClause ||
        parent is ForEachPartsWithDeclaration;
  }
}
