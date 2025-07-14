import 'dart:io';
import 'package:unused_code_cleaner/unused_code_cleaner.dart';

/// Test script to verify the critical bug fixes for unused code cleaner
void main() async {
  print('🧪 Testing Unused Code Cleaner Bug Fixes');
  print('==========================================');
  
  // Create a temporary test directory
  final testDir = await Directory.systemTemp.createTemp('bug_fix_test_');
  print('📁 Created test directory: ${testDir.path}');
  
  try {
    // Create a realistic Flutter project structure
    await _createRealisticProject(testDir);
    print('✅ Created realistic project structure');
    
    // Test the cleaner
    final cleaner = UnusedCodeCleaner();
    final options = CleanupOptions(
      verbose: true,
      dryRun: true, // ALWAYS use dry-run for testing
      removeUnusedAssets: true,
      removeUnusedFiles: true,
      removeUnusedFunctions: true,
      removeUnusedPackages: true,
    );
    
    print('\n🔍 Running analysis...');
    final result = await cleaner.analyze(testDir.path, options);
    
    print('\n📊 Results:');
    print('  • Total scanned files: ${result.totalScannedFiles}');
    print('  • Unused assets: ${result.unusedAssets.length}');
    print('  • Unused files: ${result.unusedFiles.length}');
    print('  • Unused functions: ${result.unusedFunctions.length}');
    print('  • Unused packages: ${result.unusedPackages.length}');
    
    // Verify results are reasonable (not everything marked as unused)
    if (result.totalScannedFiles > 0) {
      final percentUnused = (result.totalUnusedItems / result.totalScannedFiles) * 100;
      print('  • Percentage marked unused: ${percentUnused.toStringAsFixed(1)}%');
      
      if (percentUnused < 80) {
        print('✅ PASS: Reasonable number of items marked as unused');
      } else {
        print('❌ FAIL: Too many items marked as unused (${percentUnused.toStringAsFixed(1)}%)');
      }
    }
    
    // Check that essential files are protected
    final protectedFiles = [
      'lib/main.dart',
      'test/widget_test.dart',
      'lib/app.dart',
    ];
    
    bool allProtected = true;
    for (final file in protectedFiles) {
      final isMarkedUnused = result.unusedFiles.any((item) => item.path.endsWith(file));
      if (isMarkedUnused) {
        print('❌ FAIL: Essential file $file marked as unused');
        allProtected = false;
      }
    }
    
    if (allProtected) {
      print('✅ PASS: Essential files are protected');
    }
    
    print('\n🎉 Bug fix testing completed successfully!');
    
  } catch (e) {
    print('❌ ERROR: $e');
  } finally {
    // Clean up
    try {
      await testDir.delete(recursive: true);
      print('🧹 Cleaned up test directory');
    } catch (e) {
      print('⚠️  Warning: Could not clean up test directory: $e');
    }
  }
}

Future<void> _createRealisticProject(Directory testDir) async {
  // Create pubspec.yaml
  await File('${testDir.path}/pubspec.yaml').writeAsString('''
name: test_app
description: A test Flutter app

version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: ">=3.0.0"

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.2
  http: ^1.0.0
  
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/icon.png  # Specific asset declaration
    - assets/config.json
''');

  // Create lib structure
  await Directory('${testDir.path}/lib').create(recursive: true);
  
  // Main.dart (should be protected)
  await File('${testDir.path}/lib/main.dart').writeAsString('''
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app.dart';

void main() {
  runApp(MyApp());
}

void usedFunction() {
  print('This function is called');
  http.get(Uri.parse('https://example.com'));
}

void unusedFunction() {
  print('This is never called');
}
''');

  // App.dart (imported and should be protected)
  await File('${testDir.path}/lib/app.dart').writeAsString('''
import 'package:flutter/material.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Test App',
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Image.asset('assets/images/icon.png'),
    );
  }
}
''');

  // Unused file (should be marked as unused)
  await File('${testDir.path}/lib/unused_utils.dart').writeAsString('''
class UnusedUtility {
  static void doSomething() {
    print('Never used');
  }
}
''');

  // Test directory (should be protected)
  await Directory('${testDir.path}/test').create(recursive: true);
  await File('${testDir.path}/test/widget_test.dart').writeAsString('''
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    expect(find.text('0'), findsOneWidget);
  });
}
''');

  // Assets directory
  await Directory('${testDir.path}/assets/images').create(recursive: true);
  
  // Declared asset (should be protected)
  await File('${testDir.path}/assets/images/icon.png').writeAsBytes([1, 2, 3, 4]);
  
  // Declared config (should be protected)
  await File('${testDir.path}/assets/config.json').writeAsString('{"version": "1.0"}');
  
  // Undeclared asset (should be marked as unused)
  await File('${testDir.path}/assets/images/unused.png').writeAsBytes([5, 6, 7, 8]);
  
  // Additional undeclared directory with assets
  await Directory('${testDir.path}/assets/extra').create(recursive: true);
  await File('${testDir.path}/assets/extra/unused_extra.json').writeAsString('{"unused": true}');
}
