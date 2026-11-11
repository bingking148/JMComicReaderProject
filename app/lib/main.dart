import 'package:flutter/material.dart';

import 'session.dart';
import 'theme.dart';
import 'ui/gate.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session();
  runApp(JmReaderApp(session: session));
  await session.boot();
}

class JmReaderApp extends StatelessWidget {
  const JmReaderApp({required this.session, super.key});
  final Session session;

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: session,
      child: MaterialApp(
        title: 'JMComicReader',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            if (session.booting) return const BootScreen();
            if (session.bootError != null) return BootError(message: session.bootError!);
            if (!session.settings.ageAccepted) return const AgeGate();
            return const Shell();
          },
        ),
      ),
    );
  }
}
