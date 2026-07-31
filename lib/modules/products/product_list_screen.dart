import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';
import '../../core/firestore/firestore_rule_safe_update.dart';
import '../../data/models/product_model.dart';
import '../../widgets/firestore_paginated_list.dart';
import '../../data/models/user_model.dart';
import 'controllers/product_ui_controller.dart';
import '../../routing/guarded_navigator.dart';
import '../../routing/permission_gate.dart';
import '../../routing/screen_permission.dart';
import 'product_form_screen.dart';

/// Product List Screen - Admin view of all products
/// Allows viewing, adding, editing, and disabling products
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final ProductUiController _uiController = Get.put(ProductUiController());
  String? _shopId;
  bool _isLoading = true;

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
          _isLoading = false;
        });
        _uiController.setLoading(false);
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
      _uiController.setLoading(false);
    }
  }

  Future<void> _toggleProductStatus(
    BuildContext pageContext,
    ProductModel product,
  ) async {
    try {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: ScreenPermission.productList,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Products')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              GuardedNavigator.push(
                context,
                permission: ScreenPermission.productForm,
                page: ProductFormScreen(),
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

          // Filter chips
          SizedBox(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildFilterChip('all', 'All'),
                  _buildFilterChip('Active', 'Active'),
                  _buildFilterChip('Inactive', 'Inactive'),
                  _buildFilterChip('low-stock', 'Low Stock'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: Obx(
              () => FirestorePaginatedList<ProductModel>(
                cacheKey: 'products_legacy_$_shopId',
                queryBuilder: () => FirebaseFirestore.instance
                    .collection('products')
                    .where('shopId', isEqualTo: _shopId)
                    .orderBy('name'),
                parse: (data, _) => ProductModel.tryFromMap(data),
                itemKey: (p) => p.productId,
                filterItems: (items) {
                  var filtered = items;
                  final q = _uiController.searchQuery.value.trim().toLowerCase();
                  if (q.isNotEmpty) {
                    filtered = filtered
                        .where((p) => p.name.toLowerCase().contains(q))
                        .toList();
                  }
                  final f = _uiController.selectedFilter.value;
                  if (f == 'Active') {
                    filtered =
                        filtered.where((p) => p.status == 'Active').toList();
                  } else if (f == 'Inactive') {
                    filtered =
                        filtered.where((p) => p.status == 'Inactive').toList();
                  } else if (f == 'low-stock') {
                    filtered =
                        filtered.where((p) => p.stock <= 10).toList();
                  }
                  return filtered;
                },
                emptyBuilder: (context) => const Center(
                  child: Text('No products match your filters'),
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
            selected: _uiController.selectedFilter.value == value,
            onSelected: (selected) {
              if (selected) {
                _uiController.setSelectedFilter(value);
              }
            },
          ),
        ));
  }

  Widget _buildProductCard(BuildContext context, ProductModel product) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLowStock = product.stock <= 10;
    final isDisabled = product.status == 'Inactive';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isDisabled
              ? colorScheme.errorContainer
              : isLowStock
                  ? colorScheme.errorContainer
                  : colorScheme.primaryContainer,
          child: Icon(
            isDisabled
                ? Icons.block
                : isLowStock
                    ? Icons.warning
                    : Icons.inventory_2,
            color: isDisabled
                ? colorScheme.onErrorContainer
                : isLowStock
                    ? colorScheme.onErrorContainer
                    : colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          product.name,
          style: TextStyle(
            decoration: isDisabled ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Price: ₹${product.price.toStringAsFixed(2)}'),
            Text('Stock: ${product.stock.toStringAsFixed(2)} ${product.measurementType}'),
            if (isLowStock && !isDisabled)
              Text(
                'Low Stock!',
                style: TextStyle(
                  color: colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
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
                    product.status == 'Active' ? Icons.block : Icons.check_circle,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(product.status == 'Active' ? 'Disable' : 'Enable'),
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
      ),
    );
  }

  Future<void> _deleteProduct(BuildContext pageContext, ProductModel product) async {
    final confirm = await showDialog<bool>(
      context: pageContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to soft-delete "${product.name}"?'),
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
      final callable = FirebaseFunctions.instance.httpsCallable('deleteProduct');
      await callable.call(<String, dynamic>{
        'productId': product.productId,
        'shopId': product.shopId,
      });
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(content: Text('Product deleted successfully')),
      );
    } catch (e) {
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(content: Text('Failed to delete product: $e')),
      );
    }
  }
}
