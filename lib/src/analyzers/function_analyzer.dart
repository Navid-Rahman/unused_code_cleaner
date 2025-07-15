import 'dart:io';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/pattern_matcher.dart';
import '../models/cleanup_options.dart';
import '../utils/ast_utils.dart';

class FunctionAnalyzer {
  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedFunctions = <UnusedItem>[];
    final allDeclarations =
        <String, FunctionInfo>{}; // Map name to FunctionInfo
    final allReferences = <String>{}; // Store referenced function names

    Logger.info('🔍 Starting function analysis (AST-based)...');

    AstUtils.initializeAnalysisContext(projectPath);

    try {
      for (final file in dartFiles) {
        if (PatternMatcher.isExcluded(file.path, options.excludePatterns)) {
          continue;
        }

        final resolvedUnit = await AstUtils.getResolvedUnit(file.path);
        if (resolvedUnit == null) {
          Logger.debug(
              'Skipping AST analysis for ${file.path} due to resolution errors.');
          continue;
        }

        final visitor = FunctionDeclarationVisitor(file.path);
        resolvedUnit.unit.accept(visitor);

        for (final decl in visitor.declarations) {
          allDeclarations[decl.name] = decl;
        }

        // Collect references from this file
        final referenceVisitor = ReferenceVisitor();
        resolvedUnit.unit.accept(referenceVisitor);
        allReferences.addAll(referenceVisitor.references);
      }

      // Identify unused functions
      for (final entry in allDeclarations.entries) {
        final functionName = entry.key;
        final functionInfo = entry.value;

        // A function is considered used if its name is referenced anywhere
        // or if it's a main function, a public API, or a framework method.
        if (!allReferences.contains(functionName) &&
            !_isMainFunction(functionInfo) &&
            !_isPublicApi(functionInfo) &&
            !_isFrameworkMethod(functionInfo)) {
          unusedFunctions.add(UnusedItem(
            name: functionInfo.name,
            path: functionInfo.filePath,
            type: UnusedItemType.function,
            lineNumber: functionInfo.lineNumber,
            description: 'Unused ${functionInfo.type} function/method',
          ));
        }
      }

      Logger.info(
          'Function analysis complete: ${unusedFunctions.length} unused functions found');
      return unusedFunctions;
    } catch (e) {
      Logger.error('Function analysis failed: $e');
      return [];
    } finally {
      AstUtils.disposeAnalysisContext();
    }
  }

  bool _isMainFunction(FunctionInfo functionInfo) {
    return functionInfo.name == 'main' && functionInfo.type == 'function';
  }

  bool _isPublicApi(FunctionInfo functionInfo) {
    // Consider functions/methods that are not private (don't start with '_')
    // Be conservative - don't mark public methods as unused
    return !functionInfo.name.startsWith('_');
  }

  bool _isFrameworkMethod(FunctionInfo functionInfo) {
    final specialPatterns = [
      r'^main$',
      r'^_.*Test$',
      r'^test.*',
      r'^setUp$',
      r'^tearDown$',
      r'^build$',
      r'^initState$',
      r'^dispose$',
      r'^didChangeDependencies$',
      r'^didUpdateWidget$',
      r'^deactivate$',
      r'^debugFillProperties$',
      r'^reassemble$',
      r'^noSuchMethod$',
      r'^call$',
      r'^copyWith$',
      r'^fromJson$',
      r'^toJson$',
      r'^fromMap$',
      r'^toMap$',
      r'^when$',
      r'^map$',
      r'^maybeMap$',
      r'^maybeWhen$',
      r'^toString$',
      r'^hashCode$',
      r'^operator==$',
      r'^on[A-Z].*', // Callbacks like onPressed
    ];

    return specialPatterns
            .any((pattern) => RegExp(pattern).hasMatch(functionInfo.name)) ||
        functionInfo.name.endsWith('Provider') ||
        functionInfo.name.contains('Generated') ||
        functionInfo.name.startsWith('_'); // Private methods - be conservative
  }
}

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

class FunctionDeclarationVisitor extends RecursiveAstVisitor<void> {
  final List<FunctionInfo> declarations = [];
  final String currentFilePath;

  FunctionDeclarationVisitor(this.currentFilePath);

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    declarations.add(FunctionInfo(
      name: node.name.lexeme,
      filePath: currentFilePath,
      lineNumber: node.name.offset,
      type: 'function',
    ));
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    declarations.add(FunctionInfo(
      name: node.name.lexeme,
      filePath: currentFilePath,
      lineNumber: node.name.offset,
      type: 'method',
    ));
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final className = (node.parent as ClassDeclaration).name.lexeme;
    final constructorName = node.name?.lexeme;
    final name =
        constructorName != null ? '$className.$constructorName' : className;

    declarations.add(FunctionInfo(
      name: name,
      filePath: currentFilePath,
      lineNumber: node.offset,
      type: 'constructor',
    ));
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    // Handle function variables (e.g., final myFunc = () => {...})
    if (node.initializer is FunctionExpression) {
      declarations.add(FunctionInfo(
        name: node.name.lexeme,
        filePath: currentFilePath,
        lineNumber: node.name.offset,
        type: 'function variable',
      ));
    }
    super.visitVariableDeclaration(node);
  }
}

class ReferenceVisitor extends RecursiveAstVisitor<void> {
  final Set<String> references = {};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // Only add if it's not part of a declaration
    if (node.parent is! FunctionDeclaration &&
        node.parent is! MethodDeclaration &&
        node.parent is! ConstructorDeclaration &&
        node.parent is! VariableDeclaration) {
      references.add(node.name);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    references.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (node.function is SimpleIdentifier) {
      references.add((node.function as SimpleIdentifier).name);
    }
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    references.add(node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    references.add(node.propertyName.name);
    super.visitPropertyAccess(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.name2.lexeme;
    references.add(typeName);

    // Add constructor name if specified
    final constructorName = node.constructorName.name?.name;
    if (constructorName != null) {
      references.add('$typeName.$constructorName');
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    references.add(node.name.label.name);
    super.visitNamedExpression(node);
  }
}
