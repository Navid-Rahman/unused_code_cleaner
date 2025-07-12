import 'package:unused_code_cleaner/src/models/unused_item.dart';

class AnalysisResult {
  final List<UnusedItem> unusedAssets;
  final List<UnusedItem> unusedFunctions;
  final List<UnusedItem> unusedPackages;
  final List<UnusedItem> unusedFiles;
  final Duration analysisTime;
  final int totalScannedFiles;

  const AnalysisResult({
    required this.unusedAssets,
    required this.unusedFunctions,
    required this.unusedPackages,
    required this.unusedFiles,
    required this.analysisTime,
    required this.totalScannedFiles,
  });

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
