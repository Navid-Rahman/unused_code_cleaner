import 'lib/src/utils/pattern_matcher.dart';

void main() {
  final testPaths = [
    'lib/main.dart',
    '.git/config',
    'build/app.js',
    'test.g.dart',
  ];

  for (final path in testPaths) {
    final excluded = PatternMatcher.isExcluded(path, []);
    print('$path -> excluded: $excluded');

    // Test against individual pattern sets
    final defaultExcluded =
        PatternMatcher.matches(path, PatternMatcher.defaultExcludePatterns);
    final systemExcluded =
        PatternMatcher.matches(path, PatternMatcher.systemExcludePatterns);

    print('  default patterns: $defaultExcluded');
    print('  system patterns: $systemExcluded');
    print('');
  }
}
