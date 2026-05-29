import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SDK persistent cache (Hive) must be initialized before NomaChat.create.
  await Hive.initFlutter();
  runApp(const NomaChatExampleApp());
}
