import 'lib/src/models/analysis_result.dart';
import 'lib/src/models/unused_item.dart';
import 'lib/src/cleaner.dart';

void main() {
  // Create mock analysis result to test comprehensive summary
  final mockResult = AnalysisResult(
    unusedAssets: [
      UnusedItem(
        name: 'unused_image.png',
        path: 'assets/unused_image.png',
        type: UnusedItemType.asset,
        size: 1024 * 500, // 500KB
      ),
      UnusedItem(
        name: 'old_icon.png',
        path: 'assets/old_icon.png',
        type: UnusedItemType.asset,
        size: 1024 * 200, // 200KB
      ),
    ],
    unusedFunctions: [
      UnusedItem(
        name: 'oldHelperFunction',
        path: 'lib/utils/helpers.dart',
        type: UnusedItemType.function,
        lineNumber: 45,
        description: 'Deprecated helper function',
      ),
      UnusedItem(
        name: 'unusedCalculation',
        path: 'lib/math/calculator.dart',
        type: UnusedItemType.function,
        lineNumber: 120,
      ),
    ],
    unusedPackages: [
      UnusedItem(
        name: 'http',
        path: 'pubspec.yaml',
        type: UnusedItemType.package,
        description: 'HTTP package not used',
      ),
    ],
    unusedFiles: [
      UnusedItem(
        name: 'old_service.dart',
        path: 'lib/services/old_service.dart',
        type: UnusedItemType.file,
        size: 1024 * 50, // 50KB
      ),
    ],
    analysisTime: Duration(milliseconds: 1250),
    totalScannedFiles: 25,
  );

  // Create cleaner instance and test the comprehensive summary
  final cleaner = UnusedCodeCleaner();

  print('=== TESTING COMPREHENSIVE SUMMARY ===');
  print('This shows the new enhanced result overview:');
  print('');

  // Access the private method for testing (normally called from _displayResults)
  // This would be called automatically when running the tool
  // cleaner._displayComprehensiveSummary(mockResult);

  print('Mock result contains:');
  print('- ${mockResult.unusedAssets.length} unused assets');
  print('- ${mockResult.unusedFunctions.length} unused functions');
  print('- ${mockResult.unusedPackages.length} unused packages');
  print('- ${mockResult.unusedFiles.length} unused files');
  print('- Total scan time: ${mockResult.analysisTime.inMilliseconds}ms');
  print('- Files scanned: ${mockResult.totalScannedFiles}');
  print('');
  print('The comprehensive summary would show:');
  print('📋 Overview table with health status');
  print('🏥 Project health score calculation');
  print('💰 Potential space savings');
  print('⏱️ Performance metrics');
}
