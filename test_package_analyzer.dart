import 'package:unused_code_cleaner/src/analyzers/package_analyzer.dart';
import 'package:unused_code_cleaner/src/models/cleanup_options.dart';
import 'package:unused_code_cleaner/src/utils/file_utils.dart';

// Simple import visitor to test what we're detecting
class TestImportVisitor extends PackageAnalyzer {
  TestImportVisitor(String projectPath) : super(projectPath);

  Future<void> testImportDetection() async {
    final dartFiles = await FileUtils.findDartFiles('example');
    final usedPackages = await super._findUsedPackages(dartFiles, 'example');

    print('=== DETECTED USED PACKAGES ===');
    for (final pkg in usedPackages) {
      print('  ✓ $pkg');
    }

    final declaredDeps = await super._getDeclaredDependencies('example');
    print('\n=== DECLARED DEPENDENCIES ===');
    for (final dep in declaredDeps.values) {
      print('  - ${dep.name} (${dep.type})');
    }

    print('\n=== COMPARISON ===');
    for (final dep in declaredDeps.values) {
      final isUsed = usedPackages.contains(dep.name);
      print(
          '  ${isUsed ? "✓" : "❌"} ${dep.name} - ${isUsed ? "USED" : "UNUSED"}');
    }
  }
}

void main() async {
  print('Testing Package Detection...');

  final tester = TestImportVisitor('example');
  await tester.testImportDetection();
}
