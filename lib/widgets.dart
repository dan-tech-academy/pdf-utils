import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import 'files.dart';
import 'viewer_screen.dart';

/// Card that lets the user pick a file (PDF or image) and shows the pick.
class PickTile extends StatelessWidget {
  const PickTile({
    super.key,
    required this.icon,
    required this.label,
    this.picked,
    required this.onPick,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? picked;
  final VoidCallback onPick;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 36, color: scheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (picked != null)
                      Text(
                        picked!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled list of selected files (merge order, etc.).
class PickedFilesList extends StatelessWidget {
  const PickedFilesList({super.key, required this.files, this.onRemove});

  final List<File> files;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i < files.length; i++)
          ListTile(
            dense: true,
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(
              fileBaseName(files[i].path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(formatBytes(files[i].lengthSync())),
            trailing: onRemove == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => onRemove!(i),
                  ),
          ),
      ],
    );
  }
}

/// Big primary action button.
class RunButton extends StatelessWidget {
  const RunButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.play_arrow),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
      ),
    );
  }
}

/// Shows progress while a tool runs; supports cancel.
class RunningPane extends StatelessWidget {
  const RunningPane({super.key, required this.message, this.onCancel});

  final String message;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (onCancel != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onCancel, child: const Text('Hủy')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Result card for one produced file.
class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.file, this.extra});

  final File file;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final isPdf = file.path.toLowerCase().endsWith('.pdf');
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileBaseName(file.path),
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        formatBytes(file.lengthSync()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (extra != null)
                        Text(
                          extra!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (isPdf)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.visibility),
                      label: const Text('Xem'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ViewerScreen(file: file),
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Mở'),
                      onPressed: () => OpenFile.open(file.path),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.share),
                    label: const Text('Chia sẻ'),
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(files: [XFile(file.path)]),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Result card for several produced files.
class ResultFilesCard extends StatelessWidget {
  const ResultFilesCard({super.key, required this.files});

  final List<File> files;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đã tạo ${files.length} file',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final f in files)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description),
                title: Text(
                  fileBaseName(f.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(formatBytes(f.lengthSync())),
                trailing: IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(files: [XFile(f.path)]),
                  ),
                ),
                onTap: f.path.toLowerCase().endsWith('.pdf')
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ViewerScreen(file: f),
                          ),
                        )
                    : () => OpenFile.open(f.path),
              ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.share),
              label: const Text('Chia sẻ tất cả'),
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                  files: files.map((f) => XFile(f.path)).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error banner.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
