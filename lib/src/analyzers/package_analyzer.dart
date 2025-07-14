import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/pattern_matcher.dart';
import '../models/cleanup_options.dart';

class PackageAnalyzer {
  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedPackages = <UnusedItem>[];

    try {
      final dependencies = await _getDependencies(projectPath);
      Logger.debug('Found ${dependencies.length} dependencies');

      final importedPackages = await _findImportedPackages(dartFiles, options);
      Logger.debug('Found ${importedPackages.length} imported packages');

      for (final package in dependencies) {
        if (!importedPackages.contains(package) && !_isEssentialPackage(package, projectPath)) {
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

  Future<List<String>> _getDependencies(String projectPath) async {
    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
    final content = await pubspecFile.readAsString();
    final yaml = loadYaml(content);

    final dependencies = <String>[];

    if (yaml['dependencies'] != null) {
      final deps = yaml['dependencies'] as Map;
      dependencies.addAll(deps.keys.map((key) => key.toString()));
    }
    if (yaml['dev_dependencies'] != null) {
      final devDeps = yaml['dev_dependencies'] as Map;
      dependencies.addAll(devDeps.keys.map((key) => key.toString()));
    }
    return dependencies;
  }

  Future<Set<String>> _findImportedPackages(List<File> dartFiles, CleanupOptions options) async {
    final imported = <String>{};

    for (final file in dartFiles) {
      if (PatternMatcher.isExcluded(file.path, options.excludePatterns)) {
        continue;
      }

      try {
        final content = await file.readAsString();
        final importPattern = RegExp(r"import\s+'package:([^/]+)");
        final matches = importPattern.allMatches(content);
        for (final match in matches) {
          final packageName = match.group(1);
          if (packageName != null) imported.add(packageName);
        }
      } catch (e) {
        Logger.debug('Error reading file ${file.path}: $e');
      }
    }

    return imported;
  }

  bool _isEssentialPackage(String packageName, String projectPath) {
    final essentialPackages = {
      'flutter', 'cupertino_icons', 'flutter_test', 'flutter_lints', 'provider', 'get_it',
      'flutter_hooks', 'riverpod', 'bloc', 'equatable'
    };
    // Dynamic check: Look for package usage in build files
    final buildFile = File(path.join(projectPath, 'build.yaml'));
    if (buildFile.existsSync() && buildFile.readAsStringSync().contains(packageName)) {
      return true;
    }
    return essentialPackages.contains(packageName);
  }
}