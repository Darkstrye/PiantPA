import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../repositories/repository_interface.dart';
import '../services/auth_service.dart';
import '../services/timer_service.dart';
import '../widgets/loading_indicator.dart';
import 'order_selection_screen.dart';
import 'active_session_screen.dart';
import 'completed_orders_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthService authService;

  const HomeScreen({
    super.key,
    required this.authService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoadingSession = true;

  RepositoryInterface get _repository =>
      Provider.of<RepositoryInterface>(context, listen: false);
  TimerService get _timerService =>
      Provider.of<TimerService>(context, listen: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSession();
    });
  }

  Future<void> _initializeSession() async {
    final userId = widget.authService.getCurrentUserId();
    if (userId != null) {
      await _timerService.loadActiveTimer(userId);
    }
    if (mounted) {
      setState(() {
        _isLoadingSession = false;
      });
    }
  }

  Future<void> _refreshSessionState() async {
    // Just trigger a rebuild - the shared TimerService already has the latest state
    // Only reload from repository if there's no in-memory state
    if (_timerService.activeRegistration == null) {
      final userId = widget.authService.getCurrentUserId();
      if (userId != null) {
        await _timerService.loadActiveTimer(userId);
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  bool get _hasActiveSession {
    return _timerService.activeRegistration != null &&
        _timerService.activeRegistration!.isActive;
  }

  String get _userName =>
      widget.authService.getCurrentUserDisplayName() ?? 'User';

  Future<void> _handleStartSession() async {
    final userId = widget.authService.getCurrentUserId();
    if (userId == null) {
      _showError('No user session found. Please log in again.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OrderSelectionScreen(
          authService: widget.authService,
          timerService: _timerService,
          repository: _repository,
          mode: OrderSelectionMode.start,
        ),
      ),
    );

    await _refreshSessionState();
  }

  Future<void> _handleContinueSession() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ActiveSessionScreen(
          authService: widget.authService,
          timerService: _timerService,
          repository: _repository,
        ),
      ),
    );

    await _refreshSessionState();
  }

  Future<void> _handleViewCompletedOrders() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompletedOrdersScreen(
          authService: widget.authService,
        ),
      ),
    );
  }

  void _handleLogout() {
    widget.authService.logout();
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Piant - Session Manager'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout),
            color: Colors.red.shade600,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoadingSession
            ? const LoadingIndicator(message: 'Loading session...')
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _HeroButton(
                              label: 'Welcome, $_userName',
                              icon: Icons.person_pin_circle,
                              backgroundColor: Colors.blue.shade600,
                              foregroundColor: Colors.white,
                              onPressed: () {},
                            ),
                            const SizedBox(height: 24),
                            _HeroButton(
                              label: 'Start Session',
                              icon: Icons.play_circle_fill,
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              onPressed: _handleStartSession,
                            ),
                            const SizedBox(height: 16),
                            if (_hasActiveSession)
                              _HeroButton(
                                label: 'Continue Active Session',
                                icon: Icons.timelapse,
                                backgroundColor: Colors.deepPurple.shade600,
                                foregroundColor: Colors.white,
                                onPressed: _handleContinueSession,
                              ),
                            if (_hasActiveSession) const SizedBox(height: 16),
                            _HeroButton(
                              label: 'View Completed Orders',
                              icon: Icons.assignment_turned_in,
                              backgroundColor: Colors.orange.shade600,
                              foregroundColor: Colors.white,
                              onPressed: _handleViewCompletedOrders,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _hasActiveSession
                          ? 'An active session is currently running.'
                          : 'No active session. Start one to begin tracking orders.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _hasActiveSession
                            ? Colors.green.shade700
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onPressed;

  const _HeroButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 24),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 6,
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 32),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}


