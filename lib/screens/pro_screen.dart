import 'package:flutter/material.dart';

import '../pro.dart';
import '../widgets.dart';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  bool _busy = false;
  String? _result;

  Future<void> _buy() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final ok = await ProManager.instance.purchase();
    if (mounted) {
      setState(() {
        _busy = false;
        _result = ok ? 'Chúc mừng! Bạn đã là Pro.' : null;
      });
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final ok = await ProManager.instance.restore();
    if (mounted) {
      setState(() {
        _busy = false;
        _result = ok
            ? 'Đã khôi phục quyền Pro.'
            : 'Không tìm thấy giao dịch Pro nào.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pro = ProManager.instance;
    final pkg = pro.offerings?.current?.availablePackages.firstOrNull;
    final price = pkg?.storeProduct.priceString ?? '\$1.99';
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Utils Pro')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.workspace_premium,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mở khóa 7 công cụ nâng cao',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mua một lần, dùng mãi mãi — $price',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _ProFeature(Icons.crop, 'Cắt lề trang'),
          const _ProFeature(Icons.format_list_numbered, 'Đánh số trang / header-footer'),
          const _ProFeature(Icons.grid_view, 'N-up (gộp trang)'),
          const _ProFeature(Icons.assignment, 'Điền form PDF'),
          const _ProFeature(Icons.document_scanner_outlined, 'OCR ảnh → text'),
          const _ProFeature(Icons.transform, 'PDF ↔ Word/Excel/PowerPoint'),
          const _ProFeature(Icons.hide_source, 'Che nội dung (redact)'),
          const SizedBox(height: 16),
          if (!pro.keysConfigured)
            const ErrorBanner(
              message:
                  'Developer: chưa cấu hình RevenueCat API key. '
                  'Xem mục Pro trong README.',
            ),
          if (pro.error != null && pro.keysConfigured)
            ErrorBanner(message: pro.error!),
          if (_result != null)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_result!),
              ),
            ),
          RunButton(
            label: pro.isPro ? 'Bạn đã là Pro' : 'Nâng cấp Pro — $price',
            enabled: !pro.isPro && !_busy,
            onPressed: _buy,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _restore,
              child: const Text('Khôi phục mua hàng'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thanh toán một lần qua Google Play / App Store. '
            'Không quảng cáo, không subscription.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ProFeature extends StatelessWidget {
  const _ProFeature(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
    );
  }
}
