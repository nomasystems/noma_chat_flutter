// Mocks the image_cropper / path_provider platform interfaces, which are
// transitive (not direct) dependencies — declaring them in pubspec just to
// satisfy the lint is noise for a test-only mock.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.tempPath);

  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

class _FakeImageCropper extends ImageCropperPlatform
    with MockPlatformInterfaceMixin {
  final List<String> sourcePaths = [];
  String? resultPath;

  @override
  Future<CroppedFile?> cropImage({
    required String sourcePath,
    int? maxWidth,
    int? maxHeight,
    CropAspectRatio? aspectRatio,
    ImageCompressFormat compressFormat = ImageCompressFormat.jpg,
    int compressQuality = 90,
    List<PlatformUiSettings>? uiSettings,
  }) async {
    sourcePaths.add(sourcePath);
    return resultPath == null ? null : CroppedFile(resultPath!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeImageCropper cropper;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('noma_avatar_crop_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    cropper = _FakeImageCropper();
    ImageCropperPlatform.instance = cropper;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<Uint8List?> runCrop(WidgetTester tester, Uint8List source) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    Uint8List? result;
    await tester.runAsync(() async {
      result = await AvatarCropPage.show(context: ctx, sourceBytes: source);
    });
    return result;
  }

  testWidgets('writes the source to a temp file and forwards it to the '
      'cropper', (tester) async {
    await runCrop(tester, Uint8List.fromList([9, 8, 7, 6]));

    expect(cropper.sourcePaths, hasLength(1));
    expect(cropper.sourcePaths.single, startsWith(tempDir.path));
  });

  testWidgets('returns null when the user cancels the crop', (tester) async {
    cropper.resultPath = null;

    final result = await runCrop(tester, Uint8List.fromList([1, 2, 3]));

    expect(result, isNull);
  });

  testWidgets('returns the cropped bytes when the cropper yields a file', (
    tester,
  ) async {
    final croppedBytes = Uint8List.fromList([42, 43, 44, 45]);
    final croppedFile = File('${tempDir.path}/cropped_out.jpg')
      ..writeAsBytesSync(croppedBytes);
    cropper.resultPath = croppedFile.path;

    final result = await runCrop(tester, Uint8List.fromList([1, 2, 3]));

    expect(result, croppedBytes);
  });

  testWidgets('deletes the temp source file after a successful crop', (
    tester,
  ) async {
    final croppedFile = File('${tempDir.path}/cropped_out.jpg')
      ..writeAsBytesSync(Uint8List.fromList([1]));
    cropper.resultPath = croppedFile.path;

    await runCrop(tester, Uint8List.fromList([1, 2, 3]));

    expect(File(cropper.sourcePaths.single).existsSync(), isFalse);
  });
}
