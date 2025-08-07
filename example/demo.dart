#!/usr/bin/env dart

import 'dart:io';
import 'package:unused_code_cleaner/unused_code_cleaner.dart';

/// Interactive demo showcasing the unused code cleaner
void main() async {
  print('🎯 Unused Code Cleaner - Interactive Demo');
  print('=' * 50);

  // Create sample project structure
  await _createDemoProject();

  print('\n📁 Created demo project with:');
  print('  ✅ 2 used assets (logo.png, icon.svg)');
  print('  ❌ 3 unused assets (old.png, temp.jpg, unused.json)');
  print('  ✅ 1 used function (calculateTotal)');
  print('  ❌ 2 unused functions (oldMethod, debugHelper)');
  print('  ❌ 1 unused package (http)');

  print('\n🔍 Running analysis...');

  final cleaner = UnusedCodeCleaner();
  final options = CleanupOptions(
    removeUnusedAssets: true,
    removeUnusedFunctions: true,
    removeUnusedPackages: true,
    verbose: true,
    interactive: false,
    dryRun: true, // Safe demo mode
  );

  try {
    final result = await cleaner.analyze('./demo_project', options);

    print('\n📊 Analysis Results:');
    print('  🗑️  Found ${result.totalUnusedItems} unused items');
    print('  💾 Potential space savings: ${_calculateSavings(result)}');
    print(
        '  ⏱️  Analysis completed in ${result.analysisTime.inMilliseconds}ms');
    print('  🏥 Project health: ${_calculateHealthScore(result)}%');

    print('\n✨ Benefits of cleanup:');
    print('  📱 Smaller app bundle size');
    print('  🚀 Faster build times');
    print('  🧹 Cleaner codebase');
    print('  📈 Better performance');
  } catch (e) {
    print('❌ Demo failed: $e');
  } finally {
    // Cleanup demo project
    await _cleanupDemo();
    print('\n🧹 Demo cleanup completed!');
  }
}

Future<void> _createDemoProject() async {
  final dir = Directory('./demo_project');
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }

  // Create project structure
  await Directory('./demo_project/lib').create(recursive: true);
  await Directory('./demo_project/assets').create(recursive: true);

  // Create main.dart with used/unused functions
  await File('./demo_project/lib/main.dart').writeAsString('''
import 'package:flutter/material.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final total = calculateTotal([1, 2, 3]); // Used function
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Image.asset('assets/logo.png'), // Used asset
            Icon(Icons.star), // Used asset reference
            Text('Total: \$total'),
          ],
        ),
      ),
    );
  }
}

// Used function
int calculateTotal(List<int> numbers) {
  return numbers.fold(0, (a, b) => a + b);
}

// Unused functions
void oldMethod() {
  print('This is never called');
}

void debugHelper() {
  print('Debug helper not used');
}
''');

  // Create pubspec.yaml with unused package
  await File('./demo_project/pubspec.yaml').writeAsString('''
name: demo_project
version: 1.0.0

dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0  # Unused package

flutter:
  assets:
    - assets/logo.png
    - assets/icon.svg
''');

  // Create used assets
  await File('./demo_project/assets/logo.png').writeAsString('FAKE_PNG_DATA');
  await File('./demo_project/assets/icon.svg').writeAsString('<svg>icon</svg>');

  // Create unused assets
  await File('./demo_project/assets/old.png').writeAsString('OLD_PNG_DATA');
  await File('./demo_project/assets/temp.jpg').writeAsString('TEMP_JPG_DATA');
  await File('./demo_project/assets/unused.json')
      .writeAsString('{"unused": true}');
}

String _calculateSavings(dynamic result) {
  // Mock calculation for demo
  return '2.5 MB';
}

int _calculateHealthScore(dynamic result) {
  // Mock calculation for demo
  return 85;
}

Future<void> _cleanupDemo() async {
  final dir = Directory('./demo_project');
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}
