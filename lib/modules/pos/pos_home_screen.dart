import 'package:flutter/material.dart';
import '../../core/observability/error_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:pos_system/modules/pos/daily_sales_summary_screen.dart';
import 'scan_product_screen.dart';
import '../../core/firestore/firestore_pagination.dart';
import '../../core/firestore/firestore_parse.dart';
import '../../core/firestore/firestore_stream_cache.dart';
import '../../data/models/product_model.dart';
import '../../data/models/user_model.dart';
import '../authentication/auth_controller.dart';
import 'controllers/cart_controller.dart';
import 'widgets/product_card.dart';
import 'widgets/category_chip.dart';
import 'widgets/cart_fab.dart';
import 'widgets/hardware_barcode_listener.dart';
import 'widgets/live_cart_pane.dart';
import 'widgets/hold_orders_dialog.dart';
import 'widgets/open_shift_dialog.dart';
import 'widgets/cash_movement_dialog.dart';
import 'widgets/close_shift_dialog.dart';
import 'controllers/shift_controller.dart';
import 'quantity_selection_dialog.dart';
import 'cart_screen.dart';
import '../../routing/guarded_navigator.dart';
import '../../routing/permission_gate.dart';
import '../../routing/screen_permission.dart';
import '../../core/hardware/printer_service.dart';
import '../../core/hardware/cfd_service.dart';
import 'cfd/customer_facing_display_screen.dart';
import '../settings/hardware_settings_screen.dart';
import '../../core/offline/offline_order_queue.dart';
import 'khata/customer_ledger_screen.dart';
import 'returns/returns_screen.dart';

/// POS Home Screen - Primary working screen for employees
/// Displays products, categories, search, and cart access
class PosHomeScreen extends StatefulWidget {
  const PosHomeScreen({super.key});

  @override
  State<PosHomeScreen> createState() => _PosHomeScreenState();
}

