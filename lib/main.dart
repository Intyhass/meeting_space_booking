import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:meeting_space_booking/booking_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DKL Meeting Space Booking',
      initialRoute: '/',
      routes: {
        '/': (context) => ScreenA(),
        '/booking': (context) => BookingPage(),
      },
    );
  }
}

class ScreenA extends StatefulWidget {
  const ScreenA({super.key});

  @override
  State<ScreenA> createState() => _ScreenAState();
}

class _ScreenAState extends State<ScreenA> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    // Refresh every minute to update ongoing bookings
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    // TODO: implement dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookingsRef = FirebaseFirestore.instance.collection('bookings');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Board Room', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF810725),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
        ),
      ),
      body: Container(
        color: const Color(0xFFF8F9FA),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titles
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                Text(
                  'Ongoing',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Upcoming',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF388E3C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Content
            Expanded(
              child: Row(
                children: [
                  // Ongoing section
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream:
                          bookingsRef
                              .where(
                                'startTime',
                                isGreaterThanOrEqualTo: DateTime(
                                  DateTime.now().year,
                                  DateTime.now().month,
                                  DateTime.now().day,
                                ),
                              )
                              .where(
                                'startTime',
                                isLessThan: DateTime(
                                  DateTime.now().year,
                                  DateTime.now().month,
                                  DateTime.now().day + 1,
                                ),
                              )
                              .orderBy('startTime')
                              .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(child: Text('No bookings today'));
                        }

                        final bookings =
                            snapshot.data!.docs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return {
                                'title': data['title'] ?? 'No Title',
                                'startTime':
                                    (data['startTime'] as Timestamp).toDate(),
                                'endTime':
                                    (data['endTime'] as Timestamp).toDate(),
                              };
                            }).toList();

                        final now = DateTime.now();
                        final ongoing = bookings.firstWhere(
                          (b) =>
                              now.isAfter(b['startTime']) &&
                              now.isBefore(b['endTime']),
                          orElse: () => {},
                        );

                        if (ongoing.isNotEmpty) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ongoing['title'],
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ends at: ${DateFormat.jm().format(ongoing['endTime'])}',
                                style: const TextStyle(
                                  color: Color(0xFF555555),
                                ),
                              ),
                            ],
                          );
                        } else {
                          return const Text("No ongoing meeting");
                        }
                      },
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Upcoming section
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFE0E0E0),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: StreamBuilder<QuerySnapshot>(
                              stream:
                                  bookingsRef
                                      .where(
                                        'startTime',
                                        isGreaterThan:
                                            DateTime.now(), // only future
                                      )
                                      .orderBy('startTime', descending: false)
                                      .snapshots(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (!snapshot.hasData ||
                                    snapshot.data!.docs.isEmpty) {
                                  return const Center(
                                    child: Text('No upcoming bookings'),
                                  );
                                }

                                final bookings = snapshot.data!.docs;

                                return SingleChildScrollView(
                                  child: Column(
                                    children:
                                        bookings.map((doc) {
                                          final data =
                                              doc.data()
                                                  as Map<String, dynamic>;
                                          final title =
                                              data['title'] ?? 'No Title';
                                          final startTime =
                                              (data['startTime'] as Timestamp)
                                                  .toDate();
                                          final formattedTime = DateFormat.jm()
                                              .format(startTime);

                                          return ListTile(
                                            leading: const Icon(
                                              Icons.event,
                                              color: Color(0xFF810725),
                                            ),
                                            title: Text(title),
                                            subtitle: Text(
                                              DateFormat(
                                                'EEEE, MMM d, yyyy',
                                              ).format(startTime),
                                              style: const TextStyle(
                                                color: Color(0xFF777777),
                                              ),
                                            ),
                                            trailing: Text(
                                              formattedTime,
                                              style: const TextStyle(
                                                color: Color(0xFF555555),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // Reserve button
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: TextButton(
                            onPressed: () {
                              Navigator.pushNamed(context, '/booking');
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFF810725),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Reserve Room',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
