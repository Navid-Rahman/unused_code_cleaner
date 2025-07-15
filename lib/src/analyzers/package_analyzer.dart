import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/pattern_matcher.dart';
import '../models/cleanup_options.dart';

class PackageAnalyzer {
  final String projectPath;

  PackageAnalyzer(this.projectPath);

  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedPackages = <UnusedItem>[];

    try {
      final dependencies = await _getDependencies();
      Logger.debug('Found ${dependencies.length} dependencies');

      final importedPackages = await _findImportedPackages(dartFiles, options);
      Logger.debug('Found ${importedPackages.length} imported packages');

      final transitiveDeps = await _getTransitiveDependencies();
      Logger.debug('Found ${transitiveDeps.length} transitive dependencies');

      for (final package in dependencies) {
        if (!importedPackages.contains(package) &&
            !transitiveDeps.contains(package) &&
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

  Future<List<String>> _getDependencies() async {
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

  Future<Set<String>> _findImportedPackages(
      List<File> dartFiles, CleanupOptions options) async {
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

  Future<Set<String>> _getTransitiveDependencies() async {
    final transitiveDeps = <String>{};

    // Check pubspec.lock for all resolved dependencies
    final pubspecLock = File(path.join(projectPath, 'pubspec.lock'));
    if (await pubspecLock.exists()) {
      try {
        final content = await pubspecLock.readAsString();
        final yaml = loadYaml(content);
        if (yaml['packages'] != null) {
          final packages = yaml['packages'] as Map;
          transitiveDeps.addAll(packages.keys.map((key) => key.toString()));
        }
      } catch (e) {
        Logger.debug('Error reading pubspec.lock: $e');
      }
    }

    // Check build.yaml for build dependencies
    final buildFile = File(path.join(projectPath, 'build.yaml'));
    if (await buildFile.exists()) {
      try {
        final content = await buildFile.readAsString();
        final yaml = loadYaml(content);
        if (yaml['dependencies'] != null) {
          final deps = yaml['dependencies'] as Map;
          transitiveDeps.addAll(deps.keys.map((key) => key.toString()));
        }
        if (yaml['targets'] != null) {
          final targets = yaml['targets'] as Map;
          targets.forEach((key, value) {
            if (value is Map && value['dependencies'] != null) {
              final deps = value['dependencies'] as List;
              transitiveDeps.addAll(deps.map((dep) => dep.toString()));
            }
          });
        }
      } catch (e) {
        Logger.debug('Error reading build.yaml: $e');
      }
    }

    return transitiveDeps;
  }

  bool _isEssentialPackage(String packageName) {
    final essentialPackages = {
      'flutter',
      'flutter_test',
      'cupertino_icons',
      'flutter_lints',
      'build_runner',
      'json_annotation',
      'freezed',
      'provider',
      'get_it',
      'flutter_hooks',
      'riverpod',
      'bloc',
      'equatable',
      'meta',
      'collection',
      'vector_math',
      'sky_engine',
      'material_color_utilities',
    };

    // Check for generator packages
    if (packageName.endsWith('_generator') ||
        packageName.startsWith('build_')) {
      return true;
    }

    // Check for analyzer packages
    if (packageName.contains('analyzer') ||
        packageName.contains('source_gen')) {
      return true;
    }

    return essentialPackages.contains(packageName);
  }
}
