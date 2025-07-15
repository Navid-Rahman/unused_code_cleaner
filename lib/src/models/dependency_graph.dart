import 'dart:collection';
import 'package:path/path.dart' as path;

/// A dependency graph to track file imports and their relationships.
///
/// This class helps identify which files are transitively imported from entry points,
/// preventing false positives when marking files as unused.
class DependencyGraph {
  final Map<String, Set<String>> _graph = {};

  /// Adds a file and its imports to the dependency graph.
  ///
  /// [filePath] The absolute path to the file
  /// [imports] Set of absolute paths that this file imports
  void addFile(String filePath, Set<String> imports) {
    _graph[path.normalize(filePath)] = imports.map(path.normalize).toSet();
  }

  /// Gets the dependencies (imports) for a given file.
  ///
  /// Returns an empty set if the file is not in the graph.
  Set<String> getDependencies(String filePath) {
    return _graph[path.normalize(filePath)] ?? {};
  }

  /// Finds all reachable files from a set of entry points using BFS.
  ///
  /// This ensures that files transitively imported from entry points
  /// (like main.dart or test files) are not marked as unused.
  Set<String> findReachableFiles(List<String> entryPoints) {
    final reachable = <String>{};
    final queue = Queue<String>.from(entryPoints.map(path.normalize));

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (reachable.contains(current)) continue;

      reachable.add(current);
      final dependencies = getDependencies(current);
      for (final dep in dependencies) {
        if (!reachable.contains(dep)) {
          queue.add(dep);
        }
      }
    }

    return reachable;
  }

  /// Gets all files in the dependency graph.
  Set<String> getAllFiles() {
    return _graph.keys.toSet();
  }

  /// Checks if a file exists in the dependency graph.
  bool containsFile(String filePath) {
    return _graph.containsKey(path.normalize(filePath));
  }

  /// Gets the number of files in the dependency graph.
  int get fileCount => _graph.length;

  /// Clears all data from the dependency graph.
  void clear() {
    _graph.clear();
  }
}
