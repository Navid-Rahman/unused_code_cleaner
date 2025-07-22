import 'dart:io';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/pattern_matcher.dart';
import '../models/cleanup_options.dart';

/// Enhanced package analyzer using proper dependency resolution
class PackageAnalyzer {
  final String projectPath;
  AnalysisContextCollection? _collection;

  PackageAnalyzer(this.projectPath);

  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedPackages = <UnusedItem>[];

    try {
      Logger.info('🔍 Starting enhanced package dependency analysis...');

      // Initialize analysis context collection with proper package resolution
      _collection = AnalysisContextCollection(
        includedPaths: [path.normalize(path.absolute(projectPath))],
        excludedPaths: [
          path.join(projectPath, '.dart_tool'),
          path.join(projectPath, 'build'),
          path.join(projectPath, '.pub'),
        ],
      );

      final declaredDependencies = await _getDeclaredDependencies(projectPath);
      Logger.debug(
          'Found ${declaredDependencies.length} declared dependencies');

      final usedPackages =
          await _findUsedPackagesWithProperResolution(dartFiles, projectPath);
      Logger.debug('Found ${usedPackages.length} used packages');

      // Add packages that are implicitly used by Flutter
      _addImplicitlyUsedPackages(usedPackages, projectPath);

      for (final packageName in declaredDependencies.keys) {
        if (PatternMatcher.isExcluded(packageName, options.excludePatterns)) {
          Logger.debug('✅ Skipping excluded package: $packageName');
          continue;
        }

        if (_isEssentialPackage(packageName)) {
          Logger.debug('✅ Protecting essential package: $packageName');
          continue;
        }

        if (!usedPackages.contains(packageName)) {
          final dependency = declaredDependencies[packageName]!;
          unusedPackages.add(UnusedItem(
            name: packageName,
            path: path.join(projectPath, 'pubspec.yaml'),
            type: UnusedItemType.package,
            description: 'Unused ${dependency.type} dependency',
          ));
        }
      }

      Logger.info(
          'Enhanced package analysis complete: ${unusedPackages.length} unused packages found');
      return unusedPackages;
    } catch (e, stackTrace) {
      Logger.error('Enhanced package analysis failed: $e');
      Logger.debug('Stack trace: $stackTrace');
      return [];
    } finally {
      _collection = null;
    }
  }

  Future<Map<String, PackageDependency>> _getDeclaredDependencies(
      String projectPath) async {
    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) return {};

    try {
      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content);
      final dependencies = <String, PackageDependency>{};

      // Regular dependencies
      if (yaml['dependencies'] != null) {
        final deps = yaml['dependencies'] as Map;
        for (final entry in deps.entries) {
          dependencies[entry.key.toString()] = PackageDependency(
            name: entry.key.toString(),
            type: 'dependency',
            version: entry.value.toString(),
          );
        }
      }

      // Dev dependencies (be more aggressive with these)
      if (yaml['dev_dependencies'] != null) {
        final devDeps = yaml['dev_dependencies'] as Map;
        for (final entry in devDeps.entries) {
          dependencies[entry.key.toString()] = PackageDependency(
            name: entry.key.toString(),
            type: 'dev_dependency',
            version: entry.value.toString(),
          );
        }
      }

      return dependencies;
    } catch (e) {
      Logger.error('Error reading pubspec.yaml: $e');
      return {};
    }
  }

  Future<Set<String>> _findUsedPackagesWithProperResolution(
      List<File> dartFiles, String projectPath) async {
    final usedPackages = <String>{};

    try {
      Logger.info(
          '🔍 Analyzing ${dartFiles.length} files for package usage...');

      for (final file in dartFiles) {
        try {
          final context = _collection!.contextFor(file.path);
          final result =
              await context.currentSession.getResolvedUnit(file.path);

          if (result is ResolvedUnitResult) {
            final visitor = EnhancedPackageUsageVisitor(usedPackages);
            result.unit.accept(visitor);
            Logger.debug('✅ Analyzed ${file.path} successfully');
          } else {
            // Fallback to basic import parsing for files with errors
            Logger.debug('⚠️ Falling back to basic parsing for ${file.path}');
            await _parseImportsBasic(file, usedPackages);
          }
        } catch (e) {
          Logger.debug('❌ Error analyzing ${file.path}: $e');
          // Continue with basic import parsing as fallback
          await _parseImportsBasic(file, usedPackages);
        }
      }

      // Check for Flutter-specific usage patterns
      await _checkFlutterSpecificUsage(projectPath, usedPackages);

      // Check for pubspec.yaml references
      await _checkPubspecReferences(projectPath, usedPackages);

      // Check for generated file patterns
      await _checkGeneratedFilePatterns(dartFiles, usedPackages);

      Logger.info(
          '📦 Found ${usedPackages.length} used packages: ${usedPackages.join(', ')}');
      return usedPackages;
    } catch (e) {
      Logger.error('Error in _findUsedPackagesWithProperResolution: $e');
      return usedPackages;
    }
  }

  Future<void> _parseImportsBasic(File file, Set<String> usedPackages) async {
    try {
      final content = await file.readAsString();
      final lines = content.split('\n');

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
          final match =
              RegExp(r'''['"](package:([^/']+)/[^'"]*|dart:[^'"]*)['"']''')
                  .firstMatch(trimmed);
          if (match != null) {
            final uri = match.group(1)!;
            final packageName = _extractPackageName(uri);
            if (packageName != null) {
              usedPackages.add(packageName);
              Logger.debug(
                  '📦 Found package import: $packageName in ${path.basename(file.path)}');
            }
          }
        }
      }
    } catch (e) {
      Logger.debug('Error parsing imports in ${file.path}: $e');
    }
  }

  void _addImplicitlyUsedPackages(
      Set<String> usedPackages, String projectPath) {
    // Add Flutter if it's a Flutter project
    if (_isFlutterProject(projectPath)) {
      usedPackages.add('flutter');

      // Add commonly implicitly used Flutter packages
      usedPackages.addAll([
        'flutter_test', // Often used but not explicitly imported
        'sky_engine', // Core Flutter dependency
      ]);
    }

    // Add Dart SDK packages that are always implicitly available
    usedPackages.add('dart');
  }

  bool _isFlutterProject(String projectPath) {
    try {
      final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
      if (pubspecFile.existsSync()) {
        final content = pubspecFile.readAsStringSync();
        return content.contains('flutter:') ||
            content.contains('flutter_test:') ||
            content.contains('uses-material-design:');
      }
    } catch (e) {
      Logger.debug('Error checking if Flutter project: $e');
    }
    return false;
  }

  Future<void> _checkPubspecReferences(
      String projectPath, Set<String> usedPackages) async {
    try {
      final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
      if (!await pubspecFile.exists()) return;

      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content);

      // Check for flutter section usage
      if (yaml['flutter'] != null) {
        usedPackages.add('flutter');

        final flutter = yaml['flutter'];
        if (flutter is Map) {
          // Check for assets - indicates possible use of asset-related packages
          if (flutter['assets'] != null) {
            // Don't add specific packages here, just note the usage pattern
          }

          // Check for fonts
          if (flutter['fonts'] != null) {
            // Don't add specific packages here
          }

          // Check for plugin usage
          if (flutter['plugin'] != null) {
            usedPackages.add('flutter');
          }
        }
      }

      // Check for build_runner configuration
      if (content.contains('build_runner') || content.contains('build.yaml')) {
        usedPackages.add('build_runner');
      }
    } catch (e) {
      Logger.debug('Error checking pubspec references: $e');
    }
  }

  Future<void> _checkGeneratedFilePatterns(
      List<File> dartFiles, Set<String> usedPackages) async {
    for (final file in dartFiles) {
      final fileName = path.basename(file.path);

      // Check for generated files and their associated packages
      if (fileName.endsWith('.g.dart')) {
        usedPackages.addAll(['json_annotation', 'build_runner']);
      } else if (fileName.endsWith('.freezed.dart')) {
        usedPackages.addAll(['freezed', 'freezed_annotation']);
      } else if (fileName.endsWith('.gr.dart')) {
        usedPackages.add('auto_route');
      } else if (fileName.endsWith('.chopper.dart')) {
        usedPackages.add('chopper');
      } else if (fileName.endsWith('.retrofit.dart')) {
        usedPackages.add('retrofit');
      }
    }
  }

  Future<void> _checkFlutterSpecificUsage(
      String projectPath, Set<String> usedPackages) async {
    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) return;

    try {
      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content);

      // Check for flutter-specific usage
      if (yaml['flutter'] != null) {
        usedPackages.add('flutter');

        // Check for assets (might indicate asset-related packages)
        if (yaml['flutter']['assets'] != null) {
          usedPackages.add('flutter_svg'); // Commonly used with assets
        }

        // Check for fonts
        if (yaml['flutter']['fonts'] != null) {
          usedPackages.add('google_fonts'); // Commonly used with custom fonts
        }

        // Check for plugin usage
        if (yaml['flutter']['plugin'] != null) {
          usedPackages.add('plugin_platform_interface');
        }
      }

      // Check for specific patterns in the pubspec that indicate usage
      if (content.contains('uses-material-design: true')) {
        usedPackages.add('flutter');
      }
    } catch (e) {
      Logger.debug('Error checking Flutter-specific usage: $e');
    }
  }

  bool _isEssentialPackage(String packageName) {
    // Packages that should never be considered unused
    final essentialPackages = {
      'flutter',
      'flutter_test',
      'flutter_driver',
      'integration_test',
      'test',
      'mockito',
      'flutter_lints',
      'lints',
      'very_good_analysis',
      'meta',
      'build_runner',
      'json_annotation',
      'freezed_annotation',
      'retrofit',
      'dio',
      'sky_engine',
      'dart',
    };

    // Development tools that are commonly used indirectly
    final devTools = {
      'build_runner',
      'json_serializable',
      'freezed',
      'retrofit_generator',
      'floor_generator',
      'hive_generator',
      'injectable_generator',
      'auto_route_generator',
    };

    return essentialPackages.contains(packageName) ||
        devTools.contains(packageName) ||
        packageName.endsWith('_generator') ||
        packageName.endsWith('_builder') ||
        packageName.startsWith('dart:');
  }

  String? _extractPackageName(String uri) {
    try {
      if (uri.startsWith('package:')) {
        final afterPackage = uri.substring(8);
        if (afterPackage.isEmpty) return null;

        final segments = afterPackage.split('/');
        return segments.isNotEmpty && segments.first.isNotEmpty
            ? segments.first
            : null;
      } else if (uri.startsWith('dart:')) {
        // Built-in Dart libraries
        return 'dart';
      }
      return null;
    } catch (e) {
      Logger.debug('Error extracting package name from URI "$uri": $e');
      return null;
    }
  }
}

