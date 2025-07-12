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
  print('Unused Code Cleaner - Flutter Package');
  print('');
  print('Usage: unused_code_cleaner [options]');
  print('');
  print('Options:');
  print(parser.usage);
}
