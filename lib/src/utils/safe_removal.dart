import 'dart:io';
import 'package:path/path.dart' as path;

import '../models/unused_item.dart';
import 'logger.dart';
import 'file_utils.dart';

/// Safe removal utility with backup and recovery capabilities.
///
/// This class ensures that file removals are safe by creating backups,
/// validating the project after removal, and providing rollback capabilities.
class SafeRemoval {
  final String projectPath;
  final String backupPath;

  SafeRemoval(this.projectPath)
      : backupPath = path.join(projectPath,
            'unused_code_cleaner_backup_${DateTime.now().toIso8601String().replaceAll(':', '_').replaceAll('.', '_')}');

  /// Creates a backup of critical project files before removal.
  Future<void> createBackup() async {
    final backupDir = Directory(backupPath);
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
    }
    await backupDir.create(recursive: true);
    Logger.info('📦 Creating backup at $backupPath');

    // Backup critical files
    await _backupFile('pubspec.yaml');
    await _backupFile('pubspec.lock');
    await _backupFile('analysis_options.yaml');

    // Backup important directories
    await _backupDirectory('lib');
    await _backupDirectory('assets');
    await _backupDirectory('images');
    await _backupDirectory('fonts');
    await _backupDirectory('data');
    await _backupDirectory('test');

