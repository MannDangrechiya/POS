/// RBAC permissions for sub-screens (beyond top-level [AppRoutes] dashboards).
///
/// Used by [GuardedNavigator] and [PermissionGate]. Aligns with
/// [RoleBasedRouter] role strings: SuperAdmin, Admin, Employee, Viewer.
enum ScreenPermission {
  /// Accessible without authentication (login flow only).
  public,

  // ── Employee POS ──────────────────────────────────────────────────────────
  posHome,
  cart,
  payment,
  customerSelect,
  scanProduct,
  receipt,
  dailySalesSummary,

  // ── Admin shop management ───────────────────────────────────────────────────
  adminDashboard,
  productList,
  productForm,
  inventory,
  inventoryAdjustment,
  lowStockAlerts,
  employeeList,
  employeeForm,
  categoryList,
  categoryForm,
  expenseList,
  expenseForm,
  customerList,
  customerDetail,
  adminSettings,

  // ── Reports & orders (read-heavy; role-scoped data in Firestore) ───────────
  reportsDashboard,
  salesReport,
  productSalesReport,
  employeePerformanceReport,
  expenseReport,
  orderHistory,
  orderDetail,

  // ── Audit (Admin + SuperAdmin) ────────────────────────────────────────────
  auditLogs,

  // ── Super Admin ─────────────────────────────────────────────────────────────
  superAdminDashboard,
  createShop,
  shopList,
  shopDetail,
  createAdmin,
  userManagement,
  globalReports,
  systemSettings,
}

/// Maps each [ScreenPermission] to roles allowed to open that screen.
class ScreenPermissionPolicy {
  ScreenPermissionPolicy._();

  static const Set<String> _superAdminOnly = {'SuperAdmin'};
  static const Set<String> _adminOnly = {'Admin'};
  static const Set<String> _employeeOnly = {'Employee'};
  static const Set<String> _adminAndSuperAdmin = {'Admin', 'SuperAdmin'};
  static const Set<String> _reportsRoles = {'Admin', 'Viewer', 'SuperAdmin'};
  static const Set<String> _orderHistoryRoles = {'Admin', 'Employee', 'Viewer', 'SuperAdmin'};

  static Set<String> allowedRoles(ScreenPermission permission) {
    switch (permission) {
      case ScreenPermission.public:
        return {};

      case ScreenPermission.posHome:
      case ScreenPermission.cart:
      case ScreenPermission.payment:
      case ScreenPermission.customerSelect:
      case ScreenPermission.scanProduct:
      case ScreenPermission.receipt:
      case ScreenPermission.dailySalesSummary:
        return _employeeOnly;

      case ScreenPermission.adminDashboard:
      case ScreenPermission.productList:
      case ScreenPermission.productForm:
      case ScreenPermission.inventory:
      case ScreenPermission.inventoryAdjustment:
      case ScreenPermission.employeeList:
      case ScreenPermission.employeeForm:
      case ScreenPermission.categoryList:
      case ScreenPermission.categoryForm:
      case ScreenPermission.expenseList:
      case ScreenPermission.expenseForm:
      case ScreenPermission.customerList:
      case ScreenPermission.customerDetail:
      case ScreenPermission.adminSettings:
        return _adminOnly;

      case ScreenPermission.reportsDashboard:
      case ScreenPermission.salesReport:
      case ScreenPermission.productSalesReport:
      case ScreenPermission.employeePerformanceReport:
      case ScreenPermission.expenseReport:
        return _reportsRoles;

      case ScreenPermission.orderHistory:
      case ScreenPermission.orderDetail:
        return _orderHistoryRoles;

      case ScreenPermission.auditLogs:
      case ScreenPermission.lowStockAlerts:
        return _adminAndSuperAdmin;

      case ScreenPermission.superAdminDashboard:
      case ScreenPermission.createShop:
      case ScreenPermission.shopList:
      case ScreenPermission.shopDetail:
      case ScreenPermission.createAdmin:
      case ScreenPermission.userManagement:
      case ScreenPermission.globalReports:
      case ScreenPermission.systemSettings:
        return _superAdminOnly;
    }
  }

  static bool isAllowed(String role, ScreenPermission permission) {
    if (permission == ScreenPermission.public) return true;
    final allowed = allowedRoles(permission);
    return allowed.isNotEmpty && allowed.contains(role);
  }
}
