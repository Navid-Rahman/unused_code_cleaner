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
  static bool isExcluded(String filePath, List<String> excludePatterns) {
    return matches(filePath, excludePatterns);
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
