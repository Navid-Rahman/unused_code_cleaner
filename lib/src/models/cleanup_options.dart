/// Configuration options for customizing the unused code cleanup process.
///
/// Allows fine-grained control over what types of unused items to remove,
/// how the cleanup process behaves, and which files to include or exclude.
class CleanupOptions {
  /// Whether to remove unused asset files (images, fonts, etc.).
  final bool removeUnusedAssets;

  /// Whether to remove unused Dart functions and methods.
  final bool removeUnusedFunctions;

  /// Whether to remove unused package dependencies from pubspec.yaml.
  final bool removeUnusedPackages;

  /// Whether to remove unused Dart files.
  final bool removeUnusedFiles;

  /// Whether to prompt the user for confirmation before removing each item.
  final bool interactive;

  /// Whether to enable verbose logging during the cleanup process.
  final bool verbose;

  /// List of glob patterns for files/directories to exclude from analysis.
  final List<String> excludePatterns;

  /// List of specific paths to include in the analysis (empty means include all).
  final List<String> includePaths;

  /// Creates a new [CleanupOptions] with the specified configuration.
  ///
  /// By default, all removal options are disabled and interactive mode is enabled.
  const CleanupOptions({
    this.removeUnusedAssets = false,
    this.removeUnusedFunctions = false,
    this.removeUnusedPackages = false,
    this.removeUnusedFiles = false,
    this.interactive = true,
    this.verbose = false,
    this.excludePatterns = const [],
    this.includePaths = const [],
  });
}
