# Unused Code Cleaner

[![Pub Version](https://img.shields.io/pub/v/unused_code_cleaner)](https://pub.dev/packages/unused_code_cleaner)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/Navid-Rahman/unused_code_cleaner/pulls)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **🎯 LATEST UPDATE - v1.8.1**  
> **PUB POINTS OPTIMIZATION & LOGGING SYSTEM OVERHAUL**  
> Complete logging system redesign with clean, professional output. Enhanced pub.dev scoring with modernized dependencies and improved compatibility.  
> **Now features clean structured sections with professional visual hierarchy**

A powerful and **SAFE** Dart CLI tool to identify and remove unused assets, functions, packages, and files from your Flutter and Dart projects, with comprehensive safety features and beautiful colored logging.

## 🛡️ ENHANCED SAFETY FEATURES

**LATEST IN v1.8.1 - PROFESSIONAL LOGGING & MODERNIZATION:**

1. **Clean Output System**: Professional structured sections with clean visual hierarchy
2. **Enhanced Analysis**: Advanced semantic analysis using Dart analyzer's Element system
3. **Flutter-Aware Detection**: Smart recognition of Flutter lifecycle methods and widgets
4. **Cross-File Dependencies**: Proper resolution of imports, exports, and library boundaries
5. **Enhanced Asset Detection**: Variable value tracking and fuzzy path matching
6. **Semantic Function Analysis**: Element-based tracking with framework method protection
7. **Advanced Package Analysis**: Sophisticated import tracking with conditional import handling
8. **Comprehensive Safety**: Multiple validation layers and intelligent exclusion patterns
9. **Modernized Dependencies**: Updated to latest analyzer and improved pub.dev compatibility

**ALWAYS FOLLOW THESE SAFETY STEPS:**

1. **Commit your code to version control first**
2. **Always run with `--dry-run` first**
3. **Review the list carefully before proceeding**
4. **Keep automatic backups enabled (default)**

```bash
# SAFE WORKFLOW - Always start here:
dart run unused_code_cleaner --dry-run --all --verbose

# Review output carefully, then if safe:
dart run unused_code_cleaner --all --verbose
```

🚀 **Features**

- 🖼️ **Asset Analysis**: Safely detects unused images, fonts, JSON files, and other assets with semantic AST-based detection
- ⚡ **Function Analysis**: Identifies unused functions and methods using enhanced semantic analysis with Flutter awareness
- 📦 **Package Analysis**: Finds unused dependencies with sophisticated import tracking and element resolution
- 📄 **File Analysis**: Locates unused Dart files not imported anywhere
- � **Comprehensive Analysis Summary**: Complete overview of all 4 core functionalities with health assessment
- 🏥 **Project Health Scoring**: Dynamic health scoring (0-100%) with weighted issue severity assessment
- 💰 **Actionable Improvement Recommendations**: Clear space savings calculations and optimization suggestions
- ⏱️ **Performance Metrics**: Analysis time tracking with processing speed and throughput statistics
- �🛡️ **Safety Features**: Dry-run mode, automatic backups, and multiple confirmations
- 🎨 **Colored Logging**: Clear, emoji-enhanced, colored console output
- 🔧 **Interactive Mode**: Prompts for confirmation before removing items
- 📊 **Detailed Reports**: Comprehensive analysis reports with file sizes
- 🛠 **Customizable**: Supports exclude patterns and configuration files
- ✅ **Cross-Platform**: Works on all platforms with enhanced path handling
- 🔍 **AST-Based Analysis**: Advanced code analysis using Dart's Abstract Syntax Tree
- 🚀 **Enhanced Semantic Analysis**: Deep semantic analysis with element tracking (enabled by default)

📦 **Installation**

For use as a command-line tool, activate it globally:

```bash
dart pub global activate unused_code_cleaner
```

Or add it to your `dev_dependencies` in `pubspec.yaml`:

```yaml
dev_dependencies:
  unused_code_cleaner: ^1.8.1
```

## 🚀 Advanced Analysis Features

**Semantic Analysis** provides significantly more accurate detection by using Dart's semantic model:

```bash
# Advanced semantic analysis is enabled by default
dart run unused_code_cleaner --dry-run --all --verbose
```

**Advanced Features:**

- 🧠 **Element-Based Tracking**: Uses semantic elements instead of name matching
- 🔍 **Cross-File Analysis**: Tracks dependencies across compilation units
- 🎯 **Flutter-Aware**: Recognizes Flutter widget lifecycle methods and patterns
- 📝 **Variable Resolution**: Tracks variable assignments and usages semantically
- 🔗 **Import Chain Analysis**: Handles conditional imports and export chains
- ⚡ **Accurate Asset Detection**: Semantic analysis of Image.asset(), AssetImage(), etc.

**Trade-offs:**

- ✅ **More Accurate**: Significantly fewer false positives
- ✅ **Context-Aware**: Understands framework patterns and generated code
- ⚠️ **Slower**: Takes longer due to comprehensive semantic analysis
- 💡 **Recommended**: For final cleanup or when accuracy is critical

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

# 2. Advanced semantic analysis is enabled by default
dart run unused_code_cleaner --dry-run --all --verbose

# 3. Review the output carefully - check for any assets you need

# 4. If the results look correct, run without dry-run
dart run unused_code_cleaner --all --verbose

# 5. Backups are automatically created in unused_code_cleaner_backup_* folder
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

**Analysis Examples:**

```bash
# Advanced semantic analysis with dry-run
dart run unused_code_cleaner --functions --dry-run

# Asset analysis with variable tracking
dart run unused_code_cleaner --assets --verbose --dry-run

# Package analysis with dependency chain tracking
dart run unused_code_cleaner --packages --dry-run
```

Remove specific types of unused items:

```bash
dart run unused_code_cleaner --assets --packages
```

Enable verbose logging:

```bash
dart run unused_code_cleaner --verbose
```

Exclude specific patterns:

```bash
dart run unused_code_cleaner --exclude "**/*.g.dart" --exclude "**/*.freezed.dart"
```

Specify a custom project path:

```bash
dart run unused_code_cleaner --path=/path/to/your/project
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
| `--dry-run`     | Preview changes without executing them (RECOMMENDED)                     |
| `--no-backup`   | Skip creating backups before deletion                                    |

## Example Output

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
- ✅ Enhanced semantic analysis with element-based tracking
- ✅ Project health scoring and comprehensive result overview
- ✅ Professional logging system with clean output
- ✅ Multi-platform support and modern dependency management

### 📋 Upcoming Features:

- ❌ Configuration file support (`unused_code_cleaner.yaml`)
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
