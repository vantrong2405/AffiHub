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
