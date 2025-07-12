class UnusedCodeCleanerException implements Exception {
  final String message;

  const UnusedCodeCleanerException(this.message);

  @override
  String toString() => 'UnusedCodeCleanerException: $message';
}

class ProjectValidationException extends UnusedCodeCleanerException {
  const ProjectValidationException(super.message);
}

class AnalysisException extends UnusedCodeCleanerException {
  const AnalysisException(super.message);
}
