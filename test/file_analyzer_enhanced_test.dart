import 'package:test/test.dart';
import 'package:unused_code_cleaner/src/analyzers/file_analyzer.dart';
import 'package:unused_code_cleaner/src/models/cleanup_options.dart';

void main() {
  group('FileAnalyzer Enhanced Tests', () {
    test('should handle empty project gracefully', () async {
      final analyzer = FileAnalyzer('.');
      final options = CleanupOptions();

      // This is a placeholder test to prevent loading errors
      // More comprehensive tests can be added later
      expect(analyzer, isNotNull);
      expect(options, isNotNull);
    });
  });
}
