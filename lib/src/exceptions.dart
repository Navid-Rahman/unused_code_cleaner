/// Base exception class for all unused code cleaner related errors.
///
/// This is the parent class for all exceptions thrown by the unused code cleaner.
class UnusedCodeCleanerException implements Exception {
  /// The error message describing what went wrong.
  final String message;

  /// Creates a new [UnusedCodeCleanerException] with the given [message].
  const UnusedCodeCleanerException(this.message);

  @override
  String toString() => 'UnusedCodeCleanerException: $message';
}

/// Exception thrown when project validation fails.
///
/// This exception is thrown when the project structure is invalid or
/// required files (like pubspec.yaml) are missing or malformed.
class ProjectValidationException extends UnusedCodeCleanerException {
  /// Creates a new [ProjectValidationException] with the given [message].
  const ProjectValidationException(super.message);
}

/// Exception thrown when code analysis fails.
///
/// This exception is thrown when the analyzer encounters errors while
/// parsing Dart code or analyzing the project structure.
class AnalysisException extends UnusedCodeCleanerException {
  /// Creates a new [AnalysisException] with the given [message].
  const AnalysisException(super.message);
}
