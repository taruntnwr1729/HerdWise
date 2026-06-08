import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Import your main app file
import 'package:animal_health_app/main.dart';

void main() {
testWidgets('HerdWise app loads successfully', (WidgetTester tester) async {
// Build the app
await tester.pumpWidget(const HerdWiseApp());

```
// Verify that MaterialApp is present
expect(find.byType(MaterialApp), findsOneWidget);

// You can also check for your app title text
expect(find.text('HerdWise Pro'), findsOneWidget);
```

});
}
