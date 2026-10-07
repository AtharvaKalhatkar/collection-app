import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';
import '../utils/theme.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  void _showAddOrEditUserDialog(BuildContext context, {UserModel? userToEdit}) {
    final auth = context.read<AuthProvider>();
    final isEditing = userToEdit != null;

    final nameCtrl = TextEditingController(text: userToEdit?.name ?? '');
    final phoneCtrl = TextEditingController(text: userToEdit?.phone ?? '');
    final passCtrl = TextEditingController(text: userToEdit?.password ?? 'pass123');
    UserRole selectedRole = userToEdit?.role ?? UserRole.salesman;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isEditing ? 'Edit Staff Member' : 'Add New Staff Member',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Staff Name',
                    hintText: 'e.g. Akash or Office 1',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    hintText: 'e.g. 76209 95547',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'e.g. pass123',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Assigned Role:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<UserRole>(
                  initialValue: selectedRole,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: UserRole.superAdmin,
                      child: Text('👑 Super Admin'),
                    ),
                    DropdownMenuItem(
                      value: UserRole.office,
                      child: Text('🏢 Office Staff'),
                    ),
                    DropdownMenuItem(
                      value: UserRole.salesman,
                      child: Text('🛵 Sales & Collection'),
                    ),
                  ],
                  onChanged: (newRole) {
                    if (newRole != null) {
                      setModalState(() {
                        selectedRole = newRole;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final cleanPhone = UserModel.normalizePhone(phoneCtrl.text.trim());
                final cleanName = nameCtrl.text.trim();
                final cleanPass = passCtrl.text.trim();

                if (cleanPhone.isEmpty || cleanName.isEmpty || cleanPass.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields')),
                  );
                  return;
                }

                final user = UserModel(
                  id: userToEdit?.id ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
                  phone: cleanPhone,
                  name: cleanName,
                  role: selectedRole,
                  password: cleanPass,
                  isActive: userToEdit?.isActive ?? true,
                  createdAt: userToEdit?.createdAt ?? DateTime.now(),
                );

                await auth.saveUser(user);
                if (dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Staff member "${user.name}" saved successfully!'),
                      backgroundColor: Colors.green.shade700,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Save Staff'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final users = auth.users;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Staff & Role Management',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Add Staff Member',
            onPressed: () => _showAddOrEditUserDialog(context),
          ),
        ],
      ),
      body: users.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              itemCount: users.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (ctx, index) {
                final user = users[index];
                final isCurrent = auth.currentUser?.id == user.id;

                Color badgeColor;
                IconData roleIcon;
                switch (user.role) {
                  case UserRole.superAdmin:
                    badgeColor = const Color(0xFF2563EB);
                    roleIcon = Icons.admin_panel_settings_rounded;
                    break;
                  case UserRole.office:
                    badgeColor = const Color(0xFF0F766E);
                    roleIcon = Icons.business_center_rounded;
                    break;
                  case UserRole.salesman:
                    badgeColor = const Color(0xFFD97706);
                    roleIcon = Icons.two_wheeler_rounded;
                    break;
                }

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isCurrent ? AppTheme.secondary : const Color(0xFFE2E8F0),
                      width: isCurrent ? 1.8 : 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Avatar / Role Icon
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(roleIcon, color: badgeColor, size: 24),
                        ),
                        const SizedBox(width: 14),

                        // Name, Phone, Role
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    user.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'YOU',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF1D4ED8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '📱 ${user.phone}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      user.roleDisplayName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: badgeColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '🔑 ${user.password}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Edit Button
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: AppTheme.secondary),
                          tooltip: 'Edit details & credentials',
                          onPressed: () => _showAddOrEditUserDialog(context, userToEdit: user),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
