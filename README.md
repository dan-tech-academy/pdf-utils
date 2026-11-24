# PDF Utils

![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart)
![Platform](https://img.shields.io/badge/Android%20%7C%20iOS-supported-brightgreen)
![License](https://img.shields.io/badge/Features-100%25%20FREE-orange)

**Xử lý mọi vấn đề với file PDF — ngay trên điện thoại, hoàn toàn miễn phí.**

PDF Utils là app Flutter cho Android & iOS gom **21 công cụ PDF** vào một nơi: nén, ghép, tách, sắp xếp, chèn ảnh, ký tên, watermark, đánh số trang, cắt lề, N-up, điền form, che nội dung, OCR, PDF ↔ Word/Excel/PowerPoint, scan tài liệu, chuyển ảnh ↔ PDF, khóa/mở khóa, trích xuất text và sửa metadata. Mọi xử lý chạy **on-device** bằng engine Rust của [`pdf_manipulator`](https://pub.dev/packages/pdf_manipulator) — không cần server, không tải file lên đâu cả.

![Màn hình chính](docs/screenshots/home.png)

## Mục lục

- [Tính năng](#tính-năng)
- [Ảnh màn hình thật](#ảnh-màn-hình-thật)
- [Kiến trúc](#kiến-trúc)
- [Công nghệ & thư viện](#công-nghệ--thư-viện)
- [Cài đặt & chạy](#cài-đặt--chạy)
- [Quyền truy cập](#quyền-truy-cập)
- [Giấy phép](#giấy-phép)

## Tính năng

| Công cụ | Mô tả |
|---|---|
| **Nén PDF** | Giảm dung lượng với 4 mức: Nhẹ nhất (72ppi/q60), Cân bằng (150ppi/q75), Chất lượng cao (300ppi/q85), Không mất chất lượng (lossless) |
| **Ghép PDF** | Nối nhiều PDF thành một, sắp thứ tự trước khi ghép |
| **Tách PDF** | Chia theo mỗi N trang / từng trang / giới hạn MB mỗi file |
| **Sắp xếp trang** | Kéo-thả đổi thứ tự, xoay 90°, xóa trang — có thumbnail preview |
| **Chèn ảnh** | Đặt ảnh lên trang PDF: chọn trang, góc đặt, kích thước %, độ mờ |
| **Ký tên** | Vẽ chữ ký trên pad hoặc chọn từ thư viện chữ ký đã lưu (lưu/xóa nhiều chữ ký), đặt vào PDF như ảnh chèn |
| **Watermark** | Đóng dấu chữ lên trang: nội dung, cỡ chữ, màu, góc, độ mờ, lớp trên/dưới |
| **Scan → PDF** | Quét tài liệu bằng camera (ML Kit document scanner), fallback chụp ảnh thường |
| **Ảnh → PDF** | Tạo PDF từ nhiều ảnh; trang theo ảnh / A4 / Letter, fit contain/cover |
| **PDF → Ảnh** | Xuất từng trang ra PNG, chọn DPI 72–300 |
| **Khóa / Mở khóa** | Đặt mật khẩu (AES) hoặc gỡ mật khẩu PDF |
| **Cắt lề trang** | Bớt lề trái/phải/trên/dưới (mm) — set CropBox |
| **Đánh số trang** | Thêm số trang / header-footer dạng `Trang {i} / {n}`, 4 góc, cỡ chữ, lề |
| **N-up** | Gộp 2/4/6/9 trang lên một tờ A4 ngang (raster) |
| **Điền form** | Đọc và điền AcroForm: text, checkbox, dropdown, radio |
| **OCR ảnh → text** | Nhận diện chữ trong ảnh (ML Kit on-device), copy hoặc lưu `.txt` |
| **PDF ↔ Office** | PDF → Word/Excel/PowerPoint và ngược lại |
| **Che nội dung** | Redaction thật — kéo vùng trên trang để xóa vĩnh viễn text/ảnh bên dưới |
| **Trích xuất text** | Lấy toàn bộ text ra file `.txt`, copy nhanh |
| **Metadata** | Sửa tiêu đề, tác giả, chủ đề, từ khóa của PDF |
| **Xem PDF** | Đọc PDF trong app (flutter_pdfview), đếm trang, chia sẻ |

**100% FREE** — không quảng cáo, không giới hạn, không cần tài khoản, xử lý hoàn toàn trên máy.

## Ảnh màn hình thật

Chụp từ Android emulator chạy build debug thật:

| Ghép PDF | Kết quả ghép (5 trang, đúng thứ tự) |
|---|---|
| ![Chọn file ghép](docs/screenshots/merge_picked.png) | ![Kết quả](docs/screenshots/merge_result.png) |

| Nén PDF (1.2 KB → 782 B) | Chèn ảnh (tùy chọn) | Kết quả chèn ảnh |
|---|---|---|
| ![Nén](docs/screenshots/comp_done.png) | ![Tùy chọn chèn](docs/screenshots/stamp_ready.png) | ![Đã chèn](docs/screenshots/stamp_done.png) |

| Xem PDF trong app | Ảnh → PDF |
|---|---|
| ![Viewer](docs/screenshots/viewer.png) | ![Ảnh to PDF](docs/screenshots/i2p_done.png) |

## Kiến trúc

```
lib/
├── main.dart              # MaterialApp, light/dark theme
├── engine.dart            # PdfEngine — wrapper mỏng quanh pdf_manipulator (Rust engine)
├── files.dart             # outputs dir, file picker, image picker, content:// resolver
├── widgets.dart           # PickTile / RunButton / ResultCard / ErrorBanner
├── home_screen.dart       # Grid 21 công cụ + danh sách "File đã tạo"
├── viewer_screen.dart     # Xem PDF trong app
└── screens/               # Một màn hình cho mỗi công cụ
    ├── compress_screen.dart
    ├── merge_screen.dart
    ├── split_screen.dart
    ├── pages_screen.dart        # sắp xếp / xoay / xóa trang với thumbnail
    ├── stamp_screen.dart        # chèn ảnh
    ├── sign_screen.dart         # signature pad → chèn ảnh
    ├── watermark_screen.dart
    ├── scan_screen.dart         # ML Kit scan + fallback camera
    ├── images_to_pdf_screen.dart
    ├── pdf_to_images_screen.dart
    ├── protect_screen.dart      # khóa / mở khóa
    ├── text_screen.dart         # trích xuất text
    ├── metadata_screen.dart
    ├── crop_screen.dart         # cắt lề trang (cropMargins)
    ├── numbering_screen.dart    # đánh số trang / header-footer
    ├── nup_screen.dart          # N-up: render trang → lưới → PDF
    ├── form_screen.dart         # điền AcroForm
    ├── ocr_screen.dart          # ML Kit text recognition
    ├── office_screen.dart       # PDF ↔ docx/xlsx/pptx
    └── redact_screen.dart       # redact vùng kéo trên trang
```

Mọi file kết quả nằm ở `<Documents>/pdf_utils/` và xuất hiện trong mục **File đã tạo** trên màn hình chính — Xem / Mở / Chia sẻ trực tiếp.

## Công nghệ & thư viện

- **[pdf_manipulator](https://pub.dev/packages/pdf_manipulator) 6.0.0** — engine Rust chạy off-main-thread: merge, split, compress, rewrite (xoay/sắp xếp/xóa trang, watermark, image stamp, crop, redaction, form fill, metadata), mã hóa AES, render bitmap, trích text, chuyển đổi Office.
- **[flutter_pdfview](https://pub.dev/packages/flutter_pdfview)** — xem PDF trong app.
- **[doc_scanner_kit](https://pub.dev/packages/doc_scanner_kit)** — quét tài liệu (Google ML Kit); có fallback chụp ảnh.
- **[google_mlkit_text_recognition](https://pub.dev/packages/google_mlkit_text_recognition)** — OCR on-device (không cần Play services).
- **[image](https://pub.dev/packages/image)** — ghép lưới trang cho N-up.
- **[file_picker](https://pub.dev/packages/file_picker)** / **[image_picker](https://pub.dev/packages/image_picker)** — chọn file / ảnh / camera.
- **[share_plus](https://pub.dev/packages/share_plus)** / **[open_file](https://pub.dev/packages/open_file)** — chia sẻ & mở kết quả.
- **[permission_handler](https://pub.dev/packages/permission_handler)** — quyền camera.

Tất cả thư viện đều mã nguồn mở (MIT/BSD) và miễn phí.

## Cài đặt & chạy

Yêu cầu: Flutter ≥ 3.47 (Dart 3.13), Android SDK 37 (do `permission_handler` yêu cầu), Xcode cho iOS.

```bash
git clone <repo>
cd pdf-utils
flutter pub get

# Android
flutter build apk --debug        # hoặc flutter run với device/emulator

# iOS (trên macOS)
cd ios && pod install && cd ..
flutter build ios --no-codesign  # hoặc flutter run trên simulator
```

`pdf_manipulator` tự tải binary engine đã build sẵn (~25 MB) qua build hook — không cần cài Rust.

## Quyền truy cập

| Quyền | Dùng cho |
|---|---|
| Camera | Scan tài liệu, chụp ảnh |
| Photo library (iOS) | Chọn ảnh |

App không cần quyền storage đặc biệt — file chọn qua SAF/photo picker, file kết quả trong thư mục riêng của app.

## Giấy phép

Mọi tính năng miễn phí. Mã nguồn phát hành theo MIT License.
