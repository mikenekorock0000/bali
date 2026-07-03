import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/save_service.dart';

class SaveListSection extends StatefulWidget {
  const SaveListSection({super.key});

  @override
  State<SaveListSection> createState() => _SaveListSectionState();
}

class _SaveListSectionState extends State<SaveListSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshSaves();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.saves.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('続きから', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...app.saves.take(3).map((save) => _SaveTile(save: save)),
          ],
        ),
      ),
    );
  }
}

class _SaveTile extends StatelessWidget {
  const _SaveTile({required this.save});

  final SaveSummary save;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(save.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${save.phase} · ${save.playerCount}人'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () => app.deleteSave(save.id),
      ),
      onTap: () => app.resumeFromSave(save.id),
    );
  }
}
