import 'dart:io';
import 'package:args/args.dart';
import 'package:unused_code_cleaner/unused_code_cleaner.dart';

/// Main entry point for the Unused Code Cleaner CLI tool.
///
/// Provides command-line interface for analyzing and cleaning unused code in Dart/Flutter projects.
/// Supports various cleanup options, interactive mode, and customizable exclusion patterns.
///
/// Usage: unused_code_cleaner [options]
void main(List<String> arguments) async {
  // Configure command-line argument parser with all available options
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', help: 'Show this help message')
    ..addFlag('verbose', abbr: 'v', help: 'Enable verbose logging')
    ..addFlag('assets', help: 'Remove unused assets')
    ..addFlag('functions', help: 'Remove unused functions')
    ..addFlag('packages', help: 'Remove unused packages')
    ..addFlag('files', help: 'Remove unused files')
    ..addFlag('all', help: 'Remove all unused items')
    ..addFlag('interactive', defaultsTo: true, help: 'Interactive mode')
    ..addFlag('dry-run',
        help: 'Preview changes without executing them (RECOMMENDED)')
    ..addFlag('no-backup', help: 'Skip creating backups before deletion')
    ..addMultiOption('exclude', help: 'Exclude patterns')
    ..addOption('path', defaultsTo: '.', help: 'Project path to analyze');

  try {
    final results = parser.parse(arguments);

    // Show help message if requested
    if (results['help']) {
      _printUsage(parser);
      return;
    }

    // Build cleanup options from command-line arguments
    final options = CleanupOptions(
      removeUnusedAssets: results['assets'] || results['all'],
      removeUnusedFunctions: results['functions'] || results['all'],
      removeUnusedPackages: results['packages'] || results['all'],
      removeUnusedFiles: results['files'] || results['all'],
      interactive: results['interactive'],
      verbose: results['verbose'],
      excludePatterns: results['exclude'],
      dryRun: results['dry-run'],
      createBackup: !results['no-backup'],
    );

    // Execute analysis and cleanup
    final cleaner = UnusedCodeCleaner();
    await cleaner.analyze(results['path'], options);
  } catch (e) {
    // Handle command-line parsing errors and other exceptions
    print('Error: $e');
    _printUsage(parser);
    exit(1);
  }
}

/// Displays usage information and available command-line options.
///
/// Shows the tool name, basic usage syntax, and detailed option descriptions
/// generated from the argument parser configuration.
void _printUsage(ArgParser parser) {
  print('🧹 Unused Code Cleaner - Comprehensive Dart/Flutter Cleanup Tool');
  print('');
  print('⚠️  IMPORTANT: Always run with --dry-run first to preview changes!');
  print('');
  print('Usage: unused_code_cleaner [options]');
  print('');
  print('Examples:');
  print(
      '  unused_code_cleaner --dry-run --all --verbose     # Preview all cleanup');
  print(
      '  unused_code_cleaner --assets --dry-run            # Preview asset cleanup');
  print(
      '  unused_code_cleaner --assets --exclude "assets/icons/**"  # Protect icons');
  print(
      '  unused_code_cleaner --functions --dry-run         # Function analysis');
  print('');
  print('Options:');
  print(parser.usage);
  print('');
  print('🔒 Safety Features:');
  print('  • Assets declared in pubspec.yaml are automatically protected');
  print('  • Dry-run mode to preview changes without deletion');
  print('  • Automatic backups created before deletion');
  print('  • Enhanced warnings for large-scale deletions');
  print('  • Multiple confirmation prompts for file deletion');
  print('');
  print('🚀 Advanced Analysis:');
  print('  • Semantic AST-based analysis is enabled by default');
  print('  • More accurate detection with Flutter-aware patterns');
  print('  • Better handling of complex reference patterns');
}