    Logger.success('✅ Backup created successfully');
  }

  /// Backs up a single file if it exists.
  Future<void> _backupFile(String relativePath) async {
    final source = File(path.join(projectPath, relativePath));
    if (await source.exists()) {
      final destination = File(path.join(backupPath, relativePath));
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
      Logger.debug('Backed up $relativePath');
    }
  }

  /// Backs up an entire directory if it exists.
  Future<void> _backupDirectory(String relativePath) async {
    final sourceDir = Directory(path.join(projectPath, relativePath));
    if (await sourceDir.exists()) {
      final destinationDir = Directory(path.join(backupPath, relativePath));
      await destinationDir.create(recursive: true);

      await for (final entity in sourceDir.list(recursive: true)) {
        if (entity is File) {
          final relPath = path.relative(entity.path, from: projectPath);
          final destPath = path.join(backupPath, relPath);
          await Directory(path.dirname(destPath)).create(recursive: true);
          await entity.copy(destPath);
          Logger.debug('Backed up $relPath');
        }
      }
    }
  }

  /// Safely removes unused items with optional dry-run mode.
  Future<void> removeUnusedItems(List<UnusedItem> items,
      {bool dryRun = false}) async {
    if (items.isEmpty) {
      Logger.info('No unused items to remove');
      return;
    }

    if (!dryRun) {
      await createBackup();
    }

    try {
      final assetItems =
          items.where((item) => item.type == UnusedItemType.asset).toList();
      final fileItems =
          items.where((item) => item.type == UnusedItemType.file).toList();
      final packageItems =
          items.where((item) => item.type == UnusedItemType.package).toList();
      final functionItems =
          items.where((item) => item.type == UnusedItemType.function).toList();

      // Remove assets and files
      for (final item in [...assetItems, ...fileItems]) {
        if (dryRun) {
          Logger.info('Would remove: ${item.path} (${item.description})');
          continue;
        }

        if (await FileUtils.deleteFile(item.path)) {
          Logger.success('🗑️ Removed ${item.path}');
        } else {
          Logger.warning('⚠️ Could not remove ${item.path}');
        }
      }

      // Remove packages from pubspec.yaml
      for (final item in packageItems) {
        if (dryRun) {
          Logger.info('Would remove package: ${item.name} from pubspec.yaml');
          continue;
        }

        await _removePackage(item.name);
      }

      // Functions require manual removal (too risky to automate)
      if (functionItems.isNotEmpty) {
        Logger.warning('🔧 Function removal requires manual intervention:');
        for (final item in functionItems) {
          Logger.warning(
              '  - ${item.name} in ${item.path}:${item.lineNumber ?? 'unknown'}');
        }
      }

      if (!dryRun) {
        await _validateProject();
      }
    } catch (e) {
      Logger.error('Error during removal: $e');
      if (!dryRun) {
        Logger.warning('Attempting to restore backup...');
        await restoreBackup();
      }
      rethrow;
    }
  }

  /// Removes a package from pubspec.yaml.
  Future<void> _removePackage(String packageName) async {
    final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) {
      Logger.warning('pubspec.yaml not found');
      return;
    }

    try {
      final content = await pubspecFile.readAsString();
      final lines = content.split('\n');
      final updatedLines = <String>[];
      bool inDependencies = false;
      bool inDevDependencies = false;

      for (final line in lines) {
        final trimmed = line.trim();

        // Check if we're entering a dependencies section
        if (trimmed == 'dependencies:') {
          inDependencies = true;
          inDevDependencies = false;
        } else if (trimmed == 'dev_dependencies:') {
          inDevDependencies = true;
          inDependencies = false;
        } else if (trimmed.endsWith(':') && !trimmed.startsWith(' ')) {
          inDependencies = false;
          inDevDependencies = false;
        }

        // Skip the package line if we're in a dependencies section
        if ((inDependencies || inDevDependencies) &&
            trimmed.startsWith('$packageName:')) {
          Logger.debug('Removing package line: $line');
          continue;
        }

        updatedLines.add(line);
      }

      await pubspecFile.writeAsString(updatedLines.join('\n'));
      Logger.success('✅ Removed package $packageName from pubspec.yaml');
    } catch (e) {
      Logger.error('Error removing package $packageName: $e');
    }
  }

  /// Validates the project after removal by running flutter analyze and tests.
  Future<void> _validateProject() async {
    Logger.info('🔍 Validating project after removal...');

    try {
      // Run flutter analyze
      final analyzeProcess = await Process.run(
        'flutter',
        ['analyze'],
        workingDirectory: projectPath,
      );

      if (analyzeProcess.exitCode == 0) {
        Logger.success('✅ flutter analyze passed');
      } else {
        Logger.warning('⚠️ flutter analyze reported issues:');
        Logger.warning(analyzeProcess.stdout.toString());
        if (analyzeProcess.stderr.toString().isNotEmpty) {
          Logger.warning(analyzeProcess.stderr.toString());
        }
      }

      // Run flutter test (if test directory exists)
      final testDir = Directory(path.join(projectPath, 'test'));
      if (await testDir.exists()) {
        Logger.info('Running flutter test...');
        final testProcess = await Process.run(
          'flutter',
          ['test'],
          workingDirectory: projectPath,
        );

        if (testProcess.exitCode == 0) {
          Logger.success('✅ flutter test passed');
        } else {
          Logger.warning('⚠️ flutter test reported issues:');
          Logger.warning(testProcess.stdout.toString());
          if (testProcess.stderr.toString().isNotEmpty) {
            Logger.warning(testProcess.stderr.toString());
          }
        }
      }
    } catch (e) {
      Logger.error('Project validation failed: $e');
    }
  }

  /// Restores the project from backup.
  Future<void> restoreBackup() async {
    final backupDir = Directory(backupPath);
    if (!await backupDir.exists()) {
      Logger.error('No backup found at $backupPath');
      return;
    }

    Logger.info('📦 Restoring backup from $backupPath');

    try {
      await for (final entity in backupDir.list(recursive: true)) {
        if (entity is File) {
          final relPath = path.relative(entity.path, from: backupPath);
          final destPath = path.join(projectPath, relPath);
          await Directory(path.dirname(destPath)).create(recursive: true);
          await entity.copy(destPath);
          Logger.debug('Restored $relPath');
        }
      }
      Logger.success('✅ Backup restored successfully from $backupPath');
    } catch (e) {
      Logger.error('Error restoring backup: $e');
      rethrow;
    }
  }

  /// Cleans up old backup directories (keeps only the 5 most recent).
  Future<void> cleanupOldBackups() async {
    try {
      final backupPattern = RegExp(r'unused_code_cleaner_backup_.*');
      final projectDir = Directory(projectPath);
      final backupDirs = <Directory>[];

      await for (final entity in projectDir.list()) {
        if (entity is Directory &&
            backupPattern.hasMatch(path.basename(entity.path))) {
          backupDirs.add(entity);
        }
      }

      if (backupDirs.length > 5) {
        // Sort by creation time (newest first)
        backupDirs.sort((a, b) {
          final statA = a.statSync();
          final statB = b.statSync();
          return statB.modified.compareTo(statA.modified);
        });

        // Remove old backups (keep only 5 most recent)
        for (int i = 5; i < backupDirs.length; i++) {
          await backupDirs[i].delete(recursive: true);
          Logger.debug(
              'Cleaned up old backup: ${path.basename(backupDirs[i].path)}');
        }
      }
    } catch (e) {
      Logger.debug('Error cleaning up old backups: $e');
    }
  }
}
