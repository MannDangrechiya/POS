/**
 * Employee Deletion Cloud Function
 *
 * LOCATION: firebase/functions/src/auth/deleteEmployee.ts
 *
 * WHY THIS EXISTS:
 * Firestore rules deny `delete` on the `users` collection unconditionally
 * ("no role, including SuperAdmin, may delete a user") and no Cloud Function
 * existed to remove an employee any other way. Requirement in Detail §28.2
 * grants Super Admin a delete capability on employees that Admin does not
 * have, while §28.3 requires "Deletion does NOT remove historical data" —
 * employee sales/order history must remain intact (orders reference
 * employeeId directly).
 *
 * WHY SOFT DELETE, NOT A HARD DELETE / NOT AUTH ACCOUNT REMOVAL:
 * Hard-deleting the Firestore user doc (or the Firebase Auth account) would
 * break every historical order/audit-log lookup that resolves employeeId ->
 * name. Soft-deleting (status: 'Deleted') keeps the document resolvable,
 * blocks login (isActive requires status === 'Active', same as
 * Inactive/Suspended), and hides the employee from the regular employee list
 * — while preserving all their order/sales history exactly as before.
 *
 * Mirrors the SuperAdmin-only soft-delete pattern used in deleteProduct.ts.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { validateSuperAdmin } from '../utils/roleValidation';
import { validateRequiredString } from '../utils/validation';
import { createAuditLog } from '../utils/auditLogger';

const db = admin.firestore();

interface DeleteEmployeeRequest {
  userId: string;
  shopId: string;
}

export const deleteEmployee = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const callerId = context.auth.uid;
  const req = data as DeleteEmployeeRequest;
  const targetUserId = validateRequiredString(req?.userId, 'userId');
  const shopId = validateRequiredString(req?.shopId, 'shopId');

  try {
    // Only Super Admin may delete employees (Admin can only activate/deactivate).
    const caller = await validateSuperAdmin(callerId);

    const userRef = db.collection('users').doc(targetUserId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Employee not found');
    }

    const target = userSnap.data()!;
    if (target.shopId !== shopId) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Employee does not belong to this shop'
      );
    }
    if (target.role !== 'Employee') {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Only Employee accounts can be deleted through this function'
      );
    }
    if (target.status === 'Deleted') {
      throw new functions.https.HttpsError('failed-precondition', 'Employee already deleted');
    }

    await userRef.update({ status: 'Deleted' });

    // Disable the Firebase Auth account too so the (blocked-by-status) login
    // path can never be raced by a still-valid session token.
    try {
      await admin.auth().updateUser(targetUserId, { disabled: true });
    } catch (authErr: any) {
      console.error(`Failed to disable Auth account for deleted employee ${targetUserId}:`, authErr?.message);
    }

    await createAuditLog(caller, 'employee_delete', 'user', targetUserId, {
      name: target.name,
      email: target.email,
      shopId,
      previousStatus: target.status,
    });

    return { success: true, userId: targetUserId };
  } catch (err: any) {
    if (err instanceof functions.https.HttpsError) throw err;
    if (err instanceof Error && err.message.includes('Access denied')) {
      throw new functions.https.HttpsError('permission-denied', err.message);
    }
    throw new functions.https.HttpsError('internal', err?.message ?? 'Failed to delete employee');
  }
});
