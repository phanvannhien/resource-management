# Service Manager – Phân tích nghiệp vụ & Giải pháp

App mobile (Expo / React Native, chạy trên Android & iOS) quản lý khách hàng, Domain / Hosting / VPS, tài khoản đăng nhập và nhắc gia hạn.

---

## 1. Bài toán & mục tiêu

| Vấn đề hiện tại | Mục tiêu của app |
|---|---|
| Nhiều dịch vụ, nhiều nhà cung cấp, dễ quên ngày hết hạn | Tự động nhắc trước 15 ngày, không bỏ sót |
| Không biết VPS hết hạn thì ảnh hưởng tới những ai | Thấy ngay "VPS này đang chứa hosting của khách nào" |
| Thông tin đăng nhập nằm rải rác (note, Zalo, Excel) | Kho tài khoản tập trung, mã hoá, có khoá app |
| Không rõ lãi/lỗ từng dịch vụ | Lưu giá vốn / giá bán, lịch sử gia hạn |

Nguyên tắc thiết kế: **mở app là thấy ngay việc cần làm hôm nay**; thêm/gia hạn dịch vụ trong ≤ 3 thao tác.

---

## 2. Phân tích nghiệp vụ

### 2.1 Các đối tượng (entity)

```
Khách hàng ─┬─< Dịch vụ (Domain / Hosting / VPS) >── Nhà cung cấp
            │        │
            │        ├── VPS ─< Hosting tự tạo (parent_vps)
            │        │
            │        └─< Lịch sử gia hạn
            │
            └─< Tài khoản (portal NCC, cPanel/DirectAdmin, SSH, FTP, DB...)
```

1. **Khách hàng** – người mua dịch vụ của bạn.
2. **Nhà cung cấp (NCC)** – nơi bạn mua: Tenten, Mắt Bão, PA, iNET, Vultr, DigitalOcean, Namecheap...
3. **Dịch vụ** – gộp chung 1 bảng, phân biệt bằng `type` = DOMAIN | HOSTING | VPS.
   - **Chủ sở hữu**: `customer_id = null` → *của mình* (VPS tự mua, domain riêng). Có `customer_id` → của khách.
   - **Hosting có 2 nguồn**:
     - Mua từ NCC (`provider_id` có giá trị).
     - Tự tạo trên VPS (`parent_vps_id` trỏ tới VPS của mình **hoặc** VPS của khách).
4. **Tài khoản** – thông tin đăng nhập, gắn vào NCC, khách hàng và/hoặc dịch vụ cụ thể.
5. **Lịch sử gia hạn** – mỗi lần gia hạn ghi lại: hạn cũ → hạn mới, số tiền, đã thu tiền khách chưa, đã thanh toán NCC chưa.

### 2.2 Ví dụ quan hệ thực tế

```
VPS "VPS-SG-01" (của mình, Vultr, hết hạn 10/11/2026)
 ├─ Hosting "host-abc"  → Khách A → domain abc.vn
 ├─ Hosting "host-xyz"  → Khách B → domain xyz.com
 └─ Hosting "host-shop" → Khách C → domain shopc.vn

VPS "VPS-KhachD" (của khách D, mình quản trị)
 └─ Hosting "host-d2"   → Khách D (site phụ)
```
→ Nếu VPS-SG-01 sắp hết hạn: app cảnh báo **mức nghiêm trọng cao**, liệt kê 3 hosting / 3 khách bị ảnh hưởng.

### 2.3 Quy tắc nghiệp vụ

| Mã | Quy tắc |
|---|---|
| R1 | `số ngày còn lại = ngày hết hạn − hôm nay`. Trạng thái tính tự động: **Hoạt động** (>15), **Sắp hết hạn** (0–15), **Quá hạn** (<0). Trạng thái thủ công: **Ngừng / Không gia hạn**. |
| R2 | Ngưỡng nhắc mặc định 15 ngày, cho phép chỉnh riêng từng dịch vụ (vd domain .vn nên 30 ngày). |
| R3 | Nhắc vào 08:00 mỗi ngày khi dịch vụ nằm trong ngưỡng; nhắc mạnh hơn (heads-up) ở mốc 7, 3, 1, 0 ngày. Quá hạn vẫn nhắc hằng ngày tới khi gia hạn hoặc đánh dấu "Ngừng". |
| R4 | Gia hạn: `hạn mới = hạn cũ + chu kỳ` (không phải hôm nay + chu kỳ) → không mất ngày của khách. Tự ghi lịch sử. |
| R5 | VPS sắp hết hạn → kèm danh sách hosting con & khách bị ảnh hưởng. |
| R6 | Hosting tự tạo có hạn **vượt quá** hạn VPS cha → hiện cảnh báo (không chặn). |
| R7 | Dịch vụ "Ngừng" không bị nhắc, không tính vào thống kê sắp hết hạn. |
| R8 | Xoá khách hàng → không xoá cứng; chuyển sang "Ngừng" để giữ lịch sử. |

---

## 3. Thiết kế dữ liệu (Postgres)

