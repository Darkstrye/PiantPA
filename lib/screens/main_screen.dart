import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/order.dart';
import '../models/hour_registration_order.dart';
import '../repositories/repository_interface.dart';
import '../repositories/excel_repository.dart';
import '../services/auth_service.dart';
import '../services/timer_service.dart';
import '../widgets/order_list_item.dart';
import '../widgets/order_detail_panel.dart';
import 'completed_orders_screen.dart';
import '../utils/reset_completed_orders.dart';

class MainScreen extends StatefulWidget {
  final AuthService authService;

  const MainScreen({
    super.key,
    required this.authService,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final RepositoryInterface _repository;
  late final TimerService _timerService;
  static const bool _verboseLogs = false;
  void _log(String message) {
    // ignore: avoid_print
    if (_verboseLogs) print(message);
  }
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Order> _orders = [];
  Order? _selectedOrder;
  bool _isLoading = true;
  Duration? _elapsedTime;
  Duration? _downtime;
  List<HourRegistrationOrder> _activeOrderLinks = [];
  final Set<String> _selectedOrdersForSession = {};
  StreamSubscription<Duration>? _timerSubscription;
  StreamSubscription<Duration>? _downtimeSubscription;

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<RepositoryInterface>(context, listen: false);
    _timerService = TimerService(_repository);
    _searchController.addListener(() {
      final next = _searchController.text.trim();
      if (next != _searchQuery) {
        setState(() {
          _searchQuery = next;
        });
      }
    });
    _loadData();
    _loadActiveTimer();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final orders = await _repository.getAllOrders();
      // Filter to show only in-progress orders
      final filteredOrders = orders
          .where((order) => order.status == OrderStatus.inProgress)
          .toList();
      
      // Remove duplicates by orderNumber - keep the most recent one
      final uniqueOrders = <String, Order>{};
      for (var order in filteredOrders) {
        if (!uniqueOrders.containsKey(order.orderNumber) ||
            uniqueOrders[order.orderNumber]!.modifiedOn.isBefore(order.modifiedOn)) {
          uniqueOrders[order.orderNumber] = order;
        }
      }
      
      final finalOrders = uniqueOrders.values.toList();
      finalOrders.sort((a, b) => b.createdOn.compareTo(a.createdOn));

      setState(() {
        _orders = finalOrders;
        if (_selectedOrder != null) {
          // Update selected order if it still exists
          final updated = _orders.firstWhere(
            (o) => o.orderId == _selectedOrder!.orderId,
            orElse: () => _selectedOrder!,
          );
          _selectedOrder = updated;
        }
        _selectedOrdersForSession.retainWhere(
          (id) => finalOrders.any((order) => order.orderId == id),
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading orders: $e')),
        );
      }
    }
  }

  Future<void> _loadActiveTimer() async {
    final userId = widget.authService.getCurrentUserId();
    if (userId != null) {
      await _timerService.loadActiveTimer(userId);

      setState(() {
        _activeOrderLinks = List.of(_timerService.activeOrderLinks);
      });

      _subscribeToTimerStreams();

      // Check if timer is running for current selected order
      final activeReg = _timerService.activeRegistration;
      final activeOrderIds = _timerService.activeOrderIds;
      if (activeReg != null &&
          _selectedOrder != null &&
          activeOrderIds.contains(_selectedOrder!.orderId)) {
        // Already subscribed above; no-op here
      }
    }
  }

  void _handleElapsedUpdate(Duration duration) {
    setState(() {
      final previous = _elapsedTime;
      final isPaused = _timerService.isTimerPaused;
      if (!isPaused && previous != null && duration < previous) {
        _log('[MainScreen] elapsedTimeStream -> ignored regressive update ${duration.inSeconds}s (previous ${previous.inSeconds}s)');
        return;
      }
      _elapsedTime = duration;
      _activeOrderLinks = List.of(_timerService.activeOrderLinks);
    });
  }

  void _handleDowntimeUpdate(Duration duration) {
    setState(() {
      final previous = _downtime;
      final isPaused = _timerService.isTimerPaused;
      if (!isPaused && previous != null && duration < previous) {
        _log('[MainScreen] downtimeStream -> ignored regressive update ${duration.inSeconds}s (previous ${previous.inSeconds}s)');
        return;
      }
      _downtime = duration;
      _activeOrderLinks = List.of(_timerService.activeOrderLinks);
    });
  }

  void _subscribeToTimerStreams() {
    _timerSubscription?.cancel();
    _timerSubscription = _timerService.elapsedTimeStream.listen((duration) {
      if (mounted) {
        _log('[MainScreen] elapsedTimeStream -> received ${duration.inSeconds}s');
        _handleElapsedUpdate(duration);
      }
    });

    _downtimeSubscription?.cancel();
    _downtimeSubscription = _timerService.downtimeStream.listen((duration) {
      if (mounted) {
        _log('[MainScreen] downtimeStream -> received ${duration.inSeconds}s');
        _handleDowntimeUpdate(duration);
      }
    });

    final downtimeSnapshot = _timerService.currentDowntime;
    if (mounted && downtimeSnapshot != null) {
      _handleDowntimeUpdate(downtimeSnapshot);
    }
  }

  Future<void> _startTimer() async {
    final userId = widget.authService.getCurrentUserId();
    if (userId == null) return;

    final activeReg = _timerService.activeRegistration;
    if (activeReg != null &&
        activeReg.isActive &&
        _timerService.isTimerPaused) {
      final resumed = await _timerService.resumeTimer();
      if (resumed) {
        _subscribeToTimerStreams();
        setState(() {
          _log('[MainScreen] resumeTimer -> keeping existing timers');
          _activeOrderLinks = List.of(_timerService.activeOrderLinks);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Timer resumed')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kon de timer niet hervatten. Probeer opnieuw.'),
          ),
        );
      }
      return;
    }

    Set<String> selectedOrderIds;
    if (_selectedOrdersForSession.isNotEmpty) {
      selectedOrderIds = _selectedOrdersForSession.toSet();
    } else if (_selectedOrder != null) {
      selectedOrderIds = {_selectedOrder!.orderId};
    } else {
      selectedOrderIds = {};
    }

    if (selectedOrderIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select at least één order om de timer te starten.'),
          ),
        );
      }
      return;
    }

    final success = await _timerService.startTimerForOrders(
      selectedOrderIds.toList(),
      userId,
    );

    if (success) {
      _subscribeToTimerStreams();

      for (final order in _orders) {
        if (selectedOrderIds.contains(order.orderId)) {
          final updatedOrder = order.copyWith(status: OrderStatus.inProgress);
          await _repository.updateOrder(updatedOrder);
        }
      }

      setState(() {
        if (_selectedOrder != null &&
            selectedOrderIds.contains(_selectedOrder!.orderId)) {
          _selectedOrder = _selectedOrder!.copyWith(
            status: OrderStatus.inProgress,
          );
        }
        _selectedOrdersForSession.clear();
        _activeOrderLinks = List.of(_timerService.activeOrderLinks);
      });

      if (_repository is ExcelRepository) {
        (_repository as ExcelRepository).clearCache();
      }
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timer gestart voor geselecteerde orders.')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timer kon niet worden gestart. Controleer of er al een sessie actief is.'),
          ),
        );
      }
    }
  }

  Future<void> _pauseTimer() async {
    final success = await _timerService.pauseTimer();
    
    if (success) {
      // Update elapsed time from paused state
      final activeReg = _timerService.activeRegistration;
      if (activeReg != null && activeReg.pausedElapsedTime != null) {
        final duration = Duration(seconds: (activeReg.pausedElapsedTime! * 3600).toInt());
        setState(() {
          _elapsedTime = duration;
          _downtime = Duration(seconds: ((activeReg.downtimeElapsedTime ?? 0.0) * 3600).toInt());
          _activeOrderLinks = List.of(_timerService.activeOrderLinks);
        });
      }
      
      _timerSubscription?.cancel();
      _timerSubscription = null;
      
      await _loadData();
      
      // Reload elapsed time for the selected order
      if (_selectedOrder != null) {
        await _loadDurationsForOrder(_selectedOrder!.orderId);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timer paused')),
        );
      }
    }
  }

  Future<void> _finishOrder() async {
    if (_selectedOrder == null) return;

    // Check if there's an active timer for this order
    final activeReg = _timerService.activeRegistration;
    final activeOrderIds = _timerService.activeOrderIds;
    if (activeReg == null ||
        !activeOrderIds.contains(_selectedOrder!.orderId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active timer found for this order.')),
        );
      }
      return;
    }

    final currentActiveOrderIds = Set<String>.from(activeOrderIds);
    final success = await _timerService.finishTimer();
    
    if (success) {
      _timerSubscription?.cancel();
      _timerSubscription = null;
      _downtimeSubscription?.cancel();
      _downtimeSubscription = null;
      setState(() {
        _activeOrderLinks = [];
      });
      try {
        for (final order in _orders) {
          if (currentActiveOrderIds.contains(order.orderId)) {
            final updatedOrder = order.copyWith(status: OrderStatus.completed);
            await _repository.updateOrder(updatedOrder);
            if (_selectedOrder != null &&
                _selectedOrder!.orderId == updatedOrder.orderId) {
              setState(() {
                _selectedOrder = updatedOrder;
              });
            }
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not save order status. Close Excel files in data/ and retry. Details: $e'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        return;
      }
      
      await _loadData();
      
      // Reload elapsed time for the selected order
      if (_selectedOrder != null) {
        await _loadDurationsForOrder(_selectedOrder!.orderId);
      }
      // Verify persisted status by reloading from disk
      if (_repository is ExcelRepository) {
        (_repository as ExcelRepository).clearCache();
      }
      bool allCompleted = true;
      for (final id in currentActiveOrderIds) {
        final refreshed = await _repository.getOrderById(id);
        if (refreshed?.status != OrderStatus.completed) {
          allCompleted = false;
          break;
        }
      }
      if (mounted) {
        if (!allCompleted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Saved locally, but files seem locked. Close Excel files in data/ and retry.'),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Order(s) completed'),
              action: SnackBarAction(
                label: 'View Completed',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => CompletedOrdersScreen(
                        authService: widget.authService,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to finish order. Please try again.')),
        );
      }
    }
  }

  Future<void> _finishSingleOrder(String orderId) async {
    final success = await _timerService.finishOrder(orderId);

    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kon deze order niet afronden. Probeer opnieuw.'),
          ),
        );
      }
      return;
    }

    Order? orderToUpdate;
    try {
      orderToUpdate = _orders.firstWhere((order) => order.orderId == orderId);
    } catch (_) {
      orderToUpdate = null;
    }

    if (orderToUpdate != null) {
      try {
        final updatedOrder = orderToUpdate.copyWith(
          status: OrderStatus.completed,
        );
        await _repository.updateOrder(updatedOrder);
        if (_selectedOrder != null && _selectedOrder!.orderId == orderId) {
          setState(() {
            _selectedOrder = updatedOrder;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not save order status. Close Excel files in data/ and retry. Details: $e'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        return;
      }
    }

    setState(() {
      _activeOrderLinks = List.of(_timerService.activeOrderLinks);
    });

    await _loadData();

    if (_timerService.activeRegistration == null) {
      _timerSubscription?.cancel();
      _timerSubscription = null;
      _downtimeSubscription?.cancel();
      _downtimeSubscription = null;
    }

    // Verify persisted status by reloading from disk
    if (_repository is ExcelRepository) {
      (_repository as ExcelRepository).clearCache();
    }
    final refreshed = await _repository.getOrderById(orderId);
    final completed = refreshed?.status == OrderStatus.completed;

    if (mounted) {
      if (!completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Saved locally, but files seem locked. Close Excel files in data/ and retry.'),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Order afgerond.'),
            action: SnackBarAction(
              label: 'View Completed',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CompletedOrdersScreen(
                      authService: widget.authService,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }
    }
  }

  void _selectOrder(Order order) async {
    setState(() {
      _selectedOrder = order;
    });

    // Check if there's an active timer for this order
    final activeReg = _timerService.activeRegistration;
    final activeOrderIds = _timerService.activeOrderIds;
    if (activeReg != null &&
        activeReg.isActive &&
        activeOrderIds.contains(order.orderId)) {
      // Active timer for this order - subscribe to live updates
      _subscribeToTimerStreams();
      setState(() {
        _activeOrderLinks = List.of(_timerService.activeOrderLinks);
      });
    } else {
      // No active timer for this order - load total elapsed time from all registrations
      await _loadDurationsForOrder(order.orderId);
      _timerSubscription?.cancel();
      _timerSubscription = null;
      _downtimeSubscription?.cancel();
      _downtimeSubscription = null;
    }
  }

  Future<void> _loadDurationsForOrder(String orderId) async {
    final activeReg = _timerService.activeRegistration;
    final activeOrderIds = _timerService.activeOrderIds;
    if (activeReg != null &&
        activeReg.isActive &&
        activeOrderIds.contains(orderId)) {
      _log('[MainScreen] _loadDurationsForOrder -> skipped for active order $orderId');
      return;
    }
    try {
      final totalElapsed = await _timerService.getTotalElapsedTimeForOrder(orderId);
      final totalDowntime = await _timerService.getTotalDowntimeForOrder(orderId);
      if (mounted) {
        setState(() {
          _elapsedTime = totalElapsed;
          _downtime = totalDowntime;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _elapsedTime = null;
          _downtime = null;
        });
      }
    }
  }

  void _handleLogout() {
    _timerService.dispose();
    _timerSubscription?.cancel();
    _downtimeSubscription?.cancel();
    widget.authService.logout();
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  void dispose() {
    _timerSubscription?.cancel();
    _downtimeSubscription?.cancel();
    _timerService.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeReg = _timerService.activeRegistration;
    final activeOrderIds = _timerService.activeOrderIds;
    final isTimerRunning = _timerService.isTimerRunning;
    final isTimerPaused = _timerService.isTimerPaused;
    final hasActiveTimer = activeReg != null && activeReg.isActive;
    final isTimerForSelectedOrder = _selectedOrder != null &&
        activeOrderIds.contains(_selectedOrder!.orderId);
    final selectionLocked = false;
    final ordersById = {
      for (final order in _orders) order.orderId: order,
    };

    // Filter visible orders by search
    final lower = _searchQuery.toLowerCase();
    final visibleOrders = lower.isEmpty
        ? _orders
        : _orders.where((o) {
            final on = o.orderNumber.toLowerCase();
            final m = o.machine.toLowerCase();
            return on.contains(lower) || m.contains(lower);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Processing'),
        actions: [
          // Completed Orders Button - More prominent with badge style
          Container(
            margin: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CompletedOrdersScreen(
                      authService: widget.authService,
                    ),
                  ),
                ).then((result) {
                  // Refresh data when returning from completed orders
                  // result will be true if orders were reset
                  _log('[MainScreen] Returning from completed orders screen, result: $result');
                  if (result == true || result == null) {
                    // Always refresh when returning, especially if reset happened
                    _log('[MainScreen] Refreshing data after returning from completed orders');
                    if (_repository is ExcelRepository) {
                      (_repository as ExcelRepository).clearCache();
                    }
                    _loadData();
                    // Also reload durations for selected order if it exists
                    if (_selectedOrder != null) {
                      _loadDurationsForOrder(_selectedOrder!.orderId);
                    }
                  }
                });
              },
              icon: const Icon(Icons.assignment_turned_in, size: 20),
              label: const Text('Completed'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          // User name with icon
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                const Icon(Icons.person, size: 20),
                const SizedBox(width: 4),
                Text(
                  widget.authService.getCurrentUserDisplayName() ?? 'User',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
          // Logout button
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: _handleLogout,
            tooltip: 'Logout',
            color: Colors.red.shade700,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Left Panel - Order List
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.list_alt, color: Colors.blue.shade700, size: 28),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Active Orders (${visibleOrders.length})',
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      // Small reset button
                                      Tooltip(
                                        message: 'Reset All Completed Orders',
                                        child: IconButton(
                                          icon: const Icon(Icons.restart_alt, size: 18),
                                          onPressed: () async {
                                            final confirmed = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('Reset Completed Orders'),
                                                content: const Text(
                                                  'This will reset all completed orders to In Progress and delete all their time registrations. This action cannot be undone.\n\nAre you sure?',
                                                ),
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
                                                    child: const Text('Reset All'),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirmed == true) {
                                              try {
                                                await ResetCompletedOrders.resetAll(repository: _repository);
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('All completed orders have been reset'),
                                                      backgroundColor: Colors.green,
                                                    ),
                                                  );
                                                  if (_repository is ExcelRepository) {
                                                    (_repository as ExcelRepository).clearCache();
                                                  }
                                                  _loadData(); // Refresh the list
                                                }
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('Error resetting orders: $e'),
                                                      backgroundColor: Colors.red,
                                                    ),
                                                  );
                                                }
                                              }
                                            }
                                          },
                                          tooltip: 'Reset Completed Orders',
                                          color: Colors.orange.shade700,
                                          padding: const EdgeInsets.all(8),
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                        ),
                                      ),
                                      // Refresh button
                                      Tooltip(
                                        message: 'Refresh Orders',
                                        child: IconButton(
                                          icon: const Icon(Icons.refresh),
                                          onPressed: () {
                                            if (_repository is ExcelRepository) {
                                              (_repository as ExcelRepository).clearCache();
                                            }
                                            _loadData();
                                          },
                                          tooltip: 'Refresh',
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search),
                                  hintText: 'Search by order or machine',
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: visibleOrders.isEmpty
                              ? const Center(
                                  child: Text('No orders available'),
                                )
                              : ListView.builder(
                                  itemCount: visibleOrders.length,
                                  itemBuilder: (context, index) {
                                    final order = visibleOrders[index];
                                    return OrderListItem(
                                      order: order,
                                      isSelected: _selectedOrder?.orderId == order.orderId,
                                      isSessionSelected: _selectedOrdersForSession.contains(order.orderId),
                                      enableSessionSelection: !selectionLocked,
                                      onSessionSelectionChanged: selectionLocked
                                          ? null
                                          : (value) {
                                              setState(() {
                                                if (value ?? false) {
                                                  _selectedOrdersForSession.add(order.orderId);
                                                } else {
                                                  _selectedOrdersForSession.remove(order.orderId);
                                                }
                                              });
                                            },
                                      onTap: () => _selectOrder(order),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Right Panel - Order Details
                Expanded(
                  flex: 3,
                  child: OrderDetailPanel(
                    order: _selectedOrder,
                    isTimerRunning: isTimerRunning,
                    isTimerPaused: isTimerPaused,
                    hasActiveTimer: hasActiveTimer,
                    isTimerForSelectedOrder: isTimerForSelectedOrder,
                    elapsedTime: _elapsedTime,
                    downtime: _downtime,
                    ordersById: ordersById,
                    activeOrderLinks: _activeOrderLinks,
                    pendingOrderIds: _selectedOrdersForSession,
                    selectionLocked: selectionLocked,
                    isSelectedForSession: _selectedOrder != null &&
                        _selectedOrdersForSession.contains(_selectedOrder!.orderId),
                    onToggleSessionSelection: (include) {
                      if (_selectedOrder == null || selectionLocked) {
                        return;
                      }
                      setState(() {
                        if (include) {
                          _selectedOrdersForSession.add(_selectedOrder!.orderId);
                        } else {
                          _selectedOrdersForSession.remove(_selectedOrder!.orderId);
                        }
                      });
                    },
                    onStartTimer: _startTimer,
                    onPauseTimer: _pauseTimer,
                    onFinishOrder: _finishOrder,
                    onFinishIndividualOrder: _finishSingleOrder,
                  ),
                ),
              ],
            ),
    );
  }
}

