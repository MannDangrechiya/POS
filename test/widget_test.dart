import 'package:flutter_test/flutter_test.dart';
import 'package:pos_system/core/rbac/role_constants.dart';
import 'package:pos_system/routing/role_based_router.dart';
import 'package:pos_system/routing/app_routes.dart';
import 'package:pos_system/data/models/user_model.dart';
import 'package:pos_system/data/models/order_model.dart';
import 'package:pos_system/core/firestore/firestore_rule_safe_update.dart';

void main() {
  group('Role Constants and Routing Verification', () {
    test('RoleConstants match canonical PascalCase values', () {
      expect(RoleConstants.superAdmin, 'SuperAdmin');
      expect(RoleConstants.admin, 'Admin');
      expect(RoleConstants.employee, 'Employee');
      expect(RoleConstants.viewer, 'Viewer');
    });

    test('RoleBasedRouter maps roles to initial routes', () {
      expect(RoleBasedRouter.getInitialRoute('SuperAdmin'), AppRoutes.superAdmin);
      expect(RoleBasedRouter.getInitialRoute('Admin'), AppRoutes.admin);
      expect(RoleBasedRouter.getInitialRoute('Employee'), AppRoutes.employee);
      expect(RoleBasedRouter.getInitialRoute('Viewer'), AppRoutes.viewer);
    });

    test('RoleBasedRouter normalizes case variants', () {
      expect(RoleBasedRouter.getInitialRoute('super_admin'), AppRoutes.superAdmin);
      expect(RoleBasedRouter.getInitialRoute('admin'), AppRoutes.admin);
      expect(RoleBasedRouter.getInitialRoute('employee'), AppRoutes.employee);
      expect(RoleBasedRouter.getInitialRoute('viewer'), AppRoutes.viewer);
    });

    test('RoleBasedRouter validates recognized roles', () {
      expect(RoleBasedRouter.isValidRole('SuperAdmin'), isTrue);
      expect(RoleBasedRouter.isValidRole('Admin'), isTrue);
      expect(RoleBasedRouter.isValidRole('Employee'), isTrue);
      expect(RoleBasedRouter.isValidRole('Viewer'), isTrue);
      expect(RoleBasedRouter.isValidRole('Unknown'), isFalse);
    });
  });

  group('UserModel Canonical Normalization', () {
    test('Normalizes legacy role and status strings to canonical values', () {
      final user = UserModel.fromMap({
        'userId': 'usr_1',
        'name': 'Test User',
        'email': 'test@example.com',
        'phone': '1234567890',
        'role': 'super_admin',
        'shopId': 'shop_1',
        'status': 'active',
        'createdAt': DateTime(2025, 1, 1),
      });

      expect(user.role, 'SuperAdmin');
      expect(user.status, 'Active');
      expect(user.isActive, isTrue);
      expect(user.isSuspended, isFalse);
      expect(user.isDeleted, isFalse);
    });

    test('Normalizes suspended and deleted statuses', () {
      final suspendedUser = UserModel.fromMap({
        'userId': 'usr_2',
        'name': 'Suspended User',
        'email': 's@example.com',
        'phone': '1234567890',
        'role': 'employee',
        'shopId': 'shop_1',
        'status': 'Suspended',
        'createdAt': DateTime(2025, 1, 1),
      });
      expect(suspendedUser.isActive, isFalse);
      expect(suspendedUser.isSuspended, isTrue);

      final deletedUser = UserModel.fromMap({
        'userId': 'usr_3',
        'name': 'Deleted User',
        'email': 'd@example.com',
        'phone': '1234567890',
        'role': 'employee',
        'shopId': 'shop_1',
        'status': 'Deleted',
        'createdAt': DateTime(2025, 1, 1),
      });
      expect(deletedUser.isActive, isFalse);
      expect(deletedUser.isDeleted, isTrue);
    });
  });

  group('OrderModel Verification', () {
    test('Parses locked orders correctly', () {
      final order = OrderModel.fromMap({
        'orderId': 'ord_123',
        'shopId': 'shop_1',
        'customerId': 'cust_1',
        'employeeId': 'emp_1',
        'totalAmount': 250.0,
        'paymentMethod': 'cash',
        'paymentStatus': 'Success',
        'orderStatus': 'locked',
        'createdAt': DateTime(2025, 1, 1),
      });

      expect(order.isCompleted, isTrue);
      expect(order.isCancelled, isFalse);
      expect(order.isPending, isFalse);
      expect(order.totalAmount, 250.0);
    });
  });

  group('FirestoreRuleSafeUpdate Verification', () {
    test('Preserves immutable user fields on update', () {
      final user = UserModel(
        userId: 'u_100',
        name: 'Initial Name',
        email: 'init@test.com',
        phone: '9999999999',
        role: 'Employee',
        shopId: 'shop_abc',
        status: 'Active',
        createdAt: DateTime(2025, 1, 1),
      );

      final updatePayload = FirestoreRuleSafeUpdate.user(
        user,
        changes: {'status': 'Inactive'},
      );

      expect(updatePayload['userId'], 'u_100');
      expect(updatePayload['role'], 'Employee');
      expect(updatePayload['shopId'], 'shop_abc');
      expect(updatePayload['status'], 'Inactive');
    });
  });
}
