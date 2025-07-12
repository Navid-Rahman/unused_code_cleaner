import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../models/cleanup_options.dart';

/// Analyzes package dependencies to identify unused packages within a Dart/Flutter project.
///
/// This analyzer examines package declarations in pubspec.yaml and scans for package
/// imports in Dart code to identify packages that are declared but never used.
class PackageAnalyzer {
  /// Analyzes the project to find unused package dependencies.
  ///
  /// [projectPath] - Root path of the project
  /// [dartFiles] - List of Dart files to scan for package imports
  /// [options] - Cleanup options including exclude patterns
  /// Returns a list of unused items representing unused packages.
  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedPackages = <UnusedItem>[];

    try {
      // Get dependencies from pubspec.yaml
      final dependencies = await _getDependencies(projectPath);
      Logger.debug('Found ${dependencies.length} dependencies');

      // Find imported packages in Dart files
      final importedPackages = await _findImportedPackages(dartFiles, options);
      Logger.debug('Found ${importedPackages.length} imported packages');

      // Find unused packages
      for (final package in dependencies) {
        if (!importedPackages.contains(package) &&
            !_isEssentialPackage(package)) {
          unusedPackages.add(UnusedItem(
            name: package,
            path: 'pubspec.yaml',
            type: UnusedItemType.package,
            description: 'Unused package dependency',
          ));
        }
      }

      Logger.info('Found ${unusedPackages.length} unused packages');
      return unusedPackages;
    } catch (e) {
      Logger.error('Package analysis failed: $e');
      return [];
    }
  }

  /// Gets package dependencies from pubspec.yaml file.
  ///
  /// [projectPath] - Root path of the project
  /// Returns a list of package names declared as dependencies.
  Future<List<String>> _getDependencies(String projectPath) async {
    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
    final content = await pubspecFile.readAsString();
    final yaml = loadYaml(content);

    final dependencies = <String>[];

    if (yaml['dependencies'] != null) {
      final deps = yaml['dependencies'] as Map;
      dependencies.addAll(deps.keys.map((key) => key.toString()));
    }

    return dependencies;
  }

  /// Scans Dart files to find imported packages.
  ///
  /// Looks for package imports in the form 'package:package_name/...'
  ///
  /// [dartFiles] - List of Dart files to scan for imports
  /// [options] - Cleanup options including exclude patterns
  /// Returns a set of package names that are imported in the code.
  Future<Set<String>> _findImportedPackages(
      List<File> dartFiles, CleanupOptions options) async {
    final imported = <String>{};

    for (final file in dartFiles) {
      // Skip excluded files
      if (options.excludePatterns
          .any((pattern) => file.path.contains(pattern))) {
        continue;
      }

      try {
        final content = await file.readAsString();
        final lines = content.split('\n');

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('import \'package:')) {
            // Extract package name using string parsing
            final packageStart =
                trimmed.indexOf('package:') + 8; // Length of 'package:'
            final remaining = trimmed.substring(packageStart);
            final slashIndex = remaining.indexOf('/');
            final quoteIndex = remaining.indexOf('\'');

            if (slashIndex != -1 &&
                (quoteIndex == -1 || slashIndex < quoteIndex)) {
              final packageName = remaining.substring(0, slashIndex);
              imported.add(packageName);
            } else if (quoteIndex != -1) {
              final packageName = remaining.substring(0, quoteIndex);
              imported.add(packageName);
            }
          }
        }
      } catch (e) {
        Logger.debug('Error reading file ${file.path}: $e');
      }
    }

    return imported;
  }

  /// Determines if a package is essential and should not be marked as unused.
  ///
  /// Essential packages include core Flutter packages and common development tools
  /// that may not have explicit imports but are still necessary.
  ///
  /// [packageName] - Name of the package to check
  /// Returns true if the package is essential, false otherwise.
  bool _isEssentialPackage(String packageName) {
    // Don't mark these as unused - they're core Flutter packages
    final essentialPackages = {
      'flutter', // Core Flutter SDK
      'cupertino_icons', // Default iOS-style icons
      'flutter_test', // Testing framework
      'flutter_lints', // Code analysis rules
    };

    return essentialPackages.contains(packageName);
  }
}
