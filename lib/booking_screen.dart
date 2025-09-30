import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BookingPage extends StatefulWidget {
  const BookingPage({Key? key}) : super(key: key);

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final titleController = TextEditingController();
  final dateController = TextEditingController();
  final startTimeController = TextEditingController();
  final endTimeController = TextEditingController();

  final bookingsRef = FirebaseFirestore.instance.collection('bookings');

  // 📌 Pick Date
  Future<void> _pickDate(TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // 📌 Pick Time in 24h format
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
      setState(() {
        controller.text = DateFormat('HH:mm').format(dt); // Always "HH:mm"
      });
    }
  }

  // 📌 Save booking with overlap prevention
  Future<void> saveBooking() async {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dateController.text);

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

      if (endDateTime.isBefore(startDateTime) ||
          endDateTime.isAtSameMomentAs(startDateTime)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End time must be after start time ⏱️')),
        );
        return;
      }

      // 🔍 Query all bookings for the same date
      final querySnapshot =
          await bookingsRef.where('date', isEqualTo: dateController.text).get();

      bool hasOverlap = false;
      for (var booking in querySnapshot.docs) {
        final bookedStart = (booking['startTime'] as Timestamp).toDate();
        final bookedEnd = (booking['endTime'] as Timestamp).toDate();

        final overlap =
            startDateTime.isBefore(bookedEnd) &&
            endDateTime.isAfter(bookedStart);

        if (overlap) {
          hasOverlap = true;
          break;
        }
      }

      if (hasOverlap) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⛔ Time slot already booked!')),
        );
        return;
      }

      // ✅ Save booking
      await bookingsRef.add({
        'title': titleController.text,
        'date': dateController.text,
        'startTime': Timestamp.fromDate(startDateTime),
        'endTime': Timestamp.fromDate(endDateTime),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking saved successfully ✅')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving booking: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Booking')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: dateController,
              readOnly: true,
              onTap: () => _pickDate(dateController),
              decoration: const InputDecoration(labelText: 'Date'),
            ),
            TextField(
              controller: startTimeController,
              readOnly: true,
              onTap: () => _pickTime(startTimeController),
              decoration: const InputDecoration(
                labelText: 'Start Time (HH:mm)',
              ),
            ),
            TextField(
              controller: endTimeController,
              readOnly: true,
              onTap: () => _pickTime(endTimeController),
              decoration: const InputDecoration(labelText: 'End Time (HH:mm)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: saveBooking,
              child: const Text('Save Booking'),
            ),
          ],
        ),
      ),
    );
  }
}
