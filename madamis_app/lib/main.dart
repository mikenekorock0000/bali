import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MadamisApp());
}

class MadamisApp extends StatelessWidget {
  const MadamisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'マダミス GM',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.dark(
            primary: const Color(0xFFE94560),
            secondary: const Color(0xFF533483),
            surface: const Color(0xFF1A1A2E),
          ),
          scaffoldBackgroundColor: const Color(0xFF0F0F1A),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
