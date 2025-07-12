class CleanupOptions {
  final bool removeUnusedAssets;
  final bool removeUnusedFunctions;
  final bool removeUnusedPackages;
  final bool removeUnusedFiles;
  final bool interactive;
  final bool verbose;
  final List<String> excludePatterns;
  final List<String> includePaths;

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
