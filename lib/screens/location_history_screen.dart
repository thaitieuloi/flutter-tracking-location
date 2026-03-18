import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

/// Screen to view location history for a family member
class LocationHistoryScreen extends StatefulWidget {
  final FamilyMember member;

  const LocationHistoryScreen({Key? key, required this.member}) : super(key: key);

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  List<UserLocation> _history = [];
  List<Trip> _trips = [];
  bool _isLoading = true;
  bool _showByTrip = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _groupIntoTrips(List<UserLocation> history) {
    if (history.isEmpty) {
      _trips = [];
      return;
    }

    final List<Trip> trips = [];
    List<UserLocation> currentTripPoints = [history.last];

    // history is DESCENDING (most recent first)
    // To process trips, it's easier to iterate chronologically
    final chronologicalHistory = history.reversed.toList();
    
    currentTripPoints = [chronologicalHistory.first];
    
    for (int i = 1; i < chronologicalHistory.length; i++) {
      final prev = chronologicalHistory[i - 1];
      final curr = chronologicalHistory[i];
      
      final gap = curr.timestamp.difference(prev.timestamp).inMinutes;
      
      if (gap > 15) {
        // New trip started
        trips.add(Trip(points: List.from(currentTripPoints)));
        currentTripPoints = [curr];
      } else {
        currentTripPoints.add(curr);
      }
    }
    
    if (currentTripPoints.isNotEmpty) {
      trips.add(Trip(points: currentTripPoints));
    }

    // Sort trips descending (most recent first)
    _trips = trips.reversed.toList();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<AppProvider>(context, listen: false);
    final history = await provider.getLocationHistory(widget.member.id, limit: 200);
    if (mounted) {
      setState(() {
        _history = history;
        _groupIntoTrips(history);
        _isLoading = false;
      });
    }
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return DateFormat('dd/MM HH:mm').format(local);
  }

  String _formatFullTime(DateTime dt) {
    return DateFormat('HH:mm:ss - dd/MM/yyyy').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.member.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Lịch sử vị trí',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? _buildEmptyState(colorScheme)
              : _buildHistoryView(colorScheme),
    );
  }

  Widget _buildHistoryView(ColorScheme colorScheme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('Chế độ xem:', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              ChoiceChip(
                label: const Text('Theo Trip'),
                selected: _showByTrip,
                onSelected: (val) => setState(() => _showByTrip = true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Tất cả'),
                selected: !_showByTrip,
                onSelected: (val) => setState(() => _showByTrip = false),
              ),
            ],
          ),
        ),
        Expanded(
          child: _showByTrip ? _buildTripList(colorScheme) : _buildHistoryList(colorScheme),
        ),
      ],
    );
  }

  Widget _buildTripList(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _trips.length,
      itemBuilder: (context, index) {
        final trip = _trips[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            leading: Icon(Icons.directions_car, color: colorScheme.primary),
            title: Text(
              'Chuyến đi lúc ${DateFormat('HH:mm').format(trip.startTime.toLocal())}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${DateFormat('dd/MM').format(trip.startTime.toLocal())} • ${trip.durationMinutes} phút • ${trip.points.length} điểm',
            ),
            children: trip.points.reversed.map((loc) => ListTile(
              dense: true,
              leading: const Icon(Icons.location_on_outlined, size: 18),
              title: Text(_formatFullTime(loc.timestamp)),
              subtitle: Text(loc.address ?? '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}'),
            )).toList(),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off_rounded, size: 80, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'Chưa có lịch sử vị trí',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.member.name} chưa chia sẻ vị trí',
            style: TextStyle(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(ColorScheme colorScheme) {
    return Column(
      children: [
        // Summary header
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.primary,
                radius: 22,
                child: Text(
                  widget.member.name[0].toUpperCase(),
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.member.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      '${_history.length} điểm vị trí',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (_history.isNotEmpty)
                Chip(
                  label: Text(
                    _formatTime(_history.first.timestamp),
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: colorScheme.secondaryContainer,
                ),
            ],
          ),
        ),

        // Timeline list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final loc = _history[index];
              final isFirst = index == 0;
              final isLast = index == _history.length - 1;

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Timeline indicator
                    SizedBox(
                      width: 40,
                      child: Column(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(top: 16),
                            decoration: BoxDecoration(
                              color: isFirst ? colorScheme.primary : colorScheme.outline,
                              shape: BoxShape.circle,
                            ),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Container(
                                width: 2,
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Location card
                    Expanded(
                      child: Card(
                        margin: const EdgeInsets.only(left: 8, bottom: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isFirst ? Icons.location_on : Icons.location_on_outlined,
                                    size: 16,
                                    color: isFirst ? colorScheme.primary : colorScheme.outline,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _formatFullTime(loc.timestamp),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isFirst ? FontWeight.bold : FontWeight.normal,
                                        color: isFirst ? colorScheme.primary : colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  if (isFirst)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Mới nhất',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.my_location, size: 13, color: colorScheme.outline),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                              if (loc.accuracy != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.gps_fixed, size: 13, color: colorScheme.outline),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Độ chính xác: ±${loc.accuracy!.toStringAsFixed(0)}m',
                                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                                    ),
                                  ],
                                ),
                              ],
                              if (loc.address != null && loc.address!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.place_outlined, size: 13, color: colorScheme.outline),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        loc.address!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
class Trip {
  final List<UserLocation> points;
  
  Trip({required this.points});
  
  DateTime get startTime => points.first.timestamp;
  DateTime get endTime => points.last.timestamp;
  int get durationMinutes => endTime.difference(startTime).inMinutes;
}
