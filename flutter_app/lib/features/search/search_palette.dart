/// Global search command palette (Ctrl/Cmd+K).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../providers.dart';

void showSearchPalette(BuildContext context, WidgetRef ref) {
  showDialog<void>(
    context: context,
    builder: (_) => const Dialog(
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.only(top: 80, left: 24, right: 24),
      child: SizedBox(width: 640, child: _SearchPalette()),
    ),
  );
}

class _SearchPalette extends ConsumerStatefulWidget {
  const _SearchPalette();

  @override
  ConsumerState<_SearchPalette> createState() => _SearchPaletteState();
}

class _SearchPaletteState extends ConsumerState<_SearchPalette> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final state = stateOf(ref);
    final hits = globalSearch(state, query);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search contacts, messages, calls, campaigns…',
            ),
            onChanged: (v) => setState(() => query = v),
          ),
        ),
        Flexible(
          child: hits.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(query.isEmpty ? 'Type to search everything.' : 'No results.',
                      style: const TextStyle(color: PowerlineColors.textSecondary)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: hits.length,
                  itemBuilder: (c, i) {
                    final h = hits[i];
                    return ListTile(
                      dense: true,
                      leading: Chip(
                        label: Text(h.category, style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                      ),
                      title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(h.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.go(h.route);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
