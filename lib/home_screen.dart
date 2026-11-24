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

class _Tool {
  const _Tool(this.icon, this.title, this.subtitle, this.builder,
      {this.isPro = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
  final bool isPro;
}

final _tools = <_Tool>[
  _Tool(
    Icons.compress,
    'Nén PDF',
    'Giảm dung lượng file',
    (_) => const CompressScreen(),
  ),
  _Tool(
    Icons.merge_type,
    'Ghép PDF',
    'Nối nhiều PDF thành một',
    (_) => const MergeScreen(),
  ),
  _Tool(
    Icons.call_split,
    'Tách PDF',
    'Chia thành nhiều file nhỏ',
    (_) => const SplitScreen(),
  ),
  _Tool(
    Icons.auto_awesome_motion,
    'Sắp xếp trang',
    'Xoay, xóa, đổi thứ tự trang',
    (_) => const PagesScreen(),
  ),
  _Tool(
    Icons.add_photo_alternate,
    'Chèn ảnh',
    'Đặt ảnh lên trang PDF',
    (_) => const StampScreen(),
  ),
  _Tool(
    Icons.draw,
    'Ký tên',
    'Vẽ chữ ký, đặt vào PDF',
    (_) => const SignScreen(),
  ),
  _Tool(
    Icons.branding_watermark,
    'Watermark',
    'Đóng dấu chữ lên trang',
    (_) => const WatermarkScreen(),
  ),
  _Tool(
    Icons.document_scanner,
    'Scan → PDF',
    'Quét tài liệu bằng camera',
    (_) => const ScanScreen(),
  ),
  _Tool(
    Icons.photo_library,
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
    Icons.crop,
    'Cắt lề trang',
    'Bớt lề trái/phải/trên/dưới',
    (_) => const CropScreen(),
    isPro: true,
  ),
  _Tool(
    Icons.format_list_numbered,
    'Đánh số trang',
    'Thêm số trang / header-footer',
    (_) => const NumberingScreen(),
    isPro: true,
  ),
  _Tool(
    Icons.grid_view,
    'N-up',
    'Gộp 2/4/6/9 trang lên 1 tờ',
    (_) => const NupScreen(),
    isPro: true,
  ),
  _Tool(
    Icons.assignment,
    'Điền form',
    'Điền form PDF (AcroForm)',
    (_) => const FormScreen(),
    isPro: true,
  ),
  _Tool(
    Icons.lock,
    'Khóa / Mở khóa',
    'Đặt hoặc gỡ mật khẩu PDF',
    (_) => const ProtectScreen(),
  ),
  _Tool(
    Icons.text_snippet,
    'Trích xuất text',
    'Lấy text ra file .txt',
    (_) => const TextScreen(),
  ),
  _Tool(
    Icons.document_scanner_outlined,
    'OCR ảnh → text',
    'Nhận diện chữ trong ảnh (ML Kit)',
    (_) => const OcrScreen(),
    isPro: true,
  ),
  _Tool(
    Icons.transform,
    'PDF ↔ Office',
    'Đổi PDF sang Word/Excel/PPT & ngược lại',
    (_) => const OfficeScreen(),
    isPro: true,
  ),
  _Tool(
    Icons.hide_source,
    'Che nội dung',
    'Xóa vĩnh viễn vùng nhạy cảm',
    (_) => const RedactScreen(),
    isPro: true,
  ),
  _Tool(
    Icons.edit_note,
    'Metadata',
    'Sửa tiêu đề, tác giả',
    (_) => const MetadataScreen(),
  ),
  _Tool(
    Icons.picture_as_pdf,
    'Xem PDF',
    'Đọc file PDF trong app',
    (_) => const ViewerPickScreen(),
  ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Utils'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.workspace_premium,
              color: ProManager.instance.isPro
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: 'PDF Utils Pro',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProScreen()),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.9,
              ),
              itemCount: _tools.length,
              itemBuilder: (context, i) {
                final t = _tools[i];
                final locked = t.isPro && !ProManager.instance.isPro;
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openTool(context, t),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                t.icon,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const Spacer(),
                              if (locked)
                                Icon(
                                  Icons.lock,
                                  size: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline,
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            t.title,
                            style: Theme.of(context).textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            t.subtitle,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'File đã tạo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (_outputs.isNotEmpty)
                  Text('${_outputs.length} file',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            if (_outputs.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Chưa có file nào. Kết quả của các công cụ sẽ hiện ở đây.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              for (final f in _outputs.take(20)) _OutputTile(file: f),
            const SizedBox(height: 32),
            Text(
              'Xử lý hoàn toàn trên máy • Pro mở khóa công cụ nâng cao',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _OutputTile extends StatelessWidget {
  const _OutputTile({required this.file});
  final File file;

  @override
  Widget build(BuildContext context) {
    final isPdf = file.path.toLowerCase().endsWith('.pdf');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(isPdf ? Icons.picture_as_pdf : Icons.image),
      title: Text(
        fileBaseName(file.path),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(formatBytes(file.lengthSync())),
      trailing: IconButton(
        icon: const Icon(Icons.share),
        onPressed: () => SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)]),
        ),
      ),
      onTap: isPdf
          ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ViewerScreen(file: file)),
              )
          : null,
    );
  }
}
