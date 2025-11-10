import 'package:flutter/material.dart';
import '../models/order.dart';
import '../repositories/repository_interface.dart';
import '../repositories/excel_repository.dart';
import '../services/auth_service.dart';
import '../services/timer_service.dart';
import '../widgets/order_list_item.dart';
import '../widgets/order_detail_panel.dart';
import '../widgets/timer_display.dart';
import '../utils/reset_completed_orders.dart';

class CompletedOrdersScreen extends StatefulWidget {
  final AuthService authService;

  const CompletedOrdersScreen({
    super.key,
    required this.authService,
  });

  @override
  State<CompletedOrdersScreen> createState() => _CompletedOrdersScreenState();
}

class _CompletedOrdersScreenState extends State<CompletedOrdersScreen> {
  final RepositoryInterface _repository = ExcelRepository();
  late final TimerService _timerService;
  
  List<Order> _orders = [];
  Order? _selectedOrder;
  bool _isLoading = true;
  Duration? _elapsedTime;
  Duration? _downtime;

  @override
  void initState() {
    super.initState();
    _timerService = TimerService(_repository);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final orders = await _repository.getAllOrders();
      // Filter only completed orders
      final filteredOrders = orders
          .where((order) => order.status == OrderStatus.completed)
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
      finalOrders.sort((a, b) => b.modifiedOn.compareTo(a.modifiedOn));

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

  void _selectOrder(Order order) async {
    setState(() {
      _selectedOrder = order;
    });
    
    // Load time metrics for this completed order
    await _loadDurationsForOrder(order.orderId);
  }

  Future<void> _loadDurationsForOrder(String orderId) async {
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
    widget.authService.logout();
    Navigator.of(context).pushReplacementNamed('/login');
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _timerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.assignment_turned_in, color: Colors.green.shade700, size: 24),
            const SizedBox(width: 8),
            const Text('Completed Orders'),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back to Active Orders',
        ),
        actions: [
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
          // Reset button
          Tooltip(
            message: 'Reset All Completed Orders',
            child: IconButton(
              icon: const Icon(Icons.restart_alt),
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
                      _loadData();
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
              tooltip: 'Reset All Completed Orders',
              color: Colors.orange.shade700,
            ),
          ),
          // Refresh button
          Tooltip(
            message: 'Refresh Completed Orders',
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'Refresh',
              color: Colors.green.shade700,
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
                // Left Panel - Completed Order List
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
                                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Completed Orders (${_orders.length})',
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
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
                                  child: Text('No completed orders'),
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
                // Right Panel - Order Details (Read-only for completed orders)
                Expanded(
                  flex: 3,
                  child: _selectedOrder == null
                      ? const Center(
                          child: Text(
                            'Select an order to view details',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order Details',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 24),
                              _buildDetailRow('Order Number', _selectedOrder!.orderNumber),
                              const SizedBox(height: 16),
                              _buildDetailRow('Machine', _selectedOrder!.machine.isNotEmpty ? _selectedOrder!.machine : 'N/A'),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Text(
                                    'Status: ',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Text(
                                      'Completed',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),
                              if (_elapsedTime != null) ...[
                                const Text(
                                  'Total Time:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TimerDisplay(duration: _elapsedTime!),
                                if (_downtime != null) ...[
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Total Downtime:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TimerDisplay(
                                    duration: _downtime!,
                                    title: 'Downtime',
                                    accentColor: Colors.orange.shade700,
                                  ),
                                ],
                              ] else ...[
                                const Center(
                                  child: Text(
                                    'No time recorded for this order',
                                    style: TextStyle(fontSize: 16, color: Colors.grey),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

