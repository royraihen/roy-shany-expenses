import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<String?> loadWebStorageExpensesJson() async => null;

Future<void> saveWebStorageExpensesJson(String jsonStr) async {}

Future<String?> loadWebPairingPassword() async => null;

Future<void> saveWebPairingPassword(String password) async {}

String? consumeInitialWebSyncParam() => null;

Future<void> triggerWebNotification({
  required String title,
  required String body,
}) async {}

Future<void> shareRasbBytes({
  required String fileName,
  required String content,
  required String subject,
}) async {
  final tempDir = await getTemporaryDirectory();
  final filePath = p.join(tempDir.path, fileName);
  final file = File(filePath);
  await file.writeAsString(content, flush: true);

  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(
          file.path,
          name: fileName,
        ),
      ],
      subject: subject,
    ),
  );
}

Future<Map<String, String>?> pickRasbFileFromDevice() async => null;
