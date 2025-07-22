#!/usr/bin/env dart

/// Demo script to showcase the enhanced analyzers vs legacy analyzers
///
/// This script creates sample code patterns and shows how the enhanced
/// analyzers detect them more accurately than the legacy ones.

import 'dart:io';
import 'package:path/path.dart' as path;

void main() async {
  print('🚀 Enhanced Analyzers Demo');
  print('=' * 50);

  // Create a temporary demo project
  final tempDir = await Directory.systemTemp.createTemp('enhanced_demo_');
  final projectPath = tempDir.path;

  try {
    await _createDemoProject(projectPath);

    print('📁 Created demo project at: $projectPath');
    print('');
    print('🔍 Demo showcases these enhanced detection patterns:');
    print('');
    print('1. 🎯 Asset Variables:');
    print('   const kLogo = "assets/logo.png"');
    print('   Image.asset(kLogo) // Enhanced: ✅ Detected | Legacy: ❌ Missed');
    print('');
    print('2. 🧬 Flutter Lifecycle:');
    print(
        '   initState(), build(), dispose() // Enhanced: ✅ Protected | Legacy: ❌ False positive');
    print('');
    print('3. 🔗 Semantic Imports:');
    print(
        '   package:http/http.dart as http // Enhanced: ✅ Tracks usage | Legacy: ❌ Name-based');
    print('');
    print('4. 🎨 Complex Asset Patterns:');
    print(
        '   BoxDecoration(image: AssetImage(...)) // Enhanced: ✅ Detected | Legacy: ❌ Missed');
    print('');

    print('To test the enhanced analyzers on this demo project:');
    print('');
    print('💡 Legacy Analysis:');
    print(
        '   dart run unused_code_cleaner --dry-run --all --path="$projectPath"');
    print('');
    print('🚀 Enhanced Analysis:');
    print(
        '   dart run unused_code_cleaner --enhanced --dry-run --all --path="$projectPath"');
    print('');
    print('Compare the results to see the accuracy improvements!');
  } catch (e) {
    print('Error creating demo: $e');
  } finally {
    // Clean up
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<void> _createDemoProject(String projectPath) async {
  // Create directory structure
  final libDir = Directory(path.join(projectPath, 'lib'));
  final assetsDir = Directory(path.join(projectPath, 'assets', 'images'));
  await libDir.create(recursive: true);
  await assetsDir.create(recursive: true);

  // Create pubspec.yaml with dependencies
  final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
  await pubspecFile.writeAsString('''
name: enhanced_demo
version: 1.0.0

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  http: ^0.13.0
  unused_package: ^1.0.0  # This should be detected as unused

dev_dependencies:
  flutter_test:
    sdk: flutter

flutter:
  assets:
    - assets/images/
''');

  // Create asset files
  final usedAsset = File(path.join(assetsDir.path, 'logo.png'));
  final unusedAsset = File(path.join(assetsDir.path, 'unused.png'));
  await usedAsset.writeAsBytes([0, 1, 2, 3]); // Dummy PNG content
  await unusedAsset.writeAsBytes([0, 1, 2, 3]); // Dummy PNG content

  // Create main.dart with complex patterns
  final mainFile = File(path.join(projectPath, 'lib', 'main.dart'));
  await mainFile.writeAsString('''
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // Asset variable pattern - Enhanced analyzer should detect this
  static const String kLogoPath = 'assets/images/logo.png';
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Flutter lifecycle methods - Enhanced analyzer should protect these
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Enhanced Demo'),
      ),
      body: Column(
        children: [
          // Complex asset usage pattern
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(MyApp.kLogoPath), // Variable reference
                fit: BoxFit.cover,
              ),
            ),
            child: Text('Asset via variable'),
          ),
          ElevatedButton(
            onPressed: _fetchData,
            child: Text('Fetch Data'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Lifecycle method - should be protected
    super.dispose();
  }

  // This private method should be detected as unused
  void _unusedPrivateMethod() {
    print('This method is never called');
  }

  // This method is used and should be protected
  void _loadData() {
    print('Loading initial data...');
  }

  // This method uses the http package
  Future<void> _fetchData() async {
    try {
      final response = await http.get(Uri.parse('https://api.example.com/data'));
      print('Response: \${response.statusCode}');
    } catch (e) {
      print('Error: \$e');
    }
  }
}

// This class should be detected as unused
class UnusedClass {
  void unusedMethod() {
    print('This entire class is unused');
  }
}
''');

  // Create a widget file with more patterns
  final widgetFile = File(path.join(projectPath, 'lib', 'custom_widget.dart'));
  await widgetFile.writeAsString('''
import 'package:flutter/material.dart';

class CustomWidget extends StatefulWidget {
  @override
  _CustomWidgetState createState() => _CustomWidgetState();
}

class _CustomWidgetState extends State<CustomWidget> {
  // Another asset variable pattern
  static const String _iconPath = 'assets/images/icon.png';
  
  @override
  Widget build(BuildContext context) {
    return Container(
      child: Image.asset(_iconPath), // This creates a reference
    );
  }
  
  // Private method that's never called - should be detected as unused
  void _helperMethod() {
    print('Helper method not used');
  }
}

// Utility function that's never called - should be detected as unused
void unusedUtilityFunction() {
  print('This function is never called');
}
''');

  print('✅ Demo project created successfully!');
}
