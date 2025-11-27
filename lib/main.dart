import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'repositories/repository_interface.dart';
import 'repositories/excel_repository.dart';
import 'services/timer_service.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        Provider<RepositoryInterface>(
          create: (_) => ExcelRepository(),
        ),
        ProxyProvider<RepositoryInterface, TimerService>(
          update: (_, repository, previous) =>
              previous ?? TimerService(repository),
          dispose: (_, timerService) => timerService.dispose(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Order Processing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}
