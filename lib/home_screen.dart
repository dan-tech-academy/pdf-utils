import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'diacritics.dart';
import 'files.dart';
import 'screens/compare_screen.dart';
import 'screens/compress_screen.dart';
import 'screens/crop_screen.dart';
import 'screens/edit_screen.dart';
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
import 'screens/pdfa_screen.dart';
import 'screens/protect_screen.dart';
import 'screens/redact_screen.dart';
import 'screens/repair_screen.dart';
import 'screens/rotate_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/select_pages_screen.dart';
import 'screens/sign_screen.dart';
import 'screens/split_screen.dart';
import 'screens/stamp_screen.dart';
import 'screens/summarize_screen.dart';
import 'screens/text_screen.dart';
import 'screens/translate_screen.dart';
import 'screens/watermark_screen.dart';
import 'screens/web_to_pdf_screen.dart';
import 'viewer_screen.dart';
import 'widgets.dart';

class _Tool {
  const _Tool(
    this.icon,
    this.title,
    this.subtitle,
    this.builder, {
    this.keywords = '',
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  /// Extra words the search box should match: synonyms and English names,
  /// written without accents.
  final String keywords;

  /// Accent-free, lowercase words the search box matches against.
  List<String> get searchWords => _wordsOf('$title $subtitle $keywords');
}

final _nonWord = RegExp(r'[^a-z0-9]+');

/// [text] as accent-free, lowercase words ("Đóng dấu" → [dong, dau]).
List<String> _wordsOf(String text) => removeDiacritics(
  text.toLowerCase(),
).split(_nonWord).where((w) => w.isNotEmpty).toList();

class _ToolGroup {
  const _ToolGroup(this.title, this.tools);
  final String title;
  final List<_Tool> tools;
}

/// Home sections, in display order.
final _groups = <_ToolGroup>[
  _ToolGroup('Nén, ghép & tách', [
    _Tool(
      Icons.compress_outlined,
      'Nén PDF',
      'Giảm dung lượng để gửi email, Zalo',
      (_) => const CompressScreen(),
      keywords: 'giam nhe compress dung luong',
    ),
    _Tool(
      Icons.merge_type_outlined,
      'Ghép PDF',
      'Nối nhiều file PDF thành một',
      (_) => const MergeScreen(),
      keywords: 'noi gop merge combine',
    ),
    _Tool(
      Icons.call_split_outlined,
      'Tách PDF',
      'Chia một file thành nhiều file nhỏ',
      (_) => const SplitScreen(),
      keywords: 'chia split',
    ),
    _Tool(
      Icons.healing_outlined,
      'Sửa PDF lỗi',
      'Cứu file không mở được hoặc báo lỗi',
      (_) => const RepairScreen(),
      keywords: 'repair hong loi corrupt',
    ),
  ]),
  _ToolGroup('Trang', [
    _Tool(
      Icons.auto_awesome_motion_outlined,
      'Sắp xếp trang',
      'Kéo thả đổi thứ tự, xoay, xóa từng trang',
      (_) => const PagesScreen(),
      keywords: 'organize thu tu',
    ),
    _Tool(
      Icons.delete_sweep_outlined,
      'Xóa trang',
      'Bỏ những trang không cần',
      (_) => const SelectPagesScreen(mode: SelectPagesMode.remove),
      keywords: 'remove delete bo',
    ),
    _Tool(
      Icons.file_copy_outlined,
      'Trích trang',
      'Lấy vài trang ra thành file mới',
      (_) => const SelectPagesScreen(mode: SelectPagesMode.extract),
      keywords: 'extract lay rut',
    ),
    _Tool(
      Icons.rotate_90_degrees_cw_outlined,
      'Xoay PDF',
      'Xoay mọi trang, nhiều file một lúc',
      (_) => const RotateScreen(),
      keywords: 'rotate quay lat nguoc',
    ),
    _Tool(
      Icons.crop_outlined,
      'Cắt lề trang',
      'Bớt lề trái, phải, trên, dưới',
      (_) => const CropScreen(),
      keywords: 'crop le',
    ),
    _Tool(
      Icons.grid_view_outlined,
      'Gộp trang lên 1 tờ',
      '2, 4, 6 hoặc 9 trang trên một tờ để in',
      (_) => const NupScreen(),
      keywords: 'n-up nup in tiet kiem giay',
    ),
  ]),
  _ToolGroup('Chỉnh sửa & ký', [
    _Tool(
      Icons.edit_outlined,
      'Chỉnh sửa PDF',
      'Thêm chữ, vẽ, đóng khung, tô sáng',
      (_) => const EditScreen(),
      keywords:
          'edit sua them chu viet ve danh dau to sang khung ghi chu '
          'highlight annotate',
    ),
    _Tool(
      Icons.draw_outlined,
      'Ký tên',
      'Vẽ chữ ký rồi đặt vào PDF',
      (_) => const SignScreen(),
      keywords: 'chu ky sign',
    ),
    _Tool(
      Icons.add_photo_alternate_outlined,
      'Chèn ảnh',
      'Đặt ảnh, con dấu, logo lên trang',
      (_) => const StampScreen(),
      keywords: 'anh hinh con dau logo image',
    ),
    _Tool(
      Icons.branding_watermark_outlined,
      'Đóng dấu chữ',
      'In chữ mờ lên trang: BẢN SAO, MẬT…',
      (_) => const WatermarkScreen(),
      keywords: 'watermark ban sao mat',
    ),
    _Tool(
      Icons.format_list_numbered_outlined,
      'Đánh số trang',
      'Thêm số trang ở đầu hoặc cuối trang',
      (_) => const NumberingScreen(),
      keywords: 'page number so trang header footer',
    ),
    _Tool(
      Icons.assignment_outlined,
      'Điền form',
      'Điền vào các ô của biểu mẫu PDF',
      (_) => const FormScreen(),
      keywords: 'form bieu mau to khai',
    ),
  ]),
  _ToolGroup('Chuyển đổi', [
    _Tool(
      Icons.document_scanner_outlined,
      'Scan → PDF',
      'Chụp giấy tờ bằng camera thành PDF',
      (_) => const ScanScreen(),
      keywords: 'scan quet chup camera',
    ),
    _Tool(
      Icons.photo_library_outlined,
      'Ảnh → PDF',
      'Gộp nhiều ảnh thành một file PDF',
      (_) => const ImagesToPdfScreen(),
      keywords: 'anh hinh jpg png image',
    ),
    _Tool(
      Icons.image_outlined,
      'PDF → Ảnh',
      'Đổi trang thành ảnh JPG, lấy ảnh trong file',
      (_) => const PdfToImagesScreen(),
      keywords: 'anh jpg png image',
    ),
    _Tool(
      Icons.swap_horiz_rounded,
      'PDF ↔ Word, Excel, PPT',
      'Chuyển qua lại giữa PDF và file Office',
      (_) => const OfficeScreen(),
      keywords: 'word excel powerpoint ppt doc docx xlsx pptx office',
    ),
    _Tool(
      Icons.public_outlined,
      'Trang web → PDF',
      'Lưu một trang web thành file PDF',
      (_) => const WebToPdfScreen(),
      keywords: 'html web link url bai bao',
    ),
    _Tool(
      Icons.inventory_2_outlined,
      'PDF/A (lưu trữ)',
      'Chuẩn lưu trữ, nộp hồ sơ điện tử',
      (_) => const PdfaScreen(),
      keywords: 'pdfa luu tru archive nop ho so',
    ),
  ]),
  _ToolGroup('Đọc & hiểu', [
    _Tool(
      Icons.picture_as_pdf_outlined,
      'Xem PDF',
      'Đọc file PDF ngay trong ứng dụng',
      (_) => const ViewerPickScreen(),
      keywords: 'doc view mo',
    ),
    _Tool(
      Icons.text_snippet_outlined,
      'Trích xuất chữ',
      'Lấy toàn bộ chữ ra file .txt hoặc Markdown',
      (_) => const TextScreen(),
      keywords: 'text van ban markdown copy',
    ),
    _Tool(
      Icons.text_fields_outlined,
      'Nhận dạng chữ (OCR)',
      'Lấy chữ từ ảnh chụp hoặc PDF bản scan',
      (_) => const OcrScreen(),
      keywords: 'ocr scan nhan dien chu anh',
    ),
    _Tool(
      Icons.summarize_outlined,
      'Tóm tắt PDF',
      'Rút ra những câu quan trọng nhất',
      (_) => const SummarizeScreen(),
      keywords: 'summary tom tat y chinh ai',
    ),
    _Tool(
      Icons.translate_outlined,
      'Dịch PDF',
      'Dịch sang tiếng Việt, Anh, Trung, Nhật, Hàn',
      (_) => const TranslateScreen(),
      keywords: 'translate dich tieng anh',
    ),
    _Tool(
      Icons.difference_outlined,
      'So sánh PDF',
      'Tìm chỗ khác nhau giữa hai bản',
      (_) => const CompareScreen(),
      keywords: 'compare khac nhau phien ban',
    ),
  ]),
  _ToolGroup('Bảo mật', [
    _Tool(
      Icons.lock_outline,
      'Khóa / Mở khóa',
      'Đặt hoặc gỡ mật khẩu PDF',
      (_) => const ProtectScreen(),
      keywords: 'mat khau password protect unlock',
    ),
    _Tool(
      Icons.hide_source_outlined,
      'Che nội dung',
      'Xóa vĩnh viễn thông tin nhạy cảm',
      (_) => const RedactScreen(),
      keywords: 'redact boi den an che',
    ),
    _Tool(
      Icons.edit_note_outlined,
      'Thông tin file',
      'Sửa tiêu đề, tác giả, từ khóa',
      (_) => const MetadataScreen(),
      keywords: 'metadata thuoc tinh tieu de tac gia',
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
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openTool(BuildContext context, _Tool t) {
    FocusScope.of(context).unfocus();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: t.builder))
        .then((_) => _refresh());
  }

  /// Tools where every word typed starts one of the tool's words,
  /// accent-insensitive ("nen" finds "Nén PDF", "word" doesn't find
  /// "password"); null while the box is empty. Tools whose title holds the
  /// whole query come first, then those whose title has every word, so
  /// "dong dau" puts "Đóng dấu chữ" above tools that only mention the words;
  /// home order breaks ties.
  List<_Tool>? _searchHits() {
    final words = _wordsOf(_search.text);
    if (words.isEmpty) return null;
    bool covers(List<String> have) =>
        words.every((q) => have.any((w) => w.startsWith(q)));
    final query = words.join(' ');
    final ranked = <(int, int, _Tool)>[];
    for (final group in _groups) {
      for (final t in group.tools) {
        if (!covers(t.searchWords)) continue;
        final title = _wordsOf(t.title);
        final rank = title.join(' ').contains(query)
            ? 0
            : covers(title)
            ? 1
            : 2;
        ranked.add((rank, ranked.length, t));
      }
    }
    ranked.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    return [for (final (_, _, t) in ranked) t];
  }

  Future<void> _refresh() async {
    final files = await listOutputs();
    if (mounted) setState(() => _outputs = files);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hits = _searchHits();
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Utils'),
        titleTextStyle: theme.textTheme.headlineSmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        toolbarHeight: 64,
        actions: [
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
              const SizedBox(height: 4),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Tìm công cụ, vd: nén, ký tên, word',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Xóa tìm kiếm',
                          onPressed: _search.clear,
                        ),
                ),
              ),
              if (hits == null)
                for (final group in _groups) ...[
                  _SectionHeader(group.title),
                  _GroupCard(
                    children: [
                      for (final t in group.tools)
                        _ToolRow(
                          tool: t,
                          onTap: () => _openTool(context, t),
                        ),
                    ],
                  ),
                ]
              else ...[
                _SectionHeader(
                  'Kết quả',
                  trailing: hits.isEmpty ? null : '${hits.length} công cụ',
                ),
                if (hits.isEmpty)
                  _NoticeCard(
                    icon: Icons.search_off_rounded,
                    text:
                        'Không có công cụ nào khớp "${_search.text.trim()}". '
                        'Thử từ khác, vd: nén, ghép, word, ký.',
                  )
                else
                  _GroupCard(
                    children: [
                      for (final t in hits)
                        _ToolRow(tool: t, onTap: () => _openTool(context, t)),
                    ],
                  ),
              ],
              _SectionHeader(
                'File đã tạo',
                trailing: _outputs.isEmpty ? null : '${_outputs.length} file',
              ),
              if (_outputs.isEmpty)
                const _NoticeCard(
                  icon: Icons.folder_open_outlined,
                  text:
                      'Chưa có file nào. Kết quả của các công cụ sẽ hiện ở đây.',
                )
              else
                _GroupCard(
                  children: [
                    for (final f in _outputs.take(20)) _OutputRow(file: f),
                  ],
                ),
              const SizedBox(height: 28),
              Text(
                'Miễn phí • Xử lý hoàn toàn trên máy',
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
  const _ToolRow({required this.tool, required this.onTap});

  final _Tool tool;
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
                  Text(
                    tool.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// A card with a muted icon and message, for empty states.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

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
            Icon(icon, color: muted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
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
