import 'dart:async';
import 'package:flutter/material.dart';
import '../models/order.dart';
import '../repositories/repository_interface.dart';
import '../repositories/excel_repository.dart';
import '../services/auth_service.dart';
import '../services/timer_service.dart';
import '../widgets/order_list_item.dart';
import '../widgets/order_detail_panel.dart';

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
      // Filter out completed orders and sort by CreatedOn descending
      final filteredOrders = orders
          .where((order) => order.status != OrderStatus.completed)
          .toList();
      filteredOrders.sort((a, b) => b.createdOn.compareTo(a.createdOn));

      setState(() {
        _orders = filteredOrders;
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
        setState(() {
          _elapsedTime = DateTime.now().difference(activeReg.startTime);
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
      // Subscribe to timer updates
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
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timer started')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot start timer. You may already have an active timer.')),
        );
      }
    }
  }

  Future<void> _stopTimer() async {
    final success = await _timerService.stopTimer();
    
    if (success) {
      _timerSubscription?.cancel();
      _timerSubscription = null;
      
      setState(() {
        _elapsedTime = null;
      });

      // Update order if it's the selected one
      if (_selectedOrder != null) {
        final activeReg = _timerService.activeRegistration;
        if (activeReg == null || activeReg.orderId == _selectedOrder!.orderId) {
          // Order status might remain In Progress or be updated elsewhere
          await _loadData();
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timer stopped')),
        );
      }
    }
  }

  void _selectOrder(Order order) {
    setState(() {
      _selectedOrder = order;
      _elapsedTime = null;
    });

    // Check if there's an active timer for this order
    final activeReg = _timerService.activeRegistration;
    if (activeReg != null && activeReg.orderId == order.orderId && activeReg.isActive) {
      setState(() {
        _elapsedTime = DateTime.now().difference(activeReg.startTime);
      });
      
      // Subscribe to timer updates if not already subscribed
      _timerSubscription?.cancel();
      _timerSubscription = _timerService.elapsedTimeStream.listen((duration) {
        if (mounted) {
          setState(() {
            _elapsedTime = duration;
          });
        }
      });
    } else {
      _timerSubscription?.cancel();
      _timerSubscription = null;
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
    final isTimerRunning = _timerService.isTimerRunning && 
        _selectedOrder != null &&
        _timerService.activeRegistration?.orderId == _selectedOrder!.orderId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Processing'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Text(
              widget.authService.getCurrentUserDisplayName() ?? 'User',
              style: const TextStyle(fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Logout',
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
                              Text(
                                'Orders',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: _loadData,
                                tooltip: 'Refresh',
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
                    elapsedTime: _elapsedTime,
                    onStartTimer: _startTimer,
                    onStopTimer: _stopTimer,
                  ),
                ),
              ],
            ),
    );
  }
}

