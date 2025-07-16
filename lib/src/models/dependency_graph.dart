import 'dart:collection';
import 'package:path/path.dart' as path;
import '../utils/logger.dart';

class DependencyGraph {
  final Map<String, Set<String>> _graph = {};

  /// Adds a file and its imports to the dependency graph.
  void addFile(String filePath, Set<String> imports) {
    final normalizedPath = path.normalize(filePath);
    final normalizedImports = imports.map((imp) => path.normalize(imp)).toSet();
    _graph[normalizedPath] = normalizedImports;
  }

  /// Gets the dependencies (imports) for a given file.
  Set<String> getDependencies(String filePath) {
    return _graph[path.normalize(filePath)] ?? {};
  }

  /// Finds all reachable files from a set of entry points using BFS.
  Set<String> findReachableFiles(List<String> entryPoints) {
    final reachable = <String>{};
    final queue = Queue<String>();

    // Add all entry points to the queue
    for (final entryPoint in entryPoints) {
      final normalizedEntry = path.normalize(entryPoint);
      queue.add(normalizedEntry);
    }

    Logger.debug('Starting BFS from ${entryPoints.length} entry points');

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();

      if (reachable.contains(current)) {
        continue;
      }

      reachable.add(current);
      Logger.debug('Marked as reachable: ${path.basename(current)}');

      final dependencies = getDependencies(current);
      for (final dep in dependencies) {
        if (!reachable.contains(dep)) {
          queue.add(dep);
        }
      }
    }

    Logger.debug('Total reachable files: ${reachable.length}');
    return reachable;
  }

  /// Debug method to print the dependency graph
  void printGraph() {
    Logger.debug('=== Dependency Graph ===');
    _graph.forEach((file, deps) {
      final fileName = path.basename(file);
      final depNames = deps.map((d) => path.basename(d)).join(', ');
      Logger.debug('$fileName -> [$depNames]');
    });
    Logger.debug('========================');
  }
}
