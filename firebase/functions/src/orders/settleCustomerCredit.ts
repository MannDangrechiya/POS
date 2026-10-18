/**
 * settleCustomerCredit Cloud Function
 *
 * Callable HTTPS. Allows Employee or Admin to accept partial or full Khata / Udhar
 * settlement payments from a customer.
 *
 * Atomically updates customer balance, creates a credit ledger entry,
 * records shift cash collection (if cash payment), and creates an audit log.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { Customer } from '../types';
import { validateRequiredString } from '../utils/validation';

const db = admin.firestore();

interface SettleCustomerCreditPayload {
  customerId: string;
  shopId: string;
  amountPaid: number;
  paymentMethod: string; // 'cash' | 'upi' | 'card'
  shiftId?: string;
  notes?: string;
}

export const settleCustomerCredit = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated'
    );
  }

  const userId = context.auth.uid;
  const payload = data as SettleCustomerCreditPayload;

  const shopId = validateRequiredString(payload?.shopId, 'shopId');
  const customerId = validateRequiredString(payload?.customerId, 'customerId');
  const paymentMethod = validateRequiredString(payload?.paymentMethod, 'paymentMethod');

  if (typeof payload?.amountPaid !== 'number' || payload.amountPaid <= 0) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'amountPaid must be a positive number'
    );
  }

  const validMethods = ['cash', 'upi', 'card'];
  if (!validMethods.includes(paymentMethod.toLowerCase())) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'paymentMethod must be one of: cash, upi, card'
    );
  }

  // Validate caller is an active Employee or Admin in this shop
  const userSnap = await db.collection('users').doc(userId).get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'User profile not found');
  }
  const userData = userSnap.data();
  if (!userData || (userData.status !== 'Active' && userData.status !== true)) {
    throw new functions.https.HttpsError('permission-denied', 'User account is inactive');
  }

  const isSuperAdmin = userData.role === 'SuperAdmin';
  if (!isSuperAdmin && userData.shopId !== shopId) {
    throw new functions.https.HttpsError('permission-denied', 'User does not belong to this shop');
  }

  try {
    const result = await db.runTransaction(async (transaction) => {
      const now = admin.firestore.Timestamp.now();

      // 1. Fetch customer
      const customerRef = db.collection('customers').doc(customerId);
      const customerSnap = await transaction.get(customerRef);
      if (!customerSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Customer not found');
      }

      const customer = customerSnap.data() as Customer;
      if (customer.shopId !== shopId) {
        throw new functions.https.HttpsError('permission-denied', 'Customer does not belong to this shop');
      }

      const currentBalance = typeof customer.currentBalance === 'number' ? customer.currentBalance : 0.0;
      if (currentBalance <= 0) {
        throw new functions.https.HttpsError('failed-precondition', 'Customer has no outstanding credit balance to settle');
      }

      if (payload.amountPaid > currentBalance + 0.05) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          `Amount paid (Rs.${payload.amountPaid.toFixed(2)}) exceeds current outstanding balance (Rs.${currentBalance.toFixed(2)})`
        );
      }

      const newBalance = Math.max(0, currentBalance - payload.amountPaid);

      // 2. Write credit ledger record (type: 'credit' decreases customer debt)
      const ledgerRef = db.collection('credit_ledgers').doc();
      const ledgerId = ledgerRef.id;

      transaction.set(ledgerRef, {
        ledgerId,
        customerId,
        shopId,
        type: 'credit',
        amount: payload.amountPaid,
        balanceAfter: newBalance,
        paymentMethod: paymentMethod.toLowerCase(),
        description: `Khata settlement (${paymentMethod.toUpperCase()})${payload.notes ? `: ${payload.notes}` : ''}`,
        createdBy: userId,
        createdAt: now,
      });

      // 3. Update customer's currentBalance
      transaction.update(customerRef, {
        currentBalance: newBalance,
      });

      // 4. If active shift provided, accumulate into shift drawer
      if (payload.shiftId) {
        const shiftRef = db.collection('shifts').doc(payload.shiftId);
        const shiftSnap = await transaction.get(shiftRef);
        if (shiftSnap.exists) {
          const shiftData = shiftSnap.data() || {};
          const methodLower = paymentMethod.toLowerCase();
          const updateObj: Record<string, any> = {
            lastOrderAt: now,
          };
          if (methodLower === 'cash') {
            updateObj.cashSales = Number(shiftData.cashSales || 0) + payload.amountPaid;
          } else if (methodLower === 'upi') {
            updateObj.upiSales = Number(shiftData.upiSales || 0) + payload.amountPaid;
          } else if (methodLower === 'card') {
            updateObj.cardSales = Number(shiftData.cardSales || 0) + payload.amountPaid;
          }
          transaction.update(shiftRef, updateObj);
        }
      }

      // 5. Audit log
      const auditRef = db.collection('audit_logs').doc();
      transaction.set(auditRef, {
        logId: auditRef.id,
        userId,
        role: userData.role,
        shopId,
        action: 'CUSTOMER_CREDIT_SETTLED',
        entityType: 'customer',
        entityId: customerId,
        amount: payload.amountPaid,
        previousBalance: currentBalance,
        newBalance,
        paymentMethod,
        ledgerId,
        timestamp: now,
      });

      return {
        success: true,
        ledgerId,
        customerId,
        customerName: customer.name,
        customerMobile: customer.mobile,
        previousBalance: currentBalance,
        amountPaid: payload.amountPaid,
        newBalance,
        paymentMethod,
      };
    });

    return result;
  } catch (err: any) {
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError(
      'internal',
      err?.message || 'Failed to settle customer credit'
    );
  }
});
