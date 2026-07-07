import 'dart:convert';
import 'dart:io';

void main() {
  final cases = <String, Map<String, dynamic>>{};

  // Case 1: Basic Insert
  cases['01_basic_insert'] = {
    'name': 'Basic Insert (Dart -> Go)',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Hello'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'}
    ],
    'expected': {
      'text': {'note': 'Hello'}
    }
  };

  // Case 2: Go -> Dart
  cases['02_go_to_dart'] = {
    'name': 'Go -> Dart sync',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Hello'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': ' World'},
      {'client': 'B', 'action': 'export_update', 'id': 'u2'},
      {'client': 'A', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'text': {'note': 'Hello World'}
    }
  };

  // Case 3: Out of Order Updates
  cases['03_out_of_order'] = {
    'name': 'Out of Order updates',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Hello'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': ' World'},
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 11, 'value': '!!!'},
      {'client': 'A', 'action': 'export_update', 'id': 'u3'},
      // Import out of order on B
      {'client': 'B', 'action': 'import_update', 'id': 'u3'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'text': {'note': 'Hello World!!!'}
    }
  };

  // Case 4: Duplicate Updates
  cases['04_duplicate'] = {
    'name': 'Duplicate updates',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Hello'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'} // Duplicate import
    ],
    'expected': {
      'text': {'note': 'Hello'}
    }
  };

  // Case 5: State Vector Sync
  cases['05_state_vector'] = {
    'name': 'State Vector diffing',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Hello'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // Concurrent edits
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': '!'},
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': ' World'},
      
      // Sync A to B using state vectors
      {'client': 'A', 'action': 'export_state_vector', 'id': 'svA'},
      {'client': 'B', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svA', 'diff_id': 'diffB'},
      {'client': 'A', 'action': 'import_update', 'id': 'diffB'},

      // Sync B to A using state vectors
      {'client': 'B', 'action': 'export_state_vector', 'id': 'svB'},
      {'client': 'A', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svB', 'diff_id': 'diffA'},
      {'client': 'B', 'action': 'import_update', 'id': 'diffA'}
    ],
    'expected': {
      'text': {'note': 'Hello World!'}
    }
  };

  // Case 6: Snapshot
  cases['06_snapshot'] = {
    'name': 'Snapshot capture and restore',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Hello'},
      {'client': 'A', 'action': 'take_snapshot', 'id': 'snap1'},
      {'client': 'A', 'action': 'text_delete', 'name': 'note', 'index': 2, 'length': 3}, // Text is "He"
      {'client': 'B', 'action': 'restore_snapshot', 'source_client': 'A', 'snapshot_id': 'snap1'}
    ],
    'expected': {
      'text': {'note': 'Hello'} // Client B restored snapshot state
    }
  };

  // Case 7: Anti-interleaving
  cases['07_anti_interleaving'] = {
    'name': 'Anti-interleaving (concurrent inserts)',
    'clients': ['A', 'B', 'C'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Hello'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'C', 'action': 'import_update', 'id': 'u1'},
      
      // Concurrent inserts at same index 5
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': ' Ola'},
      {'client': 'B', 'action': 'export_update', 'id': 'u2'},
      {'client': 'C', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': ' World'},
      {'client': 'C', 'action': 'export_update', 'id': 'u3'},
      
      // Sync B and C
      {'client': 'B', 'action': 'import_update', 'id': 'u3'},
      {'client': 'C', 'action': 'import_update', 'id': 'u2'},
      {'client': 'A', 'action': 'import_update', 'id': 'u2'},
      {'client': 'A', 'action': 'import_update', 'id': 'u3'}
    ],
    'expected': {
      // Must be identical and either "Hello Ola World" or "Hello World Ola"
      'text_any_of': {
        'note': ['Hello Ola World', 'Hello World Ola']
      }
    }
  };

  // Case 8: Overlapping Deletes
  cases['08_overlapping_deletes'] = {
    'name': 'Concurrent overlapping deletes',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'The quick brown fox jumps over the lazy dog'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // A deletes indices 4-16 ("quick brown ")
      {'client': 'A', 'action': 'text_delete', 'name': 'note', 'index': 4, 'length': 12},
      
      // B deletes indices 10-22 ("brown fox ju")
      {'client': 'B', 'action': 'text_delete', 'name': 'note', 'index': 10, 'length': 12},
      
      // Sync A and B using state vector diffs to prevent clientID collisions
      {'client': 'A', 'action': 'export_state_vector', 'id': 'svA'},
      {'client': 'B', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svA', 'diff_id': 'diffB'},
      {'client': 'A', 'action': 'import_update', 'id': 'diffB'},

      {'client': 'B', 'action': 'export_state_vector', 'id': 'svB'},
      {'client': 'A', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svB', 'diff_id': 'diffA'},
      {'client': 'B', 'action': 'import_update', 'id': 'diffA'}
    ],
    'expected': {
      'text': {'note': 'The mps over the lazy dog'}
    }
  };

  // Case 9: Map properties
  cases['09_map'] = {
    'name': 'Map compatibility (nested objects)',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'map_set', 'name': 'meta', 'key': 'title', 'value': 'Nota'},
      {'client': 'A', 'action': 'map_set', 'name': 'meta', 'key': 'tags', 'value': ['flutter', 'sync']},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'}
    ],
    'expected': {
      'map': {
        'meta': {
          'title': 'Nota',
          'tags': ['flutter', 'sync']
        }
      }
    }
  };

  // Case 10: Array properties
  cases['10_array'] = {
    'name': 'Array compatibility (push and insert)',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'array_insert', 'name': 'list', 'index': 0, 'value': 'item1'},
      {'client': 'A', 'action': 'array_insert', 'name': 'list', 'index': 1, 'value': 'item2'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      {'client': 'B', 'action': 'array_insert', 'name': 'list', 'index': 0, 'value': 'item0'},
      {'client': 'B', 'action': 'export_update', 'id': 'u2'},
      {'client': 'A', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'array': {
        'list': ['item0', 'item1', 'item2']
      }
    }
  };

  // Case 11: Large Document (10k characters)
  final largeText = 'Line of text for large document scale test.\n' * 250; // ~11k characters
  cases['11_large_doc'] = {
    'name': 'Large Document scale integration',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': largeText},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'}
    ],
    'expected': {
      'text': {'note': largeText}
    }
  };

  // Case 12: Fuzzing (Pre-defined pseudo-random actions)
  cases['12_fuzzing'] = {
    'name': 'Deterministic Fuzzing convergence',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Initial'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // Sequence of random-like concurrent edits
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 7, 'value': ' EditA'},
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'EditB '},
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      {'client': 'B', 'action': 'export_update', 'id': 'u3'},
      
      {'client': 'A', 'action': 'import_update', 'id': 'u3'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'},
      
      {'client': 'A', 'action': 'text_delete', 'name': 'note', 'index': 6, 'length': 8},
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 2, 'value': 'x'},
      {'client': 'A', 'action': 'export_update', 'id': 'u4'},
      {'client': 'B', 'action': 'export_update', 'id': 'u5'},
      
      {'client': 'A', 'action': 'import_update', 'id': 'u5'},
      {'client': 'B', 'action': 'import_update', 'id': 'u4'}
    ],
    'expected': {
      'text': {'note': 'EdxitiAl EditA'} // Will be updated by generator
    }
  };

  // Case 13: Persistence (Full update backup & restore)
  cases['13_persistence'] = {
    'name': 'Full document persistence backup & restore',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Saved State'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      
      // Restoring B from u1 (like disk read)
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // Continue editing
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 11, 'value': ' - Loaded'},
      {'client': 'B', 'action': 'export_update', 'id': 'u2'},
      {'client': 'A', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'text': {'note': 'Saved State - Loaded'}
    }
  };

  // Case 14: Incremental sync
  cases['14_incremental'] = {
    'name': 'Incremental sync updates exchange',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Start'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': ' A'},
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'},
      
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 7, 'value': ' B'},
      {'client': 'B', 'action': 'export_update', 'id': 'u3'},
      {'client': 'A', 'action': 'import_update', 'id': 'u3'}
    ],
    'expected': {
      'text': {'note': 'Start A B'}
    }
  };

  // Case 15: SupaNotes Real-world Markdown Sync
  final initialMarkdown = '# Projeto\n\n- [ ] Comprar VPS\n\n## Backend\n\nLorem ipsum...';
  cases['15_supanotes_markdown'] = {
    'name': 'SupaNotes Markdown concurrent task edit',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': initialMarkdown},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // A marks task completed: updates "- [ ]" to "- [x]" (replaces ' ' with 'x' at index 14)
      {'client': 'A', 'action': 'text_delete', 'name': 'note', 'index': 14, 'length': 1},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 14, 'value': 'x'},
      
      // B concurrently changes title to "# Projeto SupaNotes" (inserts " SupaNotes" at index 9)
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 9, 'value': ' SupaNotes'},
      
      // Sync A and B using state vector diffs to prevent clientID collisions
      {'client': 'A', 'action': 'export_state_vector', 'id': 'svA'},
      {'client': 'B', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svA', 'diff_id': 'diffB'},
      {'client': 'A', 'action': 'import_update', 'id': 'diffB'},

      {'client': 'B', 'action': 'export_state_vector', 'id': 'svB'},
      {'client': 'A', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svB', 'diff_id': 'diffA'},
      {'client': 'B', 'action': 'import_update', 'id': 'diffA'}
    ],
    'expected': {
      'text': {
        'note': '# Projeto SupaNotes\n\n- [x] Comprar VPS\n\n## Backend\n\nLorem ipsum...'
      }
    }
  };

  // Write all case steps files
  cases.forEach((dirName, data) {
    final dir = Directory('compatibility_test/cases/$dirName');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    
    // Write steps.json
    final stepsFile = File('${dir.path}/steps.json');
    stepsFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    print('Generated cases/$dirName/steps.json');
  });

  print('Done generating all cases.');
}
