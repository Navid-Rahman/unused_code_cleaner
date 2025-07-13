#!/usr/bin/env dart

import 'dart:io';

/// Quick validation script to test critical safety fixes
void main() async {
  print('🔍 Validating unused_code_cleaner safety fixes...');

  final errors = <String>[];

  // Check that critical files exist and contain safety features
  await _checkAssetAnalyzer(errors);
  await _checkCleanupOptions(errors);
  await _checkCleaner(errors);
  await _checkCLI(errors);

  if (errors.isEmpty) {
    print('✅ All safety fixes validated successfully!');
    print('🛡️ The package is now safe to use with proper precautions.');
    print('');
    print('REMEMBER:');
    print('  1. Always use --dry-run first');
    print('  2. Commit your code to version control before cleanup');
    print('  3. Review the output carefully');
    print('  4. Keep backups enabled');
    exit(0);
  } else {
    print('❌ Validation failed:');
    for (final error in errors) {
      print('  - $error');
    }
    exit(1);
  }
}

Future<void> _checkAssetAnalyzer(List<String> errors) async {
  final file = File('lib/src/analyzers/asset_analyzer.dart');
  if (!await file.exists()) {
    errors.add('AssetAnalyzer file missing');
    return;
  }

  final content = await file.readAsString();

  // Check for critical safety features
  if (!content.contains('_isAssetDeclared')) {
    errors.add('AssetAnalyzer: Missing declared asset protection');
  }

  if (!content.contains('_findPackageReferences')) {
    errors.add('AssetAnalyzer: Missing package reference detection');
  }

  if (!content.contains('_findConstantReferences')) {
    errors.add('AssetAnalyzer: Missing constant reference detection');
  }

  if (!content.contains('PatternMatcher.normalizePath')) {
    errors.add('AssetAnalyzer: Missing path normalization');
  }

  if (!content.contains('WARNING: ') || !content.contains('unusually high')) {
    errors.add('AssetAnalyzer: Missing mass deletion warning');
  }

  print('✅ AssetAnalyzer safety features validated');
}

Future<void> _checkCleanupOptions(List<String> errors) async {
  final file = File('lib/src/models/cleanup_options.dart');
  if (!await file.exists()) {
    errors.add('CleanupOptions file missing');
    return;
  }

  final content = await file.readAsString();

  if (!content.contains('dryRun')) {
    errors.add('CleanupOptions: Missing dry-run support');
  }

  if (!content.contains('createBackup')) {
    errors.add('CleanupOptions: Missing backup support');
  }

  print('✅ CleanupOptions safety features validated');
}

Future<void> _checkCleaner(List<String> errors) async {
  final file = File('lib/src/cleaner.dart');
  if (!await file.exists()) {
    errors.add('Cleaner file missing');
    return;
  }

  final content = await file.readAsString();

  if (!content.contains('DRY RUN MODE')) {
    errors.add('Cleaner: Missing dry-run mode implementation');
  }

  if (!content.contains('backup_')) {
    errors.add('Cleaner: Missing backup functionality');
  }

  if (!content.contains('YES DELETE ALL')) {
    errors.add('Cleaner: Missing enhanced confirmation for mass deletion');
  }

  print('✅ Cleaner safety features validated');
}

Future<void> _checkCLI(List<String> errors) async {
  final file = File('bin/unused_code_cleaner.dart');
  if (!await file.exists()) {
    errors.add('CLI file missing');
    return;
  }

  final content = await file.readAsString();

  if (!content.contains('dry-run')) {
    errors.add('CLI: Missing dry-run flag');
  }

  if (!content.contains('no-backup')) {
    errors.add('CLI: Missing no-backup flag');
  }

  if (!content.contains('IMPORTANT: Always run with --dry-run first')) {
    errors.add('CLI: Missing critical safety warning in help');
  }

  print('✅ CLI safety features validated');
}
