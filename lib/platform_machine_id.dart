import 'platform_machine_id_stub.dart'
    if (dart.library.io) 'platform_machine_id_io.dart' as impl;

bool get isWindowsDesktopPlatform => impl.isWindowsDesktopPlatform;

Future<String?> getPlatformMachineCode() => impl.getPlatformMachineCode();
