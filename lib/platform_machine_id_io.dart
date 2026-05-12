import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

bool get isWindowsDesktopPlatform => Platform.isWindows;

Future<String?> getPlatformMachineCode() async {
  if (!Platform.isWindows) return null;

  try {
    final result = await Process.run(
      'reg',
      const [
        'query',
        r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
      ],
    );

    final output = '${result.stdout}';
    final guidMatch = RegExp(
      r'MachineGuid\s+REG_SZ\s+([^\r\n]+)',
      caseSensitive: false,
    ).firstMatch(output);
    final machineGuid = guidMatch?.group(1)?.trim();

    final computerName = Platform.environment['COMPUTERNAME']?.trim() ?? '';

    if (machineGuid == null || machineGuid.isEmpty || computerName.isEmpty) {
      return null;
    }

    final raw = '$machineGuid|$computerName|PEGUEI_PAGUEI_WINDOWS';
    return sha256
        .convert(utf8.encode(raw))
        .toString()
        .substring(0, 32)
        .toUpperCase();
  } catch (_) {
    return null;
  }
}
