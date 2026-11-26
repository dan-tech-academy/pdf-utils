import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import 'files.dart';
import 'viewer_screen.dart';

/// Icon on a softly tinted rounded square — the leading visual for tools,
/// pick targets and results.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 40});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.52, color: scheme.onPrimaryContainer),
    );
  }
}

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
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconTile(icon, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.titleMedium),
                    if (picked != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        picked!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing case final t?) ...[
                const SizedBox(width: 12),
                // A short badge; capping its growth keeps the row from
                // overflowing at the largest accessibility text sizes.
                MediaQuery.withClampedTextScaling(maxScaleFactor: 2, child: t),
              ],
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
            leading: CircleAvatar(
              radius: 14,
              child: Text(
                '${i + 1}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            title: Text(
              fileBaseName(files[i].path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(formatBytes(files[i].lengthSync())),
            trailing: onRemove == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Bỏ khỏi danh sách',
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
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
      child: Text(label),
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
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
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
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final isPdf = file.path.toLowerCase().endsWith('.pdf');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconTile(Icons.check_rounded),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileBaseName(file.path),
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(formatBytes(file.lengthSync()), style: muted),
                      if (extra != null) Text(extra!, style: muted),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: isPdf
                      ? OutlinedButton.icon(
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Xem'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ViewerScreen(file: file),
                            ),
                          ),
                        )
                      : OutlinedButton.icon(
                          icon: const Icon(Icons.open_in_new_outlined),
                          label: const Text('Mở'),
                          onPressed: () => OpenFile.open(file.path),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.share_outlined),
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
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconTile(Icons.check_rounded),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Đã tạo ${files.length} file',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final f in files)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(
                  fileBaseName(f.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(formatBytes(f.lengthSync())),
                trailing: IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Chia sẻ',
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
              icon: const Icon(Icons.share_outlined),
              label: const Text('Chia sẻ tất cả'),
              onPressed: () => SharePlus.instance.share(
                ShareParams(files: files.map((f) => XFile(f.path)).toList()),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.errorContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.error.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: scheme.error, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
