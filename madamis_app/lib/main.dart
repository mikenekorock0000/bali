import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/app_state.dart';
import 'theme/app_theme.dart';

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
        theme: AppTheme.build(),
        home: const HomeScreen(),
      ),
    );
  }
}
