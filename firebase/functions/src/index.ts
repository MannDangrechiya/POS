/**
 * Firebase Cloud Functions Entry Point
 * 
 * LOCATION: firebase/functions/src/index.ts
 * 
 * REQUIREMENTS:
 * - Export confirmOrder
 * - Export cancelOrder
 * - Export inventoryLogs
 * - Export expenseAudit
 * - Export auth_audit
 * 
 * This file exports all Cloud Functions for the POS System.
 * 
 * STRICT RULES:
 * - All critical business rules are enforced in individual functions
 * - Never trust frontend data
 * - Validate role and shopId in every function
 * - Use Firestore transactions for atomic operations
 * - Write audit logs for all critical actions
 * 
 * Based on TECHNICAL REQUIREMENTS IN DETAIL.md
 */

import * as admin from 'firebase-admin';

// Initialize Firebase Admin
admin.initializeApp();

// ============================================================================
// ORDER FUNCTIONS
// ============================================================================

// Export confirmOrder - Confirms order and deducts inventory atomically
export { confirmOrder } from './orders/confirmOrder';

// Export cancelOrder - Cancels pending orders (Admin/Super Admin only)
export { cancelOrder } from './orders/cancelOrder';

// ============================================================================
// INVENTORY LOGS
// ============================================================================

// Export inventory logging functions
export {
  createInventoryLog,
  createInventoryLogsBatch,
  getInventoryLogsForProduct,
  getInventoryLogsForShop,
} from './inventory/inventoryLogs';

// Inventory adjustment callable (Admin/SuperAdmin only)
export { adjustStock } from './inventory/adjustStock';

// Low-stock alert trigger (fires on every product stock change)
export { onProductStockChange } from './inventory/lowStockAlerts';

// ============================================================================
// EXPENSE AUDIT FUNCTIONS
// ============================================================================

// Export expense callable functions (create/update with role validation)
export {
  createOrUpdateExpense,
  createExpense,
  updateExpense,
} from './expenses/expenseAudit';

// Export expense Firestore triggers (backup audit logging)
export {
  onExpenseCreate,
  onExpenseUpdate,
  onExpenseDelete,
} from './expenses/expenseAudit';

// ============================================================================
// AUTHENTICATION AUDIT FUNCTIONS
// ============================================================================

// Export authentication audit callable functions
export {
  logLoginSuccess,
  logLoginFailure,
  logLogout,
  logPasswordResetRequest,
  logPasswordResetComplete,
  logAuthEvent,
  bootstrapFirstUser,
} from './auth/auth_audit';

// Session management (concurrent login restriction)
export {
  setActiveSession,
} from './auth/session';

// Login failure lockout system
export {
  recordLoginFailure,
  resetLoginFailure,
  checkLoginLockout,
} from './auth/loginLockout';

// Export authentication Firestore triggers
export {
  onUserStatusChange,
} from './auth/auth_audit';

// Super Admin: create Admin user (Auth + Firestore)
export { createAdminUser } from './auth/createAdminUser';

// Admin / Super Admin: create Employee user (Auth + Firestore; caller stays signed in)
export { createEmployeeUser } from './auth/createEmployeeUser';

// Super Admin only: soft-delete an Employee (status -> 'Deleted')
export { deleteEmployee } from './auth/deleteEmployee';

// ============================================================================
// PRODUCT TRIGGERS
// ============================================================================

// Export product price change trigger
export { onPriceChange } from './products/onPriceChange';

// Super Admin only: soft-delete a product (status -> 'Deleted')
export { deleteProduct } from './products/deleteProduct';
