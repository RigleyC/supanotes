import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:args/args.dart';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:yjs_dart/src/utils/snapshot.dart'; // Direct import for encode/decodeSnapshot
import 'package:yjs_dart/src/utils/struct_store.dart'; // For getState, findIndexSS, getItemCleanStart
import 'package:yjs_dart/src/utils/id_set.dart' hide findIndexSS; // For writeIdSet
import 'package:yjs_dart/src/lib0/encoding.dart' as lib0_encoding;
import 'package:yjs_dart/src/structs/item.dart';
import 'package:yjs_dart/src/structs/content.dart';

void main(List<String> args) async {
  // Fix yjs_dart library bug: override buggy _ContentStringStub with real ContentString reader
  contentRefs[4] = (decoder) => ContentString(decoder.readString() as String);

  final parser = ArgParser()
    ..addOption('mode', allowed: ['generate', 'verify'], defaultsTo: 'verify')
    ..addOption('case');
  
  final results = parser.parse(args);
  final mode = results['mode']!;
  final targetCase = results['case'];

  final casesDir = Directory('../cases');
  if (!casesDir.existsSync()) {
    print('Error: cases directory does not exist');
    exit(1);
  }

  final cases = casesDir.listSync()
      .whereType<Directory>()
      .map((d) => d.path.split(Platform.pathSeparator).last)
      .toList()
    ..sort();

  var failed = false;

  for (final caseName in cases) {
    if (targetCase != null && caseName != targetCase) continue;
    print('Running case: $caseName in $mode mode...');
    try {
      await runCase(caseName, mode);
      print('✅ Case $caseName passed');
    } catch (e, stack) {
      print('❌ Case $caseName FAILED: $e');
      print(stack);
      failed = true;
    }
  }

  if (failed) {
    exit(1);
  }
}

// Custom V1 snapshot restoration to bypass the yjs_dart V2 StringDecoder bug
Doc customCreateDocFromSnapshot(Doc originDoc, Snapshot snap, Doc newDoc) {
  if (originDoc.gc) {
    throw StateError('Garbage-collection must be disabled in originDoc!');
  }

  final sv = snap.sv;
  final ds = snap.ds;
  final encoder = UpdateEncoderV1();

  originDoc.transact((transaction) {
    var size = 0;
    sv.forEach((client, clock) {
      if (clock > 0) size++;
    });
    lib0_encoding.writeVarUint(encoder.restEncoder, size);
    final store = originDoc.store;
    for (final entry in sv.entries) {
      final client = entry.key;
      final clock = entry.value;
      if (clock == 0) continue;
      if (clock < getState(store, client)) {
        getItemCleanStart(transaction, createID(client, clock));
      }
      final structs = store.clients[client] ?? [];
      final lastStructIndex = findIndexSS(structs, clock - 1);
      lib0_encoding.writeVarUint(encoder.restEncoder, lastStructIndex + 1);
      encoder.writeClient(client);
      lib0_encoding.writeVarUint(encoder.restEncoder, 0);
      for (var i = 0; i <= lastStructIndex; i++) {
        // ignore: avoid_dynamic_calls
        (structs[i] as dynamic).write(encoder, 0, 0);
      }
    }
    writeIdSet(encoder, ds);
  });

  applyUpdate(newDoc, encoder.toUint8Array());
  return newDoc;
}

