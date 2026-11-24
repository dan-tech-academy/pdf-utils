import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat entitlement + product ids.
/// Setup: create a RevenueCat project, add entitlement `pro` and a
/// non-consumable/lifetime product (e.g. `pdfutils_pro` at $1.99),
/// attach it to an Offering, then paste the public SDK keys below
/// (or pass via --dart-define RC_ANDROID_KEY / RC_IOS_KEY).
const kProEntitlement = 'pro';

const _androidKey = String.fromEnvironment(
  'RC_ANDROID_KEY',
  defaultValue: 'goog_REPLACE_ME',
);
const _iosKey = String.fromEnvironment(
  'RC_IOS_KEY',
  defaultValue: 'appl_REPLACE_ME',
);

class ProManager extends ChangeNotifier {
  ProManager._();

  static final ProManager instance = ProManager._();

  bool _initialized = false;
  bool _isPro = false;
  Offerings? _offerings;
  String? _error;

  bool get isPro => _isPro;
  Offerings? get offerings => _offerings;
  String? get error => _error;

  /// True when SDK keys are placeholders — lets UI show a friendly note
  /// instead of a store error.
  bool get keysConfigured =>
      !_androidKey.contains('REPLACE_ME') && !_iosKey.contains('REPLACE_ME');

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (!keysConfigured) {
      _error = 'Chưa cấu hình RevenueCat API key';
      notifyListeners();
      return;
    }
    try {
      await Purchases.configure(
        PurchasesConfiguration(Platform.isAndroid ? _androidKey : _iosKey),
      );
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      await refresh();
    } catch (e) {
      _error = '$e';
      notifyListeners();
    }
  }

  void _onCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.all[kProEntitlement]?.isActive ?? false;
    if (active != _isPro) {
      _isPro = active;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _onCustomerInfo(info);
      _offerings = await Purchases.getOfferings();
      _error = null;
    } catch (e) {
      _error = '$e';
    }
    notifyListeners();
  }

  /// Purchases the single Pro package from the current offering.
  /// Returns true if the entitlement is active afterwards.
  Future<bool> purchase() async {
    if (!keysConfigured) return false;
    try {
      await refresh();
      final current = _offerings?.current;
      if (current == null || current.availablePackages.isEmpty) {
        _error = 'Không tìm thấy gói Pro trên store';
        notifyListeners();
        return false;
      }
      final result = await Purchases.purchase(
        PurchaseParams.package(current.availablePackages.first),
      );
      _onCustomerInfo(result.customerInfo);
      _error = null;
      notifyListeners();
      return _isPro;
    } on PlatformException catch (e) {
      final details = e.details as Map?;
      // purchases_flutter wraps errors in PlatformException with details.
      if (details?['userCancelled'] == true) return false;
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = '$e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> restore() async {
    if (!keysConfigured) return false;
    try {
      final info = await Purchases.restorePurchases();
      _onCustomerInfo(info);
      _error = null;
      notifyListeners();
      return _isPro;
    } catch (e) {
      _error = '$e';
      notifyListeners();
      return false;
    }
  }
}
