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

  static const _features = [
    _ProFeature(Icons.crop_outlined, 'Cắt lề trang'),
    _ProFeature(
      Icons.format_list_numbered_outlined,
      'Đánh số trang / header-footer',
    ),
    _ProFeature(Icons.grid_view_outlined, 'N-up (gộp trang)'),
    _ProFeature(Icons.assignment_outlined, 'Điền form PDF'),
    _ProFeature(Icons.text_fields_outlined, 'OCR ảnh → text'),
    _ProFeature(Icons.swap_horiz_rounded, 'PDF ↔ Word/Excel/PowerPoint'),
    _ProFeature(Icons.hide_source_outlined, 'Che nội dung (redact)'),
  ];

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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final pro = ProManager.instance;
    final pkg = pro.offerings?.current?.availablePackages.firstOrNull;
    final price = pkg?.storeProduct.priceString ?? '\$1.99';
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Utils Pro')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Center(
            child: IconTile(Icons.workspace_premium_outlined, size: 64),
          ),
          const SizedBox(height: 16),
          Text(
            'Mở khóa 7 công cụ nâng cao',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Mua một lần, dùng mãi mãi — $price',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _features.length; i++) ...[
                  if (i > 0) const Divider(indent: 66),
                  _features[i],
                ],
              ],
            ),
          ),
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
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _result!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
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
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          IconTile(icon, size: 36),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          Icon(Icons.check_rounded, size: 20, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}
