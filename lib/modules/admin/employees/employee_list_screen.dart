import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';
import '../../../core/firestore/firestore_rule_safe_update.dart';
import '../../../data/models/user_model.dart';
import '../../../widgets/firestore_paginated_list.dart';
import '../../../core/rbac/role_constants.dart';
import 'employee_controller.dart';
import '../../../routing/guarded_navigator.dart';
import '../../../routing/screen_permission.dart';
import 'employee_form_screen.dart';

/// Employee List Screen - Admin view of all employees
/// Allows viewing, adding, and toggling employee status
class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});

  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  final EmployeeController _controller = Get.put(EmployeeController());
  String? _shopId;
  String? _role;
  bool _isLoading = true;

  bool get _isSuperAdmin => _role == 'SuperAdmin';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadUserData(context);
    });
  }

  Future<void> _loadUserData(BuildContext pageContext) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (pageContext.mounted) {
          Navigator.of(pageContext).pop();
        }
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = UserModel.tryFromDocument(userDoc);
        if (userData == null) return;
        if (!mounted) return;
        setState(() {
          _shopId = userData.shopId;
          _role = userData.role;
          _isLoading = false;
        });
        _controller.setLoading(false);
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Error loading user data: $e')),
        );
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _controller.setLoading(false);
    }
  }

  /// Super Admin only. Soft-deletes the employee (status -> 'Deleted') via
  /// the deleteEmployee Cloud Function so history stays resolvable in past
  /// orders/audit logs and the deletion is audit-logged (see
  /// deleteEmployee.ts for rationale).
  Future<void> _deleteEmployee(
    BuildContext pageContext,
    UserModel employee,
  ) async {
    final confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete employee?'),
        content: Text(
          'Delete "${employee.name}"? They will no longer be able to log '
          'in, but their past orders and sales history are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      _controller.setLoading(true);
      await FirebaseFunctions.instance.httpsCallable('deleteEmployee').call(
        <String, dynamic>{
          'userId': employee.userId,
          'shopId': employee.shopId,
        },
      );
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Employee "${employee.name}" deleted')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text('Error deleting employee: ${e.message ?? e.code}'),
          ),
        );
      }
    } finally {
      _controller.setLoading(false);
    }
  }

  Future<void> _toggleEmployeeStatus(
    BuildContext pageContext,
    UserModel employee,
  ) async {
    try {
      _controller.setLoading(true);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(employee.userId)
          .update(
            FirestoreRuleSafeUpdate.user(
              employee,
              changes: {
                'status': employee.status == 'Active' ? 'Inactive' : 'Active',
              },
            ),
          );

      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(
              'Employee ${employee.status == 'Active' ? 'deactivated' : 'activated'}',
            ),
          ),
        );
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Error updating employee: $e')),
        );
      }
    } finally {
      _controller.setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Employees')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              GuardedNavigator.push(
                context,
                permission: ScreenPermission.employeeForm,
                page: const EmployeeFormScreen(),
              );
            },
            tooltip: 'Add Employee',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search employees...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Obx(() {
                  if (_controller.searchQuery.value.isNotEmpty) {
                    return IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _controller.clearSearchQuery(),
                    );
                  }
                  return const SizedBox.shrink();
                }),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) => _controller.setSearchQuery(value),
            ),
          ),

          // Filter chips
          Obx(
            () => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildFilterChip('all', 'All'),
                  _buildFilterChip('Active', 'Active'),
                  _buildFilterChip('Inactive', 'Inactive'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: Obx(
              () => FirestorePaginatedList<UserModel>(
                cacheKey: 'employees_shop_$_shopId',
                queryBuilder: () => FirebaseFirestore.instance
                    .collection('users')
                    .where('shopId', isEqualTo: _shopId)
                    .where('role', isEqualTo: RoleConstants.employee)
                    .orderBy('name'),
                parse: (data, _) => UserModel.tryFromMap(data),
                itemKey: (u) => u.userId,
                filterItems: (items) {
                  // Soft-deleted employees (status: 'Deleted') never appear
                  // in the management list — only resolvable by ID for
                  // historical order/audit-log lookups.
                  var filtered =
                      items.where((e) => e.status != 'Deleted').toList();
                  final q = _controller.searchQuery.value.trim().toLowerCase();
                  if (q.isNotEmpty) {
                    filtered = filtered
                        .where(
                          (e) =>
                              e.name.toLowerCase().contains(q) ||
                              e.email.toLowerCase().contains(q) ||
                              e.phone.contains(_controller.searchQuery.value),
                        )
                        .toList();
                  }
                  final f = _controller.selectedFilter.value;
                  if (f == 'Active') {
                    filtered =
                        filtered.where((e) => e.status == 'Active').toList();
                  } else if (f == 'Inactive') {
                    filtered =
                        filtered.where((e) => e.status == 'Inactive').toList();
                  }
                  return filtered;
                },
                emptyBuilder: (context) => const Center(
                  child: Text('No employees match your filters'),
                ),
                itemBuilder: (context, employee) =>
                    _buildEmployeeCard(context, employee),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    return Obx(
      () => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(label),
          selected: _controller.selectedFilter.value == value,
          onSelected: (selected) {
            if (selected) {
              _controller.setSelectedFilter(value);
            }
          },
        ),
      ),
    );
  }

  Widget _buildEmployeeCard(BuildContext context, UserModel employee) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = employee.status == 'Active';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive
              ? colorScheme.primaryContainer
              : colorScheme.errorContainer,
          child: Icon(
            isActive ? Icons.person : Icons.person_off,
            color: isActive
                ? colorScheme.onPrimaryContainer
                : colorScheme.onErrorContainer,
          ),
        ),
        title: Text(employee.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Email: ${employee.email}'),
            Text('Phone: ${employee.phone}'),
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(
                  label: const Text('EMPLOYEE', style: TextStyle(fontSize: 11)),
                  backgroundColor: colorScheme.secondaryContainer,
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    employee.status,
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor: isActive
                      ? colorScheme.primaryContainer
                      : colorScheme.errorContainer,
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') {
              GuardedNavigator.push(
                context,
                permission: ScreenPermission.employeeForm,
                page: EmployeeFormScreen(employee: employee),
              );
            } else if (value == 'toggle') {
              _toggleEmployeeStatus(context, employee);
            } else if (value == 'delete') {
              _deleteEmployee(context, employee);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'toggle',
              child: Row(
                children: [
                  Icon(isActive ? Icons.block : Icons.check_circle, size: 20),
                  const SizedBox(width: 8),
                  Text(isActive ? 'Deactivate' : 'Activate'),
                ],
              ),
            ),
            // Delete is Super Admin only (Requirement in Detail §28.2 —
            // Admin can activate/deactivate but never delete).
            if (_isSuperAdmin)
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: colorScheme.error)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
