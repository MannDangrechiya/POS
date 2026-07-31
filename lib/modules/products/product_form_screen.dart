import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firestore/firestore_rule_safe_update.dart';
import '../../data/models/product_model.dart';
import '../../data/models/user_model.dart';

/// Product Form Screen - Add or Edit Product
/// Allows Admin to create new products or edit existing ones
class ProductFormScreen extends StatefulWidget {
  final ProductModel? product;

  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  String? _shopId;
  String _measurementType = 'kg';
  bool _isLoading = false;
  bool _isEditing = false;

  final List<String> _measurementTypes = ['kg', 'gm', 'piece', 'box'];

  @override
  void initState() {
    super.initState();
    _isEditing = widget.product != null;
    if (_isEditing && widget.product != null) {
      _nameController.text = widget.product!.name;
      _priceController.text = widget.product!.price.toString();
      _stockController.text = widget.product!.stock.toString();
      _measurementType = widget.product!.measurementType;
    }
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
        });
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Error loading user data: $e')),
        );
      }
    }
  }

  Future<void> _saveProduct(BuildContext pageContext) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_shopId == null) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(content: Text('Shop ID not found')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final price = double.parse(_priceController.text);

      if (price <= 0) {
        throw Exception('Price must be greater than zero');
      }

      final name = _nameController.text.trim();

      // Check product name uniqueness per shop (§26.4 requirement)
      final existingQuery = await FirebaseFirestore.instance
          .collection('products')
          .where('shopId', isEqualTo: _shopId)
          .where('name', isEqualTo: name)
          .get();

      final currentProductId = widget.product?.productId;
      final duplicates = existingQuery.docs.where((doc) => doc.id != currentProductId);
      if (duplicates.isNotEmpty) {
        throw Exception('A product with the name "$name" already exists in this shop.');
      }

      if (_isEditing && widget.product != null) {
        // Update existing product (stock is immutable on client — use adjustStock)
        await FirebaseFirestore.instance
            .collection('products')
            .doc(widget.product!.productId)
            .update(
              FirestoreRuleSafeUpdate.product(
                widget.product!,
                changes: {
                  'name': _nameController.text.trim(),
                  'price': price,
                },
              ),
            );

        if (pageContext.mounted) {
          ScaffoldMessenger.of(pageContext).showSnackBar(
            const SnackBar(content: Text('Product updated successfully')),
          );
          Navigator.of(pageContext).pop();
        }
      } else {
        // Create new product (initial stock allowed on create per Firestore rules)
        final stock = double.parse(_stockController.text);
        if (stock < 0) {
          throw Exception('Stock cannot be negative');
        }

        final productId = FirebaseFirestore.instance
            .collection('products')
            .doc()
            .id;

        await FirebaseFirestore.instance
            .collection('products')
            .doc(productId)
            .set({
          'productId': productId,
          'shopId': _shopId!,
          'name': _nameController.text.trim(),
          'price': price,
          'measurementType': _measurementType,
          'stock': stock,
          'status': 'Active',
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (pageContext.mounted) {
          ScaffoldMessenger.of(pageContext).showSnackBar(
            const SnackBar(content: Text('Product created successfully')),
          );
          Navigator.of(pageContext).pop();
        }
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Error saving product: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Product' : 'Add Product'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Product Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.inventory_2),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Product name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Price (₹)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Price is required';
                  }
                  final price = double.tryParse(value);
                  if (price == null || price <= 0) {
                    return 'Price must be greater than zero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (!_isEditing) ...[
                DropdownButtonFormField<String>(
                  initialValue: _measurementType,
                  decoration: const InputDecoration(
                    labelText: 'Measurement Type',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.straighten),
                  ),
                  items: _measurementTypes.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _measurementType = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
              ] else ...[
                TextFormField(
                  initialValue: _measurementType.toUpperCase(),
                  decoration: const InputDecoration(
                    labelText: 'Measurement Type',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.straighten),
                  ),
                  enabled: false,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _stockController,
                decoration: InputDecoration(
                  labelText: _isEditing ? 'Current Stock' : 'Stock Quantity',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.warehouse),
                  helperText: _isEditing
                      ? 'Use Inventory Adjustment to change stock'
                      : null,
                ),
                keyboardType: TextInputType.number,
                readOnly: _isEditing,
                enabled: !_isEditing,
                validator: (value) {
                  if (_isEditing) return null;
                  if (value == null || value.trim().isEmpty) {
                    return 'Stock quantity is required';
                  }
                  final stock = double.tryParse(value);
                  if (stock == null || stock < 0) {
                    return 'Stock cannot be negative';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _isLoading ? null : () => _saveProduct(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditing ? 'Update Product' : 'Create Product'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