```
customers        id, name, phone, email, zalo, company, note, is_active, created_at

providers        id, name, website, support_contact, note

services         id, type(DOMAIN|HOSTING|VPS), name,
                 customer_id?        -- null = của mình
                 provider_id?, parent_vps_id?, account_id?,
                 start_date, expiry_date, cycle_months,
                 cost_price, sell_price, notify_days (default 15),
                 status(ACTIVE|CANCELLED), note,
                 -- trường riêng (nullable)
                 ip, os, cpu, ram_gb, disk_gb, panel,      -- VPS / Hosting
                 nameservers, linked_hosting_id            -- Domain

accounts         id, kind(PORTAL|CONTROL_PANEL|SSH|FTP|DATABASE|EMAIL|OTHER),
                 label, login_url, username, password_enc, port,
                 provider_id?, customer_id?, service_id?, note

renewals         id, service_id, renewed_at, old_expiry, new_expiry,
                 months, amount, customer_paid(bool), provider_paid(bool), note
```

Gộp Domain/Hosting/VPS vào 1 bảng `services` để: 1 truy vấn ra toàn bộ danh sách sắp hết hạn, 1 màn hình danh sách, 1 luồng gia hạn.

---

## 4. Giao diện (mobile-first, 4 tab dưới)

```
┌─────────────────────────────────┐
│  Tổng quan          🔍   ⚙       │
├─────────────────────────────────┤
│ ┌───────┐ ┌───────┐ ┌───────┐   │
│ │  🔴 2 │ │  🟠 6 │ │  🟢 48│   │
│ │Quá hạn│ │≤15ngày│ │Ổn định│   │
│ └───────┘ └───────┘ └───────┘   │
│                                 │
│ CẦN GIA HẠN (nhóm theo khách)   │
│ ┌─────────────────────────────┐ │
│ │ ⚠ CỦA TÔI                   │ │
│ │  VPS-SG-01  còn 3 ngày      │ │
│ │  ↳ ảnh hưởng 3 hosting      │ │
│ │                 [Gia hạn]   │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ Nguyễn Văn A   📞  💬        │ │
│ │  🌐 abc.vn      còn 5 ngày  │ │
│ │  🗄 host-abc    còn 12 ngày │ │
│ │       [Nhắn nhắc] [Gia hạn] │ │
│ └─────────────────────────────┘ │
├─────────────────────────────────┤
│ 🏠Tổng quan 📦Dịch vụ 👥Khách 🔑TK│
└─────────────────────────────────┘
```

| Tab | Nội dung |
|---|---|
| **Tổng quan** | 3 thẻ đếm (bấm để lọc) + danh sách cần gia hạn, nhóm theo khách; "Của tôi" luôn nằm trên cùng. |
| **Dịch vụ** | Bộ lọc nhanh: Tất cả / Domain / Hosting / VPS · Của tôi / Của khách · Sắp hết hạn. Sắp xếp theo ngày hết hạn. Mỗi dòng có chip màu số ngày còn lại. |
| **Khách hàng** | Danh sách + tìm kiếm. Chi tiết khách: thông tin liên hệ, tất cả dịch vụ, tài khoản, tổng tiền/năm. |
| **Tài khoản** | Kho mật khẩu: nhóm theo NCC/khách; mật khẩu ẩn, bấm 👁 để xem, 📋 để copy (tự xoá clipboard sau 30s). |

**Chi tiết VPS**: thông số, ngày hết hạn, tài khoản SSH/panel, **danh sách hosting đang chạy trên VPS** (+ nút thêm hosting con).

**Form thêm dịch vụ** (1 form chung, các trường đổi theo loại):
1. Chọn loại: Domain / Hosting / VPS
2. Chủ sở hữu: Của tôi / chọn khách (có nút "+ khách mới" ngay trong form)
3. Tên, NCC (hoặc VPS cha nếu là hosting tự tạo)
4. Ngày bắt đầu + chu kỳ (1/3/6/12/24 tháng) → **tự tính ngày hết hạn** (vẫn sửa tay được)
5. Giá vốn / giá bán (tuỳ chọn), ghi chú

**Luồng gia hạn (1 bottom sheet)**: chọn chu kỳ (mặc định = chu kỳ cũ) → hiện "Hạn mới: dd/MM/yyyy" → tick "Đã thu tiền khách" / "Đã trả NCC" → Lưu.

**Nút "Nhắn nhắc"**: tạo sẵn tin nhắn mẫu và mở Zalo/SMS:
> Chào anh A, domain abc.vn và hosting host-abc sẽ hết hạn ngày 02/11/2026. Phí gia hạn 1 năm: 1.200.000đ. Anh xác nhận để em gia hạn nhé.

---

## 5. Kiểm tra hết hạn

Không chạy nền, không push notification. **Mở app → tính ngay**:
- Màn Tổng quan tính `số ngày còn lại` cho mọi dịch vụ lúc mở và hiện danh sách Quá hạn / ≤15 ngày.
- Có thể thêm sau: email nhắc hằng ngày bằng cron miễn phí của Supabase (không cần sửa app).

---

## 6. Hình thức app: Expo (React Native) – build trên cloud

