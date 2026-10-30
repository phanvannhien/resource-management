#!/bin/zsh
# Build và cài AMV-WebManage lên iPhone đang cắm cáp (Apple ID miễn phí: app hết hạn sau 7 ngày,
# chạy lại script này để gia hạn). Dùng: ./tool/install_ios.sh
set -e
source /Volumes/data/sdk/env.sh
cd "$(dirname "$0")/.."

# Lấy mã thiết bị (UUID) của iPhone đang kết nối; tên máy có thể chứa dấu cách nên không tách theo cột
DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep -i 'iphone' | grep -v 'unavailable' | grep 'available' \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
if [ -z "$DEVICE" ]; then
  echo "Không thấy iPhone. Cắm cáp, mở khoá máy rồi chạy lại."; exit 1
fi

flutter build ios --release --dart-define-from-file=env.json
xcrun devicectl device install app --device "$DEVICE" build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device "$DEVICE" vn.servicemanager.serviceManager || \
  echo "Đã cài. Nếu không mở được: Cài đặt → Cài đặt chung → Quản lý VPN & thiết bị → tin cậy Apple ID."
