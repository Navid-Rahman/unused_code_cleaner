# Changelog

## 1.0.1+hotfix.1 - Documentation Safety Update

### Documentation Updates:
- **ADDED**: Critical safety warnings in README.md
- **ENHANCED**: Installation instructions with version safety notes
- **ADDED**: Comprehensive safety features section
- **UPDATED**: Version constraints to ensure users get safe version

## 1.0.1+hotfix - CRITICAL SAFETY UPDATE

**🚨 EMERGENCY HOTFIX - ALL USERS MUST UPDATE IMMEDIATELY**

### Critical Bug Fixes:

- **FIXED**: Catastrophic file deletion bug in file analyzer that was removing ALL files instead of just unused ones
- **FIXED**: Overly broad `contains()` matching in `_isSpecialFile()` method
- **ADDED**: Self-analysis prevention - package cannot analyze itself
- **ADDED**: System directory protection - prevents analysis of C:\, Windows, Program Files, etc.
- **ADDED**: Default exclusion patterns for generated files, build artifacts, git files
- **ENHANCED**: Multi-level confirmation dialogs with detailed file lists before deletion
- **IMPROVED**: Specific path pattern matching instead of dangerous substring matching

### Safety Features Added:

- Pattern normalization and cross-platform path handling
- Comprehensive system path validation
- Enhanced error messages and warnings
- Automatic exclusion of .git, .dart_tool, build/, \*.g.dart, etc.

### ⚠️ Version 1.0.0 Advisory:

**DO NOT USE version 1.0.0** - contains critical bug that can delete entire projects.
All users must upgrade to 1.0.1+hotfix immediately.

## 1.0.0

- Initial release
- Features:
  - Detect and remove unused assets
  - Detect and remove unused functions
  - Detect and remove unused packages
  - Detect and remove unused files
  - Colored logging with detailed reports
  - Interactive cleanup mode
  - Support for exclude patterns and include paths
