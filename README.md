# Unused Code Cleaner

[![Pub Version](https://img.shields.io/pub/v/unused_code_cleaner)](https://pub.dev/packages/unused_code_cleaner)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**🧹 Automatically find and remove unused code from your Flutter/Dart projects**

Clean up your codebase in seconds - remove unused assets, functions, packages, and files with one simple command.

## ⚡ Quick Start

```bash
# Install
dart pub global activate unused_code_cleaner

# Preview what will be cleaned (always start here!)
dart run unused_code_cleaner --dry-run --all

# Clean your project
dart run unused_code_cleaner --all
```

## ✨ What It Does

- 🖼️ **Removes unused assets** (images, fonts, JSON files)
- ⚡ **Deletes unused functions** and methods
- 📦 **Cleans unused packages** from pubspec.yaml
- 📄 **Removes unused Dart files**
- 🛡️ **Safe by default** - creates backups automatically

## 📱 Perfect For

- **Flutter apps** with too many assets
- **Code cleanup** after refactoring
- **Reducing app size** before release
- **Maintaining clean** codebases

## �️ Safety First

This tool is designed to be safe:

- ✅ Always creates backups before deletion
- ✅ Excludes critical files automatically
- ✅ `--dry-run` mode to preview changes
- ✅ Requires confirmation before deletion

**Golden Rule**: Always run `--dry-run` first!

## 🛡️ Safety Features

## 🚀 Common Commands

```bash
# Clean everything (recommended)
dart run unused_code_cleaner --dry-run --all

# Clean only assets
dart run unused_code_cleaner --assets --dry-run

# Clean only unused packages
dart run unused_code_cleaner --packages --dry-run

# Exclude certain files
dart run unused_code_cleaner --exclude "**/*.g.dart" --dry-run --all
```

## 📋 Example Output

```
🔍 Analyzing project...
✅ Found 3 unused assets (saving 2.1 MB)
✅ Found 5 unused functions
✅ Found 1 unused package

📊 Results:
├── 🖼️  unused_logo.png (1.2 MB)
├── 📄 old_config.json (0.9 MB)
├── ⚡ debugHelper() function
└── 📦 http package

💾 Total space savings: 2.1 MB
⏱️  Analysis completed in 1.2s

❓ Remove these items? (y/N)
```

## 🛠️ Options

| Command       | What it does                |
| ------------- | --------------------------- |
| `--all`       | Clean everything            |
| `--assets`    | Clean unused assets only    |
| `--functions` | Clean unused functions only |
| `--packages`  | Clean unused packages only  |
| `--dry-run`   | Preview without deleting    |
| `--verbose`   | Show detailed info          |

## 🤝 Contributing

Found a bug? Want a feature? [Open an issue](https://github.com/Navid-Rahman/unused_code_cleaner/issues)!

## 📜 License

MIT License - free to use in your projects.
