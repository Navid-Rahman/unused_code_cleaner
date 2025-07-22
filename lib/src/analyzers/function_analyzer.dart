import 'dart:io';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/pattern_matcher.dart';
import '../models/cleanup_options.dart';
import '../utils/ast_utils.dart';

/// Enhanced function analyzer using semantic element analysis
class FunctionAnalyzer {
  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedFunctions = <UnusedItem>[];
    final tracker = ElementUsageTracker();

    Logger.info('🔍 Starting enhanced function analysis (semantic-based)...');

    AstUtils.initializeAnalysisContext(projectPath);

    try {
      // First pass: collect all declarations and usages
      for (final file in dartFiles) {
        if (PatternMatcher.isExcluded(file.path, options.excludePatterns)) {
          continue;
        }

        final resolvedUnit = await AstUtils.getResolvedUnit(file.path);
        if (resolvedUnit == null) {
          Logger.debug(
              'Skipping analysis for ${file.path} due to resolution errors.');
          continue;
        }

        final visitor = SemanticElementVisitor(tracker, file.path);
        resolvedUnit.unit.accept(visitor);

        // Also collect Flutter-specific patterns
        final flutterVisitor = FlutterAwareVisitor(tracker);
        resolvedUnit.unit.accept(flutterVisitor);
      }

      // Second pass: identify unused functions
      for (final declaredElement in tracker.declaredElements) {
        if (_isFunctionElement(declaredElement) &&
            !tracker.isElementUsed(declaredElement) &&
            !_isExcludedFromAnalysis(declaredElement)) {
          final location = _getElementLocation(declaredElement);
          if (location != null) {
            unusedFunctions.add(UnusedItem(
              name: declaredElement.displayName,
              path: location.filePath,
              type: UnusedItemType.function,
              lineNumber: location.lineNumber,
              description:
                  'Unused ${_getElementTypeDescription(declaredElement)}',
            ));
          }
        }
      }

      Logger.info(
          'Enhanced function analysis complete: ${unusedFunctions.length} unused functions found');
      return unusedFunctions;
    } catch (e) {
      Logger.error('Enhanced function analysis failed: $e');
      return [];
    } finally {
      AstUtils.disposeAnalysisContext();
    }
  }

  bool _isFunctionElement(Element element) {
    return element is FunctionElement ||
        element is MethodElement ||
        element is ConstructorElement ||
        element is PropertyAccessorElement && element.isSetter == false;
  }

  bool _isExcludedFromAnalysis(Element element) {
    final name = element.displayName;

    // Main function
    if (name == 'main' && element is FunctionElement) {
      return true;
    }

    // Public API (conservative approach)
    if (!name.startsWith('_')) {
      return true;
    }

    // Flutter framework methods
    if (_isFlutterFrameworkMethod(element)) {
      return true;
    }

    // Test methods
    if (_isTestMethod(element)) {
      return true;
    }

    // Generated code patterns
    if (_isGeneratedCode(element)) {
      return true;
    }

    // Override methods
    if (_isOverrideMethod(element)) {
      return true;
    }

    return false;
  }

  bool _isFlutterFrameworkMethod(Element element) {
    if (element is! MethodElement) return false;

    final methodName = element.name;
    final flutterMethods = {
      'build',
      'initState',
      'dispose',
      'didChangeDependencies',
      'didUpdateWidget',
      'deactivate',
      'reassemble',
      'debugFillProperties',
      'createState',
      'createElement',
      'canUpdate'
    };

    if (flutterMethods.contains(methodName)) {
      return true;
    }

    // Check if it's in a Flutter widget/state class
    final enclosingClass = element.enclosingElement3;
    if (enclosingClass is ClassElement) {
      final className = enclosingClass.name;
      if (className.endsWith('Widget') || className.endsWith('State')) {
        return true;
      }

      // Check supertype chain for Flutter classes
      return _hasFlutterSupertype(enclosingClass);
    }

    return false;
  }

  bool _hasFlutterSupertype(ClassElement classElement) {
    final supertype = classElement.supertype;
    if (supertype == null) return false;

    final supertypeName = supertype.element.name;
    final flutterBaseClasses = {
      'Widget',
      'StatelessWidget',
      'StatefulWidget',
      'State',
      'InheritedWidget',
      'RenderObject',
      'RenderBox'
    };

    if (flutterBaseClasses.contains(supertypeName)) {
      return true;
    }

    // Check interfaces
    for (final interface in classElement.interfaces) {
      if (flutterBaseClasses.contains(interface.element.name)) {
        return true;
      }
    }

    // Recursively check supertype
    if (supertype.element is ClassElement) {
      return _hasFlutterSupertype(supertype.element as ClassElement);
    }
    return false;
  }

  bool _isTestMethod(Element element) {
    final name = element.displayName;
    return name.startsWith('test') ||
        name == 'setUp' ||
        name == 'tearDown' ||
        name.endsWith('Test');
  }

  bool _isGeneratedCode(Element element) {
    final source = element.source;
    if (source == null) return false;

    final filePath = source.fullName;
    return filePath.endsWith('.g.dart') ||
        filePath.endsWith('.freezed.dart') ||
        filePath.endsWith('.gr.dart') ||
        filePath.contains('.generated.');
  }

  bool _isOverrideMethod(Element element) {
    if (element is! MethodElement) return false;

    // Check if method has @override annotation
    return element.metadata
        .any((annotation) => annotation.element?.displayName == 'override');
  }

  String _getElementTypeDescription(Element element) {
    if (element is FunctionElement) return 'function';
    if (element is MethodElement) return 'method';
    if (element is ConstructorElement) return 'constructor';
    if (element is PropertyAccessorElement) return 'getter';
    return 'declaration';
  }

  ElementLocation? _getElementLocation(Element element) {
    final source = element.source;
    if (source == null) return null;

    final nameOffset = element.nameOffset;
    if (nameOffset == -1) return null;

    // We would need line info to get the actual line number
    // For now, we'll use the offset as a proxy
    return ElementLocation(
      filePath: source.fullName,
      lineNumber: nameOffset,
    );
  }
}

/// Flutter-aware visitor for special framework patterns
class FlutterAwareVisitor extends RecursiveAstVisitor<void> {
  final ElementUsageTracker tracker;

  FlutterAwareVisitor(this.tracker);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    // Handle Flutter State lifecycle methods specially
    final methodName = node.name.lexeme;
    if (_isStateLifecycleMethod(methodName)) {
      final element = node.declaredElement;
      if (element != null) {
        // Mark as used if it's a framework method
        tracker.recordUsedElement(element);
      }
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Handle widget instantiation
    final element = node.constructorName.staticElement;
    if (element != null) {
      tracker.recordUsedElement(element);

      // Also mark the class as used
      final classElement = element.enclosingElement3;
      tracker.recordUsedElement(classElement);
    }
    super.visitInstanceCreationExpression(node);
  }

  bool _isStateLifecycleMethod(String methodName) {
    const lifecycleMethods = {
      'initState',
      'build',
      'dispose',
      'didChangeDependencies',
      'didUpdateWidget',
      'deactivate',
      'reassemble'
    };
    return lifecycleMethods.contains(methodName);
  }
}

class ElementLocation {
  final String filePath;
  final int lineNumber;

  ElementLocation({required this.filePath, required this.lineNumber});
}
