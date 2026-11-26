import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

/// A plain-Vietnamese message for an error shown to the user, with a hint
/// at what to do next. The technical detail stays in brackets at the end
/// only for errors without a known cause.
String friendlyError(Object error) => switch (error) {
  PdfPasswordRequired() =>
    'File này đang có mật khẩu. Hãy gỡ mật khẩu bằng công cụ '
        '"Khóa / Mở khóa" rồi thử lại.',
  PdfWrongPassword() => 'Mật khẩu chưa đúng. Hãy kiểm tra rồi nhập lại.',
  PdfCryptoFailed() =>
    'Không mở được file đã khóa (mật khẩu sai hoặc kiểu khóa chưa hỗ trợ).',
  PdfCorrupted() =>
    'File PDF bị hỏng hoặc không phải PDF. Hãy thử công cụ "Sửa PDF lỗi".',
  PdfPageOutOfRange() => 'Trang đã chọn không có trong file.',
  PdfUnsupported() => 'Công cụ này chưa hỗ trợ loại file này.',
  PdfIoFailed() || FileSystemException() =>
    'Không đọc hoặc ghi được file. Hãy kiểm tra bộ nhớ trống rồi thử lại.',
  PdfCancelled() => 'Đã hủy.',
  SocketException() || HttpException() || HandshakeException() =>
    'Không kết nối được mạng. Hãy kiểm tra Internet rồi thử lại.',
  TimeoutException() => 'Quá lâu không có phản hồi. Hãy thử lại.',
  // Failures inside the phone's own components (ML Kit, web view, sharing).
  PlatformException() =>
    'Máy không chạy được bước này. Hãy thử lại, hoặc mở lại ứng dụng.',
  PdfError(:final message) => 'Không xử lý được file ($message).',
  _ => 'Có lỗi xảy ra ($error).',
};
