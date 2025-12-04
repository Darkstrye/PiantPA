import 'dart:async';

import 'package:flutter/material.dart';
import '../models/order.dart';
import '../models/hour_registration_order.dart';
import '../repositories/repository_interface.dart';
import '../repositories/excel_repository.dart';
import '../services/auth_service.dart';
import '../services/timer_service.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/timer_display.dart';
import 'completed_orders_screen.dart';
import 'order_selection_screen.dart';

class ActiveSessionScreen extends StatefulWidget {
  final AuthService authService;
  final TimerService timerService;
  final RepositoryInterface repository;

  const ActiveSessionScreen({
    super.key,
    required this.authService,
    required this.timerService,
    required this.repository,
  });

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  List<HourRegistrationOrder> _activeLinks = [];
  Map<String, Order> _ordersById = {};
  Duration? _sessionElapsed;
  Duration? _sessionDowntime;
  Duration _debugTimeOffset = Duration.zero; // Debug offset for testing
  bool _isLoading = true;
  bool _isProcessing = false;

  StreamSubscription<Duration>? _elapsedSubscription;
  StreamSubscription<Duration>? _downtimeSubscription;

  RepositoryInterface get _repository => widget.repository;
  TimerService get _timerService => widget.timerService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  Future<void> _initialize() async {
    // Only load from repository if TimerService doesn't have active data
    if (_timerService.activeRegistration == null) {
      final userId = widget.authService.getCurrentUserId();
      if (userId != null) {
        await _timerService.loadActiveTimer(userId);
      }
    }
    await _refreshActiveOrders();
    _primeSessionDurations();
    _subscribeToStreams();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _primeSessionDurations() {
    final active = _timerService.activeRegistration;
    if (active == null) return;
    final elapsedHours =
        active.pausedElapsedTime ?? active.elapsedTime ?? 0.0;
    final downtimeHours = active.downtimeElapsedTime ?? 0.0;
    _sessionElapsed =
        Duration(seconds: (elapsedHours * 3600).toInt());
    _sessionDowntime =
        Duration(seconds: (downtimeHours * 3600).toInt());
  }

  void _subscribeToStreams() {
    _elapsedSubscription = _timerService.elapsedTimeStream.listen((duration) {
      if (!mounted) return;
      setState(() {
        _sessionElapsed = duration + _debugTimeOffset; // Add debug offset
        _activeLinks = _timerService.activeOrderLinks
            .where((link) => link.isActive)
            .toList();
      });
    });

    _downtimeSubscription =
        _timerService.downtimeStream.listen((duration) {
      if (!mounted) return;
      setState(() {
        _sessionDowntime = duration;
      });
    });
  }

  Future<void> _refreshActiveOrders() async {
    final links = _timerService.activeOrderLinks
        .where((link) => link.isActive)
        .toList();
    final ids = links.map((link) => link.orderId).toList();

    // Only fetch the orders we need, not all orders
    final byId = await _repository.getOrdersByIds(ids);

    if (mounted) {
      setState(() {
        _activeLinks = links;
        _ordersById = byId;
      });
    }
  }

  bool get _hasActiveSession =>
      _timerService.activeRegistration != null &&
      _timerService.activeRegistration!.isActive;

  /// Calculate total VOCA from all active orders
  double _calculateTotalVoca() {
    double total = 0;
    for (final link in _activeLinks) {
      final order = _ordersById[link.orderId];
      if (order?.vocaInUur != null) {
        total += order!.vocaInUur!;
      }
    }
    return total;
  }

  /// Debug: Add 1 hour to elapsed time for testing progress bar
  void _handleAddHour() {
    setState(() {
      _debugTimeOffset += const Duration(hours: 1);
      if (_sessionElapsed != null) {
        _sessionElapsed = _sessionElapsed! + const Duration(hours: 1);
      }
    });
  }

  Future<void> _handlePauseResume() async {
    if (!_hasActiveSession) return;
    setState(() => _isProcessing = true);
    bool success;
    if (_timerService.isTimerPaused) {
      success = await _timerService.resumeTimer();
    } else {
      success = await _timerService.pauseTimer();
    }
    setState(() => _isProcessing = false);
    if (!success || !mounted) return;
    await _refreshActiveOrders();
  }

  Future<void> _handleFinishSession() async {
    if (!_hasActiveSession) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finish Session'),
        content: const Text(
            'Completing the session will mark all orders as completed. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Finish Session'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    final activeIds =
        _activeLinks.map((link) => link.orderId).toSet();
    final success = await _timerService.finishTimer();
    setState(() => _isProcessing = false);

    if (!success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Failed to finish session. Please try again.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    for (final id in activeIds) {
      final order = _ordersById[id];
      if (order == null) continue;
      try {
        final updated = order.copyWith(
          status: OrderStatus.completed,
          modifiedOn: DateTime.now(),
        );
        await _repository.updateOrder(updated);
      } catch (e) {
        // ignore: avoid_print
        print('[ActiveSessionScreen] Failed to mark order $id completed: $e');
      }
    }

    // Only clear orders cache since we updated order statuses
    if (_repository is ExcelRepository) {
      (_repository as ExcelRepository).clearOrdersCache();
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _handleFinishOrder(String orderId) async {
    setState(() => _isProcessing = true);
    final success = await _timerService.finishOrder(orderId);
    setState(() => _isProcessing = false);

    if (!success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to finish this order. Try again.'),
        ),
      );
      return;
    }

    final order = _ordersById[orderId];
    if (order != null) {
      try {
        final updated = order.copyWith(
          status: OrderStatus.completed,
          modifiedOn: DateTime.now(),
        );
        await _repository.updateOrder(updated);
      } catch (e) {
        // ignore: avoid_print
        print('[ActiveSessionScreen] Failed to persist order $orderId: $e');
      }
    }

    await _refreshActiveOrders();
    if (!mounted) return;
    if (_activeLinks.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleAddOrders() async {
    final disabled = _activeLinks.map((link) => link.orderId).toSet();
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrderSelectionScreen(
          authService: widget.authService,
          timerService: _timerService,
          repository: _repository,
          mode: OrderSelectionMode.add,
          disabledOrderIds: disabled,
        ),
      ),
    );

    if (result == true) {
      await _refreshActiveOrders();
    }
  }

  Future<void> _handleViewCompleted() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompletedOrdersScreen(
          authService: widget.authService,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _elapsedSubscription?.cancel();
    _downtimeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: const LoadingIndicator(message: 'Loading session...'),
      );
    }

    if (!_hasActiveSession) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Active Session'),
        ),
        body: const Center(
          child: Text('No active session at the moment.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Session'),
        actions: [
          IconButton(
            tooltip: 'Completed Orders',
            onPressed: _handleViewCompleted,
            icon: const Icon(Icons.assignment_turned_in),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcessing ? null : _handleAddOrders,
        icon: const Icon(Icons.playlist_add),
        label: const Text('Add Order'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SessionSummary(
                isPaused: _timerService.isTimerPaused,
                elapsed: _sessionElapsed,
                downtime: _sessionDowntime,
                totalVoca: _calculateTotalVoca(),
                onAddHour: _handleAddHour,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _activeLinks.isEmpty
                    ? const _EmptyOrdersHint()
                    : _OrderGrid(
                        links: _activeLinks,
                        ordersById: _ordersById,
                        timerService: _timerService,
                        onFinish: _handleFinishOrder,
                      ),
              ),
              const SizedBox(height: 12),
              _SessionControls(
                isPaused: _timerService.isTimerPaused,
                isProcessing: _isProcessing,
                onPauseResume: _handlePauseResume,
                onFinishSession: _handleFinishSession,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionSummary extends StatelessWidget {
  final bool isPaused;
  final Duration? elapsed;
  final Duration? downtime;
  final double totalVoca;
  final VoidCallback? onAddHour;

  const _SessionSummary({
    required this.isPaused,
    required this.elapsed,
    required this.downtime,
    required this.totalVoca,
    this.onAddHour,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPaused ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: isPaused ? Colors.orange : Colors.green,
                  size: 32,
                ),
                const SizedBox(width: 8),
                Text(
                  isPaused ? 'Session Paused' : 'Session Running',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (elapsed != null)
              TimerDisplay(
                duration: elapsed!,
                title: 'Elapsed Time',
              ),
            if (downtime != null && downtime! > Duration.zero)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: TimerDisplay(
                  duration: downtime!,
                  title: 'Downtime',
                  accentColor: Colors.orange.shade700,
                ),
              ),
            // Total VOCA progress bar
            if (totalVoca > 0 && elapsed != null) ...[
              const SizedBox(height: 16),
              _buildTotalProgressBar(context),
            ],
            // Debug button
            if (onAddHour != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onAddHour,
                  icon: const Icon(Icons.fast_forward),
                  label: const Text('+1 uur (TEST)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotalProgressBar(BuildContext context) {
    final totalVocaSeconds = totalVoca * 3600;
    final elapsedSeconds = elapsed!.inSeconds.toDouble();
    final rawProgress = elapsedSeconds / totalVocaSeconds;
    final progress = rawProgress.clamp(0.0, 1.0);
    final percentage = (rawProgress * 100).toInt();
    
    // Color based on progress
    final Color progressColor;
    if (rawProgress >= 1.0) {
      progressColor = Colors.green.shade600;
    } else if (rawProgress >= 0.75) {
      progressColor = Colors.blue.shade600;
    } else if (rawProgress >= 0.5) {
      progressColor = Colors.orange.shade600;
    } else {
      progressColor = Colors.grey.shade500;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Totale Voortgang',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            Text(
              '$percentage%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: progressColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 14,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Totaal VOCA: ${totalVoca.toStringAsFixed(2).replaceAll('.', ',')} uur',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

class _OrderGrid extends StatelessWidget {
  final List<HourRegistrationOrder> links;
  final Map<String, Order> ordersById;
  final TimerService timerService;
  final Future<void> Function(String orderId) onFinish;

  const _OrderGrid({
    required this.links,
    required this.ordersById,
    required this.timerService,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 1400
            ? 3
            : width > 900
                ? 2
                : 1;
        const spacing = 12.0;

        // Build cards as a list of widgets
        final cards = links.map((link) {
          final order = ordersById[link.orderId];
          final timing = timerService.getOrderTimingSnapshot(link);
          return _OrderSessionCard(
            ordernummer: order?.ordernummer,
            orderregel: order?.orderregel,
            orderNumber: order?.orderNumber ?? link.orderId,
            machine: order?.machine ?? 'Unknown machine',
            voca: order?.vocaInUur,
            omschrijving: order?.omschrijving,
            leverdatum: order?.leverdatum,
            statusNaam: order?.statusNaam,
            elapsed: timing.elapsed,
            downtime: timing.downtime,
            onFinish: () => onFinish(link.orderId),
          );
        }).toList();

        // For single column, use a simple ListView
        if (crossAxisCount == 1) {
          return ListView.separated(
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(height: spacing),
            itemBuilder: (_, index) => cards[index],
          );
        }

        // For multi-column, group cards into rows
        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += crossAxisCount) {
          final rowChildren = <Widget>[];
          for (var j = 0; j < crossAxisCount; j++) {
            final idx = i + j;
            if (idx < cards.length) {
              rowChildren.add(Expanded(child: cards[idx]));
            } else {
              rowChildren.add(const Expanded(child: SizedBox.shrink()));
            }
            if (j < crossAxisCount - 1) {
              rowChildren.add(const SizedBox(width: spacing));
            }
          }
          rows.add(IntrinsicHeight(child: Row(children: rowChildren)));
          if (i + crossAxisCount < cards.length) {
            rows.add(const SizedBox(height: spacing));
          }
        }

        return SingleChildScrollView(
          child: Column(children: rows),
        );
      },
    );
  }
}

class _OrderSessionCard extends StatelessWidget {
  final String? ordernummer;
  final String? orderregel;
  final String orderNumber;
  final String machine;
  final double? voca;
  final String? omschrijving;
  final DateTime? leverdatum;
  final String? statusNaam;
  final Duration elapsed;
  final Duration downtime;
  final VoidCallback onFinish;

  const _OrderSessionCard({
    this.ordernummer,
    this.orderregel,
    required this.orderNumber,
    required this.machine,
    required this.voca,
    this.omschrijving,
    this.leverdatum,
    this.statusNaam,
    required this.elapsed,
    required this.downtime,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate progress: elapsed time / VOCA time
    final double progress;
    final String progressText;
    final Color progressColor;
    
    if (voca != null && voca! > 0) {
      final vocaInSeconds = voca! * 3600; // Convert hours to seconds
      final elapsedSeconds = elapsed.inSeconds.toDouble();
      final rawProgress = elapsedSeconds / vocaInSeconds;
      progress = rawProgress.clamp(0.0, 1.0);
      final percentage = (rawProgress * 100).toInt();
      progressText = '$percentage%';
      
      // Color based on progress
      if (rawProgress >= 1.0) {
        progressColor = Colors.green.shade600; // Completed target
      } else if (rawProgress >= 0.75) {
        progressColor = Colors.blue.shade600; // Almost there
      } else if (rawProgress >= 0.5) {
        progressColor = Colors.orange.shade600; // Halfway
      } else {
        progressColor = Colors.grey.shade500; // Just started
      }
    } else {
      progress = 0.0;
      progressText = '-';
      progressColor = Colors.grey.shade400;
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ordernummer en Orderregel
            if (ordernummer != null || orderregel != null) ...[
              Text(
                'Ordernummer: ${ordernummer ?? "-"}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'Orderregel: ${orderregel ?? "-"}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey.shade700),
              ),
            ] else ...[
              Text(
                orderNumber,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
            
            // Omschrijving (max 25 karakters)
            if (omschrijving != null && omschrijving!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                omschrijving!.length > 25 
                    ? '${omschrijving!.substring(0, 25)}...' 
                    : omschrijving!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            
            const SizedBox(height: 8),
            
            // Compact info row: Machine | Status | Leverdatum
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (machine.isNotEmpty)
                  _InfoChip(
                    icon: Icons.precision_manufacturing,
                    label: machine,
                  ),
                if (statusNaam != null && statusNaam!.isNotEmpty)
                  _InfoChip(
                    icon: Icons.flag,
                    label: statusNaam!,
                    color: Colors.blue.shade700,
                  ),
                if (leverdatum != null)
                  _InfoChip(
                    icon: Icons.calendar_today,
                    label: '${leverdatum!.day.toString().padLeft(2, '0')}-${leverdatum!.month.toString().padLeft(2, '0')}-${leverdatum!.year}',
                    color: Colors.orange.shade700,
                  ),
              ],
            ),
            
            if (voca != null) ...[
              const SizedBox(height: 8),
              Text(
                'Voca: ${voca!.toStringAsFixed(2).replaceAll('.', ',')} uur',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 12),
            
            // Progress bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Voortgang',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      progressText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: progressColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            TimerDisplay(
              duration: elapsed,
              title: 'Elapsed',
            ),
            const SizedBox(height: 12),
            TimerDisplay(
              duration: downtime,
              title: 'Downtime',
              accentColor: Colors.orange.shade700,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onFinish,
                icon: const Icon(Icons.check_circle),
                label: const Text('Finish Order'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionControls extends StatelessWidget {
  final bool isPaused;
  final bool isProcessing;
  final VoidCallback onPauseResume;
  final VoidCallback onFinishSession;

  const _SessionControls({
    required this.isPaused,
    required this.isProcessing,
    required this.onPauseResume,
    required this.onFinishSession,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isProcessing ? null : onPauseResume,
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
            label: Text(isPaused ? 'Resume Session' : 'Pause Session'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor:
                  isPaused ? Colors.green.shade600 : Colors.orange.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isProcessing ? null : onFinishSession,
            icon: const Icon(Icons.stop_circle),
            label: const Text('Finish Session'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyOrdersHint extends StatelessWidget {
  const _EmptyOrdersHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'No active orders in this session.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Use the "Add Order" button to include orders.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chipColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: chipColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
