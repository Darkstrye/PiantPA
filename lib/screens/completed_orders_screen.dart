import 'package:flutter/material.dart';
import '../models/order.dart';
import '../repositories/repository_interface.dart';
import '../repositories/excel_repository.dart';
import '../services/auth_service.dart';
import '../widgets/order_list_item.dart';
import '../widgets/order_detail_panel.dart';

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
  
  List<Order> _orders = [];
  Order? _selectedOrder;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final orders = await _repository.getAllOrders();
      // Filter only completed orders and sort by ModifiedOn descending (most recently completed first)
      final filteredOrders = orders
          .where((order) => order.status == OrderStatus.completed)
          .toList();
      filteredOrders.sort((a, b) => b.modifiedOn.compareTo(a.modifiedOn));

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

  void _selectOrder(Order order) {
    setState(() {
      _selectedOrder = order;
    });
  }

  void _handleLogout() {
    widget.authService.logout();
    Navigator.of(context).pushReplacementNamed('/login');
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
                  child: OrderDetailPanel(
                    order: _selectedOrder,
                    isTimerRunning: false,
                    isTimerPaused: false,
                    hasActiveTimer: false,
                    isTimerForSelectedOrder: false,
                    elapsedTime: null,
                    onStartTimer: null,
                    onPauseTimer: null,
                    onFinishOrder: null,
                  ),
                ),
              ],
            ),
    );
  }
}

