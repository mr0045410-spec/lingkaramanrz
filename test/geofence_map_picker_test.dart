import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:lingkar_aman/widgets/geofence_map_picker.dart';

void main() {
  testWidgets('GeofenceMapPicker renders UI elements properly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GeofenceMapPicker(
          circleId: 'test-circle-id',
          initialCenter: LatLng(-6.2088, 106.8456),
          initialCategory: 'home',
          initialRadius: 200.0,
        ),
      ),
    );

    // Verify title and prompt exist
    expect(find.text('Geser peta untuk menentukan titik zona'), findsOneWidget);
    expect(find.text('Zona Aman Ada di Sini'), findsOneWidget);
    expect(find.text('Radius:'), findsOneWidget);
    expect(find.text('Rumah'), findsWidgets);
    expect(find.text('Sekolah'), findsOneWidget);
    expect(find.text('Kantor'), findsOneWidget);
  });
}
