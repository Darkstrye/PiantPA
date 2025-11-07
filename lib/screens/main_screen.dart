import 'dart:async';
import 'package:flutter/material.dart';
import '../models/order.dart';
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
  final RepositoryInterface _repository = ExcelRepository();
  late final TimerService _timerService;
  
  List<Order> _orders = [];
  Order? _selectedOrder;
  bool _isLoading = true;
  Duration? _elapsedTime;
  StreamSubscription<Duration>? _timerSubscription;

  @override
  void initState() {
    super.initState();
    _timerService = TimerService(_repository);
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
      
      // Subscribe to timer updates
      _timerSubscription = _timerService.elapsedTimeStream.listen((duration) {
        if (mounted) {
          setState(() {
            _elapsedTime = duration;
          });
        }
      });

      // Check if timer is running for current selected order
      final activeReg = _timerService.activeRegistration;
      if (activeReg != null && _selectedOrder?.orderId == activeReg.orderId) {
        // Subscribe to timer updates instead of calculating directly
        // This ensures we get the correct value from the timer service
        _timerSubscription?.cancel();
        _timerSubscription = _timerService.elapsedTimeStream.listen((duration) {
          if (mounted) {
            setState(() {
              _elapsedTime = duration;
            });
          }
        });
      }
    }
  }

  Future<void> _startTimer() async {
    if (_selectedOrder == null) return;

    final userId = widget.authService.getCurrentUserId();
    if (userId == null) return;

    final success = await _timerService.startTimer(_selectedOrder!.orderId, userId);
    
    if (success) {
      // Subscribe to timer updates FIRST, before any other operations
      // This ensures we get the correct initial value from the timer service
      _timerSubscription?.cancel();
      _timerSubscription = _timerService.elapsedTimeStream.listen((duration) {
        if (mounted) {
          setState(() {
            _elapsedTime = duration;
          });
        }
      });

      // Update order status to In Progress
      final updatedOrder = _selectedOrder!.copyWith(
        status: OrderStatus.inProgress,
      );
      await _repository.updateOrder(updatedOrder);
      
      setState(() {
        _selectedOrder = updatedOrder;
      });
      
      await _loadData(); // Refresh list
      
      // Don't reload elapsed time here - the stream will provide the correct value
      // Loading from database could overwrite the correct stream value
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timer started')),
        );
      }
    } else {
      if (mounted) {
        // Check why it failed
        final allRegistrations = await _repository.getHourRegistrationsByOrderId(_selectedOrder!.orderId);
        final hasCompleted = allRegistrations.any((reg) => !reg.isActive && reg.elapsedTime != null && reg.elapsedTime! > 0);
        
        if (hasCompleted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This order has already been completed. You can only start an order once.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot start timer. You may already have an active timer.')),
          );
        }
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
        });
      }
      
      _timerSubscription?.cancel();
      _timerSubscription = null;
      
      await _loadData();
      
      // Reload elapsed time for the selected order
      if (_selectedOrder != null) {
        await _loadElapsedTimeForOrder(_selectedOrder!.orderId);
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
    if (activeReg == null || activeReg.orderId != _selectedOrder!.orderId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active timer found for this order.')),
        );
      }
      return;
    }

    final success = await _timerService.finishTimer();
    
    if (success) {
      _timerSubscription?.cancel();
      _timerSubscription = null;
      
      // Mark order as completed
      final updatedOrder = _selectedOrder!.copyWith(
        status: OrderStatus.completed,
      );
      await _repository.updateOrder(updatedOrder);
      
      setState(() {
        _selectedOrder = updatedOrder;
      });
      
      await _loadData();
      
      // Reload elapsed time for the selected order
      if (_selectedOrder != null) {
        await _loadElapsedTimeForOrder(_selectedOrder!.orderId);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order completed')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to finish order. Please try again.')),
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
    if (activeReg != null && activeReg.isActive && activeReg.orderId == order.orderId) {
      // Active timer for this order - subscribe to live updates
      _timerSubscription?.cancel();
      _timerSubscription = _timerService.elapsedTimeStream.listen((duration) {
        if (mounted) {
          setState(() {
            _elapsedTime = duration;
          });
        }
      });
    } else {
      // No active timer for this order - load total elapsed time from all registrations
      await _loadElapsedTimeForOrder(order.orderId);
      _timerSubscription?.cancel();
      _timerSubscription = null;
    }
  }

  Future<void> _loadElapsedTimeForOrder(String orderId) async {
    try {
      final totalElapsed = await _timerService.getTotalElapsedTimeForOrder(orderId);
      if (mounted) {
        setState(() {
          _elapsedTime = totalElapsed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _elapsedTime = null;
        });
      }
    }
  }

  void _handleLogout() {
    _timerService.dispose();
    _timerSubscription?.cancel();
    widget.authService.logout();
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  void dispose() {
    _timerSubscription?.cancel();
    _timerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeReg = _timerService.activeRegistration;
    final isTimerRunning = _timerService.isTimerRunning;
    final isTimerPaused = _timerService.isTimerPaused;
    final hasActiveTimer = activeReg != null && activeReg.isActive;
    final isTimerForSelectedOrder = activeReg != null && 
        _selectedOrder != null &&
        activeReg.orderId == _selectedOrder!.orderId;

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
                ).then((_) {
                  // Refresh data when returning from completed orders
                  _loadData();
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.list_alt, color: Colors.blue.shade700, size: 28),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Active Orders (${_orders.length})',
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
                                            await ResetCompletedOrders.resetAll();
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('All completed orders have been reset'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
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
                                      onPressed: _loadData,
                                      tooltip: 'Refresh',
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _orders.isEmpty
                              ? const Center(
                                  child: Text('No orders available'),
                                )
                              : ListView.builder(
                                  itemCount: _orders.length,
                                  itemBuilder: (context, index) {
                                    final order = _orders[index];
                                    return OrderListItem(
                                      order: order,
                                      isSelected: _selectedOrder?.orderId == order.orderId,
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
                    onStartTimer: _startTimer,
                    onPauseTimer: _pauseTimer,
                    onFinishOrder: _finishOrder,
                  ),
                ),
              ],
            ),
    );
  }
}

