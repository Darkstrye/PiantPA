import 'package:flutter/material.dart';
import '../models/order.dart';
import '../repositories/repository_interface.dart';
import '../repositories/excel_repository.dart';
import '../repositories/hybrid_repository.dart';
import '../services/auth_service.dart';
import '../services/timer_service.dart';
import '../widgets/loading_indicator.dart';
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

  // Filter state
  Map<int, String> _machines = {};
  Map<int, String> _machineGroups = {};
  Map<int, String> _statuses = {};
  int? _selectedMachineId;
  int? _selectedMachineGroupId;
  int? _selectedStatusId;
  bool _filtersLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _loadOrders();
    _searchController.addListener(() {
      _applyFilter(_searchController.text);
    });
  }

  Future<void> _loadFilters() async {
    if (widget.repository is HybridRepository) {
      final repo = widget.repository as HybridRepository;
      final machines = await repo.getMachines();
      final machineGroups = await repo.getMachineGroups();
      final statuses = await repo.getStatuses();
      
      if (mounted) {
        setState(() {
          _machines = machines;
          _machineGroups = machineGroups;
          _statuses = statuses;
          _filtersLoaded = true;
        });
      }
    }
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
    });

    try {
      List<Order> allOrders;
      
      // Use filtered query if HybridRepository and filters are set
      if (widget.repository is HybridRepository && 
          (_selectedMachineId != null || _selectedMachineGroupId != null || _selectedStatusId != null)) {
        final repo = widget.repository as HybridRepository;
        allOrders = await repo.getOrdersWithFilters(
          machineId: _selectedMachineId,
          machineGroupId: _selectedMachineGroupId,
          statusId: _selectedStatusId,
        );
      } else {
        allOrders = await widget.repository.getAllOrders();
      }
      
      final availableOrders = allOrders
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

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => _FilterDialog(
        machines: _machines,
        machineGroups: _machineGroups,
        statuses: _statuses,
        selectedMachineId: _selectedMachineId,
        selectedMachineGroupId: _selectedMachineGroupId,
        selectedStatusId: _selectedStatusId,
        onApply: (machineId, machineGroupId, statusId) {
          setState(() {
            _selectedMachineId = machineId;
            _selectedMachineGroupId = machineGroupId;
            _selectedStatusId = statusId;
          });
          _loadOrders();
        },
      ),
    );
  }

  bool get _hasActiveFilters => 
      _selectedMachineId != null || 
      _selectedMachineGroupId != null || 
      _selectedStatusId != null;

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
        final ordernummer = (order.ordernummer ?? '').toLowerCase();
        final orderregel = (order.orderregel ?? '').toLowerCase();
        final machine = order.machine.toLowerCase();
        return ordernummer.contains(lower) || 
               orderregel.contains(lower) || 
               machine.contains(lower);
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Zoek op ordernummer, orderregel of machine',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.filter_list, size: 28),
                        tooltip: 'Filter',
                        onPressed: _filtersLoaded ? _showFilterDialog : null,
                        style: IconButton.styleFrom(
                          backgroundColor: _hasActiveFilters 
                              ? Colors.blue.shade100 
                              : Colors.grey.shade200,
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                      if (_hasActiveFilters)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.blue.shade700,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (_hasActiveFilters)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (_selectedMachineId != null)
                      Chip(
                        label: Text('Machine: ${_machines[_selectedMachineId]}'),
                        onDeleted: () {
                          setState(() => _selectedMachineId = null);
                          _loadOrders();
                        },
                        deleteIconColor: Colors.grey.shade600,
                      ),
                    if (_selectedMachineGroupId != null)
                      Chip(
                        label: Text('Groep: ${_machineGroups[_selectedMachineGroupId]}'),
                        onDeleted: () {
                          setState(() => _selectedMachineGroupId = null);
                          _loadOrders();
                        },
                        deleteIconColor: Colors.grey.shade600,
                      ),
                    if (_selectedStatusId != null)
                      Chip(
                        label: Text('Status: ${_statuses[_selectedStatusId]}'),
                        onDeleted: () {
                          setState(() => _selectedStatusId = null);
                          _loadOrders();
                        },
                        deleteIconColor: Colors.grey.shade600,
                      ),
                  ],
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const LoadingIndicator(message: 'Loading orders...')
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
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ordernummer: ${order.ordernummer ?? "-"}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Orderregel: ${order.orderregel ?? "-"}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Omschrijving (max 30 chars)
                                      if (order.omschrijving != null && order.omschrijving!.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 4),
                                          child: Text(
                                            order.omschrijving!.length > 30
                                                ? '${order.omschrijving!.substring(0, 30)}...'
                                                : order.omschrijving!,
                                            style: TextStyle(
                                              fontStyle: FontStyle.italic,
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      // Compact info chips
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (order.machine.isNotEmpty)
                                            _buildInfoChip(Icons.precision_manufacturing, order.machine),
                                          if (order.statusNaam != null && order.statusNaam!.isNotEmpty)
                                            _buildInfoChip(Icons.flag, order.statusNaam!, Colors.blue.shade700),
                                          if (order.leverdatum != null)
                                            _buildInfoChip(
                                              Icons.calendar_today,
                                              '${order.leverdatum!.day.toString().padLeft(2, '0')}-${order.leverdatum!.month.toString().padLeft(2, '0')}-${order.leverdatum!.year}',
                                              Colors.orange.shade700,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      // Voca, Geproduceerd, Totaal in one row
                                      Wrap(
                                        spacing: 12,
                                        children: [
                                          if (order.vocaInUur != null)
                                            Text(
                                              'Voca: ${order.vocaInUur!.toStringAsFixed(2).replaceAll('.', ',')}u',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          if (order.geproduceerd != null && order.geproduceerd! > 0)
                                            Text(
                                              'Geprod: ${order.geproduceerd!.toStringAsFixed(0)}',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          if (order.totaalBedrag != null && order.totaalBedrag! > 0)
                                            Text(
                                              '€${order.totaalBedrag!.toStringAsFixed(2).replaceAll('.', ',')}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.green.shade700,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
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

  Widget _buildInfoChip(IconData icon, String label, [Color? color]) {
    final chipColor = color ?? Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chipColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: chipColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDialog extends StatefulWidget {
  final Map<int, String> machines;
  final Map<int, String> machineGroups;
  final Map<int, String> statuses;
  final int? selectedMachineId;
  final int? selectedMachineGroupId;
  final int? selectedStatusId;
  final void Function(int?, int?, int?) onApply;

  const _FilterDialog({
    required this.machines,
    required this.machineGroups,
    required this.statuses,
    this.selectedMachineId,
    this.selectedMachineGroupId,
    this.selectedStatusId,
    required this.onApply,
  });

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  int? _machineId;
  int? _machineGroupId;
  int? _statusId;

  @override
  void initState() {
    super.initState();
    _machineId = widget.selectedMachineId;
    _machineGroupId = widget.selectedMachineGroupId;
    _statusId = widget.selectedStatusId;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filter Orders'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Machine dropdown
            const Text('Machine', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: _machineId,
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              hint: const Text('Alle machines'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Alle machines')),
                ...widget.machines.entries.map((e) => 
                  DropdownMenuItem<int?>(value: e.key, child: Text(e.value)),
                ),
              ],
              onChanged: (value) => setState(() => _machineId = value),
            ),
            const SizedBox(height: 16),

            // Machine Group dropdown
            const Text('Machinegroep', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: _machineGroupId,
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              hint: const Text('Alle groepen'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Alle groepen')),
                ...widget.machineGroups.entries.map((e) => 
                  DropdownMenuItem<int?>(value: e.key, child: Text(e.value)),
                ),
              ],
              onChanged: (value) => setState(() => _machineGroupId = value),
            ),
            const SizedBox(height: 16),

            // Status dropdown
            const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: _statusId,
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              hint: const Text('Alle statussen'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Alle statussen')),
                ...widget.statuses.entries.map((e) => 
                  DropdownMenuItem<int?>(value: e.key, child: Text(e.value)),
                ),
              ],
              onChanged: (value) => setState(() => _statusId = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _machineId = null;
              _machineGroupId = null;
              _statusId = null;
            });
          },
          child: const Text('Reset'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuleren'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onApply(_machineId, _machineGroupId, _statusId);
            Navigator.of(context).pop();
          },
          child: const Text('Toepassen'),
        ),
      ],
    );
  }
}
