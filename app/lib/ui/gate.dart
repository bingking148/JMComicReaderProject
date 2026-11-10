import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session.dart';
import '../theme.dart';
import 'widgets.dart';

class BootScreen extends StatelessWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wordmark(),
            SizedBox(height: 18),
            SizedBox(width: 120, child: ProgressRule(value: 0)),
          ],
        ),
      ),
    );
  }
}

class BootError extends StatelessWidget {
  const BootError({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QuietMessage(title: '引擎没有起来', detail: message),
    );
  }
}

class AgeGate extends StatelessWidget {
  const AgeGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Wordmark(),
                const SizedBox(height: 28),
                const Text('阅读之前', style: TextStyle(fontSize: 28)),
                const SizedBox(height: 12),
                const Text(
                  '这里会直接连接漫画站点，并把下载的页面保存在这台设备上。内容面向成年人。请确认你已年满 18 岁，并只把本程序用于个人学习。',
                  style: TextStyle(color: InkColors.dim, height: 1.55),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () => SessionScope.of(context).acceptAge(),
                  child: const Text('我已年满十八岁'),
                ),
                TextButton(onPressed: SystemNavigator.pop, child: const Text('退出')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
