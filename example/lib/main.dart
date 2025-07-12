import 'package:flutter/material.dart';
import 'package:unused_code_cleaner/unused_code_cleaner.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unused Code Cleaner Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/used.png'),
            ElevatedButton(
              onPressed: () async {
                final cleaner = UnusedCodeCleaner();
                final options = CleanupOptions(
                  removeUnusedAssets: true,
                  removeUnusedFiles: true,
                  verbose: true,
                  interactive: false,
                  excludePatterns: ['**/*.g.dart'],
                );
                final result = await cleaner.analyze('.', options);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Found ${result.totalUnusedItems} unused items'),
                    ),
                  );
                }
              },
              child: const Text('Run Cleaner'),
            ),
          ],
        ),
      ),
    );
  }
}

void usedFunction() {
  print('This function is used');
}

void unusedFunction() {
  print('This function is not used');
}