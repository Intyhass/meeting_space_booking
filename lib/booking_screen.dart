// booking_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BookingPage extends StatefulWidget {
  const BookingPage({super.key});

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final titleController = TextEditingController();
  final dateController = TextEditingController();
  final startTimeController = TextEditingController();
  final endTimeController = TextEditingController();

  final CollectionReference bookingsRef = FirebaseFirestore.instance.collection(
    'bookings',
  );

  DateTime? selectedDate;
  List<Map<String, dynamic>> bookedRanges = []; // from Firestore
  List<Map<String, dynamic>> slots = []; // generated slots for selectedDate

  final ScrollController _scrollController = ScrollController();
  bool _showLeftArrow = false;
  bool _showRightArrow = false;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(() {
      // safe guard in case controller has no attached position yet
      if (!_scrollController.hasClients) return;
      setState(() {
        _showLeftArrow = _scrollController.offset > 10;
        _showRightArrow =
            _scrollController.offset <
            _scrollController.position.maxScrollExtent - 10;
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    titleController.dispose();
    dateController.dispose();
    startTimeController.dispose();
    endTimeController.dispose();
    super.dispose();
  }

  // --- Date picker (fetch bookings when a date is chosen) ---
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
        dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
      await _fetchBookedRangesAndGenerateSlots(picked);
      // after build, update arrow visibility
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _updateArrowVisibility(),
      );
    }
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      final now = DateTime.now();
      final dt = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
      controller.text = DateFormat('HH:mm').format(dt);
    }
  }

  // --- Fetch bookings for the day and generate slots with availability ---
  Future<void> _fetchBookedRangesAndGenerateSlots(DateTime date) async {
    setState(() => isLoading = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final snapshot =
          await bookingsRef.where('date', isEqualTo: dateStr).get();

      bookedRanges =
          snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'start': (data['startTime'] as Timestamp).toDate(),
              'end': (data['endTime'] as Timestamp).toDate(),
              'title': data['title'] ?? '',
            };
          }).toList();
    } catch (e) {
      bookedRanges = [];
      debugPrint('Error fetching bookings: $e');
    }

    _generateSlotsForDate(date);
    setState(() => isLoading = false);
  }

  void _generateSlotsForDate(DateTime date) {
    slots = [];
    final dayStart = DateTime(date.year, date.month, date.day, 7, 0); // 07:00
    final dayEnd = DateTime(date.year, date.month, date.day, 20, 0); // 20:00

    for (
      DateTime time = dayStart;
      time.isBefore(dayEnd);
      time = time.add(const Duration(hours: 1))
    ) {
      final slotStart = time;
      final slotEnd = time.add(const Duration(hours: 1));
      bool available = true;
      for (var b in bookedRanges) {
        final bookedStart = b['start'] as DateTime;
        final bookedEnd = b['end'] as DateTime;
        // overlap check: if slotStart < bookedEnd && slotEnd > bookedStart => overlapping
        if (slotStart.isBefore(bookedEnd) && slotEnd.isAfter(bookedStart)) {
          available = false;
          break;
        }
      }
      slots.add({'start': slotStart, 'end': slotEnd, 'available': available});
    }
  }

  void _updateArrowVisibility() {
    if (!_scrollController.hasClients) return;
    setState(() {
      _showLeftArrow = _scrollController.offset > 10;
      _showRightArrow =
          _scrollController.offset <
          _scrollController.position.maxScrollExtent - 10;
    });
  }

  // --- Save booking with overlap prevention (works with manual and grid picks) ---
  Future<void> _saveBooking() async {
    if (titleController.text.trim().isEmpty ||
        dateController.text.trim().isEmpty ||
        startTimeController.text.trim().isEmpty ||
        endTimeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill Title, Date, Start and End time'),
        ),
      );
      return;
    }

    try {
      final date = DateFormat('yyyy-MM-dd').parse(dateController.text.trim());
      final startParts = startTimeController.text.split(':');
      final endParts = endTimeController.text.split(':');

      final startDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(startParts[0]),
        int.parse(startParts[1]),
      );
      final endDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(endParts[0]),
        int.parse(endParts[1]),
      );

      if (!endDateTime.isAfter(startDateTime)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End time must be after start time ⏱️')),
        );
        return;
      }

      // Check overlaps with DB entries for that date
      final snapshot =
          await bookingsRef
              .where('date', isEqualTo: dateController.text.trim())
              .get();
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final bookedStart = (data['startTime'] as Timestamp).toDate();
        final bookedEnd = (data['endTime'] as Timestamp).toDate();
        if (startDateTime.isBefore(bookedEnd) &&
            endDateTime.isAfter(bookedStart)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⛔ Time slot already booked!')),
          );
          return;
        }
      }

      // Save
      await bookingsRef.add({
        'title': titleController.text.trim(),
        'date': dateController.text.trim(),
        'startTime': Timestamp.fromDate(startDateTime),
        'endTime': Timestamp.fromDate(endDateTime),
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✅ Booking saved')));

      // Clear and refresh slots
      titleController.clear();
      startTimeController.clear();
      endTimeController.clear();
      await _fetchBookedRangesAndGenerateSlots(date);
      // Optionally close screen:
      // Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // --- Build UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'New Reservation',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF810725),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + Date
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: dateController,
              readOnly: true,
              onTap: _pickDate,
              decoration: const InputDecoration(
                labelText: 'Date',
                suffixIcon: Icon(Icons.calendar_today),
              ),
            ),
            const SizedBox(height: 14),

            // Slot row (compact horizontal)
            if (isLoading)
              const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (selectedDate == null)
              const Text('Select a date to view available slots')
            else
              SizedBox(
                height: 46,
                child: Stack(
                  children: [
                    ListView.separated(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      itemCount: slots.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final slot = slots[index];
                        final s = slot['start'] as DateTime;
                        final e = slot['end'] as DateTime;
                        final available = slot['available'] as bool;
                        final label =
                            '${DateFormat('HH:mm').format(s)} - ${DateFormat('HH:mm').format(e)}';

                        return ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 120),
                          child: ElevatedButton(
                            onPressed:
                                available
                                    ? () {
                                      setState(() {
                                        startTimeController.text = DateFormat(
                                          'HH:mm',
                                        ).format(s);
                                        endTimeController.text = DateFormat(
                                          'HH:mm',
                                        ).format(e);
                                      });
                                    }
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  available
                                      ? Colors.white
                                      : Colors.grey.shade200,
                              foregroundColor:
                                  available
                                      ? const Color(0xFF810725)
                                      : Colors.grey.shade600,
                              elevation: 0,
                              side: BorderSide(
                                color:
                                    available
                                        ? const Color(0xFF810725)
                                        : Colors.grey.shade300,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        );
                      },
                    ),

                    // left fade + arrow
                    if (_showLeftArrow)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 28,
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white,
                                Colors.white.withOpacity(0.0),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                          child: const Icon(
                            Icons.chevron_left,
                            size: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ),

                    // right fade + arrow
                    if (_showRightArrow)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 28,
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.0),
                                Colors.white,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                          child: const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Manual pickers (still available for custom durations)
            TextField(
              controller: startTimeController,
              readOnly: true,
              onTap: () => _pickTime(startTimeController),
              decoration: const InputDecoration(
                labelText: 'Start Time (custom)',
                suffixIcon: Icon(Icons.access_time),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: endTimeController,
              readOnly: true,
              onTap: () => _pickTime(endTimeController),
              decoration: const InputDecoration(
                labelText: 'End Time (custom)',
                suffixIcon: Icon(Icons.access_time),
              ),
            ),

            const SizedBox(height: 18),

            Center(
              child: ElevatedButton(
                onPressed: _saveBooking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF810725),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Save Booking',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
