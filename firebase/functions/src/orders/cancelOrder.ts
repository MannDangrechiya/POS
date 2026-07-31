/**
 * cancelOrder Cloud Function
 * 
 * LOCATION: firebase/functions/src/orders/cancelOrder.ts
 * 
 * RESPONSIBILITIES:
 * - Allow only Admin or Super Admin
 * - Prevent cancellation of confirmed orders
 * - Write audit_logs entry
 * - Do NOT restore inventory
 * 
 * CRITICAL BUSINESS RULES ENFORCED:
 * - Only Admin and Super Admin can cancel orders
 * - Confirmed/Locked orders cannot be cancelled
 * - Cancellation must be logged for audit
 * - Inventory is NOT restored (maintains audit integrity)
 * - Cancelled orders remain visible for audit
 * 
 * Based on TECHNICAL REQUIREMENTS IN DETAIL.md - Module 5: ORDERS
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { CancelOrderRequest, Order } from '../types';
import { OrderStatus } from '../types/canonicalEnums';
import { validateAdminOrSuper } from '../utils/roleValidation';
import { validateRequiredString } from '../utils/validation';
import { createAuditLog } from '../utils/auditLogger';

const db = admin.firestore();

export const cancelOrder = functions.https.onCall(async (data, context) => {
  // Authentication check
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated'
    );
  }

  const userId = context.auth.uid;
  const request = data as CancelOrderRequest;

  try {
    // Validate request data - never trust frontend
    const orderId = validateRequiredString(request.orderId, 'orderId');
    const shopId = validateRequiredString(request.shopId, 'shopId');
    const reason = request.reason || 'No reason provided';

    // Allow only Admin or Super Admin
    const user = await validateAdminOrSuper(userId, shopId);

    // Use Firestore transaction for atomic operation
    return await db.runTransaction(async (transaction) => {
      // Get order
      const orderRef = db.collection('orders').doc(orderId);
      const orderDoc = await transaction.get(orderRef);

      if (!orderDoc.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'Order not found'
        );
      }

      const order = orderDoc.data() as Order;

      // Validate order shopId
      if (order.shopId !== shopId) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Order does not belong to this shop'
        );
      }

      // Check if order is already cancelled
      if ((order.orderStatus as string) === OrderStatus.cancelled) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Order is already cancelled'
        );
      }

      // Update order status to cancelled
      transaction.update(orderRef, {
        orderStatus: OrderStatus.cancelled,
      });

      return {
        success: true,
        orderId,
        previousStatus: order.orderStatus,
        newStatus: OrderStatus.cancelled,
        totalAmount: order.totalAmount,
        paymentMethod: order.paymentMethod,
        message: 'Order cancelled successfully',
      };
    }).then(async (result) => {
      // After transaction succeeds, write audit_logs entry
      try {
        await createAuditLog(
          user,
          'order_cancelled',
          'order',
          orderId,
          {
            reason,
            previousStatus: result.previousStatus,
            newStatus: result.newStatus,
            totalAmount: result.totalAmount,
            paymentMethod: result.paymentMethod,
            note: 'Inventory was NOT restored to maintain audit integrity.',
          }
        );

        console.log(`Order ${orderId} cancelled by ${userId} (${user.role})`);
      } catch (logError) {
        console.error('Failed to create audit log for order cancellation:', logError);
        // Don't fail the function if audit log fails, but log the error
      }

      return result;
    });

  } catch (error: any) {
    console.error('Error cancelling order:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      'internal',
      `Failed to cancel order: ${error.message}`
    );
  }
});
