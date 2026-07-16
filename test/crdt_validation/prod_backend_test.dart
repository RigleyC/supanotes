import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('Phase 3 Real E2E: Collaboration via PROD Backend (fly.dev)', () async {
    const baseUrl = 'https://backend-winter-waterfall-5807.fly.dev/api/v1';
    final wsUrl = baseUrl.replaceFirst('http', 'ws');
    final dio = Dio();
    
    // 1. Criar dois usuários reais no banco de produção
    final uuid = const Uuid().v4().substring(0, 8);
    final emailA = 'userA_$uuid@test.com';
    final emailB = 'userB_$uuid@test.com';
    
    print('Registrando User A ($emailA) no Fly.io...');
    final resA = await dio.post('$baseUrl/auth/register', data: {
      'email': emailA,
      'password': 'password123',
      'name': 'Client A'
    });
    final tokenA = resA.data['access_token'];

    print('Registrando User B ($emailB) no Fly.io...');
    final resB = await dio.post('$baseUrl/auth/register', data: {
      'email': emailB,
      'password': 'password123',
      'name': 'Client B'
    });
    final tokenB = resB.data['access_token'];
    
    // 2. Setup Yjs
    final docA = CRDTDocument(peerId: PeerId.parse('00000000-0000-4000-8000-000000000001'))..registerDefaultFactories();
    final docB = CRDTDocument(peerId: PeerId.parse('00000000-0000-4000-8000-000000000002'))..registerDefaultFactories();
    
    final noteId = 'note-$uuid';
    final textA = CRDTFugueTextHandler(docA, 'note_text_$noteId');
    final textB = CRDTFugueTextHandler(docB, 'note_text_$noteId');

    // 3. Conectar WebSockets no backend de produção
    final channelA = WebSocketChannel.connect(Uri.parse('$wsUrl/sync?token=$tokenA&room=$noteId'));
    final channelB = WebSocketChannel.connect(Uri.parse('$wsUrl/sync?token=$tokenB&room=$noteId'));
    
    channelA.stream.listen((data) {
      if (data is List<int>) docA.binaryImportChanges(Uint8List.fromList(data));
    });
    channelB.stream.listen((data) {
      if (data is List<int>) docB.binaryImportChanges(Uint8List.fromList(data));
    });

    // 4. Testar Colaboração C11/C12 (Simultânea no Fly.io)
    textA.insert(0, "Backend ");
    channelA.sink.add(docA.binaryExportChanges());
    
    // Esperar um pouco para a rede propagar pelo Fly.io
    await Future.delayed(const Duration(seconds: 2));
    
    // Agora o B deveria ter recebido o "Backend " via WS do Fly.io
    textB.insert(8, "Prod ");
    channelB.sink.add(docB.binaryExportChanges());

    await Future.delayed(const Duration(seconds: 2));
    
    // Ambos inserem simultaneamente (C12)
    textA.insert(13, "Works");
    textB.insert(13, "!");
    
    channelA.sink.add(docA.binaryExportChanges());
    channelB.sink.add(docB.binaryExportChanges());

    await Future.delayed(const Duration(seconds: 3));

    print('Doc A Text: ${textA.value}');
    print('Doc B Text: ${textB.value}');

    expect(textA.value, equals(textB.value));
    
    await channelA.sink.close();
    await channelB.sink.close();
  }, timeout: const Timeout(Duration(minutes: 1)));
}
