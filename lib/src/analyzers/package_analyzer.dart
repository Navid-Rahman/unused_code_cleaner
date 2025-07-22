import 'dart:io';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/pattern_matcher.dart';
import '../models/cleanup_options.dart';
import '../utils/ast_utils.dart';

/// Enhanced package analyzer using semantic import analysis
class PackageAnalyzer {
  final String projectPath;

  PackageAnalyzer(this.projectPath);

  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedPackages = <UnusedItem>[];

    try {
      Logger.info('🔍 Starting enhanced package analysis (semantic-based)...');

      final declaredDependencies = await _getDeclaredDependencies(projectPath);
      Logger.debug(
          'Found ${declaredDependencies.length} declared dependencies');

      final usedPackages = await _findUsedPackages(dartFiles, projectPath);
      Logger.debug('Found ${usedPackages.length} used packages');

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
    } catch (e) {
      Logger.error('Enhanced package analysis failed: $e');
      return [];
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

  Future<Set<String>> _findUsedPackages(
      List<File> dartFiles, String projectPath) async {
    final usedPackages = <String>{};

    AstUtils.initializeAnalysisContext(projectPath);

    try {
      for (final file in dartFiles) {
        try {
          final resolvedUnit = await AstUtils.getResolvedUnit(file.path);
          if (resolvedUnit != null) {
            final visitor = SemanticImportVisitor(usedPackages);
            resolvedUnit.unit.accept(visitor);
          }
        } catch (e) {
          Logger.debug('Error analyzing imports in ${file.path}: $e');
          // Continue processing other files even if one fails
        }
      }

      // Also check pubspec.yaml for flutter dependencies
      await _checkFlutterSpecificUsage(projectPath, usedPackages);

      Logger.debug('Found used packages: ${usedPackages.join(', ')}');
      return usedPackages;
    } catch (e) {
      Logger.error('Error in _findUsedPackages: $e');
      return usedPackages; // Return partial results instead of empty set
    } finally {
      AstUtils.disposeAnalysisContext();
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
    };

    // Development tools
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
        packageName.endsWith('_builder');
  }
}

/// Semantic visitor for import analysis
class SemanticImportVisitor extends RecursiveAstVisitor<void> {
  final Set<String> usedPackages;

  SemanticImportVisitor(this.usedPackages);

  @override
  void visitImportDirective(ImportDirective node) {
    try {
      final uri = node.uri.stringValue;
      Logger.debug('Processing import: $uri');
      if (uri != null && uri.isNotEmpty) {
        final packageName = _extractPackageName(uri);
        Logger.debug('Extracted package name: $packageName');
        if (packageName != null) {
          usedPackages.add(packageName);
          Logger.debug('Added package to used set: $packageName');

          // Handle conditional imports
          for (final configuration in node.configurations) {
            final configUri = configuration.uri.stringValue;
            if (configUri != null && configUri.isNotEmpty) {
              final configPackage = _extractPackageName(configUri);
              if (configPackage != null) {
                usedPackages.add(configPackage);
                Logger.debug('Added conditional package: $configPackage');
              }
            }
          }
        }
      }
    } catch (e) {
      Logger.debug('Error processing import directive: $e');
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
        usedPackages.add('json_annotation');
        usedPackages.add('build_runner');
      } else if (uri.endsWith('.freezed.dart')) {
        usedPackages.add('freezed');
        usedPackages.add('freezed_annotation');
      } else if (uri.endsWith('.gr.dart')) {
        usedPackages.add('auto_route');
      }
    }
    super.visitPartDirective(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    try {
      // Track annotation usage which might indicate package dependencies
      final element = node.element;
      if (element != null) {
        final library = element.library;
        if (library != null) {
          final librarySource = library.source.uri.toString();
          final packageName = _extractPackageName(librarySource);
          if (packageName != null) {
            usedPackages.add(packageName);
          }
        }
      }
    } catch (e) {
      // Ignore errors for individual annotations and continue
    }
    super.visitAnnotation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    try {
      // Track method invocations that might indicate package usage
      final element = node.methodName.staticElement;
      if (element != null) {
        final library = element.library;
        if (library != null) {
          final librarySource = library.source.uri.toString();
          final packageName = _extractPackageName(librarySource);
          if (packageName != null) {
            usedPackages.add(packageName);
          }
        }
      }
    } catch (e) {
      // Ignore errors for individual method invocations and continue
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    try {
      // Track constructor usage
      final element = node.constructorName.staticElement;
      if (element != null) {
        final library = element.library;
        final librarySource = library.source.uri.toString();
        final packageName = _extractPackageName(librarySource);
        if (packageName != null) {
          usedPackages.add(packageName);
        }
      }
    } catch (e) {
      // Ignore errors for individual constructor calls and continue
    }
    super.visitInstanceCreationExpression(node);
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
