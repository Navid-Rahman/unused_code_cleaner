enum UnusedItemType { asset, function, package, file }

class UnusedItem {
  final String name;
  final String path;
  final UnusedItemType type;
  final int? lineNumber;
  final String? description;
  final int? size;

  const UnusedItem({
    required this.name,
    required this.path,
    required this.type,
    this.lineNumber,
    this.description,
    this.size,
  });

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
}
