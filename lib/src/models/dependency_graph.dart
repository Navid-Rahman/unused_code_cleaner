import 'dart:collection';
import 'package:path/path.dart' as path;
import '../utils/logger.dart';

class DependencyGraph {
  final Map<String, Set<String>> _graph = {};
  final Map<String, Set<String>> _reverseGraph = {};

  /// Adds a file and its imports to the dependency graph.
  void addFile(String filePath, Set<String> imports) {
    final normalizedPath = path.normalize(filePath);
    final normalizedImports = imports.map((imp) => path.normalize(imp)).toSet();

    _graph[normalizedPath] = normalizedImports;

    // Build reverse graph for efficient reverse lookups
    _reverseGraph[normalizedPath] ??= <String>{};
    for (final import in normalizedImports) {
      _reverseGraph[import] ??= <String>{};
      _reverseGraph[import]!.add(normalizedPath);
    }
  }

  /// Gets the dependencies (imports) for a given file.
  Set<String> getDependencies(String filePath) {
    return _graph[path.normalize(filePath)] ?? {};
  }

  /// Gets all files that depend on (import) the given file.
  Set<String> getDependents(String filePath) {
    return _reverseGraph[path.normalize(filePath)] ?? {};
  }

  /// Finds all reachable files from a set of entry points using BFS.
  Set<String> findReachableFiles(List<String> entryPoints) {
    final reachable = <String>{};
    final queue = Queue<String>();

    // Add all entry points to the queue
    for (final entryPoint in entryPoints) {
      final normalizedEntry = path.normalize(entryPoint);
      if (_graph.containsKey(normalizedEntry) ||
          _isValidFile(normalizedEntry)) {
        queue.add(normalizedEntry);
      }
    }

    Logger.debug('Starting BFS from ${entryPoints.length} entry points');
    int iterations = 0;
    const maxIterations = 10000; // Prevent infinite loops

    while (queue.isNotEmpty && iterations < maxIterations) {
      iterations++;
      final current = queue.removeFirst();

      if (reachable.contains(current)) {
        continue;
      }

      reachable.add(current);
      Logger.debug('Marked as reachable: ${path.basename(current)}');

      final dependencies = getDependencies(current);
      for (final dep in dependencies) {
        if (!reachable.contains(dep) && !queue.contains(dep)) {
          queue.add(dep);
        }
      }
    }

    if (iterations >= maxIterations) {
      Logger.warning(
          '⚠️ Dependency graph traversal hit iteration limit. Possible circular dependencies.');
    }

    Logger.info(
        'Total reachable files: ${reachable.length} ($iterations iterations)');
    return reachable;
  }

  /// Checks if a file path is valid (exists in our graph or on disk)
  bool _isValidFile(String filePath) {
    return _graph.containsKey(filePath) || _reverseGraph.containsKey(filePath);
  }

  /// Finds circular dependencies in the graph
  List<List<String>> findCircularDependencies() {
    final cycles = <List<String>>[];
    final visited = <String>{};
    final recursionStack = <String>{};

    for (final file in _graph.keys) {
      if (!visited.contains(file)) {
        final cycle = _findCycleDFS(file, visited, recursionStack, []);
        if (cycle.isNotEmpty) {
          cycles.add(cycle);
        }
      }
    }

    return cycles;
  }

  List<String> _findCycleDFS(String current, Set<String> visited,
      Set<String> recursionStack, List<String> path) {
    visited.add(current);
    recursionStack.add(current);
    path.add(current);

    final dependencies = getDependencies(current);
    for (final dep in dependencies) {
      if (!visited.contains(dep)) {
        final cycle =
            _findCycleDFS(dep, visited, recursionStack, List.from(path));
        if (cycle.isNotEmpty) {
          return cycle;
        }
      } else if (recursionStack.contains(dep)) {
        // Found cycle
        final cycleStartIndex = path.indexOf(dep);
        return path.sublist(cycleStartIndex)..add(dep);
      }
    }

    recursionStack.remove(current);
    return [];
  }

  /// Gets statistics about the dependency graph
  Map<String, dynamic> getStatistics() {
    final totalFiles = _graph.length;
    final totalDependencies = _graph.values
        .map((deps) => deps.length)
        .fold(0, (sum, count) => sum + count);

    final filesWithNoDependencies =
        _graph.values.where((deps) => deps.isEmpty).length;

    final filesNotImported =
        _graph.keys.where((file) => getDependents(file).isEmpty).length;

    return {
      'totalFiles': totalFiles,
      'totalDependencies': totalDependencies,
      'averageDependenciesPerFile':
          totalFiles > 0 ? totalDependencies / totalFiles : 0,
      'filesWithNoDependencies': filesWithNoDependencies,
      'filesNotImported': filesNotImported,
      'circularDependencies': findCircularDependencies().length,
    };
  }

  /// Debug method to print the dependency graph
  void printGraph() {
    Logger.debug('=== Dependency Graph ===');
    final stats = getStatistics();
    Logger.debug('Statistics: $stats');

    Logger.debug('--- File Dependencies ---');
    _graph.forEach((file, deps) {
      final fileName = path.basename(file);
      final depNames = deps.map((d) => path.basename(d)).join(', ');
      Logger.debug('$fileName -> [$depNames]');
    });

    final cycles = findCircularDependencies();
    if (cycles.isNotEmpty) {
      Logger.debug('--- Circular Dependencies ---');
      for (var i = 0; i < cycles.length; i++) {
        final cycleNames = cycles[i].map((f) => path.basename(f)).join(' -> ');
        Logger.debug('Cycle ${i + 1}: $cycleNames');
      }
    }

    Logger.debug('========================');
  }
}
