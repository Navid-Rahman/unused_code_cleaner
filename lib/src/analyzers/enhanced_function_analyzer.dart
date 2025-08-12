import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;

import '../models/unused_item.dart';
import '../models/cleanup_options.dart';
import '../utils/logger.dart';

/// Enhanced function analyzer using dart-code-metrics proven patterns
/// for detecting unused functions and methods through comprehensive usage analysis
class EnhancedFunctionAnalyzer {
  late AnalysisContextCollection _analysisContextCollection;

  /// Track function definitions and their usage
  final Map<String, _FunctionDefinition> _functionDefinitions =
      <String, _FunctionDefinition>{};
  final Set<String> _usedFunctions = <String>{};
  final Set<String> _entryPointFunctions = <String>{};

  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedFunctions = <UnusedItem>[];

    try {
      Logger.info('🔧 Starting enhanced function analysis...');

      // Initialize analysis context
      final absoluteProjectPath = path.normalize(path.absolute(projectPath));
      _analysisContextCollection = AnalysisContextCollection(
        includedPaths: [absoluteProjectPath],
        excludedPaths: _getExcludedPaths(absoluteProjectPath),
      );

      // Step 1: Collect all function definitions
      await _collectFunctionDefinitions(dartFiles);
      Logger.debug('Found ${_functionDefinitions.length} function definitions');

      // Step 2: Identify entry point functions
      await _identifyEntryPointFunctions();
      Logger.debug(
          'Found ${_entryPointFunctions.length} entry point functions');

      // Step 3: Analyze function usage
      await _analyzeFunctionUsage(dartFiles);
      Logger.debug('Found ${_usedFunctions.length} used functions');

      // Step 4: Identify unused functions
      for (final entry in _functionDefinitions.entries) {
        final funcKey = entry.key;
        final funcDef = entry.value;

        if (!_isUsed(funcKey) && !_isSpecialFunction(funcDef)) {
          unusedFunctions.add(UnusedItem(
            name: funcDef.name,
            path: funcDef.filePath,
            type: UnusedItemType.function,
            lineNumber: funcDef.line,
            description: 'Function declared but never called',
          ));
        }
      }

      Logger.info(
          'Enhanced function analysis complete: ${unusedFunctions.length} unused functions found');
      return unusedFunctions;
    } catch (e) {
      Logger.error('Enhanced function analysis failed: $e');
      return [];
    }
  }

  Future<void> _collectFunctionDefinitions(List<File> dartFiles) async {
    for (final dartFile in dartFiles) {
      try {
        await _collectDefinitionsFromFile(dartFile);
      } catch (e) {
        Logger.error('Error collecting definitions from ${dartFile.path}: $e');
      }
    }
  }

  Future<void> _collectDefinitionsFromFile(File dartFile) async {
    try {
      final absoluteFilePath = path.normalize(path.absolute(dartFile.path));
      final context = _analysisContextCollection.contextFor(absoluteFilePath);
      final session = context.currentSession;
      final result = await session.getResolvedUnit(absoluteFilePath);

      if (result is ResolvedUnitResult) {
        final visitor =
            _FunctionDefinitionVisitor(absoluteFilePath, _functionDefinitions);
        result.unit.visitChildren(visitor);
      }
    } catch (e) {
      Logger.error('Error getting AST for ${dartFile.path}: $e');
    }
  }

  Future<void> _identifyEntryPointFunctions() async {
    // Add main functions and other entry points
    for (final entry in _functionDefinitions.entries) {
      final funcDef = entry.value;

      if (_isEntryPointFunction(funcDef)) {
        _entryPointFunctions.add(entry.key);
        _usedFunctions.add(entry.key);
      }
    }
  }

  bool _isEntryPointFunction(_FunctionDefinition funcDef) {
    // Main functions
    if (funcDef.name == 'main') return true;

    // Test functions
    if (funcDef.name.startsWith('test') && funcDef.filePath.contains('test')) {
      return true;
    }

    // Widget build methods
    if (funcDef.name == 'build' && funcDef.isMethod) return true;

    // Lifecycle methods
    final lifecycleMethods = [
      'initState',
      'dispose',
      'didUpdateWidget',
      'didChangeDependencies',
      'createState',
      'didChangeAppLifecycleState'
    ];
    if (lifecycleMethods.contains(funcDef.name)) return true;

    // Override methods (these might be called by framework)
    if (funcDef.isOverride) return true;

    return false;
  }

  Future<void> _analyzeFunctionUsage(List<File> dartFiles) async {
    for (final dartFile in dartFiles) {
      try {
        await _analyzeFunctionUsageInFile(dartFile);
      } catch (e) {
        Logger.error('Error analyzing function usage in ${dartFile.path}: $e');
      }
    }
  }

  Future<void> _analyzeFunctionUsageInFile(File dartFile) async {
    try {
      final absoluteFilePath = path.normalize(path.absolute(dartFile.path));
      final context = _analysisContextCollection.contextFor(absoluteFilePath);
      final session = context.currentSession;
      final result = await session.getResolvedUnit(absoluteFilePath);

      if (result is ResolvedUnitResult) {
        final visitor =
            _FunctionUsageVisitor(_usedFunctions, _functionDefinitions);
        result.unit.visitChildren(visitor);
      }
    } catch (e) {
      Logger.error('Error getting AST for ${dartFile.path}: $e');
    }
  }

  bool _isUsed(String functionKey) {
    return _usedFunctions.contains(functionKey) ||
        _entryPointFunctions.contains(functionKey);
  }

  bool _isSpecialFunction(_FunctionDefinition funcDef) {
    // Generated functions (usually end with specific patterns)
    if (funcDef.name.startsWith('_\$') ||
        funcDef.name.endsWith('FromJson') ||
        funcDef.name.endsWith('ToJson') ||
        funcDef.name.startsWith('_\$\$')) {
      return true;
    }

    // Constructor functions
    if (funcDef.isConstructor) return true;

    // Operator overloads
    if (funcDef.name.startsWith('operator')) return true;

    // Private functions that might be used via reflection
    if (funcDef.name.startsWith('_') && funcDef.filePath.contains('.g.dart')) {
      return true;
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

/// Function definition information
class _FunctionDefinition {
  final String name;
  final String filePath;
  final int line;
  final bool isMethod;
  final bool isConstructor;
  final bool isOverride;
  final bool isPrivate;

  _FunctionDefinition({
    required this.name,
    required this.filePath,
    required this.line,
    this.isMethod = false,
    this.isConstructor = false,
    this.isOverride = false,
    this.isPrivate = false,
  });

  String get key => '$filePath:$name:$line';
}

/// AST visitor for collecting function definitions
class _FunctionDefinitionVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final Map<String, _FunctionDefinition> functionDefinitions;

  _FunctionDefinitionVisitor(this.filePath, this.functionDefinitions);

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final name = node.name.lexeme;
    final line = node.offset;

    final funcDef = _FunctionDefinition(
      name: name,
      filePath: filePath,
      line: line,
      isPrivate: name.startsWith('_'),
    );

    functionDefinitions[funcDef.key] = funcDef;
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    final line = node.offset;

    final funcDef = _FunctionDefinition(
      name: name,
      filePath: filePath,
      line: line,
      isMethod: true,
      isOverride: _hasOverrideAnnotation(node),
      isPrivate: name.startsWith('_'),
    );

    functionDefinitions[funcDef.key] = funcDef;
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final className =
        (node.parent as ClassDeclaration?)?.name.lexeme ?? 'Unknown';
    final name = node.name?.lexeme ?? className;
    final line = node.offset;

    final funcDef = _FunctionDefinition(
      name: name,
      filePath: filePath,
      line: line,
      isConstructor: true,
      isPrivate: name.startsWith('_'),
    );

    functionDefinitions[funcDef.key] = funcDef;
    super.visitConstructorDeclaration(node);
  }

  bool _hasOverrideAnnotation(MethodDeclaration node) {
    return node.metadata
        .any((annotation) => annotation.name.name == 'override');
  }
}

/// AST visitor for analyzing function usage
class _FunctionUsageVisitor extends RecursiveAstVisitor<void> {
  final Set<String> usedFunctions;
  final Map<String, _FunctionDefinition> functionDefinitions;

  _FunctionUsageVisitor(this.usedFunctions, this.functionDefinitions);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    _markAsUsed(methodName);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    // Handle function calls through variables
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // In the new analyzer API, we track usage through other visitor methods
    // This method handles general identifier references
    super.visitSimpleIdentifier(node);
  }

  void _markAsUsed(String functionName) {
    // Find all function definitions with this name and mark them as used
    for (final entry in functionDefinitions.entries) {
      if (entry.value.name == functionName) {
        usedFunctions.add(entry.key);
      }
    }
  }
}
