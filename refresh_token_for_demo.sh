#!/bin/bash

echo "🔄 Đang lấy Partner Token..."
PARTNER_RESP=$(curl -s -X POST https://platform-us.plaud.ai/developer/api/oauth/partner/access-token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "YOUR_CLIENT_ID:YOUR_API_KEY")

PARTNER_TOKEN=$(echo $PARTNER_RESP | grep -o '"access_token":"[^"]*' | grep -o '[^"]*$')

if [ -z "$PARTNER_TOKEN" ]; then
    echo "❌ Lỗi: Không lấy được Partner Token!"
    exit 1
fi

echo "🔄 Đang lấy User Access Token (hạn 24h)..."
USER_RESP=$(curl -s -X POST https://platform-us.plaud.ai/developer/api/open/partner/users/access-token \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $PARTNER_TOKEN" \
  -d '{
    "user_id": "user_demo_123",
    "expires_in": 86400
  }')

USER_TOKEN=$(echo $USER_RESP | grep -o '"access_token":"[^"]*' | grep -o '[^"]*$')

if [ -z "$USER_TOKEN" ]; then
    echo "❌ Lỗi: Không lấy được User Token!"
    exit 1
fi

echo "✅ Lấy Token thành công! Đang ghi vào file cấu hình..."

cat <<EOF > plaud-template-app/ios/PartnerConfig.local.xcconfig
USER_ACCESS_TOKEN = $USER_TOKEN
PLAUD_CLIENT_ID = YOUR_CLIENT_ID
PLAUD_API_KEY = YOUR_API_KEY
EOF

echo "🎉 Đã cập nhật xong! Bạn mở Xcode lên và Build lại App nhé!"
