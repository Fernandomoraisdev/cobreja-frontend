import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const List<String> _secretParts = [
  'PEGUEI&PAGUEI',
  '_WIN',
  '_LIC',
  '_2026',
  '_FMB',
  '_0720',
];

String get _secret => _secretParts.join();

String _base64Url(String input) {
  return base64Url.encode(utf8.encode(input)).replaceAll('=', '');
}

String _signature(String payloadBase64) {
  final hmac = Hmac(sha256, utf8.encode(_secret));
  return hmac.convert(utf8.encode(payloadBase64)).toString().toUpperCase();
}

String _readRequired(String label) {
  stdout.write('$label: ');
  final value = stdin.readLineSync()?.trim() ?? '';
  if (value.isEmpty) {
    stderr.writeln('Valor obrigatorio.');
    _waitToClose();
    exit(1);
  }
  return value;
}

void _waitToClose() {
  stdout.writeln('');
  stdout.write('Pressione Enter para fechar...');
  stdin.readLineSync();
}

String _safeFileName(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

void main(List<String> args) {
  stdout.writeln('=== Gerador de licencas Peguei & Paguei Windows ===');
  stdout.writeln('');

  final machineCode = _readRequired('Codigo da maquina').toUpperCase();
  final customerName = _readRequired('Nome do cliente');

  stdout.writeln('');
  stdout.writeln('Tipo de licenca:');
  stdout.writeln('1 - Vitalicia');
  stdout.writeln('2 - Uso unico');
  stdout.writeln('3 - Assinatura');
  stdout.write('Escolha: ');
  final rawType = stdin.readLineSync()?.trim() ?? '1';

  String type = 'lifetime';
  String typeLabel = 'Vitalicia';
  String? expiresAt;

  switch (rawType) {
    case '2':
      type = 'single_use';
      typeLabel = 'Uso unico';
      break;
    case '3':
      type = 'subscription';
      typeLabel = 'Assinatura';
      stdout.write('Quantidade de dias da assinatura [30]: ');
      final daysRaw = stdin.readLineSync()?.trim();
      final days = int.tryParse(daysRaw ?? '') ?? 30;
      expiresAt = DateTime.now()
          .toUtc()
          .add(Duration(days: days))
          .toIso8601String();
      break;
    default:
      type = 'lifetime';
      typeLabel = 'Vitalicia';
  }

  final payload = <String, dynamic>{
    'product': 'PEGUEI&PAGUEI_WINDOWS',
    'machineCode': machineCode,
    'type': type,
    'customerName': customerName,
    'issuedAt': DateTime.now().toUtc().toIso8601String(),
    'expiresAt': expiresAt,
    'licenseId': DateTime.now().microsecondsSinceEpoch.toString(),
  };

  final payloadBase64 = _base64Url(jsonEncode(payload));
  final license = '$payloadBase64.${_signature(payloadBase64)}';

  final outputDir = File(Platform.resolvedExecutable).parent;
  final outputFile = File(
    '${outputDir.path}\\licenca_${_safeFileName(customerName)}_${DateTime.now().millisecondsSinceEpoch}.txt',
  );

  outputFile.writeAsStringSync('''
Peguei & Paguei - Licenca Windows

Cliente: $customerName
Tipo: $typeLabel
Codigo da maquina: $machineCode
${expiresAt != null ? 'Expira em: $expiresAt' : 'Sem vencimento'}

Licenca:
$license
''');

  stdout.writeln('');
  stdout.writeln('Licenca gerada com sucesso.');
  stdout.writeln('');
  stdout.writeln('Cliente: $customerName');
  stdout.writeln('Tipo: $typeLabel');
  stdout.writeln('Codigo da maquina: $machineCode');
  if (expiresAt != null) {
    stdout.writeln('Expira em: $expiresAt');
  }
  stdout.writeln('');
  stdout.writeln('Licenca:');
  stdout.writeln(license);
  stdout.writeln('');
  stdout.writeln('Arquivo salvo em: ${outputFile.path}');

  _waitToClose();
}
