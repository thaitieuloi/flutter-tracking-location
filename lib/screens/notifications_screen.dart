import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

/// Notifications screen — shows geofence, SOS, battery, inactivity alerts
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<AppProvider>(context, listen: false);
    final list = await provider.getNotifications();
    if (mounted) {
      setState(() {
        _notifications = list;
        _isLoading = false;
      });
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'sos':
        return Icons.sos;
      case 'battery_low':
        return Icons.battery_alert;
      case 'inactivity_alert':
        return Icons.timer_off;
      case 'geofence':
      default:
        return Icons.fence;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'sos':
        return Colors.red;
      case 'battery_low':
        return Colors.orange;
      case 'inactivity_alert':
        return Colors.amber.shade700;
      case 'geofence':
      default:
        return Colors.blue;
    }
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return DateFormat('dd/MM HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final unreadCount = _notifications.where((n) => !n.read).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Thông báo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (unreadCount > 0)
              Text(
                '$unreadCount chưa đọc',
                style: TextStyle(fontSize: 12, color: colorScheme.primary),
              ),
          ],
        ),
        actions: [
          if (_notifications.any((n) => !n.read))
            TextButton.icon(
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Đã đọc tất cả'),
              onPressed: () async {
                final provider = Provider.of<AppProvider>(context, listen: false);
                await provider.markAllNotificationsRead();
                _loadNotifications();
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? _buildEmpty(colorScheme)
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notif = _notifications[index];
                      return _buildNotifCard(notif, colorScheme);
                    },
                  ),
                ),
    );
  }

  Widget _buildNotifCard(AppNotification notif, ColorScheme colorScheme) {
    final typeColor = _typeColor(notif.type);
    final unread = !notif.read;

    return Dismissible(
      key: Key(notif.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      onDismissed: (_) async {
        final provider = Provider.of<AppProvider>(context, listen: false);
        await provider.deleteNotification(notif.id);
        setState(() => _notifications.removeWhere((n) => n.id == notif.id));
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: unread ? 1 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: unread ? typeColor.withOpacity(0.3) : colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            if (!notif.read) {
              final provider = Provider.of<AppProvider>(context, listen: false);
              await provider.markNotificationRead(notif.id);
              setState(() {
                final idx = _notifications.indexWhere((n) => n.id == notif.id);
                if (idx >= 0) {
                  _notifications[idx] = _notifications[idx].copyWith(read: true);
                }
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: unread ? typeColor.withOpacity(0.04) : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_typeIcon(notif.type), color: typeColor, size: 20),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notif.title,
                              style: TextStyle(
                                fontWeight: unread ? FontWeight.bold : FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: typeColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notif.body,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatTime(notif.createdAt),
                        style: TextStyle(fontSize: 11, color: colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, size: 80, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'Chưa có thông báo',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thông báo geofence, SOS, pin thấp sẽ hiển thị ở đây',
            style: TextStyle(color: colorScheme.outline, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
