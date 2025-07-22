import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;

class DebugImportVisitor extends RecursiveAstVisitor<void> {
  final Set<String> foundPackages = <String>{};
  final List<String> debugLog = <String>[];

  @override
  void visitImportDirective(ImportDirective node) {
    try {
      debugLog.add('Import directive found: ${node.toString()}');
      final uri = node.uri.stringValue;
      debugLog.add('  URI string value: $uri');

      if (uri != null) {
        final packageName = _extractPackageName(uri);
        debugLog.add('  Extracted package: $packageName');
        if (packageName != null) {
          foundPackages.add(packageName);
        }
      }
    } catch (e, stack) {
      debugLog.add('  ERROR: $e');
      debugLog.add('  Stack: $stack');
    }
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    try {
      debugLog.add('Export directive found: ${node.toString()}');
      final uri = node.uri.stringValue;
      debugLog.add('  URI string value: $uri');

      if (uri != null) {
        final packageName = _extractPackageName(uri);
        debugLog.add('  Extracted package: $packageName');
        if (packageName != null) {
          foundPackages.add(packageName);
        }
      }
    } catch (e, stack) {
      debugLog.add('  ERROR: $e');
      debugLog.add('  Stack: $stack');
    }
    super.visitExportDirective(node);
  }

  String? _extractPackageName(String uri) {
    debugLog.add('    _extractPackageName called with: "$uri"');
    if (uri.startsWith('package:')) {
      final segments = uri.substring(8).split('/');
      debugLog.add('    Package URI segments: $segments');
      return segments.isNotEmpty ? segments.first : null;
    } else if (uri.startsWith('dart:')) {
      debugLog.add('    Dart library detected');
      return 'dart';
    }
    debugLog.add('    Not a package URI');
    return null;
  }
}

void main() async {
  final projectPath = Directory.current.path;
  print('Analyzing project: $projectPath');

  // Test with a simple Flutter app structure
  final testFile = File(path.join(projectPath, 'example', 'lib', 'main.dart'));
  if (!testFile.existsSync()) {
    print('Test file not found: ${testFile.path}');
    return;
  }

  final examplePath = path.join(projectPath, 'example');
  final collection = AnalysisContextCollection(
      includedPaths: [path.normalize(path.absolute(examplePath))]);
  final context = collection.contextFor(testFile.path);

  try {
    final result = await context.currentSession.getResolvedUnit(testFile.path);

    if (result is ResolvedUnitResult) {
      final visitor = DebugImportVisitor();
      result.unit.accept(visitor);

      print('\n=== DEBUG LOG ===');
      for (final line in visitor.debugLog) {
        print(line);
      }

      print('\n=== FOUND PACKAGES ===');
      for (final pkg in visitor.foundPackages) {
        print('- $pkg');
      }
    } else {
      print('Failed to resolve unit: $result');
    }
  } catch (e, stack) {
    print('Error during analysis: $e');
    print('Stack: $stack');
  }
}
