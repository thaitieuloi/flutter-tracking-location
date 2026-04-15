import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../services/location_service.dart';

/// Screen to view location history for a family member
/// Provides both Weekly Driving Report (charts) and Daily Trip History (timeline)
class LocationHistoryScreen extends StatefulWidget {
  final FamilyMember member;

  const LocationHistoryScreen({Key? key, required this.member}) : super(key: key);

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

enum ReportType { weekly, daily }

class _LocationHistoryScreenState extends State<LocationHistoryScreen> with TickerProviderStateMixin {
  final LocationService _locationSvc = LocationService();
  ReportType _reportType = ReportType.weekly;
  List<UserLocation> _history = [];
  List<Trip> _trips = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  // Stats for the weekly report (derived from real data)
  Map<int, double> _dailyMaxSpeeds = {};
  Map<int, double> _dailyDistances = {};
  Map<int, int> _dailyEvents = {}; // Mocked events count as we don't have event detection yet
  double _weeklyMaxSpeed = 0;
  double _totalWeeklyDistance = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _addressCache.clear();
    });
    
    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      
      DateTime start;
      DateTime end;

      if (_reportType == ReportType.weekly) {
        // Last 14 days to be sure we have some data
        end = DateTime.now();
        start = end.subtract(const Duration(days: 14)).copyWith(hour: 0, minute: 0, second: 0);
      } else {
        // Selected day only
        start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0, 0);
        end = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
      }

      final history = await provider.getLocationHistory(
        widget.member.id, 
        limit: 3000, // Increased to ensure coverage for a full week
        startTime: start.toUtc(), 
        endTime: end.toUtc()
      );
      
      if (mounted) {
        setState(() {
          _history = history;
          if (_reportType == ReportType.daily) {
            _groupIntoTrips(history);
          } else {
            _calculateWeeklyStats(history);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tải được dữ liệu: $e')),
        );
      }
    }
  }

  void _calculateWeeklyStats(List<UserLocation> history) {
    _dailyMaxSpeeds.clear();
    _dailyDistances.clear();
    _dailyEvents.clear();
    _weeklyMaxSpeed = 0;
    _totalWeeklyDistance = 0;

    if (history.isEmpty) return;

    for (int i = 0; i < 7; i++) {
       _dailyMaxSpeeds[i] = 0;
       _dailyDistances[i] = 0;
       _dailyEvents[i] = 0;
    }

    // Points are reversed (latest first), so chronological is history.reversed
    final chron = history.reversed.toList();

    for (int i = 0; i < chron.length - 1; i++) {
       final p1 = chron[i];
       final p2 = chron[i+1];
       
       // Normalize weekday: 1=Mon...7=Sun. Map to 0=Sun...6=Sat
       int dayIndex = p1.timestamp.toLocal().weekday % 7; 
       
       double dist = _calculateDistance(p1.latitude, p1.longitude, p2.latitude, p2.longitude);
       double timeHours = p2.timestamp.difference(p1.timestamp).inSeconds.abs() / 3600.0;
       
       if (dist > 0.01) { // Ignore tiny jitter
         _dailyDistances[dayIndex] = (_dailyDistances[dayIndex] ?? 0) + dist;
         
         double speed = timeHours > 0.001 ? (dist / timeHours) : 0;
         if (speed > 5 && speed < 160) { // Filter noise and stationary jitter
           if (speed > (_dailyMaxSpeeds[dayIndex] ?? 0)) {
             _dailyMaxSpeeds[dayIndex] = speed;
           }
           if (speed > 80) _dailyEvents[dayIndex] = (_dailyEvents[dayIndex] ?? 0) + 1;
         }
       }
    }

    _dailyMaxSpeeds.forEach((k, v) {
      if (v > _weeklyMaxSpeed) _weeklyMaxSpeed = v;
    });
    _dailyDistances.forEach((k, v) {
      _totalWeeklyDistance += v;
    });
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, LatLng(lat1, lon1), LatLng(lat2, lon2)) / 1000.0;
  }

  final Map<String, String> _addressCache = {};

  void _groupIntoTrips(List<UserLocation> history) {
    if (history.isEmpty) {
      _trips = [];
      return;
    }

    final chron = history.reversed.toList();
    List<Trip> segments = [];
    
    // Constants
    const double stayRadius = 100.0;
    const int stayDurationMin = 10;
    const int gapThresholdMin = 15;
    const double minTripDist = 500.0;

    int i = 0;
    while (i < chron.length) {
      int startIdx = i;
      int j = i + 1;
      
      while (j < chron.length) {
        final prev = chron[j - 1];
        final curr = chron[j];
        final gap = curr.timestamp.difference(prev.timestamp).inMinutes;
        
        if (gap > gapThresholdMin) break;
        
        final distFromStart = _calculateDistance(
          chron[startIdx].latitude, chron[startIdx].longitude,
          curr.latitude, curr.longitude
        ) * 1000;
        
        if (distFromStart > stayRadius) break;
        j++;
      }

      int duration = chron[j - 1].timestamp.difference(chron[startIdx].timestamp).inMinutes;
      
      if (duration >= stayDurationMin) {
        segments.add(Trip(points: chron.sublist(startIdx, j), type: TripType.stay));
      } else {
        // If not a stay, it's a movement/trip until the next stay or gap
        int k = j;
        while (k < chron.length) {
          final prev = chron[k - 1];
          final curr = chron[k];
          final gap = curr.timestamp.difference(prev.timestamp).inMinutes;
          if (gap > gapThresholdMin) break;
          
          // Check if a stay starts here
          bool stayStarts = false;
          int lookahead = k + 1;
          while (lookahead < chron.length) {
            if (chron[lookahead].timestamp.difference(chron[k].timestamp).inMinutes > gapThresholdMin) break;
            if (_calculateDistance(chron[k].latitude, chron[k].longitude, chron[lookahead].latitude, chron[lookahead].longitude) * 1000 > stayRadius) break;
            if (chron[lookahead].timestamp.difference(chron[k].timestamp).inMinutes >= stayDurationMin) {
              stayStarts = true;
              break;
            }
            lookahead++;
          }
          if (stayStarts) break;
          k++;
        }
        segments.add(Trip(points: chron.sublist(startIdx, k), type: TripType.trip));
        j = k;
      }
      i = j;
    }

    // Filter tiny trips and merge them into stays
    List<Trip> refined = [];
    for (var seg in segments) {
      if (seg.type == TripType.trip) {
        bool isTiny = seg.distanceMeters < minTripDist && seg.durationMinutes < 10;
        if (isTiny && refined.isNotEmpty && refined.last.type == TripType.stay) {
          // Merge into previous stay
          final prevPoints = List<UserLocation>.from(refined.last.points)..addAll(seg.points);
          refined[refined.length - 1] = Trip(points: prevPoints, type: TripType.stay);
          continue;
        }
      }
      refined.add(seg);
    }

    _trips = refined.reversed.toList();
    _enrichTripsWithAddresses();
  }

  Future<void> _enrichTripsWithAddresses() async {
    for (var trip in _trips) {
      if (trip.points.isEmpty) continue;
      
      final first = trip.points.first;
      final last = trip.points.last;

      _fetchAddressForPoint(first);
      _fetchAddressForPoint(last);
    }
  }

  Future<void> _fetchAddressForPoint(UserLocation loc) async {
    final key = "${loc.latitude},${loc.longitude}";
    if (_addressCache.containsKey(key)) return;

    final addr = await _locationSvc.getAddressFromCoordinates(loc.latitude, loc.longitude);
    if (addr != null && mounted) {
      setState(() {
        _addressCache[key] = addr;
      });
    }
  }

  String _getDisplayAddress(UserLocation loc) {
    final key = "${loc.latitude},${loc.longitude}";
    if (_addressCache.containsKey(key)) return _addressCache[key]!;
    if (loc.address != null) return loc.address!;
    return '(${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})';
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _reportType = ReportType.daily;
      });
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Báo cáo lái xe',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildTabPicker(colorScheme),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _reportType == ReportType.weekly
                    ? _buildWeeklyReport(colorScheme)
                    : _buildDailyTimeline(colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPicker(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF0F2F5))),
      ),
      child: Center(
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _reportType = ReportType.weekly);
                    _loadHistory();
                  },
                  child: _buildTabItem('Hằng tuần', _reportType == ReportType.weekly),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _reportType = ReportType.daily);
                    _loadHistory();
                  },
                  child: _buildTabItem('Hằng ngày', _reportType == ReportType.daily),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isSelected
            ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
            : [],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.black87 : Colors.black45,
        ),
      ),
    );
  }

  // ── Weekly Report (Using Real Data) ──────────────────────────

  Widget _buildWeeklyReport(ColorScheme colorScheme) {
    if (_history.isEmpty) return _buildEmptyTimeline(colorScheme, msg: 'Không có dữ liệu trong tuần qua');
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildEventDistributionChart(colorScheme),
        const SizedBox(height: 16),
        _buildMaxSpeedChart(colorScheme),
        const SizedBox(height: 16),
        _buildHighSpeedDistanceChart(colorScheme),
        const SizedBox(height: 16),
        _buildTotalDistanceChart(colorScheme),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildEventDistributionChart(ColorScheme colorScheme) {
    return _buildChartCard(
      title: 'Các sự kiện lái xe',
      child: Column(
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildChartLegend(color: const Color(0xFFFF858D), label: 'Sử dụng đ.thoại'),
              _buildChartLegend(color: const Color(0xff9975ff), label: 'Phanh gấp'),
              _buildChartLegend(color: const Color(0xff5ce6cd), label: 'Tăng tốc'),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 15,
                barTouchData: BarTouchData(enabled: false),
                titlesData: _buildTitlesData(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFF0F2F5), strokeWidth: 1),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
                ),
                barGroups: List.generate(7, (i) {
                   int ev = _dailyEvents[i] ?? 0;
                   return _makeEventGroup(i, [ev * 0.2, ev * 0.5, ev * 0.3]);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _makeEventGroup(int x, List<double> values) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(toY: values[0], color: const Color(0xFFFF858D), width: 6),
        BarChartRodData(toY: values[1], color: const Color(0xff9975ff), width: 6),
        BarChartRodData(toY: values[2], color: const Color(0xff5ce6cd), width: 6),
      ],
    );
  }

  Widget _buildMaxSpeedChart(ColorScheme colorScheme) {
    return _buildChartCard(
      title: 'Tốc độ tối đa (km/h)',
      icon: Icons.speed,
      iconColor: const Color(0xFFFF8A65),
      child: SizedBox(
        height: 150,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: (_weeklyMaxSpeed > 60 ? _weeklyMaxSpeed + 20 : 80),
            barTouchData: BarTouchData(enabled: true),
            titlesData: _buildTitlesData(),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(7, (i) => _makeSpeedGroup(i, _dailyMaxSpeeds[i] ?? 0)),
          ),
        ),
      ),
    );
  }

  BarChartGroupData _makeSpeedGroup(int x, double y) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: const Color(0xFF2196F3),
          width: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
      showingTooltipIndicators: y > 0 ? [0] : [],
    );
  }

  Widget _buildHighSpeedDistanceChart(ColorScheme colorScheme) {
    double avgDist = _totalWeeklyDistance / 7;
    return _buildChartCard(
      title: 'Quãng đường lái xe TB (km)',
      icon: Icons.trending_up,
      iconColor: const Color(0xFFFF8A65),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Text(
            '${avgDist.toStringAsFixed(1)} km',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const Text('Trung bình mỗi ngày', style: TextStyle(color: Colors.black45, fontSize: 13)),
          const SizedBox(height: 20),
          _buildTinyWeeklyBar(),
        ],
      ),
    );
  }

  Widget _buildTinyWeeklyBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(7, (i) {
        double d = _dailyDistances[i] ?? 0;
        double h = (d / 20).clamp(0.05, 1.0) * 40;
        return Column(
          children: [
            Container(
              width: 12,
              height: 40,
              decoration: BoxDecoration(color: const Color(0xFFF0F2F5), borderRadius: BorderRadius.circular(6)),
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 12,
                height: h,
                decoration: BoxDecoration(color: const Color(0xFFFF8A65), borderRadius: BorderRadius.circular(6)),
              ),
            ),
            const SizedBox(height: 4),
            Text(['CN','T2','T3','T4','T5','T6','T7'][i], style: const TextStyle(fontSize: 9, color: Colors.black38)),
          ],
        );
      }),
    );
  }

  Widget _buildTotalDistanceChart(ColorScheme colorScheme) {
    return _buildChartCard(
      title: 'Tổng quãng đường (km)',
      icon: Icons.show_chart,
      iconColor: const Color(0xFF90A4AE),
      child: SizedBox(
        height: 150,
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: false),
            titlesData: _buildTitlesData(),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: List.generate(7, (i) => FlSpot(i.toDouble(), _dailyDistances[i] ?? 0)),
                isCurved: true,
                color: const Color(0xFF5C7894),
                barWidth: 3,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [const Color(0xFF5C7894).withOpacity(0.3), const Color(0xFF5C7894).withOpacity(0.0)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard({required String title, required Widget child, IconData? icon, Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Row(
              children: [
                if (icon != null) Icon(icon, size: 16, color: iconColor),
                if (icon != null) const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF555555))),
              ],
            ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildChartLegend({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  FlTitlesData _buildTitlesData() {
    return FlTitlesData(
      show: true,
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (v, meta) {
            const days = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
            if (v >= 0 && v < 7) {
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(days[v.toInt()], style: const TextStyle(color: Colors.black38, fontSize: 10)),
              );
            }
            return const SizedBox();
          },
        ),
      ),
    );
  }

  // ── Daily Timeline ─────────────────────────────────────────

  Widget _buildDailyTimeline(ColorScheme colorScheme) {
    // Calculate summary stats for the day
    int tripCount = _trips.where((t) => t.type == TripType.trip).length;
    double totalDist = _trips
        .where((t) => t.type == TripType.trip)
        .fold(0.0, (sum, t) => sum + t.distanceMeters / 1000);

    return Column(
      children: [
        _buildDateHeader(),
        // Day summary strip
        if (_trips.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF2196F3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDayStat('$tripCount', 'chế́n', Icons.route),
                Container(width: 1, height: 28, color: Colors.white24),
                _buildDayStat(
                  totalDist >= 1 ? '${totalDist.toStringAsFixed(1)} km' : '${(totalDist * 1000).round()} m',
                  'quãng đường', Icons.straighten,
                ),
                Container(width: 1, height: 28, color: Colors.white24),
                _buildDayStat('${_trips.length}', 'điểm dừng', Icons.location_on),
              ],
            ),
          ),
        Expanded(
          child: _trips.isEmpty
              ? _buildEmptyTimeline(colorScheme)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _trips.length,
                  itemBuilder: (context, index) {
                    final trip = _trips[index];
                    if (trip.type == TripType.stay) {
                      return _buildStayCard(trip);
                    } else {
                      return _buildTripCard(trip, colorScheme);
                    }
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDayStat(String value, String label, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: Colors.white60),
            const SizedBox(width: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9)),
      ],
    );
  }

  Widget _buildDateHeader() {
    final now = DateTime.now();
    bool isToday = _selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day;
    
    return InkWell(
      onTap: _selectDate,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday ? 'Hôm nay' : DateFormat('EEEE, dd/MM').format(_selectedDate),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_selectedDate),
                  style: const TextStyle(fontSize: 14, color: Colors.black45),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.calendar_month, color: Color(0xFF2196F3)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, color: Colors.black26),
          ],
        ),
      ),
    );
  }

  Widget _buildStayCard(Trip stayTrip) {
    final duration = stayTrip.durationMinutes;
    final startTime = DateFormat('HH:mm').format(stayTrip.startTime);
    final endTime = DateFormat('HH:mm').format(stayTrip.endTime);
    final addr = _getDisplayAddress(stayTrip.points.first);
    final emoji = _getPlaceEmoji(addr);
    final durationStr = duration >= 60
        ? '${(duration / 60).floor()}h ${duration % 60}p'
        : '$duration p';
    final isLongStay = duration >= 60;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category emoji icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time row
                  Row(
                    children: [
                      Text('$startTime – $endTime',
                          style: const TextStyle(color: Colors.black38, fontSize: 11, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isLongStay
                              ? const Color(0xFFFFF3E0)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined,
                                size: 10,
                                color: isLongStay ? Colors.orange[700] : Colors.black38),
                            const SizedBox(width: 3),
                            Text(durationStr,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isLongStay ? Colors.orange[700] : Colors.black45)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Address
                  Text(
                    addr,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripCard(Trip trip, ColorScheme colorScheme) {
    final startTime = DateFormat('HH:mm').format(trip.startTime);
    final endTime = DateFormat('HH:mm').format(trip.endTime);

    // Calculate distance + speed stats
    double dist = 0;
    double maxSpeedKmh = 0;
    double totalSpeedSum = 0;
    int speedCount = 0;
    for (int i = 0; i < trip.points.length - 1; i++) {
      final d = _calculateDistance(
        trip.points[i].latitude, trip.points[i].longitude,
        trip.points[i + 1].latitude, trip.points[i + 1].longitude,
      ); // km
      dist += d;
      final secs = trip.points[i + 1].timestamp.difference(trip.points[i].timestamp).inSeconds;
      if (secs > 0 && d > 0) {
        final spd = (d / secs) * 3600; // km/h
        if (spd > 0.5 && spd < 200) {
          totalSpeedSum += spd;
          speedCount++;
          if (spd > maxSpeedKmh) maxSpeedKmh = spd;
        }
      }
    }
    final avgSpeed = speedCount > 0 ? totalSpeedSum / speedCount : 0.0;

    // Activity detection
    final String actEmoji;
    final String actLabel;
    final Color actColor;
    if (avgSpeed > 25) {
      actEmoji = '🚗';
      actLabel = 'Lái xe';
      actColor = const Color(0xFF2196F3);
    } else if (avgSpeed > 8) {
      actEmoji = '🚴';
      actLabel = 'Đạp xe';
      actColor = const Color(0xFF4CAF50);
    } else {
      actEmoji = '🚶';
      actLabel = 'Đi bộ';
      actColor = const Color(0xFFFF9800);
    }

    final distStr = dist >= 1
        ? '${dist.toStringAsFixed(1)} km'
        : '${(dist * 1000).round()} m';
    final durationStr = trip.durationMinutes >= 60
        ? '${(trip.durationMinutes / 60).floor()}h${trip.durationMinutes % 60}p'
        : '${trip.durationMinutes}p';

    return InkWell(
      onTap: () => _openTripPlayback(trip),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 14,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: activity chip + time range
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: actColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(actEmoji, style: const TextStyle(fontSize: 13)),
                            const SizedBox(width: 5),
                            Text(actLabel,
                                style: TextStyle(
                                    color: actColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text('$startTime → $endTime',
                          style: const TextStyle(color: Colors.black38, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Route from → to
                  _buildTripTimeline(trip),
                  const SizedBox(height: 12),
                  // Stats chips row
                  Row(
                    children: [
                      _buildStatChip(Icons.route, distStr, const Color(0xFF2196F3)),
                      const SizedBox(width: 6),
                      _buildStatChip(Icons.timer_outlined, durationStr, Colors.black45),
                      if (maxSpeedKmh > 5) ...[
                        const SizedBox(width: 6),
                        _buildStatChip(Icons.speed, '↑${maxSpeedKmh.round()} km/h',
                            maxSpeedKmh > 80 ? Colors.red : Colors.black45),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Tap-to-play footer strip
            Container(
              decoration: BoxDecoration(
                color: actColor.withOpacity(0.06),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_outline, size: 14, color: actColor),
                  const SizedBox(width: 6),
                  Text('Xem hành trình',
                      style: TextStyle(
                          fontSize: 11,
                          color: actColor,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripTimeline(Trip trip) {
    return Column(
      children: [
                _buildTimelineRow(
                  _getDisplayAddress(trip.points.first),
                  isStart: true,
                ),
                const SizedBox(height: 8),
                _buildTimelineRow(
                  _getDisplayAddress(trip.points.last),
                  isStart: false,
                ),
      ],
    );
  }

  Widget _buildTimelineRow(String address, {required bool isStart}) {
    return Row(
      children: [
        Icon(isStart ? Icons.radio_button_checked : Icons.location_on, size: 16, color: const Color(0xFF2196F3)),
        const SizedBox(width: 12),
        Expanded(child: Text(address, style: const TextStyle(fontSize: 13, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildTripStat(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.black26),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.black38)),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ],
    );
  }

  Widget _buildStatChip(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  /// Maps address string to a place category emoji
  String _getPlaceEmoji(String address) {
    final addr = address.toLowerCase();
    if (addr.contains('nhà') || addr.contains('home') || addr.contains('house')) return '🏠';
    if (addr.contains('trường') || addr.contains('school') || addr.contains('university')) return '🏫';
    if (addr.contains('bệnh viện') || addr.contains('phòng khám') || addr.contains('hospital')) return '🏥';
    if (addr.contains('cà phê') || addr.contains('coffee') || addr.contains('cafe')) return '☕';
    if (addr.contains('nhà hàng') || addr.contains('restaurant') || addr.contains('quán ăn')) return '🍽️';
    if (addr.contains('siêu thị') || addr.contains('shop') || addr.contains('cửa hàng')) return '🛍️';
    if (addr.contains('công viên') || addr.contains('park') || addr.contains('sân')) return '🌳';
    if (addr.contains('văn phòng') || addr.contains('office') || addr.contains('công ty')) return '🏢';
    if (addr.contains('xăng') || addr.contains('gas') || addr.contains('petrol')) return '⛽';
    if (addr.contains('sân bay') || addr.contains('airport')) return '✈️';
    if (addr.contains('khách sạn') || addr.contains('hotel')) return '🏨';
    return '📍'; // default pin
  }

  void _openTripPlayback(Trip trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TripPlaybackSheet(trip: trip, member: widget.member),
    );
  }

  Widget _buildEmptyTimeline(ColorScheme colorScheme, {String msg = 'Không có dữ liệu chuyến đi'}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 80, color: Colors.black12),
          const SizedBox(height: 24),
          Text(msg, style: const TextStyle(color: Colors.black38, fontSize: 16, fontWeight: FontWeight.w500)),
          if (_reportType == ReportType.daily)
             TextButton(onPressed: _selectDate, child: const Text('Chọn ngày khác')),
        ],
      ),
    );
  }
}

class _TripPlaybackSheet extends StatefulWidget {
  final Trip trip;
  final FamilyMember member;
  const _TripPlaybackSheet({Key? key, required this.trip, required this.member}) : super(key: key);
  @override
  State<_TripPlaybackSheet> createState() => _TripPlaybackSheetState();
}

class _TripPlaybackSheetState extends State<_TripPlaybackSheet> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  int _currentIndex = 0;
  bool _isPlaying = false;
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 500), _fitBounds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _fitBounds() {
    if (widget.trip.points.isEmpty) return;
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(widget.trip.points.map((p) => LatLng(p.latitude, p.longitude)).toList()),
      padding: const EdgeInsets.all(50),
    ));
  }

  void _togglePlay() {
    if (_isPlaying) {
      _timer?.cancel();
      setState(() => _isPlaying = false);
    } else {
      setState(() => _isPlaying = true);
      _timer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
        if (_currentIndex < widget.trip.points.length - 1) {
          setState(() {
            _currentIndex++;
            final p = widget.trip.points[_currentIndex];
            _mapController.move(LatLng(p.latitude, p.longitude), _mapController.camera.zoom);
          });
        } else {
          timer.cancel();
          setState(() => _isPlaying = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.trip.points[_currentIndex];
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      child: Column(
        children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 32, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill, color: Color(0xFF2196F3), size: 32),
                const SizedBox(width: 12),
                Expanded(child: Text('Chi tiết hành trình', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: LatLng(cur.latitude, cur.longitude), initialZoom: 16),
                  children: [
                    TileLayer(urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', subdomains: const ['a', 'b', 'c', 'd']),
                    PolylineLayer(polylines: [
                       Polyline(points: widget.trip.points.map((p) => LatLng(p.latitude, p.longitude)).toList(), color: Colors.black12, strokeWidth: 3),
                       Polyline(points: widget.trip.points.sublist(0, _currentIndex + 1).map((p) => LatLng(p.latitude, p.longitude)).toList(), color: const Color(0xFF2196F3), strokeWidth: 5),
                    ]),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(cur.latitude, cur.longitude),
                        width: 40, height: 40,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, _) => Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(width: 30 * _pulseController.value, height: 30 * _pulseController.value, decoration: BoxDecoration(color: const Color(0xFF2196F3).withOpacity(0.4), shape: BoxShape.circle)),
                              Container(width: 14, height: 14, decoration: BoxDecoration(color: const Color(0xFF2196F3), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)])),
                            ],
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))]),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(DateFormat('HH:mm').format(widget.trip.startTime), style: const TextStyle(fontSize: 12, color: Colors.black26)),
                    Expanded(
                      child: Slider(
                        value: _currentIndex.toDouble(),
                        min: 0,
                        max: (widget.trip.points.length - 1).toDouble(),
                        onChanged: (v) {
                          setState(() {
                            _currentIndex = v.toInt();
                            final p = widget.trip.points[_currentIndex];
                            _mapController.move(LatLng(p.latitude, p.longitude), _mapController.camera.zoom);
                          });
                        },
                      ),
                    ),
                    Text(DateFormat('HH:mm').format(widget.trip.endTime), style: const TextStyle(fontSize: 12, color: Colors.black26)),
                  ],
                ),
                FloatingActionButton(onPressed: _togglePlay, backgroundColor: const Color(0xFF2196F3), child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white)),
                const SizedBox(height: 12),
                Text('Thời điểm: ${DateFormat('HH:mm:ss').format(cur.timestamp.toLocal())}', style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum TripType { trip, stay }

class Trip {
  final List<UserLocation> points;
  final TripType type;
  
  Trip({required this.points, this.type = TripType.trip});
  
  DateTime get startTime => points.isEmpty ? DateTime.now() : points.first.timestamp.toLocal();
  DateTime get endTime => points.isEmpty ? DateTime.now() : points.last.timestamp.toLocal();
  int get durationMinutes => endTime.difference(startTime).inMinutes;

  double get distanceMeters {
    if (points.length < 2) return 0;
    double d = 0;
    for (int i = 0; i < points.length - 1; i++) {
      d += _calculateDistanceBetween(
        points[i].latitude, points[i].longitude,
        points[i+1].latitude, points[i+1].longitude,
      );
    }
    return d * 1000;
  }

  static double _calculateDistanceBetween(double lat1, double lon1, double lat2, double lon2) {
    const distance = Distance();
    return distance.as(LengthUnit.Meter, LatLng(lat1, lon1), LatLng(lat2, lon2)) / 1000.0;
  }
}
