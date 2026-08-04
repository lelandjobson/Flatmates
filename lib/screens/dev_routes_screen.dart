import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';

class DevRoutesScreen extends StatelessWidget {
  const DevRoutesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final routes = router.configuration.routes
        .whereType<GoRoute>()
        .where((r) => r.name != 'dev_routes')
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Dev Routes'),
        backgroundColor: Colors.grey[900],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: routes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final route = routes[index];
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[850],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => context.goNamed(route.name!),
              child: Text(
                '${route.name}  →  ${route.path}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          );
        },
      ),
    );
  }
}