class _PosHomeScreenState extends State<PosHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'all';
  String _searchQuery = '';
  String? _shopId;
  UserModel? _userData;
  bool _isLoading = true;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _categoriesStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _productsStream;

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
          Navigator.of(pageContext).pushReplacementNamed('/login');
        }
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = UserModel.tryFromDocument(userDoc);
        if (userData == null) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          return;
        }
        if (!mounted) return;
        setState(() {
          _shopId = userData.shopId;
          _userData = userData;
          _isLoading = false;
          _initPosStreams();
        });
        // Check active cashier shift
        ShiftController.instance.checkActiveShift(userData.shopId, user.uid);
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    } catch (e, st) {
      if (pageContext.mounted) {
        showErrorSnackBar(
          pageContext,
          e,
          stackTrace: st,
          tag: 'PosHomeScreen._loadUser',
        );
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _initPosStreams() {
    if (_shopId == null || _shopId!.isEmpty) return;
    final db = FirebaseFirestore.instance;
    final cache = FirestoreStreamCache.instance;
    _categoriesStream ??= cache.querySnapshots(
      firstPageQuery(
        db
            .collection('categories')
            .where('shopId', isEqualTo: _shopId)
            .where('status', isEqualTo: 'Active')
            .orderBy('name'),
        pageSize: 200,
      ),
      key: 'pos_categories_$_shopId',
    );
    _productsStream ??= cache.querySnapshots(
      firstPageQuery(
        db
            .collection('products')
            .where('shopId', isEqualTo: _shopId)
            .where('status', isEqualTo: 'Active')
            .orderBy('name'),
        pageSize: FirestorePageSize.posCatalogCap,
      ),
      key: 'pos_products_$_shopId',
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleLogout(BuildContext pageContext) async {
    final confirm = await showDialog<bool>(
      context: pageContext,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await AuthController().signOut();
    if (pageContext.mounted) {
      Navigator.of(pageContext).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  int _gridCrossAxisCount(double width) {
    if (width >= 1200) return 5;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  double _gridMainAxisExtent(double width) {
    if (width >= 900) return 220;
    return 200;
  }

  Future<void> _onHardwareBarcodeScanned(String code) async {
    if (_shopId == null || _shopId!.isEmpty) return;

    ProductModel? matchedProduct;

    try {
      final db = FirebaseFirestore.instance;
      final base =
          db.collection('products').where('shopId', isEqualTo: _shopId);

      // 1. Try barcode field
      var snap = await base.where('barcode', isEqualTo: code).limit(1).get();
      if (snap.docs.isEmpty) {
        // 2. Try productId
        snap = await base.where('productId', isEqualTo: code).limit(1).get();
      }
      if (snap.docs.isEmpty) {
        // 3. Try exact name match
        snap = await base.where('name', isEqualTo: code).limit(1).get();
      }

      if (snap.docs.isNotEmpty) {
        matchedProduct = ProductModel.tryFromQueryDocument(snap.docs.first);
      }
    } catch (_) {}

    if (matchedProduct == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No product found for barcode: $code'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (matchedProduct.stock <= 0 || !matchedProduct.isActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${matchedProduct.name} is unavailable or out of stock'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (matchedProduct.isWeightBased) {
      if (mounted) {
        _onProductTap(context, matchedProduct);
      }
    } else {
      try {
        final cartController = Get.find<CartController>();
        cartController.addItem(matchedProduct, 1.0);
        CfdService.instance.syncWithCart(cartController);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${matchedProduct.name} scanned (+1)'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _onProductTap(BuildContext pageContext, ProductModel product) async {
    // Check stock availability
    if (product.stock <= 0) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(
            content: Text('Product is out of stock'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (product.status != 'Active') {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(
            content: Text('Product is not available'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Show quantity selection dialog
    final quantity = await showDialog<double>(
      context: pageContext,
      builder: (context) => QuantitySelectionDialog(product: product),
    );

    if (quantity == null || quantity <= 0) return;
    try {
      final cartController = Get.find<CartController>();
      cartController.addItem(product, quantity);
      CfdService.instance.syncWithCart(cartController);

      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text('${product.name} added to cart'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e, st) {
      if (pageContext.mounted) {
        showErrorSnackBar(
          pageContext,
          e,
          stackTrace: st,
          tag: 'PosHomeScreen.addToCart',
        );
      }
    }
  }

  void _showOpenDrawerDialog(BuildContext context) async {
    final pinController = TextEditingController();
    final requiresPin = PrinterService.instance.drawerRequiresPin.value;

    if (!requiresPin) {
      final ok = await PrinterService.instance.kickCashDrawer();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Cash drawer opened' : 'Failed to open drawer'),
            backgroundColor: ok ? Colors.green : Colors.red,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.point_of_sale_outlined),
            SizedBox(width: 8),
            Text('Open Cash Drawer'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter Manager PIN to open cash drawer (No Sale):'),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              decoration: const InputDecoration(
                labelText: 'Manager PIN',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              autofocus: true,
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open Drawer'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ok = await PrinterService.instance.kickCashDrawer(
        managerPinInput: pinController.text.trim(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Cash drawer opened' : 'Invalid PIN or printer disconnected'),
            backgroundColor: ok ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleShiftMenu(BuildContext context) async {
    final shiftCtrl = ShiftController.instance;
    final user = FirebaseAuth.instance.currentUser;
    if (_shopId == null || user == null) return;

    final cashierName = _userData?.name ?? user.email ?? 'Cashier';

    if (!shiftCtrl.hasActiveShift) {
      await showDialog(
        context: context,
        builder: (ctx) => OpenShiftDialog(
          shopId: _shopId!,
          cashierId: user.uid,
          cashierName: cashierName,
        ),
      );
      return;
    }

    // Active shift management sheet
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final shift = shiftCtrl.activeShift.value!;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.point_of_sale, color: Colors.green.shade700),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Shift #${shift.shiftId.length > 8 ? shift.shiftId.substring(0, 8) : shift.shiftId}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('Cashier: ${shift.cashierName}',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _shiftStatCol('Opening Float', '₹${shift.openingFloat.toStringAsFixed(0)}'),
                    _shiftStatCol('Cash Sales', '₹${shift.cashSales.toStringAsFixed(0)}'),
                    _shiftStatCol('Expected Cash', '₹${shift.expectedCash.toStringAsFixed(0)}', bold: true),
                  ],
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.payments_outlined, color: Colors.teal),
                  title: const Text('Cash In / Cash Out (Petty Cash)'),
                  subtitle: const Text('Record drawer cash deposit or vendor payout'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      builder: (_) => CashMovementDialog(cashierName: shift.cashierName),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long, color: Colors.deepPurple),
                  title: const Text('Close Shift (Blind Count & Z-Report)'),
                  subtitle: const Text('Blind cash count, audit variance, print report'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      builder: (_) => CloseShiftDialog(shopName: 'Fruit POS Store'),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _shiftStatCol(String label, String val, {bool bold = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(val, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: 14)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: ScreenPermission.posHome,
      child: _buildPosContent(context),
    );
  }

  Widget _buildPosContent(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    if (_shopId == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              const Text('Unable to load shop information'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _loadUserData(context),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final cartController = Get.find<CartController>();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('POS System'),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          // Cashier Shift Status & Operations Button
          Obx(() {
            final shiftCtrl = ShiftController.instance;
            final activeShift = shiftCtrl.activeShift.value;
            final isOpen = shiftCtrl.hasActiveShift;

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: isOpen ? Colors.green.shade50 : Colors.amber.shade50,
                  foregroundColor: isOpen ? Colors.green.shade800 : Colors.amber.shade900,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isOpen ? Colors.green.shade300 : Colors.amber.shade400,
                    ),
                  ),
                ),
                icon: Icon(
                  isOpen ? Icons.check_circle : Icons.warning_amber_rounded,
                  size: 16,
                  color: isOpen ? Colors.green.shade700 : Colors.amber.shade800,
                ),
                label: Text(
                  isOpen
                      ? 'Shift #${activeShift!.shiftId.length > 5 ? activeShift.shiftId.substring(0, 5) : activeShift.shiftId}'
                      : 'Open Shift',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                onPressed: () => _handleShiftMenu(context),
              ),
            );
          }),
          // Offline sync queue status badge
          Obx(() {
            final queue = OfflineOrderQueue.instance;
            final count = queue.pendingCount.value;
            final isSyncing = queue.isSyncing.value;
            if (count == 0) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: isSyncing ? Colors.blue.shade50 : Colors.orange.shade50,
                  foregroundColor: isSyncing ? Colors.blue.shade800 : Colors.orange.shade900,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: isSyncing ? Colors.blue.shade300 : Colors.orange.shade400),
                  ),
                ),
                icon: isSyncing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined, size: 16),
                label: Text(
                  isSyncing ? 'Syncing...' : 'Offline ($count)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                onPressed: isSyncing ? null : () => queue.syncPendingOrders(),
              ),
            );
          }),
          Obx(() {
            return Badge(
              label: Text('${cartController.parkedCount}'),
              isLabelVisible: cartController.parkedCount > 0,
              child: IconButton(
                icon: const Icon(Icons.receipt_long_outlined),
                onPressed: () => HoldOrdersDialog.show(context),
                tooltip: 'Parked Orders (Hold Bills)',
              ),
            );
          }),
          IconButton(
            icon: const Icon(Icons.assignment_return_outlined),
            onPressed: () {
              if (_shopId == null) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => ReturnsScreen(shopId: _shopId!),
                ),
              );
            },
            tooltip: 'Returns & Refunds',
          ),
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () {
              if (_shopId == null) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => CustomerLedgerScreen(shopId: _shopId!),
                ),
              );
            },
            tooltip: 'Customer Khata / Credit Ledger',
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              if (_shopId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Shop not loaded yet'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              GuardedNavigator.push(
                context,
                permission: ScreenPermission.scanProduct,
                page: ScanProductScreen(
                  shopId: _shopId!,
                  onProductScanned: (product) =>
                      _onProductTap(context, product),
                ),
              );
            },
            tooltip: 'Scan product barcode',
          ),
          IconButton(
            icon: const Icon(Icons.point_of_sale_outlined),
            onPressed: () => _showOpenDrawerDialog(context),
            tooltip: 'Open Cash Drawer (No Sale)',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.devices_other_outlined),
            tooltip: 'Hardware & Devices',
            onSelected: (val) {
              if (val == 'cfd') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => const CustomerFacingDisplayScreen(),
                  ),
                );
              } else if (val == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => const HardwareSettingsScreen(),
                  ),
                );
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'cfd',
                child: Row(
                  children: [
                    Icon(Icons.tv_outlined),
                    SizedBox(width: 8),
                    Text('Customer Display (CFD)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined),
                    SizedBox(width: 8),
                    Text('Hardware Settings'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
              GuardedNavigator.push(
                context,
                permission: ScreenPermission.dailySalesSummary,
                page: const DailySalesSummaryScreen(),
              );
            },
            tooltip: 'Daily Sales Summary',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(context),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: HardwareBarcodeListener(
        onBarcodeScanned: _onHardwareBarcodeScanned,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWidescreen = constraints.maxWidth >= 850;

            if (isWidescreen) {
              return Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: _buildCatalogSection(context),
                  ),
                  SizedBox(
                    width: 380,
                    child: LiveCartPane(shopId: _shopId ?? ''),
                  ),
                ],
              );
            }

            return _buildCatalogSection(context);
          },
        ),
      ),
      floatingActionButton: Obx(() {
        final isWidescreen = MediaQuery.of(context).size.width >= 850;
        if (isWidescreen || cartController.isEmpty) {
          return const SizedBox.shrink();
        }
        return CartFAB(
          itemCount: cartController.itemCount,
          totalAmount: cartController.totalAmount,
          onTap: () {
            GuardedNavigator.push(
              context,
              permission: ScreenPermission.cart,
              page: const CartScreen(),
            );
          },
        );
      }),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildCatalogSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search and category filters
        Material(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by product name...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _categoriesStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 44,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      final categories = snapshot.data!.docs;
                      final categoryList = [
                        {'categoryId': 'all', 'name': 'All'},
                        ...categories
                            .map((doc) => FirestoreParse.queryDocumentData(doc))
                            .whereType<Map<String, dynamic>>(),
                      ];

                      return SizedBox(
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: categoryList.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final category = categoryList[index];
                            final isSelected =
                                _selectedCategory ==
                                (category['categoryId'] ?? 'all');

                            return CategoryChip(
                              label: category['name'] ?? 'All',
                              isSelected: isSelected,
                              onTap: () {
                                setState(() {
                                  _selectedCategory =
                                      category['categoryId'] ?? 'all';
                                });
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _productsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text('Error loading products: ${snapshot.error}'),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState(
                    context,
                    icon: Icons.inventory_2_outlined,
                    title: 'No products available',
                    subtitle: 'Products will appear here once added by admin',
                  );
                }

                // Filter products
                final allProducts = FirestoreParse.parseQueryDocs(
                  snapshot.data!.docs,
                  ProductModel.tryFromMap,
                );

                var filteredProducts = allProducts;

                // Filter by search query
                if (_searchQuery.isNotEmpty) {
                  filteredProducts = filteredProducts
                      .where(
                        (product) =>
                            product.name.toLowerCase().contains(_searchQuery),
                      )
                      .toList();
                }

                // Filter by category
                if (_selectedCategory != 'all') {
                  filteredProducts = filteredProducts
                      .where(
                        (product) => product.categoryId == _selectedCategory,
                      )
                      .toList();
                }
                // Filter out-of-stock products (show but disabled)
                // Actually, show all products but mark out-of-stock

                if (filteredProducts.isEmpty) {
                  return _buildEmptyState(
                    context,
                    icon: Icons.search_off_rounded,
                    title: 'No products found',
                    subtitle: 'Try another search or category',
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = _gridCrossAxisCount(width);
                    final mainAxisExtent = _gridMainAxisExtent(width);

                    return CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Row(
                              children: [
                                Text(
                                  'Products',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${filteredProducts.length} items',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Obx(() {
                          final cartController = Get.find<CartController>();
                          return SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              cartController.isEmpty ? 16.0 : 88.0,
                            ),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    mainAxisExtent: mainAxisExtent,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final product = filteredProducts[index];
                                return ProductCard(
                                  product: product,
                                  onTap: () =>
                                      _onProductTap(context, product),
                                );
                              }, childCount: filteredProducts.length),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 72,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
