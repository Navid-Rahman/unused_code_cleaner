/// Enumeration of different types of unused items that can be detected.
enum UnusedItemType {
  /// An unused asset file (image, font, etc.)
  asset,

  /// An unused Dart function or method
  function,

  /// An unused package dependency
  package,

  /// An unused Dart file
  file
}

/// Represents a single unused item discovered during code analysis.
///
/// Contains information about the item including its location, type,
/// and optional metadata such as size and description.
class UnusedItem {
  /// The name of the unused item (function name, file name, etc.).
  final String name;

  /// The file system path where the unused item is located.
  final String path;

  /// The type of unused item (asset, function, package, or file).
  final UnusedItemType type;

  /// The line number where the item is defined (for functions/methods).
  final int? lineNumber;

  /// Optional description providing additional context about the item.
  final String? description;

  /// The size of the item in bytes (primarily for asset files).
  final int? size;

  /// Creates a new [UnusedItem] with the specified properties.
  const UnusedItem({
    required this.name,
    required this.path,
    required this.type,
    this.lineNumber,
    this.description,
    this.size,
  });

  /// Returns a human-readable display name for this unused item.
  String get displayName {
    switch (type) {
      case UnusedItemType.asset:
        return '🖼️  $name';
      case UnusedItemType.function:
        return '⚡ $name';
      case UnusedItemType.package:
        return '📦 $name';
      case UnusedItemType.file:
        return '📄 $name';
    }
  }

  /// Returns a formatted file size string (e.g., "1.2 MB", "512 KB").
  String get formattedSize {
    if (size == null) return 'N/A';

    final bytes = size!;
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Returns the description or a default value if null.
  String get safeDescription => description ?? 'No description';
}
