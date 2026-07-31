import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';
import '../../data/models/expense_model.dart';
import '../../widgets/firestore_paginated_list.dart';
import '../../data/models/user_model.dart';
import '../admin/controllers/expense_ui_controller.dart';
import '../../routing/guarded_navigator.dart';
import '../../routing/screen_permission.dart';
import 'expense_form_screen.dart';

/// Expense Management Screen - Admin view of all expenses
/// Allows viewing, adding, and editing expenses
class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final ExpenseUiController _uiController = Get.put(ExpenseUiController());
  String? _shopId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
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
          _isLoading = false;
        });
        _uiController.setShopId(_shopId);
        _uiController.setLoading(false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _uiController.setLoading(false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading user data: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Expenses')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              GuardedNavigator.push(
                context,
                permission: ScreenPermission.expenseForm,
                page: const ExpenseFormScreen(),
              );
            },
            tooltip: 'Add Expense',
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
                hintText: 'Search expenses...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Obx(() {
                  if (_uiController.searchQuery.value.isNotEmpty) {
                    return IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _uiController.clearSearchQuery(),
                    );
                  }
                  return const SizedBox.shrink();
                }),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) => _uiController.setSearchQuery(value),
            ),
          ),

          Expanded(
            child: Obx(
              () => FirestorePaginatedList<ExpenseModel>(
                cacheKey: 'expenses_legacy_$_shopId',
                queryBuilder: () => FirebaseFirestore.instance
                    .collection('expenses')
                    .where('shopId', isEqualTo: _shopId)
                    .orderBy('createdAt', descending: true),
                parse: (data, _) => ExpenseModel.tryFromMap(data),
                itemKey: (e) => e.expenseId,
                filterItems: (items) {
                  var filtered = items;
                  final q = _uiController.searchQuery.value.trim().toLowerCase();
                  if (q.isNotEmpty) {
                    filtered = filtered
                        .where((e) => e.description.toLowerCase().contains(q))
                        .toList();
                  }
                  final selected = _uiController.selectedDate.value;
                  if (selected != null) {
                    filtered = filtered.where((e) {
                      final d = e.createdAt;
                      return d.year == selected.year &&
                          d.month == selected.month &&
                          d.day == selected.day;
                    }).toList();
                  }
                  return filtered;
                },
                emptyBuilder: (context) => const Center(
                  child: Text('No expenses match your filters'),
                ),
                itemBuilder: (context, expense) =>
                    _buildExpenseCard(context, expense),
              ),
            ),  
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(BuildContext context, ExpenseModel expense) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormat = '${expense.createdAt.day}/${expense.createdAt.month}/${expense.createdAt.year}';
    final timeFormat = '${expense.createdAt.hour.toString().padLeft(2, '0')}:${expense.createdAt.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.errorContainer,
          child: Icon(
            Icons.account_balance_wallet,
            color: colorScheme.onErrorContainer,
          ),
        ),
        title: Text(expense.description),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Date: $dateFormat at $timeFormat'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '₹${expense.amount.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
                  ),
            ),
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'edit') {
                  GuardedNavigator.push(
                    context,
                    permission: ScreenPermission.expenseForm,
                    page: ExpenseFormScreen(expense: expense),
                  );
                } else if (val == 'delete') {
                  _deleteExpense(context, expense);
                }
              },
              itemBuilder: (ctx) => [
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
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () {
          GuardedNavigator.push(
            context,
            permission: ScreenPermission.expenseForm,
            page: ExpenseFormScreen(expense: expense),
          );
        },
      ),
    );
  }

  Future<void> _deleteExpense(BuildContext pageContext, ExpenseModel expense) async {
    final confirm = await showDialog<bool>(
      context: pageContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense'),
        content: Text('Are you sure you want to delete this expense of ₹${expense.amount.toStringAsFixed(2)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !pageContext.mounted) return;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('createOrUpdateExpense');
      await callable.call(<String, dynamic>{
        'action': 'delete',
        'expenseId': expense.expenseId,
        'shopId': expense.shopId,
      });
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(content: Text('Expense deleted successfully')),
      );
    } catch (e) {
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(content: Text('Failed to delete expense: $e')),
      );
    }
  }
}
