import 'dart:io';
import 'dart:typed_data';

Future<String?> saveFileBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  final userRoot =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];

  Directory targetDirectory = Directory.systemTemp;
  if (userRoot != null && userRoot.isNotEmpty) {
    final downloads = Directory('$userRoot${Platform.pathSeparator}Downloads');
    final documents = Directory('$userRoot${Platform.pathSeparator}Documents');
    if (await downloads.exists()) {
      targetDirectory = downloads;
    } else if (await documents.exists()) {
      targetDirectory = documents;
    }
  }

  final file = File(_buildUniquePath(targetDirectory.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

String _buildUniquePath(String directory, String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  final hasExtension = dotIndex > 0 && dotIndex < fileName.length - 1;
  final baseName = hasExtension ? fileName.substring(0, dotIndex) : fileName;
  final extension = hasExtension ? fileName.substring(dotIndex) : '';

  var candidate = '$directory${Platform.pathSeparator}$fileName';
  var counter = 2;
  while (File(candidate).existsSync()) {
    candidate =
        '$directory${Platform.pathSeparator}$baseName ($counter)$extension';
    counter++;
  }
  return candidate;
}
