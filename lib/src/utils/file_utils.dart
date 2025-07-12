import 'dart:io';
import 'package:path/path.dart' as path;

/// A utility class for file system operations commonly used in the unused code cleaner.
///
/// Provides methods for finding files, getting file sizes, and safely deleting files.
class FileUtils {
  /// Recursively finds all Dart source files (.dart) in the specified directory.
  ///
  /// [directory] - The root directory path to search in
  /// Returns a list of all found Dart files, or empty list if directory doesn't exist.
  static Future<List<File>> findDartFiles(String directory) async {
    final files = <File>[];
    final dir = Directory(directory);

    // Check if directory exists before attempting to list contents
    if (!await dir.exists()) return files;

    // Recursively iterate through all files and subdirectories
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(entity);
      }
    }

    return files;
  }

  /// Recursively finds all asset files with common extensions in the specified directory.
  ///
  /// Searches for images (.png, .jpg, .jpeg, .gif, .webp, .svg),
  /// config files (.json, .yaml, .yml, .xml), and docs (.txt, .md).
  ///
  /// [directory] - The root directory path to search in
  /// Returns a list of all found asset files, or empty list if directory doesn't exist.
  static Future<List<File>> findAssetFiles(String directory) async {
    final files = <File>[];
    final dir = Directory(directory);

    // Check if directory exists before attempting to list contents
    if (!await dir.exists()) return files;

    // Define supported asset file extensions
    final assetExtensions = {
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', // Images
      '.json', '.xml', '.yaml', '.yml', // Config files
      '.txt', '.md' // Documentation
    };

    // Recursively iterate through all files and check extensions
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final extension = path.extension(entity.path).toLowerCase();
        if (assetExtensions.contains(extension)) {
          files.add(entity);
        }
      }
    }

    return files;
  }

  /// Gets the size of a file in bytes.
  ///
  /// [filePath] - Path to the file
  /// Returns file size in bytes, or 0 if file doesn't exist or error occurs.
  static Future<int> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      final stat = await file.stat();
      return stat.size;
    } catch (e) {
      // Return 0 if file doesn't exist or can't be accessed
      return 0;
    }
  }

  /// Formats a file size in bytes into a human-readable string (B, KB, MB, GB).
  ///
  /// [bytes] - The file size in bytes to format
  /// Returns formatted string with appropriate unit suffix.
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Safely deletes a file from the file system.
  ///
  /// [filePath] - Path to the file to delete
  /// Returns true if file was successfully deleted, false if file didn't exist or error occurred.
  static Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false; // File doesn't exist
    } catch (e) {
      return false; // Error during deletion
    }
  }
}
