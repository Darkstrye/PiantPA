import 'package:flutter/material.dart';
import '../models/order.dart';
import '../repositories/repository_interface.dart';
import '../repositories/excel_repository.dart';
import '../services/auth_service.dart';
import '../services/timer_service.dart';
import 'active_session_screen.dart';

enum OrderSelectionMode { start, add }

class OrderSelectionScreen extends StatefulWidget {
  final AuthService authService;
  final TimerService timerService;
  final RepositoryInterface repository;
  final OrderSelectionMode mode;
  final Set<String> disabledOrderIds;

  const OrderSelectionScreen({
    super.key,
    required this.authService,
    required this.timerService,
    required this.repository,
    required this.mode,
    this.disabledOrderIds = const {},
  });

  bool get isAddMode => mode == OrderSelectionMode.add;

  @override
  State<OrderSelectionScreen> createState() => _OrderSelectionScreenState();
}

class _OrderSelectionScreenState extends State<OrderSelectionScreen> {
  final Set<String> _selectedOrderIds = {};
  final TextEditingController _searchController = TextEditingController();

  List<Order> _orders = [];
  List<Order> _filteredOrders = [];
  Map<String, Order> _ordersById = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _searchController.addListener(() {
      _applyFilter(_searchController.text);
    });
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final allOrders = await widget.repository.getAllOrders();
      final availableOrders = allOrders
          .where((order) => order.status == OrderStatus.inProgress)
          .where((order) => !widget.disabledOrderIds.contains(order.orderId))
          .toList()
        ..sort(
          (a, b) => a.orderNumber.compareTo(b.orderNumber),
        );

      setState(() {
        _orders = availableOrders;
        _filteredOrders = List<Order>.from(availableOrders);
        _ordersById = {for (final o in availableOrders) o.orderId: o};
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load orders: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _applyFilter(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) {
      setState(() {
        _filteredOrders = List<Order>.from(_orders);
      });
      return;
    }

    setState(() {
      _filteredOrders = _orders.where((order) {
        final number = order.orderNumber.toLowerCase();
        final machine = order.machine.toLowerCase();
        return number.contains(lower) || machine.contains(lower);
      }).toList();
    });
  }

  void _toggleSelection(String orderId) {
    setState(() {
      if (_selectedOrderIds.contains(orderId)) {
        _selectedOrderIds.remove(orderId);
      } else {
        _selectedOrderIds.add(orderId);
      }
    });
  }

  Future<void> _handleConfirmSelection() async {
    if (_selectedOrderIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one order to continue.'),
        ),
      );
      return;
    }

    final userId = widget.authService.getCurrentUserId();
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No active user session. Please log in again.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final selectedIds = _selectedOrderIds.toList();
    final success = await widget.timerService.startTimerForOrders(
      selectedIds,
      userId,
    );

    if (!success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Could not start/update the session. Close Excel files and try again.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    await _markOrdersInProgress(selectedIds);

    // Only clear orders cache since we updated order statuses
    if (widget.repository is ExcelRepository) {
      (widget.repository as ExcelRepository).clearOrdersCache();
    }

    if (!mounted) return;

    if (widget.isAddMode) {
      Navigator.of(context).pop(true);
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ActiveSessionScreen(
          authService: widget.authService,
          timerService: widget.timerService,
          repository: widget.repository,
        ),
      ),
    );
  }

  Order? _findOrderById(String orderId) => _ordersById[orderId];

  Future<void> _markOrdersInProgress(List<String> orderIds) async {
    for (final id in orderIds) {
      try {
        final order = _findOrderById(id);
        if (order == null) continue;
        final updated = order.copyWith(
          status: OrderStatus.inProgress,
          modifiedOn: DateTime.now(),
        );
        await widget.repository.updateOrder(updated);
      } catch (e) {
        // ignore: avoid_print
        print('[OrderSelectionScreen] Failed to update order $id: $e');
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buttonLabel = widget.isAddMode
        ? 'Add Orders to Session'
        : 'Start Session';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isAddMode ? 'Add Orders' : 'Select Orders',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Orders',
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search by order number or machine',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredOrders.isEmpty
                      ? const Center(
                          child: Text('No orders available.'),
                        )
                      : ListView.separated(
                          itemCount: _filteredOrders.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemBuilder: (context, index) {
                            final order = _filteredOrders[index];
                            final isSelected =
                                _selectedOrderIds.contains(order.orderId);

                            return Card(
                              elevation: isSelected ? 4 : 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                onTap: () => _toggleSelection(order.orderId),
                                leading: Checkbox(
                                  value: isSelected,
                                  onChanged: (_) =>
                                      _toggleSelection(order.orderId),
                                ),
                                title: Text(
                                  order.orderNumber,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (order.machine.isNotEmpty)
                                      Text('Machine: ${order.machine}'),
                                    if (order.vocaInUur != null)
                                      Text(
                                        'Voca: ${order.vocaInUur!.toStringAsFixed(2).replaceAll('.', ',')}',
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: SafeArea(
                top: false,
                child: ElevatedButton.icon(
                  onPressed: _handleConfirmSelection,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: widget.isAddMode
                        ? Colors.blue.shade700
                        : Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(
                    widget.isAddMode ? Icons.playlist_add : Icons.play_arrow,
                  ),
                  label: Text(
                    '$buttonLabel (${_selectedOrderIds.length})',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


