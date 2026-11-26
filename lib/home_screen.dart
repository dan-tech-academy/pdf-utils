import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'files.dart';
import 'pro.dart';
import 'screens/compress_screen.dart';
import 'screens/crop_screen.dart';
import 'screens/form_screen.dart';
import 'screens/images_to_pdf_screen.dart';
import 'screens/merge_screen.dart';
import 'screens/metadata_screen.dart';
import 'screens/numbering_screen.dart';
import 'screens/nup_screen.dart';
import 'screens/ocr_screen.dart';
import 'screens/office_screen.dart';
import 'screens/pages_screen.dart';
import 'screens/pdf_to_images_screen.dart';
import 'screens/pro_screen.dart';
import 'screens/protect_screen.dart';
import 'screens/redact_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/sign_screen.dart';
import 'screens/split_screen.dart';
import 'screens/stamp_screen.dart';
import 'screens/text_screen.dart';
import 'screens/watermark_screen.dart';
import 'viewer_screen.dart';
import 'widgets.dart';

class _Tool {
  const _Tool(this.icon, this.title, this.subtitle, this.builder,
      {this.isPro = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
  final bool isPro;
}

class _ToolGroup {
  const _ToolGroup(this.title, this.tools);
  final String title;
  final List<_Tool> tools;
}

/// Home sections, in display order. Within a group, free tools come first.
final _groups = <_ToolGroup>[
  _ToolGroup('File & trang', [
    _Tool(
      Icons.compress_outlined,
      'Nén PDF',
      'Giảm dung lượng file',
      (_) => const CompressScreen(),
    ),
    _Tool(
      Icons.merge_type_outlined,
      'Ghép PDF',
      'Nối nhiều PDF thành một',
      (_) => const MergeScreen(),
    ),
    _Tool(
      Icons.call_split_outlined,
      'Tách PDF',
      'Chia thành nhiều file nhỏ',
      (_) => const SplitScreen(),
    ),
    _Tool(
      Icons.auto_awesome_motion_outlined,
      'Sắp xếp trang',
      'Xoay, xóa, đổi thứ tự trang',
      (_) => const PagesScreen(),
    ),
    _Tool(
      Icons.crop_outlined,
      'Cắt lề trang',
      'Bớt lề trái/phải/trên/dưới',
      (_) => const CropScreen(),
      isPro: true,
    ),
    _Tool(
      Icons.grid_view_outlined,
      'N-up',
      'Gộp 2/4/6/9 trang lên 1 tờ',
      (_) => const NupScreen(),
      isPro: true,
    ),
  ]),
  _ToolGroup('Chỉnh sửa & ký', [
    _Tool(
      Icons.add_photo_alternate_outlined,
      'Chèn ảnh',
      'Đặt ảnh lên trang PDF',
      (_) => const StampScreen(),
    ),
    _Tool(
      Icons.draw_outlined,
      'Ký tên',
      'Vẽ chữ ký, đặt vào PDF',
      (_) => const SignScreen(),
    ),
    _Tool(
      Icons.branding_watermark_outlined,
      'Watermark',
      'Đóng dấu chữ lên trang',
      (_) => const WatermarkScreen(),
    ),
    _Tool(
      Icons.format_list_numbered_outlined,
      'Đánh số trang',
      'Thêm số trang / header-footer',
      (_) => const NumberingScreen(),
      isPro: true,
    ),
    _Tool(
      Icons.assignment_outlined,
      'Điền form',
      'Điền form PDF (AcroForm)',
      (_) => const FormScreen(),
      isPro: true,
    ),
    _Tool(
      Icons.hide_source_outlined,
      'Che nội dung',
      'Xóa vĩnh viễn vùng nhạy cảm',
      (_) => const RedactScreen(),
      isPro: true,
    ),
  ]),
  _ToolGroup('Chuyển đổi', [
    _Tool(
      Icons.document_scanner_outlined,
      'Scan → PDF',
      'Quét tài liệu bằng camera',
      (_) => const ScanScreen(),
    ),
    _Tool(
      Icons.photo_library_outlined,
      'Ảnh → PDF',
      'Tạo PDF từ nhiều ảnh',
      (_) => const ImagesToPdfScreen(),
    ),
    _Tool(
      Icons.image_outlined,
      'PDF → Ảnh',
      'Xuất trang PDF thành PNG',
      (_) => const PdfToImagesScreen(),
    ),
    _Tool(
      Icons.text_snippet_outlined,
      'Trích xuất text',
      'Lấy text ra file .txt',
      (_) => const TextScreen(),
    ),
    _Tool(
      Icons.text_fields_outlined,
      'OCR ảnh → text',
      'Nhận diện chữ trong ảnh (ML Kit)',
      (_) => const OcrScreen(),
      isPro: true,
    ),
    _Tool(
      Icons.swap_horiz_rounded,
      'PDF ↔ Office',
      'Đổi PDF sang Word/Excel/PPT & ngược lại',
      (_) => const OfficeScreen(),
      isPro: true,
    ),
  ]),
  _ToolGroup('Bảo mật & thông tin', [
    _Tool(
      Icons.lock_outline,
      'Khóa / Mở khóa',
      'Đặt hoặc gỡ mật khẩu PDF',
      (_) => const ProtectScreen(),
    ),
    _Tool(
      Icons.edit_note_outlined,
      'Metadata',
      'Sửa tiêu đề, tác giả',
      (_) => const MetadataScreen(),
    ),
    _Tool(
      Icons.picture_as_pdf_outlined,
      'Xem PDF',
      'Đọc file PDF trong app',
      (_) => const ViewerPickScreen(),
    ),
  ]),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<File> _outputs = const [];

  @override
  void initState() {
    super.initState();
    ProManager.instance.init();
    ProManager.instance.addListener(_onProChanged);
    _refresh();
  }

  @override
  void dispose() {
    ProManager.instance.removeListener(_onProChanged);
    super.dispose();
  }

  void _onProChanged() {
    if (mounted) setState(() {});
  }

  void _openTool(BuildContext context, _Tool t) {
    final target = (t.isPro && !ProManager.instance.isPro)
        ? (_) => const ProScreen()
        : t.builder;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: target))
        .then((_) => _refresh());
  }

