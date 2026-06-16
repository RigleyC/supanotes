import 'package:flutter/material.dart';

class ShareNoteDialog extends StatefulWidget {
  final String noteId;

  const ShareNoteDialog({super.key, required this.noteId});

  static Future<void> show(BuildContext context, String noteId) {
    return showDialog(
      context: context,
      builder: (context) => ShareNoteDialog(noteId: noteId),
    );
  }

  @override
  State<ShareNoteDialog> createState() => _ShareNoteDialogState();
}

class _ShareNoteDialogState extends State<ShareNoteDialog> {
  final _emailCtrl = TextEditingController();
  String _permission = 'view';

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Compartilhar Nota'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(labelText: 'E-mail'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _permission,
            decoration: const InputDecoration(labelText: 'Permissão'),
            items: const [
              DropdownMenuItem(value: 'view', child: Text('Visualizar')),
              DropdownMenuItem(value: 'edit', child: Text('Editar')),
            ],
            onChanged: (val) => setState(() => _permission = val!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        ElevatedButton(
          onPressed: () {
            // TODO: Call API POST /api/v1/notes/:id/shares
            Navigator.pop(context);
          },
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