App native thật (APK / IPA), **không cần domain, không cần server web**, máy chỉ cần Node.js (đã có).
Không cài Android Studio, Xcode, Flutter SDK.

| Việc | Cách làm |
|---|---|
| Code & chạy thử | `npx expo start` → mở app **Expo Go** trên điện thoại, quét QR → thấy app chạy, sửa code là cập nhật ngay |
| Build APK Android | `eas build -p android --profile preview` → build trên cloud Expo (free ~15 build/tháng) → link tải APK |
| Build iOS | GitHub Actions (macOS runner) build file `.ipa` chưa ký |
| Cài iOS không tốn phí | Sideloadly / AltStore ký bằng Apple ID thường → **phải ký lại mỗi 7 ngày** (giới hạn của Apple, mọi công nghệ đều vậy) |
| Cài iOS ổn định | Apple Developer 99 USD/năm → `eas build -p ios` + TestFlight |

Dữ liệu nằm trên Supabase → cài lại / ký lại app không mất dữ liệu.

---

## 7. Database: Supabase (gói Free)

App gọi thẳng database bằng `supabase-js`, **không viết API**.

| | **Supabase** (chọn) | Firebase Firestore | PocketBase trên VPS của mình |
|---|---|---|---|
| Miễn phí | 500 MB DB | 1 GB | Miễn phí (VPS có sẵn) |
| Kiểu dữ liệu | **SQL (Postgres)** – hợp quan hệ Khách→VPS→Hosting | NoSQL, phải denormalize | SQLite |
| Bảng điều khiển | Table editor như Excel, **import CSV** từ file cũ | Khó nhập tay | Có admin UI |
| Bảo mật trực tiếp từ client | Auth + Row Level Security | Auth + Security Rules | Auth + API Rules |
| Nhược điểm | **Tự pause sau 7 ngày không có request** | Không có | Tự lo vận hành & backup VPS |

Xử lý vụ pause: tạo cron miễn phí (GitHub Actions hoặc cron-job.org) gọi Supabase 2–3 ngày/lần. Nếu lỡ bị pause: vào dashboard bấm Restore, dữ liệu vẫn còn.

### Bảng

```
customers, providers, services, accounts, renewals   (như mục 3)
view v_expiring  -- services + customer + days_left, sắp theo expiry_date
```
Mọi bảng có cột `owner_id uuid default auth.uid()` + RLS `owner_id = auth.uid()`.

### Bảo mật

- Supabase Auth email/mật khẩu, tắt đăng ký mới sau khi tạo tài khoản của mình.
- `anon key` nằm trong code web là bình thường — RLS mới là lớp bảo vệ.
- **Mật khẩu trong Tài khoản mã hoá ngay trên điện thoại** (AES-GCM, khoá sinh từ *master password* qua PBKDF2). Database chỉ chứa chuỗi mã hoá.
- Khoá app bằng vân tay / Face ID (`expo-local-authentication`), master password cache trong `expo-secure-store`.
- Màn Tài khoản phải nhập master password (hoặc PIN) mới xem được; tự khoá sau 5 phút.
- Nút **Xuất backup** (JSON) để tự lưu thêm 1 bản.

### Công nghệ

| Thành phần | Lựa chọn |
|---|---|
| Framework | Expo SDK + React Native + TypeScript |
| Điều hướng | expo-router (bottom tabs) |
| UI | React Native Paper (Material 3) |
| Database | @supabase/supabase-js (session lưu bằng AsyncStorage) |
| Bảo mật | expo-local-authentication, expo-secure-store, @noble/ciphers + @noble/hashes |
| Gọi/Zalo/SMS | `Linking.openURL('tel:…' / 'sms:…' / 'https://zalo.me/<sđt>')` |
| Build | EAS Build (Android), GitHub Actions (iOS IPA) |

---

## 8. Lộ trình

**Giai đoạn 1 – MVP**
- CRUD Khách hàng, NCC, Dịch vụ (Domain/Hosting/VPS, hosting con của VPS), Tài khoản
- Dashboard sắp hết hạn / quá hạn, nhóm theo khách
- Tính hết hạn khi mở app, gia hạn 1 chạm + lịch sử
- Mã hoá mật khẩu, khoá vân tay, backup/restore, build APK

**Giai đoạn 2 – Tiện ích**
- Tin nhắn nhắc mẫu (Zalo/SMS), gọi nhanh
- Báo cáo doanh thu / lợi nhuận theo tháng, dự báo chi phí gia hạn 30/60/90 ngày tới
- Import từ Excel/CSV (chuyển dữ liệu cũ)
- Tự lấy ngày hết hạn domain qua RDAP/WHOIS

**Giai đoạn 3 – Mở rộng (nếu cần)**
- Phân quyền nhiều người dùng (nhân viên chỉ xem, không thấy mật khẩu)
- Email/Telegram nhắc hằng ngày qua cron của Supabase
- Thông báo local nhắc khi mở app / lên lịch sẵn (expo-notifications)
- Kiểm tra uptime website/VPS (ping) đơn giản
