import 'dart:io';
import 'package:path/path.dart' as path;

import '../models/unused_item.dart';
import '../utils/logger.dart';
import '../utils/file_utils.dart';
import '../utils/pattern_matcher.dart';
import '../models/cleanup_options.dart';

class FileAnalyzer {
  Future<List<UnusedItem>> analyze(
      String projectPath, List<File> dartFiles, CleanupOptions options) async {
    final unusedFiles = <UnusedItem>[];

    try {
      // CRITICAL FIX: Only analyze files in lib/ for imports, but check all files
      // Get all dart files in the project for completeness check
      final allDartFiles = await FileUtils.findDartFiles(projectPath);
      Logger.debug('Found ${allDartFiles.length} total Dart files');

      // Find imported files from ALL dart files, not just lib/
      final importedFiles = await _findImportedFiles(allDartFiles, projectPath, options);
      Logger.debug('Found ${importedFiles.length} imported files');

      // Check each file in lib/ directory specifically (main source files)
      final libDartFiles = allDartFiles.where((file) => 
        file.path.contains('${path.separator}lib${path.separator}') ||
        file.path.endsWith('${path.separator}lib')).toList();

      for (final file in libDartFiles) {
        final relativePath = path.relative(file.path, from: projectPath);

        if (PatternMatcher.isExcluded(relativePath, options.excludePatterns)) {
          Logger.debug('✅ Skipping excluded file: $relativePath');
          continue;
        }

        if (_isFileImported(file.path, importedFiles) || _isSpecialFile(relativePath)) {
          Logger.debug('✅ Protecting file: $relativePath');
          continue;
        }

        final size = await FileUtils.getFileSize(file.path);
        unusedFiles.add(UnusedItem(
          name: path.basename(file.path),
          path: file.path,
          type: UnusedItemType.file,
          size: size,
          description: 'Unused Dart file',
        ));
      }

      Logger.info('Found ${unusedFiles.length} unused files');
      return unusedFiles;
    } catch (e) {
      Logger.error('File analysis failed: $e');
      return [];
    }
  }

  Future<Set<String>> _findImportedFiles(
      List<File> dartFiles, String projectPath, CleanupOptions options) async {
    final imported = <String>{};

    for (final file in dartFiles) {
      if (PatternMatcher.isExcluded(file.path, options.excludePatterns)) {
        continue;
      }

      try {
        final content = await file.readAsString();
        final lines = content.split('\n');

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('import \'') && !trimmed.contains('package:')) {
            final startQuote = trimmed.indexOf('\'', 7);
            final endQuote = trimmed.indexOf('\'', startQuote + 1);
            if (startQuote != -1 && endQuote != -1) {
              String importPath = trimmed.substring(startQuote + 1, endQuote);
              if (importPath.startsWith('../') || importPath.startsWith('./') || !importPath.contains('/')) {
                final dir = path.dirname(file.path);
                importPath = path.normalize(path.join(dir, importPath));
              } else {
                importPath = path.join(projectPath, 'lib', importPath);
              }
              if (!importPath.endsWith('.dart')) importPath += '.dart';
              imported.add(PatternMatcher.normalizePath(importPath));
            }
          }
          // Enhanced: Handle part files (e.g., part 'file.dart')
          if (trimmed.startsWith('part ')) {
            final startQuote = trimmed.indexOf('\'');
            final endQuote = trimmed.indexOf('\'', startQuote + 1);
            if (startQuote != -1 && endQuote != -1) {
              String partPath = trimmed.substring(startQuote + 1, endQuote);
              if (!partPath.endsWith('.dart')) partPath += '.dart';
              final dir = path.dirname(file.path);
              final fullPath = path.normalize(path.join(dir, partPath));
              imported.add(PatternMatcher.normalizePath(fullPath));
            }
          }
        }
      } catch (e) {
        Logger.debug('Error reading file ${file.path}: $e');
      }
    }

    return imported;
  }

  bool _isFileImported(String filePath, Set<String> importedFiles) {
    final normalizedPath = PatternMatcher.normalizePath(filePath);
    if (importedFiles.contains(normalizedPath)) return true;
    final withoutExtension = normalizedPath.replaceAll('.dart', '');
    return importedFiles.any((imported) => imported.replaceAll('.dart', '') == withoutExtension);
  }

  bool _isSpecialFile(String relativePath) {
    final normalizedPath = relativePath.replaceAll('\\', '/');
    
    // Always protect these critical files
    if (normalizedPath == 'lib/main.dart') return true;
    if (normalizedPath == 'lib/firebase_options.dart') return true;
    if (normalizedPath == 'lib/generated_plugin_registrant.dart') return true;
    
    // Protect all test files
    if (normalizedPath.startsWith('test/')) return true;
    if (normalizedPath.startsWith('integration_test/')) return true;
    
    // Protect generated files
    if (normalizedPath.endsWith('.g.dart')) return true;
    if (normalizedPath.endsWith('.freezed.dart')) return true;
    if (normalizedPath.endsWith('.gr.dart')) return true;
    if (normalizedPath.endsWith('.config.dart')) return true;
    if (normalizedPath.endsWith('generated_plugin_registrant.dart')) return true;
    if (normalizedPath.startsWith('lib/generated/')) return true;
    if (normalizedPath.contains('/generated/')) return true;
    
    // Protect important entry points and app files
    if (normalizedPath.startsWith('lib/main')) return true;
    if (normalizedPath.startsWith('lib/app')) return true;
    if (normalizedPath.endsWith('/main.dart')) return true;
    
    // Protect example files
    if (normalizedPath.startsWith('example/')) return true;
    
    // Protect build/tool related files
    if (normalizedPath.startsWith('tool/')) return true;
    if (normalizedPath.startsWith('scripts/')) return true;
    
    return false;
  }
}