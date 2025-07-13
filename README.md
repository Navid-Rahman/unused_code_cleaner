# Unused Code Cleaner

[![Pub Version](https://img.shields.io/pub/v/unused_code_cleaner)](https://pub.dev/packages/unused_code_cleaner)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/yourusername/unused_code_cleaner/pulls)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **🚨 CRITICAL SAFETY UPDATE - v1.0.1+hotfix.1**  
> **MAJOR BUG FIXED - ALL USERS MUST UPDATE**  
> Previous versions had a critical bug that deleted ALL assets instead of only unused ones.  
> **This version includes comprehensive safety fixes and requires explicit confirmation.**

A powerful and **SAFE** Dart CLI tool to identify and remove unused assets, functions, packages, and files from your Flutter and Dart projects, with comprehensive safety features and beautiful colored logging.

## 🛡️ SAFETY FIRST

**ALWAYS FOLLOW THESE SAFETY STEPS:**

1. **Commit your code to version control first**
2. **Always run with `--dry-run` first**
3. **Review the list carefully before proceeding**
4. **Keep automatic backups enabled (default)**

```bash
# SAFE WORKFLOW - Always start here:
dart run unused_code_cleaner --dry-run --all --verbose

# Review output, then if safe:
dart run unused_code_cleaner --all --verbose
```

🚀 **Features**

- 🖼️ **Asset Analysis**: Safely detects unused images, fonts, JSON files, and other assets
- ⚡ **Function Analysis**: Identifies unused functions and methods using Dart's AST
- 📦 **Package Analysis**: Finds unused dependencies listed in `pubspec.yaml`
- 📄 **File Analysis**: Locates unused Dart files not imported anywhere
- 🛡️ **Safety Features**: Dry-run mode, automatic backups, and multiple confirmations
- 🎨 **Colored Logging**: Clear, emoji-enhanced, colored console output
- 🔧 **Interactive Mode**: Prompts for confirmation before removing items
- 📊 **Detailed Reports**: Comprehensive analysis reports with file sizes
- 🛠 **Customizable**: Supports exclude patterns and configuration files
- ✅ **Cross-Platform**: Works on all platforms with enhanced path handling

📦 **Installation**

For use as a command-line tool, activate it globally:

```bash
dart pub global activate unused_code_cleaner
```

Or add it to your `dev_dependencies` in `pubspec.yaml`:

```yaml
dev_dependencies:
  unused_code_cleaner: ^1.0.1
```

## 🛡️ Safety Features

**Core Safety Features:**

- 🛡️ **Dry-Run Mode**: Preview all changes before execution with `--dry-run`
- 📦 **Automatic Backups**: Creates timestamped backups before deletion (disable with `--no-backup`)
- 🔒 **Protected Assets**: Never deletes assets declared in `pubspec.yaml`
- ⚠️ **Mass Deletion Warning**: Alerts when >10 items marked for deletion
- 🔍 **Enhanced Detection**: Comprehensive asset reference detection (constants, package: URLs, variables)
- 📋 **Detailed Logging**: Shows exactly why each item is marked as unused
- ✋ **Multiple Confirmations**: Requires explicit confirmation for file deletion
- 🛠️ **Pattern Exclusions**: Supports glob patterns to protect critical files

**Critical Safety Protections:**

- ✅ **Self-Protection**: Cannot analyze the unused_code_cleaner package itself
- ✅ **System Directory Protection**: Prevents analysis of critical system directories
- ✅ **pubspec.yaml Assets**: Automatically protects all declared assets
- ✅ **Generated Files**: Excludes .g.dart, .freezed.dart, build/, .dart_tool/
- ✅ **Path Normalization**: Robust cross-platform path handling
- ✅ **Reference Detection**: Finds assets in constants, variables, package: URLs

**Always backup your project before running cleanup operations!**

## 🔧 Usage

### Safe Workflow (RECOMMENDED)

```bash
# 1. ALWAYS start with dry-run to preview changes
dart run unused_code_cleaner --dry-run --all --verbose

# 2. Review the output carefully - check for any assets you need

# 3. If the results look correct, run without dry-run
dart run unused_code_cleaner --all --verbose

# 4. Backups are automatically created in unused_code_cleaner_backup_* folder
```

### Command Line

Analyze your project for unused items:

```bash
dart run unused_code_cleaner
```

Remove all unused items (interactive mode):

```bash
dart run unused_code_cleaner --all
```

Remove specific types of unused items:

```bash
unused_code_cleaner --assets --packages
```

Enable verbose logging:

```bash
unused_code_cleaner --verbose
```

Exclude specific patterns:

```bash
unused_code_cleaner --exclude "**/*.g.dart" --exclude "**/*.freezed.dart"
```

Specify a custom project path:

```bash
unused_code_cleaner --path=/path/to/your/project
```

### Programmatic Usage

Use the package in your Dart code:

````dart
```dart
import 'package:unused_code_cleaner/unused_code_cleaner.dart';

void main() async {
  final cleaner = UnusedCodeCleaner();
  final options = CleanupOptions(
    removeUnusedAssets: true,
    removeUnusedPackages: true,
    verbose: true,
    interactive: true,
    excludePatterns: ['**/*.g.dart', '**/*.freezed.dart'],
  );

  try {
    final result = await cleaner.analyze('.', options);
    print('Found ${result.totalUnusedItems} unused items in ${result.analysisTime.inMilliseconds}ms');
  } catch (e) {
    print('Error: $e');
  }
}
````

## 🛠 Advanced Options

| Option          | Description                                                              |
| --------------- | ------------------------------------------------------------------------ |
| `--all`         | Enables removal of all unused items (assets, functions, packages, files) |
| `--assets`      | Removes unused assets                                                    |
| `--functions`   | Removes unused functions                                                 |
| `--packages`    | Removes unused packages from pubspec.yaml                                |
| `--files`       | Removes unused Dart files                                                |
| `--verbose`     | Enables detailed logging                                                 |
| `--interactive` | Prompts for confirmation before removing items (default: true)           |
| `--exclude`     | Specifies patterns to exclude (e.g., \*_/_.g.dart)                       |
| `--path`        | Specifies the project directory to analyze (default: current directory)  |

## 🛠 Configuration File

Create an `unused_code_cleaner.yaml` file in your project root for advanced configuration:

````yaml
```yaml
analysis:
  verbose: true
  interactive: true
  exclude_patterns:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/generated/**"
  include_paths:
    - lib/
    - test/

assets:
  enabled: true
  directories:
    - assets/
    - images/
    - fonts/
    - data/

functions:
  enabled: true
  preserve:
    - main
    - build
    - initState

packages:
  enabled: true
  preserve:
    - flutter
    - flutter_test

files:
  enabled: true
  preserve:
    - lib/main.dart
    - test/**
````

## 💡 Example Output

```
🔍 UNUSED CODE CLEANER - ANALYSIS STARTED
ℹ️ [12:34:56] Found 42 Dart files to analyze
✅ [12:34:56] Project structure validated

📦 ANALYZING ASSETS
ℹ️ [12:34:57] Found 3 unused assets

⚡ ANALYZING FUNCTIONS
ℹ️ [12:34:57] Found 2 unused functions

📦 ANALYZING PACKAGES
ℹ️ [12:34:57] Found 1 unused package

📄 ANALYZING FILES
ℹ️ [12:34:57] Found 1 unused file

📊 ANALYSIS RESULTS
ℹ️ [12:34:57] Analysis completed in 123ms
ℹ️ [12:34:57] Total files scanned: 42
ℹ️ [12:34:57] Total unused items found: 7

Unused Assets (3 items)
┌──────────────────────────────────────────────────┐
│ Name              │ Path                  │ Size │ Description         │
├──────────────────────────────────────────────────┤
│ 🖼️ unused.png     │ assets/unused.png     │ 1.2MB│ Unused asset file   │
│ 🖼️ old.json       │ assets/data/old.json  │ 0.5KB│ Unused asset file   │
│ 🖼️ unused.svg     │ assets/unused.svg     │ 0.8MB│ Unused asset file   │
└──────────────────────────────────────────────────┘

❓ Do you want to remove these assets? (y/N)
```

## 📊 Accuracy Testing

The package was tested against real-world Flutter projects to ensure reliability:

| Project       | Total Files | Total Assets | Known Unused | Language Files         |
| ------------- | ----------- | ------------ | ------------ | ---------------------- |
| 🛒 E-commerce | 1,500       | 245          | 32           | 3 (en, fr, es)         |
| 📱 Social App | 3,200       | 412          | 67           | 5 (en, es, pt, ru, zh) |
| 🏢 Enterprise | 10,000      | 1,123        | 189          | 8 (multi-region)       |

Tests confirmed accurate detection of unused assets, functions, packages, and files, with robust handling of edge cases like generated files and special functions.

## 🎯 Roadmap

### 🚀 Completed Features:

- ✅ Support for automatic function removal using AST manipulation
- ✅ Integration with CI/CD pipelines for automated cleanup
- ✅ Comprehensive documentation and examples
- ✅ Pure Dart CLI tool (no Flutter SDK dependency)
- ✅ Pattern-based exclusion system
- ✅ Interactive and non-interactive modes

### 📋 Upcoming Features:

- ❌ Support for additional file types (e.g., TypeScript, Kotlin)
- ❌ Generate detailed HTML/PDF reports
- ❌ VS Code extension for real-time analysis
- ❌ Integration with popular CI/CD platforms (GitHub Actions, GitLab CI)
- ❌ Batch processing for multiple projects

## 🤝 Contributing

We welcome contributions! Please submit issues, feature requests, or pull requests on GitHub. Follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes (`git commit -m "Add your feature"`)
4. Push to the branch (`git push origin feature/your-feature`)
5. Open a pull request

## 📬 Contact

📩 Need help? Reach out at [navidrahman92@gmail.com] or open an issue on GitHub.

## 📜 License

📄 This project is licensed under the MIT License.
