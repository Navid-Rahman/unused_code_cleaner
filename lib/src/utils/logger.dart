import 'dart:io';

/// Professional logging utility with clean, user-friendly output formatting.
///
/// Provides structured logging with clear sections, proper spacing,
/// and minimal noise for better user experience.
class Logger {
  // ANSI Color Codes
  static const String _reset = '\x1B[0m';
  static const String _red = '\x1B[31m';
  static const String _green = '\x1B[32m';
  static const String _yellow = '\x1B[33m';
  static const String _blue = '\x1B[34m';
  static const String _magenta = '\x1B[35m';
  static const String _cyan = '\x1B[36m';
  static const String _white = '\x1B[37m';
  static const String _bold = '\x1B[1m';
  static const String _dim = '\x1B[2m';

  /// Controls debug output visibility
  static bool _verbose = false;
  static bool _debugMode = false;

  /// Whether the terminal supports ANSI color codes
  static final bool _supportsColor = stdout.supportsAnsiEscapes;

  /// Enable/disable verbose logging
  static void setVerbose(bool verbose) {
    _verbose = verbose;
  }

  /// Enable/disable debug mode
  static void setDebugMode(bool debug) {
    _debugMode = debug;
  }

  /// Apply color formatting if supported
  static String _colorize(String text, String color) {
    return _supportsColor ? '$color$text$_reset' : text;
  }

  /// Application header
  static void header(String appName, String version) {
    print('');
    print(_colorize('🧹 $appName v$version', '$_bold$_cyan'));
    print(_colorize('Analyzing your project...', _white));
    print('');
  }

  /// Main section header with proper spacing
  static void section(String title) {
    print('');
    print(_colorize('📋 ${title.toUpperCase()}', '$_bold$_cyan'));
    print(_colorize('${'─' * (title.length + 4)}', _cyan));
  }

  /// Subsection header
  static void subsection(String title) {
    print('');
    print(_colorize('▶ $title', '$_bold$_blue'));
  }

  /// Success message with checkmark
  static void success(String message) {
    print(_colorize('✅ $message', _green));
  }

  /// Warning message with warning icon
  static void warning(String message) {
    print(_colorize('⚠️  $message', _yellow));
  }

  /// Error message with X icon
  static void error(String message) {
    print(_colorize('❌ $message', _red));
  }

  /// Info message with info icon
  static void info(String message) {
    print(_colorize('ℹ️  $message', _blue));
  }

  /// Progress message with arrow
  static void progress(String message) {
    print(_colorize('→ $message', _white));
  }

  /// Debug message (only shown in verbose mode)
  static void debug(String message) {
    if (_debugMode || _verbose) {
      print(_colorize('🔍 $message', _dim));
    }
  }

  /// Raw message without formatting
  static void plain(String message) {
    print(message);
  }

  /// Analysis start notification
  static void startAnalysis(String type) {
    progress('Starting $type analysis...');
  }

  /// Analysis completion with results
  static void completeAnalysis(String type, int found, int total) {
    if (found == 0) {
      success('$type analysis complete - No issues found');
    } else {
      info('$type analysis complete - Found $found unused items');
    }
  }

  /// File processing update
  static void processingUpdate(String type, int processed, int total) {
    if (_verbose) {
      progress('Processing $type files: $processed/$total');
    }
  }

  /// Results summary table header
  static void resultsHeader() {
    print('');
    print(_colorize('📊 ANALYSIS RESULTS', '$_bold$_cyan'));
    print(_colorize('${'═' * 50}', _cyan));
    print('');
  }

  /// Results summary footer
  static void resultsFooter() {
    print('');
    print(_colorize('${'═' * 50}', _cyan));
  }

  /// Performance summary
  static void performanceSummary(int filesScanned, int duration) {
    final seconds = (duration / 1000).toStringAsFixed(1);
    final rate = (filesScanned / (duration / 1000)).toStringAsFixed(1);
    
    print('');
    info('Analysis completed in ${seconds}s');
    info('Scanned $filesScanned files at $rate files/second');
  }

  /// Health score display
  static void healthScore(double score) {
    String emoji;
    String status;
    String color;

    if (score >= 90) {
      emoji = '🟢';
      status = 'EXCELLENT';
      color = _green;
    } else if (score >= 75) {
      emoji = '🟡';
      status = 'GOOD';
      color = _yellow;
    } else if (score >= 50) {
      emoji = '🟠';
      status = 'NEEDS ATTENTION';
      color = _yellow;
    } else {
      emoji = '🔴';
      status = 'CRITICAL';
      color = _red;
    }

    print('');
    print(_colorize('$emoji PROJECT HEALTH: $status (${score.toStringAsFixed(1)}%)', '$_bold$color'));
  }

  /// Recommendations section
  static void recommendations(List<String> recommendations) {
    if (recommendations.isEmpty) return;

    print('');
    print(_colorize('💡 RECOMMENDATIONS', '$_bold$_magenta'));
    print(_colorize('${'─' * 16}', _magenta));
    
    for (final rec in recommendations) {
      print(_colorize('• $rec', _white));
    }
  }

  /// Dry run warning
  static void dryRunWarning() {
    print('');
    warning('DRY RUN MODE: No files will be deleted. Review the results above.');
    info('To actually remove files, run without --dry-run flag.');
  }

  /// Final completion message
  static void completionMessage(bool hasIssues) {
    print('');
    if (hasIssues) {
      info('Analysis complete. Review the findings above.');
    } else {
      success('Analysis complete. Your project is clean! 🎉');
    }
    print('');
  }

  /// Legacy method for title (maps to section)
  static void title(String title) {
    section(title);
  }

  /// Simple table display with minimal formatting
  static void table(List<List<String>> data) {
    if (data.isEmpty) return;
    
    // Calculate column widths
    List<int> columnWidths = [];
    for (int col = 0; col < data[0].length; col++) {
      int maxWidth = 0;
      for (List<String> row in data) {
        if (col < row.length) {
          maxWidth = maxWidth > row[col].length ? maxWidth : row[col].length;
        }
      }
      columnWidths.add(maxWidth + 2); // Add padding
    }

    // Print header row (first row)
    if (data.isNotEmpty) {
      String headerRow = '';
      for (int col = 0; col < data[0].length; col++) {
        String cell = col < data[0].length ? data[0][col] : '';
        headerRow += cell.padRight(columnWidths[col]);
      }
      print(_colorize(headerRow, '$_bold$_cyan'));
      
      // Print separator
      String separator = '';
      for (int width in columnWidths) {
        separator += '─' * width;
      }
      print(_colorize(separator, _cyan));
    }

    // Print data rows (skip header)
    for (int row = 1; row < data.length; row++) {
      String tableRow = '';
      for (int col = 0; col < data[row].length; col++) {
        String cell = col < data[row].length ? data[row][col] : '';
        tableRow += cell.padRight(columnWidths[col]);
      }
      print('  $tableRow');
    }
    print('');
  }
}
