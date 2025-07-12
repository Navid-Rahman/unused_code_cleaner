import 'package:unused_code_cleaner/src/models/unused_item.dart';

/// Represents the result of analyzing a project for unused code.
///
/// Contains lists of different types of unused items found during analysis,
/// along with metadata about the analysis process such as timing and scope.
class AnalysisResult {
  /// List of unused asset files (images, fonts, etc.) found in the project.
  final List<UnusedItem> unusedAssets;

  /// List of unused Dart functions and methods found in the project.
  final List<UnusedItem> unusedFunctions;

  /// List of unused packages declared in pubspec.yaml but not imported.
  final List<UnusedItem> unusedPackages;

  /// List of unused Dart files that are not imported or referenced.
  final List<UnusedItem> unusedFiles;

  /// Total time taken to complete the analysis.
  final Duration analysisTime;

  /// Total number of files that were scanned during analysis.
  final int totalScannedFiles;

  /// Creates a new [AnalysisResult] with the specified unused items and metadata.
  const AnalysisResult({
    required this.unusedAssets,
    required this.unusedFunctions,
    required this.unusedPackages,
    required this.unusedFiles,
    required this.analysisTime,
    required this.totalScannedFiles,
  });

  /// Returns true if any unused items were found during analysis.
  bool get hasUnusedItems =>
      unusedAssets.isNotEmpty ||
      unusedFunctions.isNotEmpty ||
      unusedPackages.isNotEmpty ||
      unusedFiles.isNotEmpty;

  int get totalUnusedItems =>
      unusedAssets.length +
      unusedFunctions.length +
      unusedPackages.length +
      unusedFiles.length;
}
