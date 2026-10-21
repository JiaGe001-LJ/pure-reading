import 'package:flutter/material.dart';

class DonationScreen extends StatelessWidget {
  const DonationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('捐赠支持')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 8),
          Icon(Icons.favorite, color: scheme.primary, size: 44),
          const SizedBox(height: 12),
          Text(
            '如果“洁阅读”帮到了你，欢迎请作者喝杯咖啡',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '使用微信扫一扫即可捐赠，金额随意，感谢支持！',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Center(
            child: Card(
              elevation: 2,
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/donation_qr.png',
                width: 280,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '洁阅读 Pure Reading · v1.0.0',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
