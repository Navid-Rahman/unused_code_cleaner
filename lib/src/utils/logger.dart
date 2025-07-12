import 'dart:io';

/// A utility class for colored console logging with various message types and formatting.
///
/// Provides colored output with ANSI escape codes, different log levels,
/// formatted output for titles/sections/tables, and verbose mode support.
class Logger {
  // ANSI Color Codes
  /// Reset all formatting to default
  static const String _reset = '\x1B[0m';

  /// Red color for error messages
  static const String _red = '\x1B[31m';

  /// Green color for success messages
  static const String _green = '\x1B[32m';

  /// Yellow color for warning messages
  static const String _yellow = '\x1B[33m';

  /// Blue color for info messages
  static const String _blue = '\x1B[34m';

  /// Magenta color for section headers
  static const String _magenta = '\x1B[35m';

  /// Cyan color for titles and table borders
  static const String _cyan = '\x1B[36m';

  /// White color for general text
  static const String _white = '\x1B[37m';

  /// Bold text formatting
  static const String _bold = '\x1B[1m';

  /// Dim text formatting for debug messages
  /// Dim text formatting for debug messages
  static const String _dim = '\x1B[2m';

  /// Controls whether debug messages are displayed
  static bool _verbose = false;

  /// Whether the terminal supports ANSI color codes
  static bool _supportsColor = stdout.supportsAnsiEscapes;

  /// Enables or disables verbose logging mode for debug messages.
  static void setVerbose(bool verbose) {
    _verbose = verbose;
  }

  /// Logs an informational message with blue color and info icon.
  static void info(String message) {
    _log('ℹ️', message, _blue);
  }

  /// Logs a success message with green color and checkmark icon.
  /// Logs a success message with green color and checkmark icon.
  static void success(String message) {
    _log('✅', message, _green);
  }

  /// Logs a warning message with yellow color and warning icon.
  static void warning(String message) {
    _log('⚠️', message, _yellow);
  }

  /// Logs an error message with red color and error icon.
  static void error(String message) {
    _log('❌', message, _red);
  }

  /// Logs a debug message with dim color. Only shown when verbose mode is enabled.
  static void debug(String message) {
    if (_verbose) {
      _log('🐛', message, _dim);
    }
  }

  /// Prints a formatted title with decorative borders and cyan color.
  static void title(String message) {
    final separator = '=' * 50;
    print(_colorize('\n$separator', _cyan));
    print(_colorize('$_bold$message$_reset', _cyan));
    print(_colorize('$separator\n', _cyan));
  }

  /// Prints a section header with magenta color and underline.
  static void section(String message) {
    print(_colorize('\n$_bold$message$_reset', _magenta));
    print(_colorize('-' * message.length, _magenta));
  }

  /// Prints data in a formatted table with borders and headers.
  /// First row is treated as headers and displayed in bold.
  /// Column widths are automatically calculated based on content.
  static void table(List<List<String>> rows) {
    if (rows.isEmpty) return;

    // Calculate column widths based on content length
    final columnWidths = <int>[];
    for (int i = 0; i < rows[0].length; i++) {
      int maxWidth = 0;
      for (final row in rows) {
        if (i < row.length) {
          maxWidth = maxWidth < row[i].length ? row[i].length : maxWidth;
        }
      }
      columnWidths.add(maxWidth + 2); // Add padding
    }

    // Print table with Unicode box-drawing characters
    print(_colorize('┌${'─' * columnWidths.fold(0, (a, b) => a + b)}┐', _cyan));

    for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      String line = '│';

      for (int i = 0; i < row.length; i++) {
        final cell = row[i].padRight(columnWidths[i]);
        line += rowIndex == 0 ? _colorize(cell, _bold) : cell;
      }
      line += '│';

      print(_colorize(line, rowIndex == 0 ? _bold : _white));

      // Add separator after header row
      if (rowIndex == 0) {
        print(_colorize(
            '├${'─' * columnWidths.fold(0, (a, b) => a + b)}┤', _cyan));
      }
    }

    print(_colorize('└${'─' * columnWidths.fold(0, (a, b) => a + b)}┘', _cyan));
  }

  /// Internal method to format and print log messages with timestamps and icons.
  static void _log(String icon, String message, String color) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final formattedMessage = '$icon [$timestamp] $message';
    print(_colorize(formattedMessage, color));
  }

  /// Applies color formatting to text if the terminal supports ANSI escape codes.
  /// Returns plain text if colors are not supported.
  static String _colorize(String text, String color) {
    return _supportsColor ? '$color$text$_reset' : text;
  }
}
