import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/supabase_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _nameController;
  bool _isUploading = false;
  bool _isSaving = false;
  final _svc = SupabaseService();

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<AppProvider>(context, listen: false);
    _nameController = TextEditingController(text: provider.currentUser?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );

    if (image == null) return;

    setState(() => _isUploading = true);

    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      final bytes = await image.readAsBytes();
      final extension = image.path.split('.').last.toLowerCase();
      
      final newUrl = await _svc.uploadAvatar(
        provider.currentUser!.id, 
        bytes, 
        extension
      );

      if (newUrl != null && mounted) {
        await provider.loadUserData(provider.currentUser!.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật ảnh đại diện!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải ảnh: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      await _svc.updateDisplayName(provider.currentUser!.id, name);
      await provider.loadUserData(provider.currentUser!.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu thông tin cá nhân!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt cá nhân'),
        elevation: 0,
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final user = provider.currentUser;
          if (user == null) return const Center(child: CircularProgressIndicator());

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      backgroundImage: user.photoUrl != null && user.photoUrl!.isNotEmpty
                          ? NetworkImage(user.photoUrl!)
                          : null,
                      child: (user.photoUrl == null || user.photoUrl!.isEmpty)
                          ? Text(
                              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    if (_isUploading)
                      const Positioned.fill(
                        child: ClipOval(
                          child: Container(
                            color: Colors.black26,
                            child: Center(child: CircularProgressIndicator(color: Colors.white)),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: FloatingActionButton.small(
                        onPressed: _isUploading ? null : _pickAndUploadImage,
                        child: const Icon(Icons.camera_alt),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên hiển thị',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.email),
                    filled: true,
                    fillColor: Colors.grey.withOpacity(0.1),
                  ),
                  controller: TextEditingController(text: user.email),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveProfile,
                    icon: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: const Text('LƯU THAY ĐỔI'),
                  ),
                ),
                const SizedBox(height: 48),
                TextButton.icon(
                  onPressed: () => provider.signOut().then((_) => Navigator.pop(context)),
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text('Đăng xuất', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
