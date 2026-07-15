import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firestore/firestore_rule_safe_update.dart';
import '../../../data/models/category_model.dart';
import '../../../widgets/firestore_paginated_list.dart';
import '../../../data/models/user_model.dart';
import '../../../routing/guarded_navigator.dart';
import '../../../routing/screen_permission.dart';
import 'category_form_screen.dart';

/// Category List Screen - Admin view of all categories for a shop.
/// Allows viewing, creating, editing, and enabling/disabling categories.
class CategoryListScreen extends StatefulWidget {
  const CategoryListScreen({super.key});

  @override
  State<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends State<CategoryListScreen> {
  String? _shopId;
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadUserShop(context);
    });
  }

  Future<void> _loadUserShop(BuildContext pageContext) async {
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
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Error loading user data: $e')),
        );
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleStatus(
    BuildContext pageContext,
    CategoryModel category,
  ) async {
    final newStatus =
        category.status == 'Active' ? 'Inactive' : 'Active';
    try {
      await FirebaseFirestore.instance
          .collection('categories')
          .doc(category.categoryId)
          .update(
            FirestoreRuleSafeUpdate.category(
              category,
              changes: {'status': newStatus},
            ),
          );
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(
              'Category ${newStatus == 'Active' ? 'enabled' : 'disabled'}',
            ),
          ),
        );
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Error updating category: $e')),
        );
      }
    }
  }

  /// Admin/Super Admin (own shop) may delete a category — Firestore rules
  /// enforce the role+shop check (TECHNICAL REQUIREMENTS IN DETAIL.md
  /// Module 4: "Admin: Write=All"). Products referencing this category keep
  /// their existing categoryId; no cascading delete is performed.
  Future<void> _deleteCategory(
    BuildContext pageContext,
    CategoryModel category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Delete "${category.name}"? Products already assigned to this '
          'category will keep their existing link.',
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
      await FirebaseFirestore.instance
          .collection('categories')
          .doc(category.categoryId)
          .delete();
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Category "${category.name}" deleted')),
        );
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Error deleting category: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Categories')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_shopId == null || _shopId!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Categories')),
        body: const Center(child: Text('Shop not assigned')),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Category',
            onPressed: () {
              GuardedNavigator.push(
                context,
                permission: ScreenPermission.categoryForm,
                page: CategoryFormScreen(shopId: _shopId!),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search categories...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim();
                });
              },
            ),
          ),
          Expanded(
            child: FirestorePaginatedList<CategoryModel>(
              cacheKey: 'categories_shop_$_shopId',
              queryBuilder: () => FirebaseFirestore.instance
                  .collection('categories')
                  .where('shopId', isEqualTo: _shopId)
                  .orderBy('name'),
              parse: (data, _) => CategoryModel.tryFromMap(data),
              itemKey: (c) => c.categoryId,
              filterItems: (items) {
                if (_searchQuery.isEmpty) return items;
                final q = _searchQuery.toLowerCase();
                return items
                    .where((c) => c.name.toLowerCase().contains(q))
                    .toList();
              },
              emptyBuilder: (context) => Center(
                child: Text(
                  _searchQuery.isEmpty
                      ? 'No categories found'
                      : 'No categories match your search',
                ),
              ),
              itemBuilder: (context, category) {
                final isActive = category.status == 'Active';
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isActive
                          ? colorScheme.primaryContainer
                          : colorScheme.errorContainer,
                      child: Icon(
                        Icons.category,
                        color: isActive
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onErrorContainer,
                      ),
                    ),
                    title: Text(category.name),
                    subtitle: Text(
                      'Status: ${category.status}',
                      style: TextStyle(
                        color: isActive
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: isActive,
                          onChanged: (_) => _toggleStatus(context, category),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: 'Edit',
                          onPressed: () {
                            GuardedNavigator.push(
                              context,
                              permission: ScreenPermission.categoryForm,
                              page: CategoryFormScreen(
                                shopId: _shopId!,
                                category: category,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: colorScheme.error,
                          ),
                          tooltip: 'Delete',
                          onPressed: () => _deleteCategory(context, category),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

