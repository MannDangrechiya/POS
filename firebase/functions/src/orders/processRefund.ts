/**
 * processRefund Cloud Function
 * 
 * Handles itemized customer returns, restock disposition / wastage disposal,
 * refund issuance (Cash, Original, Store Credit), order status update,
 * and cashier shift cash-out deduction.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { validateRoleAndShop } from '../utils/roleValidation';
import { Role } from '../types/canonicalEnums';
import { validateRequiredString } from '../utils/validation';
import { createAuditLog } from '../utils/auditLogger';

const db = admin.firestore();

interface RefundItemPayload {
  productId: string;
  quantity: number;
  disposition: 'restock' | 'damaged';
  reason?: string;
}

interface ProcessRefundRequest {
  orderId: string;
  shopId: string;
  items: RefundItemPayload[];
  refundMethod: 'cash' | 'original' | 'store_credit';
  reason?: string;
  shiftId?: string;
}

export const processRefund = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated to process refunds'
    );
  }

  const userId = context.auth.uid;
  const request = data as ProcessRefundRequest;

  const orderId = validateRequiredString(request.orderId, 'orderId');
  const shopId = validateRequiredString(request.shopId, 'shopId');
  const items = request.items || [];
  const refundMethod = request.refundMethod || 'cash';
  const refundReason = request.reason || 'Customer return';
  const shiftId = request.shiftId;

  if (items.length === 0) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'At least one item must be selected for return'
    );
  }

  // 1. Verify user role & shop scoping
  let user: { userId: string; role: string; shopId: string; name: string; email: string; status: string };
  try {
    user = await validateRoleAndShop(userId, shopId, [Role.Employee, Role.Admin, Role.SuperAdmin]);
  } catch (e: any) {
    throw new functions.https.HttpsError(
      'permission-denied',
      e?.message || 'Access denied'
    );
  }

  // 2. Execute atomic refund transaction
  return await db.runTransaction(async (transaction) => {
    // ── READ PHASE ──
    const orderRef = db.collection('orders').doc(orderId);
    const orderDoc = await transaction.get(orderRef);

    if (!orderDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Order not found');
    }

    const orderData = orderDoc.data()!;
    if (orderData.shopId !== shopId) {
      throw new functions.https.HttpsError('permission-denied', 'Order does not belong to this shop');
    }

    if (orderData.orderStatus === 'cancelled') {
      throw new functions.https.HttpsError('failed-precondition', 'Cannot refund a cancelled order');
    }

    // Read order items to verify original purchased quantities & prices
    const orderItemsSnapshot = await transaction.get(
      db.collection('order_items').where('orderId', '==', orderId)
    );

    const originalItemsMap = new Map<string, { quantity: number; price: number; name?: string }>();
    for (const itemDoc of orderItemsSnapshot.docs) {
      const d = itemDoc.data();
      originalItemsMap.set(d.productId, {
        quantity: d.quantityOrWeight,
        price: d.priceSnapshot,
        name: d.productName || '',
      });
    }

    // Read product documents for items being returned
    const productRefs = items.map(i => db.collection('products').doc(i.productId));
    const productDocs = await Promise.all(productRefs.map(ref => transaction.get(ref)));
    const productMap = new Map<string, FirebaseFirestore.DocumentSnapshot>();
    productDocs.forEach(doc => {
      if (doc.exists) productMap.set(doc.id, doc);
    });

    // Read active shift if cash refund and shiftId provided
    let shiftRef: FirebaseFirestore.DocumentReference | null = null;
    let shiftDoc: FirebaseFirestore.DocumentSnapshot | null = null;
    if (refundMethod === 'cash' && shiftId) {
      shiftRef = db.collection('shifts').doc(shiftId);
      shiftDoc = await transaction.get(shiftRef);
    }

    // ── COMPUTATION & VALIDATION ──
    let totalRefundAmount = 0.0;
    const processedRefundItems: any[] = [];

    for (const item of items) {
      const original = originalItemsMap.get(item.productId);
      if (!original) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `Product ${item.productId} was not part of the original order`
        );
      }

      if (item.quantity <= 0 || item.quantity > original.quantity) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `Invalid return quantity ${item.quantity} for product ${item.productId}`
        );
      }

      const itemRefund = original.price * item.quantity;
      totalRefundAmount += itemRefund;

      const productSnap = productMap.get(item.productId);
      const productName = productSnap?.data()?.name || original.name || 'Returned Product';

      processedRefundItems.push({
        productId: item.productId,
        productName: productName,
        quantityReturned: item.quantity,
        unitPrice: original.price,
        refundAmount: itemRefund,
        disposition: item.disposition,
        reason: item.reason || refundReason,
      });
    }

    // ── WRITE PHASE ──
    const refundRef = db.collection('refunds').doc();
    const refundId = refundRef.id;

    // 1. Write Refund Document
    transaction.set(refundRef, {
      refundId,
      shopId,
      orderId,
      customerId: orderData.customerId || '',
      customerName: orderData.customerName || '',
      employeeId: userId,
      employeeName: user.name || '',
      shiftId: shiftId || '',
      items: processedRefundItems,
      totalRefundAmount,
      refundMethod,
      reason: refundReason,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. Restock inventory if disposition == 'restock'
    for (const item of items) {
      if (item.disposition === 'restock') {
        const prodRef = db.collection('products').doc(item.productId);
        transaction.update(prodRef, {
          stock: admin.firestore.FieldValue.increment(item.quantity),
        });

        // Write inventory log
        const invLogRef = db.collection('inventory_logs').doc();
        transaction.set(invLogRef, {
          logId: invLogRef.id,
          shopId,
          productId: item.productId,
          changeType: 'RESTOCK_RETURN',
          quantityChanged: item.quantity,
          previousStock: productMap.get(item.productId)?.data()?.stock ?? 0,
          newStock: (productMap.get(item.productId)?.data()?.stock ?? 0) + item.quantity,
          reason: `Customer Return #${orderId}`,
          performedBy: userId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    // 3. Update Order status & refundedAmount
    const currentRefunded = (orderData.refundedAmount || 0) + totalRefundAmount;
    const isFullyRefunded = Math.abs(currentRefunded - orderData.totalAmount) < 0.1 || currentRefunded >= orderData.totalAmount;
    const newStatus = isFullyRefunded ? 'refunded' : 'partially_refunded';

    transaction.update(orderRef, {
      refundedAmount: currentRefunded,
      orderStatus: newStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 4. Update Shift Cash Balance if Cash Refund
    if (shiftRef && shiftDoc && shiftDoc.exists && refundMethod === 'cash') {
      const movement = {
        id: `refund_${refundId}`,
        type: 'cash_out',
        amount: totalRefundAmount,
        reason: `Refund for Order #${orderId.substring(0, 8)}`,
        timestamp: admin.firestore.Timestamp.now(),
        authorizedBy: user.name || 'Cashier',
      };
      transaction.update(shiftRef, {
        movements: admin.firestore.FieldValue.arrayUnion(movement),
      });
    }

    return {
      success: true,
      refundId,
      orderId,
      totalRefundAmount,
      newOrderStatus: newStatus,
      items: processedRefundItems,
    };
  }).then(async (result) => {
    // Post-transaction audit logging
    try {
      await createAuditLog(
        user,
        'PROCESS_REFUND',
        'orders',
        orderId,
        {
          refundId: result.refundId,
          totalRefundAmount: result.totalRefundAmount,
          refundMethod,
          itemsCount: items.length,
        }
      );
    } catch (e) {
      functions.logger.error('Failed to write audit log for refund', e);
    }

    return result;
  });
});
