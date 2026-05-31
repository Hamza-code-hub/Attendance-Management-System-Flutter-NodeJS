import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../adjustments_provider.dart';
import '../../authentication/presentation/auth_state.dart';

class AdjustmentsScreen extends ConsumerStatefulWidget {
  const AdjustmentsScreen({super.key});

  @override
  ConsumerState<AdjustmentsScreen> createState() => _AdjustmentsScreenState();
}

class _AdjustmentsScreenState extends ConsumerState<AdjustmentsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adjState = ref.watch(adjustmentProvider);
    final roles = ref.watch(authProvider).user?.roles ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Adjustments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(adjustmentProvider.notifier).fetchHistory(),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request & History',
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Correct missed punch logs, late arrivals, or early exits.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
                if (!roles.contains('Admin'))
                  ElevatedButton.icon(
                    onPressed: () => _showRequestDialog(context),
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('Request Adjustment'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 36),
            if (adjState.error != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        adjState.error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (adjState.isLoading && adjState.history.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.all(36.0),
                child: CircularProgressIndicator(),
              ))
            else if (adjState.history.isEmpty)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60, horizontal: 20),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.edit_calendar_rounded, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No adjustment requests found.',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Submit a request using the button above.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: adjState.history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final req = adjState.history[index];
                    final dateStr = req.requestedCheckinTime != null 
                        ? DateFormat('yyyy-MM-DD').format(DateTime.parse(req.requestedCheckinTime!))
                        : DateFormat('yyyy-MM-DD').format(DateTime.parse(req.requestedCheckoutTime!));

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.edit_calendar_outlined, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      dateStr,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(width: 12),
                                    _buildTypeBadge(req.adjustmentType),
                                    const SizedBox(width: 12),
                                    _buildStatusBadge(req.status),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Reason: ${req.reason}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Requested Times:  '
                                  'In: ${req.requestedCheckinTime != null ? DateFormat('hh:mm a').format(DateTime.parse(req.requestedCheckinTime!).toLocal()) : '--:--'}  |  '
                                  'Out: ${req.requestedCheckoutTime != null ? DateFormat('hh:mm a').format(DateTime.parse(req.requestedCheckoutTime!).toLocal()) : '--:--'}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                if (req.hrComment != null && req.hrComment!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.amber.withOpacity(0.15)),
                                    ),
                                    child: Text(
                                      'HR Comment: ${req.hrComment}',
                                      style: TextStyle(color: theme.brightness == Brightness.dark ? Colors.amber[200] : Colors.amber[800], fontSize: 12),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type.replaceAll('_', ' '),
        style: const TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color badgeColor = Colors.grey;
    if (status == 'APPROVED') badgeColor = Colors.green;
    if (status == 'REJECTED') badgeColor = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeColor.withOpacity(0.2)),
      ),
      child: Text(
        status,
        style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 10),
      ),
    );
  }

  void _showRequestDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final reasonController = TextEditingController();
    
    String selectedType = 'MISSED_CHECKIN';
    DateTime selectedDate = DateTime.now();
    
    TimeOfDay? checkinTime;
    TimeOfDay? checkoutTime;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Request Adjustment'),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedType,
                          decoration: const InputDecoration(labelText: 'Adjustment Type'),
                          items: const [
                            DropdownMenuItem(value: 'MISSED_CHECKIN', child: Text('Missed Check-in')),
                            DropdownMenuItem(value: 'MISSED_CHECKOUT', child: Text('Missed Check-out')),
                            DropdownMenuItem(value: 'LATE_COMPENSATION', child: Text('Late Compensation')),
                            DropdownMenuItem(value: 'EARLY_LEAVE', child: Text('Early Leave')),
                            DropdownMenuItem(value: 'CUSTOM', child: Text('Custom / Other')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedType = val);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
                          trailing: const Icon(Icons.calendar_month),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime.now().subtract(const Duration(days: 30)),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedDate = picked);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        if (selectedType != 'MISSED_CHECKOUT') ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Requested Check-in: ${checkinTime != null ? checkinTime!.format(context) : 'Not Set'}'),
                            trailing: const Icon(Icons.access_time),
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (picked != null) {
                                setDialogState(() => checkinTime = picked);
                              }
                            },
                          ),
                        ],
                        if (selectedType != 'MISSED_CHECKIN') ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Requested Check-out: ${checkoutTime != null ? checkoutTime!.format(context) : 'Not Set'}'),
                            trailing: const Icon(Icons.access_time),
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (picked != null) {
                                setDialogState(() => checkoutTime = picked);
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: reasonController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Reason / Explanation',
                            alignLabelWithHint: true,
                            prefixIcon: Padding(
                              padding: EdgeInsets.only(bottom: 40),
                              child: Icon(Icons.comment),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'A reason is required';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      // Validate that times are entered based on type
                      if (selectedType != 'MISSED_CHECKOUT' && checkinTime == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select check-in time')),
                        );
                        return;
                      }
                      if (selectedType != 'MISSED_CHECKIN' && checkoutTime == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select check-out time')),
                        );
                        return;
                      }

                      // Build Full ISO Date Strings
                      String? checkinIso;
                      if (checkinTime != null) {
                        final dt = DateTime(
                          selectedDate.year,
                          selectedDate.month,
                          selectedDate.day,
                          checkinTime!.hour,
                          checkinTime!.minute,
                        );
                        checkinIso = dt.toUtc().toIso8601String();
                      }

                      String? checkoutIso;
                      if (checkoutTime != null) {
                        final dt = DateTime(
                          selectedDate.year,
                          selectedDate.month,
                          selectedDate.day,
                          checkoutTime!.hour,
                          checkoutTime!.minute,
                        );
                        checkoutIso = dt.toUtc().toIso8601String();
                      }

                      final success = await ref.read(adjustmentProvider.notifier).createRequest(
                            type: selectedType,
                            checkinTime: checkinIso,
                            checkoutTime: checkoutIso,
                            reason: reasonController.text.trim(),
                          );

                      if (success && context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Adjustment request submitted successfully')),
                        );
                      }
                    }
                  },
                  child: const Text('Submit Request'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
