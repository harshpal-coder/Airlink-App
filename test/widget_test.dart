import 'package:flutter_test/flutter_test.dart';
import 'package:airlink/main.dart';
import 'package:airlink/injection.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:get_it/get_it.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    // Reset GetIt between tests to avoid duplicate registrations
    GetIt.instance.reset();
    setupInjection();
  });

  testWidgets('App initializes without crash', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Just verify it builds and shows the splash screen (initial route)
    expect(find.byType(MyApp), findsOneWidget);
  });
}