/// Enhanced visitor for proper package usage detection
class EnhancedPackageUsageVisitor extends RecursiveAstVisitor<void> {
  final Set<String> usedPackages;

  EnhancedPackageUsageVisitor(this.usedPackages);

  @override
  void visitImportDirective(ImportDirective node) {
    try {
      final uri = node.uri.stringValue;
      if (uri != null && uri.isNotEmpty) {
        final packageName = _extractPackageName(uri);
        if (packageName != null) {
          usedPackages.add(packageName);

          // Handle conditional imports
          for (final configuration in node.configurations) {
            final configUri = configuration.uri.stringValue;
            if (configUri != null && configUri.isNotEmpty) {
              final configPackage = _extractPackageName(configUri);
              if (configPackage != null) {
                usedPackages.add(configPackage);
              }
            }
          }
        }
      }
    } catch (e) {
      // Ignore errors for individual import directives and continue
    }
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    try {
      final uri = node.uri.stringValue;
      if (uri != null && uri.isNotEmpty) {
        final packageName = _extractPackageName(uri);
        if (packageName != null) {
          usedPackages.add(packageName);
        }
      }
    } catch (e) {
      // Ignore errors for individual export directives and continue
    }
    super.visitExportDirective(node);
  }

  @override
  void visitPartDirective(PartDirective node) {
    // Part directives might reference generated files from packages
    final uri = node.uri.stringValue;
    if (uri != null) {
      // Check for common generated file patterns
      if (uri.endsWith('.g.dart')) {
        usedPackages.addAll(['json_annotation', 'build_runner']);
      } else if (uri.endsWith('.freezed.dart')) {
        usedPackages.addAll(['freezed', 'freezed_annotation']);
      } else if (uri.endsWith('.gr.dart')) {
        usedPackages.add('auto_route');
      }
    }
    super.visitPartDirective(node);
  }

  String? _extractPackageName(String uri) {
    try {
      if (uri.startsWith('package:')) {
        final afterPackage = uri.substring(8);
        if (afterPackage.isEmpty) return null;

        final segments = afterPackage.split('/');
        return segments.isNotEmpty && segments.first.isNotEmpty
            ? segments.first
            : null;
      } else if (uri.startsWith('dart:')) {
        // Built-in Dart libraries
        return 'dart';
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

class PackageDependency {
  final String name;
  final String type;
  final String version;

  PackageDependency({
    required this.name,
    required this.type,
    required this.version,
  });
}
