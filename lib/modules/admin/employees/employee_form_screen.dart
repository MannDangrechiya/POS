import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';
import '../../../data/models/user_model.dart';
import 'employee_controller.dart';

/// Employee Form Screen - Create or Edit an Employee
/// Create: Admin/Super Admin creates a new employee (Firebase Auth + Firestore).
/// Edit (when [employee] is provided): name/phone only — email is tied to the
/// Firebase Auth identity and is not editable here; role/status/shopId are
/// managed elsewhere (activate/deactivate toggle, Super-Admin delete).
class EmployeeFormScreen extends StatefulWidget {
  const EmployeeFormScreen({super.key, this.employee});

  /// When non-null, the form edits this employee's name/phone instead of
  /// creating a new one.
  final UserModel? employee;

  bool get isEditMode => employee != null;

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final EmployeeController _controller = Get.find<EmployeeController>();
  late final _nameController = TextEditingController(
    text: widget.employee?.name ?? '',
  );
  late final _emailController = TextEditingController(
    text: widget.employee?.email ?? '',
  );
  late final _phoneController = TextEditingController(
    text: widget.employee?.phone ?? '',
  );
  final _passwordController = TextEditingController();
  String? _shopId;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode) {
      _shopId = widget.employee!.shopId;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadUserData(context);
      });
    }
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

  Future<void> _createEmployee(BuildContext pageContext) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_shopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shop ID not found')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });
    _controller.setLoading(true);

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createEmployeeUser')
          .call({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'shopId': _shopId!,
        'password': _passwordController.text,
      });

      if (result.data['success'] == true) {
        if (pageContext.mounted) {
          ScaffoldMessenger.of(pageContext).showSnackBar(
            const SnackBar(
              content: Text('Employee created successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(pageContext).pop();
        }
      }
    } on FirebaseFunctionsException catch (e) {
      String errorMessage = e.message ?? 'Error creating employee.';
      switch (e.code) {
        case 'already-exists':
          errorMessage = 'An account already exists for that email.';
          break;
        case 'permission-denied':
          errorMessage =
              e.message ?? 'You do not have permission to create employees.';
          break;
        case 'invalid-argument':
          errorMessage = e.message ?? errorMessage;
          break;
        case 'unauthenticated':
          errorMessage = 'Please sign in again.';
          break;
        case 'failed-precondition':
          errorMessage = e.message ?? errorMessage;
          break;
      }
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text('Error creating employee: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _controller.setLoading(false);
    }
  }

  Future<void> _updateEmployee(BuildContext pageContext) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final employee = widget.employee!;
    setState(() => _isLoading = true);
    _controller.setLoading(true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(employee.userId)
          .update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
      });

      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(
            content: Text('Employee updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(pageContext).pop();
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text('Error updating employee: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _controller.setLoading(false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Employee' : 'Add Employee'),
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
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                enabled: !widget.isEditMode,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.email),
                  helperText: widget.isEditMode
                      ? 'Email cannot be changed (tied to sign-in)'
                      : null,
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Phone number is required';
                  }
                  if (value.length < 10) {
                    return 'Please enter a valid phone number';
                  }
                  return null;
                },
              ),
              if (!widget.isEditMode) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    helperText: 'Minimum 6 characters',
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password is required';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.of(context).pop();
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _isLoading
                          ? null
                          : () => widget.isEditMode
                              ? _updateEmployee(context)
                              : _createEmployee(context),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              widget.isEditMode
                                  ? 'Save Changes'
                                  : 'Create Employee',
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
