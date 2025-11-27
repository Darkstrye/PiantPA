import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../repositories/repository_interface.dart';
import '../utils/test_data_initializer.dart';
import '../services/excel_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  
  late final AuthService _authService;

  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    // Repository is provided at app root
    // Delay to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final repository = Provider.of<RepositoryInterface>(context, listen: false);
      _authService = AuthService(repository);
      _initialize(repository);
    });
  }

  Future<void> _initialize(RepositoryInterface repository) async {
    try {
      await TestDataInitializer.initializeTestData(repository);
      await _checkDataFolderWritable();
    } catch (e) {
      // Silently handle errors - data might already exist
      print('Test data initialization: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _checkDataFolderWritable() async {
    try {
      final dir = await ExcelService.getDocumentsDirectory();
      final testPath = '$dir/.write_test.tmp';
      await ExcelService.writeStringAtomic(testPath, 'ok', retries: 1);
      final f = File(testPath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Data folder not writable (files may be open). Close Excel files in data/ and retry. Details: $e',
          ),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await _authService.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    setState(() {
      _isLoading = false;
    });

    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(authService: _authService),
        ),
      );
    } else {
      setState(() {
        _errorMessage = 'Invalid username or password';
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Initializing...',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 80,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Order Processing',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please sign in to continue',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.grey,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your username';
                          }
                          return null;
                        },
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock),
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleLogin(),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.red.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Login',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // PIANT Logo in center top
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: _buildPiantLogo(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPiantLogo() {
    // Try to load image, fallback to text logo if image not found
    return Builder(
      builder: (context) {
        try {
          return Image.asset(
            'assets/images/piant_logo.png',
            height: 120,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return _buildTextLogo();
            },
          );
        } catch (e) {
          return _buildTextLogo();
        }
      },
    );
  }

  Widget _buildTextLogo() {
    // Text-based logo as fallback
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        'PIANT',
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.bold,
          letterSpacing: 2.0,
          color: Colors.black87,
        ),
      ),
    );
  }
}

