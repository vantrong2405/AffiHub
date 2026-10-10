# AffiHub

## Chạy local

PostgreSQL cần chạy trước. Lần đầu cài dependencies và chuẩn bị database:

```bash
rtk bin/setup --skip-server
```

Khởi động Rails trên loopback ở terminal thứ nhất:

```bash
rtk bin/rails server -b 127.0.0.1 -p 3000
```

## Mở preview qua Cloudflare Quick Tunnel

Sau khi Rails đang nghe ở cổng 3000, chạy lệnh này trong terminal thứ hai:

```bash
rtk cloudflared tunnel --url http://127.0.0.1:3000 --http-host-header localhost:3000 --no-autoupdate
```

Mở URL `trycloudflare.com` mà `cloudflared` in ra. Giữ cả hai tiến trình chạy trong lúc preview; nhấn `Ctrl+C` ở từng terminal để dừng.

Quick Tunnel tạo hostname ngẫu nhiên và đưa ứng dụng local ra Internet. Chỉ dùng dữ liệu thử nghiệm. Nếu hostname đổi, cập nhật hostname được phép trong `config/environments/development.rb` rồi khởi động lại Rails.

## Telegram operations bot

Bot Telegram chạy trong một tiến trình runner riêng để kiểm tra heartbeat Solid Queue kể cả khi worker gặp lỗi. Token nằm trong Rails credentials; `enabled` và `allowed_chat_ids` nằm trong `config/telegram.yml`.

1. Lưu token bằng `rtk bin/rails credentials:edit`:

   ```yaml
   telegram:
     bot_token: "TOKEN_DO_BOTFATHER_CAP"
   ```

2. Trong `config/telegram.yml`, bật `enabled` và thêm `chat_id` của bạn vào `allowed_chat_ids` dưới dạng chuỗi. Không đưa token vào YAML.
3. Mở terminal riêng tại thư mục `affihub`, chạy và giữ tiến trình này hoạt động:

   ```bash
   rtk bin/rails runner 'Telegram::PollingService.new.call'
   ```

Bot nhận `/status`, `/pause_auto_publish`, `/resume_auto_publish`, `/pause_auto_reply` và `/resume_auto_reply`. Nhấn `Ctrl+C` trong terminal runner để dừng bot. Khi `enabled` đang tắt, lệnh runner kết thúc ngay; cấu hình mặc định tắt bot và không có chat nào trong allowlist.
