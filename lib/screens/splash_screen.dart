import 'package:flutter/material.dart';
import '../services/session_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

// ============================================================
// SplashScreen — entry point aplikasi.
// Mengecek apakah ada session tersimpan (token) saat app dibuka.
// Ada  → langsung ke HomeScreen (auto-login, tidak perlu login ulang).
// Tidak ada / sudah logout → ke LoginScreen seperti biasa.
// ============================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final isLoggedIn = await SessionService.isLoggedIn();
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => isLoggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Splash sederhana — background gelap senada dengan LoginScreen
    // supaya transisi tidak "kedip" warna.
    return Scaffold(
      backgroundColor: const Color(0xFF081229),
      body: Center(
        child: Image.asset(
          'assets/icon/aibipi_pos.png',
          height: 110,
          errorBuilder: (_, __, ___) => const CircularProgressIndicator(
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}
