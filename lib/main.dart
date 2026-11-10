import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/expense_provider.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RoyShanyExpenseTrackerApp());
}

class RoyShanyExpenseTrackerApp extends StatelessWidget {
  const RoyShanyExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ExpenseProvider()..loadExpenses(),
      child: MaterialApp(
        title: 'Roy & Shany Expenses (₪)',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0F766E),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF1F5F9),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF0F172A),
            elevation: 0,
            scrolledUnderElevation: 1,
            centerTitle: false,
            titleTextStyle: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        home: const DashboardScreen(),
      ),
    );
  }
}
