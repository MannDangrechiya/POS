import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';
import '../../../core/firestore/firestore_rule_safe_update.dart';
import '../../../data/models/product_model.dart';
import '../../../widgets/firestore_paginated_list.dart';
import '../../../data/models/user_model.dart';
import 'product_controller.dart';
import '../../../routing/guarded_navigator.dart';
import '../../../routing/screen_permission.dart';
import 'product_form_screen.dart';

/// Product List Screen - Admin view of all products
/// Allows viewing, adding, editing, and toggling product status
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final ProductController _controller = Get.put(ProductController());
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

  Future<void> _toggleProductStatus(
    BuildContext pageContext,
    ProductModel product,
  ) async {
    try {
      _controller.setLoading(true);
      await FirebaseFirestore.instance
          .collection('products')
          .doc(product.productId)
          .update(
            FirestoreRuleSafeUpdate.product(
              product,
              changes: {
                'status': product.status == 'Active' ? 'Inactive' : 'Active',
              },
            ),
          );

      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(
              'Product ${product.status == 'Active' ? 'deactivated' : 'activated'}',
            ),
          ),
        );
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Error updating product: $e')),
        );
      }
    } finally {
      _controller.setLoading(false);
    }
  }

  /// Super Admin only. Soft-deletes the product (status -> 'Deleted') via the
  /// deleteProduct Cloud Function so history stays resolvable in past orders
  /// and the deletion is audit-logged (see deleteProduct.ts for rationale).
  Future<void> _deleteProduct(
    BuildContext pageContext,
    ProductModel product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          'Delete "${product.name}"? It will no longer be sellable or '
          'listed, but will remain visible in past orders.',
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
      await FirebaseFunctions.instance.httpsCallable('deleteProduct').call(
        <String, dynamic>{
          'productId': product.productId,
          'shopId': product.shopId,
        },
      );
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Product "${product.name}" deleted')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text('Error deleting product: ${e.message ?? e.code}'),
          ),
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
        appBar: AppBar(title: const Text('Products')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              GuardedNavigator.push(
                context,
                permission: ScreenPermission.productForm,
                page: const ProductFormScreen(),
              );
            },
            tooltip: 'Add Product',
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
                hintText: 'Search products...',
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
          Obx(() => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildFilterChip('all', 'All'),
                    _buildFilterChip('Active', 'Active'),
                    _buildFilterChip('Inactive', 'Inactive'),
                  ],
                ),
              )),

          const SizedBox(height: 8),

          Expanded(
            child: Obx(
              () => FirestorePaginatedList<ProductModel>(
                cacheKey: 'products_admin_$_shopId',
                queryBuilder: () => FirebaseFirestore.instance
                    .collection('products')
                    .where('shopId', isEqualTo: _shopId)
                    .orderBy('name'),
                parse: (data, _) => ProductModel.tryFromMap(data),
                itemKey: (p) => p.productId,
                filterItems: (items) {
                  // Soft-deleted products (status: 'Deleted') never appear in
                  // the management list — they only remain resolvable by ID
                  // for historical order lookups.
                  var filtered =
                      items.where((p) => p.status != 'Deleted').toList();
                  final q = _controller.searchQuery.value.trim().toLowerCase();
                  if (q.isNotEmpty) {
                    filtered = filtered
                        .where((p) => p.name.toLowerCase().contains(q))
                        .toList();
                  }
                  final f = _controller.selectedFilter.value;
                  if (f == 'Active') {
                    filtered =
                        filtered.where((p) => p.status == 'Active').toList();
                  } else if (f == 'Inactive') {
                    filtered =
                        filtered.where((p) => p.status == 'Inactive').toList();
                  }
                  return filtered;
                },
                emptyBuilder: (context) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No products found',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                itemBuilder: (context, product) =>
                    _buildProductCard(context, product),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    return Obx(() => Padding(
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
        ));
  }

  Widget _buildProductCard(BuildContext context, ProductModel product) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = product.status == 'Active';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive
              ? colorScheme.primaryContainer
              : colorScheme.errorContainer,
          child: Icon(
            isActive ? Icons.inventory_2 : Icons.block,
            color: isActive
                ? colorScheme.onPrimaryContainer
                : colorScheme.onErrorContainer,
          ),
        ),
        title: Text(
          product.name,
          style: TextStyle(
            decoration: !isActive ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Price: ₹${product.price.toStringAsFixed(2)}'),
            Text('Unit: ${product.measurementType}'),
            Text('Stock: ${product.stock.toStringAsFixed(2)}'),
            const SizedBox(height: 4),
            Chip(
              label: Text(
                product.status.toUpperCase(),
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: isActive
                  ? colorScheme.primaryContainer
                  : colorScheme.errorContainer,
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') {
              GuardedNavigator.push(
                context,
                permission: ScreenPermission.productForm,
                page: ProductFormScreen(product: product),
              );
            } else if (value == 'toggle') {
              _toggleProductStatus(context, product);
            } else if (value == 'delete') {
              _deleteProduct(context, product);
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
                  Icon(
                    isActive ? Icons.block : Icons.check_circle,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(isActive ? 'Deactivate' : 'Activate'),
                ],
              ),
            ),
            // Delete is Super Admin only (Requirement in Detail §26.2/§5.1 —
            // Admin can disable but never delete).
            if (_isSuperAdmin)
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Delete',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