Future<void> runCase(String caseName, String mode) async {
  final stepsFile = File('../cases/$caseName/steps.json');
  if (!stepsFile.existsSync()) {
    throw Exception('steps.json not found');
  }

  final data = jsonDecode(stepsFile.readAsStringSync()) as Map<String, dynamic>;
  final clientNames = List<String>.from(data['clients'] as List);
  final steps = data['steps'] as List;

  // Scan steps to determine the type schema (name -> kind)
  final typeSchemas = <String, String>{};
  for (final stepObj in steps) {
    final step = stepObj as Map<String, dynamic>;
    final action = step['action'] as String;
    final name = step['name'] as String?;
    if (name == null) continue;
    
    if (action.startsWith('text_')) {
      typeSchemas[name] = 'text';
    } else if (action.startsWith('map_')) {
      typeSchemas[name] = 'map';
    } else if (action.startsWith('array_')) {
      typeSchemas[name] = 'array';
    }
  }

  // Initialize documents with gc: false to support snapshot operations
  final docs = <String, Doc>{};
  for (final name in clientNames) {
    final clientID = name.codeUnitAt(0);
    final doc = Doc(DocOpts(gc: false, clientID: clientID));
    docs[name] = doc;
    print('DEBUG: Doc $name clientID: ${doc.clientID}');
    
    // Pre-initialize types so update decoders do not fallback to YMap
    typeSchemas.forEach((typeName, typeKind) {
      if (typeKind == 'text') {
        doc.getText(typeName);
      } else if (typeKind == 'map') {
        doc.getMap(typeName);
      } else if (typeKind == 'array') {
        doc.getArray(typeName);
      }
    });
  }

  final updates = <String, Uint8List>{};
  final stateVectors = <String, Uint8List>{};
  final snapshots = <String, Snapshot>{};
  final undoManagers = <String, Map<String, UndoManager>>{};

  // Helper to ensure parent directory for fixtures exists
  void ensureFixturesDir() {
    final dir = Directory('../cases/$caseName/fixtures');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  for (var stepIndex = 0; stepIndex < steps.length; stepIndex++) {
    final step = steps[stepIndex] as Map<String, dynamic>;
    final client = step['client'] as String?;
    final action = step['action'] as String;

    switch (action) {
      case 'text_insert':
        final doc = docs[client]!;
        final textName = step['name'] as String;
        final index = step['index'] as int;
        final value = step['value'] as String;
        final text = doc.getText(textName)!;
        text.insert(index, value);
        break;

      case 'text_delete':
        final doc = docs[client]!;
        final textName = step['name'] as String;
        final index = step['index'] as int;
        final length = step['length'] as int;
        final text = doc.getText(textName)!;
        text.delete(index, length);
        break;

      case 'map_set':
        final doc = docs[client]!;
        final mapName = step['name'] as String;
        final key = step['key'] as String;
        final value = step['value'];
        final map = doc.getMap(mapName)!;
        map.set(key, value);
        break;

      case 'array_insert':
        final doc = docs[client]!;
        final arrayName = step['name'] as String;
        final index = step['index'] as int;
        final value = step['value'];
        final array = doc.getArray(arrayName)!;
        array.insert(index, [value]);
        break;

      case 'export_update':
        final doc = docs[client]!;
        final id = step['id'] as String;
        final update = encodeStateAsUpdate(doc);
        updates[id] = update;
        if (mode == 'generate') {
          ensureFixturesDir();
          File('../cases/$caseName/fixtures/$id.bin').writeAsBytesSync(update);
        }
        break;

      case 'import_update':
        final doc = docs[client]!;
        final id = step['id'] as String;
        Uint8List updateBytes;
        if (mode == 'verify') {
          final file = File('../cases/$caseName/fixtures/$id.bin');
          if (!file.existsSync()) {
            throw Exception('Fixture $id.bin not found for case $caseName');
          }
          updateBytes = file.readAsBytesSync();
        } else {
          updateBytes = updates[id]!;
        }
        applyUpdate(doc, updateBytes);
        break;

      case 'export_state_vector':
        final doc = docs[client]!;
        final id = step['id'] as String;
        final sv = encodeStateVector(doc);
        stateVectors[id] = sv;
        break;

      case 'import_state_vector_and_export_diff':
        final doc = docs[client]!;
        final svId = step['state_vector_id'] as String;
        final diffId = step['diff_id'] as String;
        final sv = stateVectors[svId]!;
        final diff = encodeStateAsUpdate(doc, sv);
        updates[diffId] = diff;
        if (mode == 'generate') {
          ensureFixturesDir();
          File('../cases/$caseName/fixtures/$diffId.bin').writeAsBytesSync(diff);
        }
        break;

      case 'take_snapshot':
        final doc = docs[client]!;
        final id = step['id'] as String;
        final snap = snapshot(doc);
        snapshots[id] = snap;
        if (mode == 'generate') {
          ensureFixturesDir();
          final bytes = encodeSnapshot(snap);
          File('../cases/$caseName/fixtures/$id.snap').writeAsBytesSync(bytes);
        }
        break;

      case 'restore_snapshot':
        final sourceClient = step['source_client'] as String;
        final snapId = step['snapshot_id'] as String;
        final sourceDoc = docs[sourceClient]!;
        Snapshot snap;
        if (mode == 'verify') {
          final file = File('../cases/$caseName/fixtures/$snapId.snap');
          if (!file.existsSync()) {
            throw Exception('Snapshot $snapId.snap not found for case $caseName');
          }
          snap = decodeSnapshot(file.readAsBytesSync());
        } else {
          snap = snapshots[snapId]!;
        }
        final targetDoc = docs[client!]!;
        customCreateDocFromSnapshot(sourceDoc, snap, targetDoc);
        break;

      case 'undo':
        final doc = docs[client]!;
        final name = step['name'] as String;
        final clientManagers = undoManagers.putIfAbsent(client!, () => {});
        final um = clientManagers.putIfAbsent(name, () {
          final type = doc.share[name]!;
          return UndoManager(type);
        });
        um.undo();
        break;

      case 'redo':
        final doc = docs[client]!;
        final name = step['name'] as String;
        final clientManagers = undoManagers.putIfAbsent(client!, () => {});
        final um = clientManagers.putIfAbsent(name, () {
          final type = doc.share[name]!;
          return UndoManager(type);
        });
        um.redo();
        break;

      default:
        throw Exception('Unknown action: $action');
    }
  }

  // 1. Gather final states
  final finalStates = <String, Map<String, dynamic>>{};
  for (final name in clientNames) {
    final doc = docs[name]!;
    final state = <String, dynamic>{};
    
    // Serialize shared types
    final textState = <String, String>{};
    final mapState = <String, dynamic>{};
    final arrayState = <String, List<dynamic>>{};

    doc.share.forEach((key, ytype) {
      if (ytype is YText) {
        textState[key] = ytype.toString();
      } else if (ytype is YMap) {
        mapState[key] = ytype.toJson();
      } else if (ytype is YArray) {
        arrayState[key] = ytype.toJson();
      }
    });

    if (textState.isNotEmpty) state['text'] = textState;
    if (mapState.isNotEmpty) state['map'] = mapState;
    if (arrayState.isNotEmpty) state['array'] = arrayState;

    finalStates[name] = state;
  }

  final expectedFile = File('../cases/$caseName/expected.json');

  if (mode == 'generate') {
    // Write expected outcomes to expected.json
    expectedFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'states': finalStates,
      'text_any_of': data['expected']['text_any_of'] // Keep any-of patterns
    }));
  } else {
    // Verify mode: check document states match expected.json
    if (!expectedFile.existsSync()) {
      throw Exception('expected.json not found for case $caseName');
    }
    final expectedData = jsonDecode(expectedFile.readAsStringSync()) as Map<String, dynamic>;
    final expectedStates = expectedData['states'] as Map<String, dynamic>;
    final expectedTextAnyOf = expectedData['text_any_of'] as Map<String, dynamic>?;

    for (final name in clientNames) {
      final actualState = finalStates[name]!;
      final expectedState = expectedStates[name] as Map<String, dynamic>;

      // Check text types
      if (expectedState['text'] != null) {
        final expectedText = expectedState['text'] as Map<String, dynamic>;
        final actualText = (actualState['text'] ?? <String, dynamic>{}) as Map<String, dynamic>;
        expectedText.forEach((key, val) {
          expect(actualText[key], val, 'Client $name text field $key mismatch');
        });
      }

      // Check map types
      if (expectedState['map'] != null) {
        final expectedMap = expectedState['map'] as Map<String, dynamic>;
        final actualMap = (actualState['map'] ?? <String, dynamic>{}) as Map<String, dynamic>;
        expect(actualMap, expectedMap, 'Client $name map mismatch');
      }

      // Check array types
      if (expectedState['array'] != null) {
        final expectedArray = expectedState['array'] as Map<String, dynamic>;
        final actualArray = (actualState['array'] ?? <String, dynamic>{}) as Map<String, dynamic>;
        expect(actualArray, expectedArray, 'Client $name array mismatch');
      }

      // Check any_of patterns (like anti-interleaving)
      if (expectedTextAnyOf != null) {
        final actualText = actualState['text'] as Map<String, dynamic>;
        expectedTextAnyOf.forEach((key, options) {
          final optsList = List<String>.from(options as List);
          if (!optsList.contains(actualText[key])) {
            throw Exception('Assertion failed: Client $name text field $key is "${actualText[key]}", expected one of $optsList');
          }
        });
      }
    }
  }
}

void expect(dynamic actual, dynamic expected, [String? reason]) {
  if (!areEqual(actual, expected)) {
    throw Exception('Assertion failed: Expected: $expected, Actual: $actual. Reason: $reason');
  }
}

bool areEqual(dynamic a, dynamic b) {
  if (a == b) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!areEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!areEqual(a[key], b[key])) return false;
    }
    return true;
  }
  return false;
}
