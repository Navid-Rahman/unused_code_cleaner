import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../models/cleanup_options.dart';

/// Analyzes Dart files to identify unused functions and methods.
///
/// This analyzer uses the Dart analyzer package to parse AST nodes and identify
/// function declarations that are not referenced anywhere in the codebase.
/// It excludes special functions like main(), build(), lifecycle methods, etc.
class FunctionAnalyzer {
  /// Analyzes Dart files to find unused functions and methods.
  ///
  /// Scans all Dart files in the project using the analyzer package to:
  /// - Collect all function and method declarations
  /// - Track all function/method references and invocations
  /// - Identify functions that are declared but never used
  /// - Exclude special functions (main, build, lifecycle methods, etc.)
  ///
  /// Returns a list of [UnusedItem] objects representing unused functions.
  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedFunctions = <UnusedItem>[];

    try {
      // Create analysis context
      final collection =
          AnalysisContextCollection(includedPaths: [projectPath]);
      final context = collection.contextFor(projectPath);

      // Collect all function declarations
      final allFunctions = <FunctionInfo>[];
      final allReferences = <String>{};

      for (final file in dartFiles) {
        // Skip excluded files
        if (options.excludePatterns
            .any((pattern) => file.path.contains(pattern))) {
          continue;
        }

        final result = await context.currentSession.getResolvedUnit(file.path);

        if (result is ResolvedUnitResult) {
          final visitor = FunctionVisitor()..currentFilePath = file.path;
          result.unit.accept(visitor);

          allFunctions.addAll(visitor.functions);
          allReferences.addAll(visitor.references);
        }
      }

      // Find unused functions
      for (final function in allFunctions) {
        if (!allReferences.contains(function.name) &&
            !_isSpecialFunction(function.name)) {
          unusedFunctions.add(UnusedItem(
            name: function.name,
            path: function.filePath,
            type: UnusedItemType.function,
            lineNumber: function.lineNumber,
            description: 'Unused ${function.type} function',
          ));
        }
      }

      Logger.info('Found ${unusedFunctions.length} unused functions');
      return unusedFunctions;
    } catch (e) {
      Logger.error('Function analysis failed: $e');
      return [];
    }
  }

  /// Checks if a function name should be excluded from unused analysis.
  ///
  /// Special functions that should never be marked as unused:
  /// - main: Application entry point
  /// - build: Widget build methods
  /// - createState: StatefulWidget state creation
  /// - Lifecycle methods: dispose, initState, didChangeDependencies, etc.
  /// - Object methods: toString, hashCode, operator overrides
  bool _isSpecialFunction(String name) {
    // Don't mark these as unused
    final specialFunctions = {
      'main',
      'build',
      'createState',
      'dispose',
      'initState',
      'didChangeDependencies',
      'didUpdateWidget',
      'deactivate',
      'toString',
      'hashCode',
      'operator',
    };

    return specialFunctions.any((special) => name.contains(special));
  }
}

/// Represents metadata about a function or method declaration.
///
/// Contains information needed to track function usage and generate
/// unused function reports including location and type details.
class FunctionInfo {
  final String name;
  final String filePath;
  final int lineNumber;
  final String type;

  FunctionInfo({
    required this.name,
    required this.filePath,
    required this.lineNumber,
    required this.type,
  });
}

/// AST visitor that extracts function declarations and references.
///
/// Walks through the Dart AST to collect:
/// - Function declarations (top-level functions)
/// - Method declarations (class methods, excluding static)
/// - Function/method invocations and references
///
/// Used by [FunctionAnalyzer] to build a complete picture of function usage.
class FunctionVisitor extends RecursiveAstVisitor<void> {
  final functions = <FunctionInfo>[];
  final references = <String>{};
  late String currentFilePath;

  /// Visits function declarations and records their metadata.
  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    functions.add(FunctionInfo(
      name: node.name.lexeme,
      filePath: currentFilePath,
      lineNumber: node.offset,
      type: 'function',
    ));
    super.visitFunctionDeclaration(node);
  }

  /// Visits method declarations and records non-static methods.
  /// Static methods are excluded as they're often utility functions.
  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (!node.isStatic) {
      functions.add(FunctionInfo(
        name: node.name.lexeme,
        filePath: currentFilePath,
        lineNumber: node.offset,
        type: 'method',
      ));
    }
    super.visitMethodDeclaration(node);
  }

  /// Visits method invocations and records the called method names.
  @override
  void visitMethodInvocation(MethodInvocation node) {
    references.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }

  /// Visits simple identifiers and records potential function references.
  /// This catches function calls without explicit method invocation syntax.
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    references.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}