  Future<void> _refresh() async {
    final files = await listOutputs();
    if (mounted) setState(() => _outputs = files);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPro = ProManager.instance.isPro;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Utils'),
        titleTextStyle: theme.textTheme.headlineSmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        toolbarHeight: 64,
        actions: [
          IconButton(
            icon: Icon(
              isPro
                  ? Icons.workspace_premium
                  : Icons.workspace_premium_outlined,
            ),
            tooltip: 'PDF Utils Pro',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Làm mới',
            onPressed: _refresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        // Eager on purpose: every tool row is built, so widget tests can
        // find titles below the fold without scrolling.
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final group in _groups) ...[
                _SectionHeader(group.title),
                _GroupCard(
                  children: [
                    for (final t in group.tools)
                      _ToolRow(
                        tool: t,
                        locked: t.isPro && !isPro,
                        onTap: () => _openTool(context, t),
                      ),
                  ],
                ),
              ],
              _SectionHeader(
                'File đã tạo',
                trailing: _outputs.isEmpty ? null : '${_outputs.length} file',
              ),
              if (_outputs.isEmpty)
                const _EmptyOutputs()
              else
                _GroupCard(
                  children: [
                    for (final f in _outputs.take(20)) _OutputRow(file: f),
                  ],
                ),
              const SizedBox(height: 28),
              Text(
                'Xử lý hoàn toàn trên máy • Pro mở khóa công cụ nâng cao',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              semanticsLabel: title,
              style: style?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (trailing case final t?) ...[
            const SizedBox(width: 12),
            Text(t, style: style),
          ],
        ],
      ),
    );
  }
}

/// White rounded card holding rows separated by hairlines.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            // Indented to start under the row text, past the icon tile.
            if (i > 0) const Divider(indent: 70),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.tool,
    required this.locked,
    required this.onTap,
  });

  final _Tool tool;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            IconTile(tool.icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tool.title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (locked) ...[
                        const SizedBox(width: 8),
                        const _ProTag(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    tool.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// Marks a tool that needs Pro; shown only while Pro is locked.
class _ProTag extends StatelessWidget {
  const _ProTag();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.6)),
      ),
      child: Text(
        'PRO',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _EmptyOutputs extends StatelessWidget {
  const _EmptyOutputs();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.folder_open_outlined, color: muted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Chưa có file nào. Kết quả của các công cụ sẽ hiện ở đây.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutputRow extends StatelessWidget {
  const _OutputRow({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final ext = file.path.split('.').last.toLowerCase();
    final isPdf = ext == 'pdf';
    final icon = switch (ext) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'png' || 'jpg' || 'jpeg' => Icons.image_outlined,
      _ => Icons.description_outlined,
    };
    return InkWell(
      onTap: isPdf
          ? () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ViewerScreen(file: file)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            SizedBox(width: 40, child: Icon(icon, color: muted)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileBaseName(file.path),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    formatBytes(file.lengthSync()),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Chia sẻ',
              onPressed: () => SharePlus.instance.share(
                ShareParams(files: [XFile(file.path)]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
