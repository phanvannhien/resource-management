# Quản lý dịch vụ – Domain · Hosting · VPS

App Flutter (Android trước, iOS sau) + Supabase. Phân tích nghiệp vụ: [PLAN.md](PLAN.md).

## Cấu trúc

```
lib/
  main.dart                 khởi tạo Supabase, theme, locale vi
  app/                      router (go_router), khung 4 tab
  core/                     format ngày/tiền, mã hoá kho mật khẩu
  models/                   Customer, Vendor, Service, Account, Renewal
  data/                     Repository (gọi thẳng Supabase), VaultController
  features/
    dashboard/              Tổng quan: thống kê + danh sách cần gia hạn theo khách
    services/               danh sách, chi tiết, form, gia hạn
    customers/              danh sách, chi tiết, form
    accounts/               kho tài khoản, mở khoá master password / vân tay
    settings/               nhà cung cấp, backup, đăng xuất
supabase/schema.sql         bảng, RLS, hàm renew_service
```

## 1. Thiết lập Supabase (làm 1 lần)

1. Tạo project tại https://supabase.com (region **Singapore**).
2. **SQL Editor → New query** → dán toàn bộ `supabase/schema.sql` → **Run**.
3. **Authentication → Users → Add user → Create new user**: nhập email + mật khẩu, tick **Auto Confirm User**.
4. **Authentication → Sign In / Providers**: tắt **Allow new users to sign up** (chỉ mình bạn dùng).
5. **Project Settings → API Keys**: copy *Project URL* và *Publishable key* (hoặc *anon key*).

## 2. Cấu hình app

```bash
cp env.example.json env.json   # rồi điền URL + key vào env.json
```

`env.json` đã nằm trong `.gitignore`. Key này được phép nằm trong app; dữ liệu được bảo vệ bởi Row Level Security.

## 3. Build APK

```bash
source /Volumes/data/sdk/env.sh
flutter build apk --release --dart-define-from-file=env.json
```

File APK: `build/app/outputs/flutter-apk/app-release.apk` → gửi qua Zalo / Google Drive / cáp → cài trên điện thoại
(cho phép "Cài ứng dụng không rõ nguồn gốc").

### Chạy thử trực tiếp trên điện thoại (cắm cáp)

Bật **Tuỳ chọn nhà phát triển → Gỡ lỗi USB** trên điện thoại, rồi:

```bash
source /Volumes/data/sdk/env.sh
flutter run --dart-define-from-file=env.json
```

## 4. App Mac (macOS)

```bash
source /Volumes/data/sdk/env.sh
flutter build macos --release --dart-define-from-file=env.json
```
→ `build/macos/Build/Products/Release/AMV-WebManage.app` (kéo vào Applications).

## 5. iPhone (cắm cáp, Apple ID miễn phí)

```bash
./tool/install_ios.sh
```
Tự build, cài và mở app trên iPhone đang cắm. App hết hạn sau 7 ngày → chạy lại script để gia hạn.
Lần đầu: iPhone → Cài đặt → Cài đặt chung → Quản lý VPN & thiết bị → tin cậy Apple ID.

Yêu cầu: Xcode 16.4 ở `/Volumes/data/Xcode.app` (đã `sudo xcode-select -s` về đây), nền tảng iOS 18.x đã cài trong
Xcode → Settings → Components, Apple ID đã thêm vào Xcode và chọn Personal Team cho target Runner.

## 6. Nơi lưu dữ liệu

Lần đầu mở app sẽ hỏi lưu **trên máy** hay **Supabase**; đổi lại trong Cài đặt → Lưu trữ dữ liệu (có tuỳ chọn chép dữ liệu sang nơi mới).

- **Trên máy:** 1 file JSON trong thư mục app. Đồng bộ tự động qua **WebDAV** (cPanel → Files → Web Disk,
  URL dạng `https://tenmien.com:2078/thumuc/`; hoặc Nextcloud, Synology, Koofr, pCloud…) — bản nào sửa sau sẽ thắng,
  bản cũ trên máy giữ ở `amv-webmanage.prev.json`.
- **Sao lưu / khôi phục file** (cả 2 chế độ): Cài đặt → Xuất file sao lưu → lưu vào Google Drive / iCloud / Files.
- Mật khẩu tài khoản luôn mã hoá bằng master password trong mọi file.

## Lưu ý quan trọng

- **Khoá ký APK**: `android/key.properties` + `android/app/release.jks`. Hãy backup 2 file này.
  Mất chúng thì bản mới không cài đè được lên bản cũ (phải gỡ app rồi cài lại; dữ liệu trên Supabase không mất).
- **Master password** của kho tài khoản không lưu ở đâu cả. Quên = không giải mã được các mật khẩu đã lưu.
- **Supabase free tự pause sau 7 ngày không có request.** Nếu có lúc lâu không mở app, tạo job miễn phí ở
  https://cron-job.org gọi 2 ngày/lần:
  `GET https://<project>.supabase.co/rest/v1/providers?select=id&limit=1` với header `apikey: <publishable key>`.
  Nếu lỡ bị pause: vào dashboard Supabase bấm **Restore**, dữ liệu vẫn còn.
- SDK nằm ở `/Volumes/data/sdk` (Flutter, Android SDK, cache Gradle/pub). Thêm vào `~/.zshrc` để dùng lâu dài:
  `source /Volumes/data/sdk/env.sh`

## Test

```bash
flutter test
```
