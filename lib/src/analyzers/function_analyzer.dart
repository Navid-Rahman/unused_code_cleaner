import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/pattern_matcher.dart';
import '../models/cleanup_options.dart';

class FunctionAnalyzer {
  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedFunctions = <UnusedItem>[];

    try {
      final collection = AnalysisContextCollection(includedPaths: [projectPath]);
      final context = collection.contextFor(projectPath);
      final allFunctions = <FunctionInfo>[];
      final allReferences = <String>{};

      for (final file in dartFiles) {
        if (PatternMatcher.isExcluded(file.path, options.excludePatterns)) {
          continue;
        }

        try {
          final result = await context.currentSession.getResolvedUnit(file.path);
          if (result is ResolvedUnitResult) {
            final visitor = FunctionVisitor()..currentFilePath = file.path;
            result.unit.accept(visitor);
            allFunctions.addAll(visitor.functions);
            allReferences.addAll(visitor.references);
          } else {
            Logger.warning('Could not resolve ${file.path}, falling back to string parsing');
            await _parseFileFallback(file, allFunctions, allReferences);
          }
        } catch (e) {
          Logger.warning('Error analyzing ${file.path}: $e, skipping');
        }
      }

      for (final function in allFunctions) {
        if (!allReferences.contains(function.name) && !_isSpecialFunction(function.name)) {
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

  Future<void> _parseFileFallback(File file, List<FunctionInfo> functions, Set<String> references) async {
    try {
      final content = await file.readAsString();
      final lines = content.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.contains('(') && (line.contains('void ') || line.contains('Future<') || line.contains('String ') || line.contains('int '))) {
          final nameStart = line.indexOf(RegExp(r'[a-zA-Z]')) + line.indexOf('(');
          if (nameStart != -1) {
            final name = line.substring(0, nameStart).split(' ').last;
            functions.add(FunctionInfo(name: name, filePath: file.path, lineNumber: i + 1, type: 'function'));
          }
        }
        if (line.contains('.')) {
          final parts = line.split('.');
          for (final part in parts) {
            if (part.contains('(')) references.add(part.split('(')[0]);
          }
        }
      }
    } catch (e) {
      Logger.debug('Fallback parsing failed for ${file.path}: $e');
    }
  }

  bool _isSpecialFunction(String name) {
    final specialFunctions = {
      'main', 'build', 'createState', 'dispose', 'initState', 'didChangeDependencies',
      'didUpdateWidget', 'deactivate', 'toString', 'hashCode', 'operator', 'useEffect', 'useState'
    };
    return specialFunctions.any((special) => name.contains(special));
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

class FunctionVisitor extends RecursiveAstVisitor<void> {
  final functions = <FunctionInfo>[];
  final references = <String>{};
  late String currentFilePath;

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

  @override
  void visitMethodInvocation(MethodInvocation node) {
    references.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.parent is MethodInvocation || node.parent is FunctionExpressionInvocation) {
      references.add(node.name);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (node.function is SimpleIdentifier) {
      references.add((node.function as SimpleIdentifier).name);
    }
    super.visitFunctionExpressionInvocation(node);
  }
}