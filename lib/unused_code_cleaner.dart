/// A comprehensive Dart package for detecting and cleaning unused code in Flutter/Dart projects.
///
/// This library provides tools to analyze projects and identify:
/// - Unused assets (images, fonts, etc.)
/// - Unused Dart functions and methods
/// - Unused packages in pubspec.yaml
/// - Unused Dart files
///
/// Example usage:
/// ```dart
/// import 'package:unused_code_cleaner/unused_code_cleaner.dart';
///
/// final cleaner = UnusedCodeCleaner();
/// final options = CleanupOptions(
///   removeUnusedAssets: true,
///   removeUnusedFiles: true,
///   verbose: true,
/// );
///
/// final result = await cleaner.analyze('.', options);
/// print('Found ${result.totalUnusedItems} unused items');
/// ```
library unused_code_cleaner;

export 'src/models/analysis_result.dart';
export 'src/models/unused_item.dart';
export 'src/models/cleanup_options.dart';
export 'src/models/dependency_graph.dart';
export 'src/utils/safe_removal.dart';
export 'src/exceptions.dart';
export 'src/cleaner.dart';
