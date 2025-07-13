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
    '.git/**',
    '.dart_tool/**',
    'build/**',
    '.packages',
    'pubspec.lock',
    '**/.DS_Store',
    '**/Thumbs.db',
    '**/*.g.dart',
    '**/*.freezed.dart',
    '**/*.gr.dart',
    '**/generated/**',
    '**/l10n/**',
  ];

  /// Critical system directories that should never be analyzed.
  static const List<String> systemExcludePatterns = [
    'C:/**',
    'C:/Windows/**',
    'C:/Program Files/**',
    'C:/Program Files (x86)/**',
    'C:/Users/*/AppData/**',
    'C:/ProgramData/**',
    '/System/**',
    '/usr/**',
    '/bin/**',
    '/sbin/**',
    '/etc/**',
  ];

  /// Checks if a file path matches any of the provided glob patterns.
  static bool matches(String filePath, List<String> patterns) {
    for (final pattern in patterns) {
      final glob = Glob(pattern);
      if (glob.matches(filePath)) {
        return true;
      }
    }
    return false;
  }

  /// Determines if a file should be excluded from analysis.
  /// Always includes default safety patterns.
  static bool isExcluded(String filePath, List<String> excludePatterns) {
    final allExcludePatterns = [
      ...defaultExcludePatterns,
      ...systemExcludePatterns,
      ...excludePatterns,
    ];
    return matches(filePath, allExcludePatterns);
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
