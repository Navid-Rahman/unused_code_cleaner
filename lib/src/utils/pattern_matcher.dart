/// Provides glob pattern matching utilities for file path filtering.
///
/// This file contains the [PatternMatcher] class which handles:
/// - Glob pattern matching against file paths
/// - Inclusion/exclusion filtering for analysis
/// - Cross-platform path normalization
library;

import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;

/// Utility class for glob pattern matching and path filtering.
class PatternMatcher {
  /// Default patterns that should always be excluded for safety.
  static const List<String> defaultExcludePatterns = [
    '.packages',
    'pubspec.lock',
    '.DS_Store',
    'Thumbs.db',
  ];

  /// Critical system directories that should never be analyzed.
  static const List<String> systemExcludePatterns = [
    'C:\\Windows\\**',
    'C:\\Program Files\\**',
    'C:\\Program Files (x86)\\**',
    'C:\\ProgramData\\**',
  ];

  /// Checks if a file path matches any of the provided glob patterns.
  static bool matches(String filePath, List<String> patterns) {
    final normalizedPath = normalizePath(filePath);

    for (final pattern in patterns) {
      try {
        // Handle simple patterns without glob if they contain special characters
        if (pattern.contains('*') || pattern.contains('?')) {
          final glob = Glob(pattern);
          if (glob.matches(normalizedPath)) {
            return true;
          }
        } else {
          // Simple string matching for exact paths
          if (normalizedPath == pattern ||
              normalizedPath.endsWith('/$pattern')) {
            return true;
          }
        }
      } catch (e) {
        // If glob parsing fails, fall back to simple string matching
        if (normalizedPath.contains(pattern.replaceAll('*', ''))) {
          return true;
        }
      }
    }
    return false;
  }

  /// Determines if a file should be excluded from analysis.
  /// Always includes default safety patterns.
  static bool isExcluded(String filePath, List<String> excludePatterns) {
    final normalizedPath = normalizePath(filePath);

    // Check default patterns (simple string matching)
    if (matches(normalizedPath, defaultExcludePatterns)) {
      return true;
    }

    // Manual checks for common exclusions with enhanced safety
    if (normalizedPath.startsWith('.git/') ||
        normalizedPath.startsWith('.dart_tool/') ||
        normalizedPath.startsWith('build/') ||
        normalizedPath.endsWith('.g.dart') ||
        normalizedPath.endsWith('.freezed.dart') ||
        normalizedPath.endsWith('.gr.dart') ||
        normalizedPath.contains('/generated/') ||
        normalizedPath.startsWith('generated/') ||
        normalizedPath.contains('/l10n/') ||
        normalizedPath.startsWith('l10n/') ||
        // Enhanced: Protect more critical directories
        normalizedPath.startsWith('.vscode/') ||
        normalizedPath.startsWith('.idea/') ||
        normalizedPath.startsWith('.gradle/') ||
        normalizedPath.startsWith('android/') ||
        normalizedPath.startsWith('ios/') ||
        normalizedPath.startsWith('web/') ||
        normalizedPath.startsWith('windows/') ||
        normalizedPath.startsWith('macos/') ||
        normalizedPath.startsWith('linux/')) {
      return true;
    }

    // Check system paths manually for safety
    if (_isSystemPath(normalizedPath)) {
      return true;
    }

    // Check user provided patterns
    if (matches(normalizedPath, excludePatterns)) {
      return true;
    }

    return false;
  }

  /// Manually checks for system paths to avoid glob parsing issues
  static bool _isSystemPath(String normalizedPath) {
    final systemPrefixes = [
      'C:/Windows/',
      'C:/Program Files/',
      'C:/Program Files (x86)/',
      'C:/ProgramData/',
      '/System/',
      '/usr/',
      '/bin/',
      '/sbin/',
      '/etc/',
    ];

    return systemPrefixes.any((prefix) => normalizedPath.startsWith(prefix));
  }

  /// Determines if a file should be included in analysis.
  static bool isIncluded(String filePath, List<String> includePaths) {
    if (includePaths.isEmpty) return true; // Include all if no specific paths
    return matches(filePath, includePaths);
  }

  /// Normalizes file paths for cross-platform compatibility.
  static String normalizePath(String filePath) {
    return path.normalize(filePath).replaceAll(r'\', '/');
  }
}
