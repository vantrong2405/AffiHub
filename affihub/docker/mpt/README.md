# Image MoneyPrinterTurbo

Image này build MoneyPrinterTurbo từ commit v1.3.8 đã pin và áp dụng hai patch:

- `0001-support-vieneu-wav.patch` cấu hình Chatterbox gửi WAV tới VieNeu-TTS và lưu file
  thành `audio.wav`.
- `0002-tts-fallback-callback.patch` gửi narration cùng Azure voice đã duyệt tới callback Rails
  có chữ ký khi VieNeu-TTS không tạo được `SubMaker`. MPT đánh dấu task lỗi nếu Rails không trả WAV hợp lệ.

Build từ thư mục `affihub/`:

```sh
rtk docker build -f docker/mpt/Dockerfile -t affihub-mpt-wav .
```

Build đã được kiểm tra thành công với command trên, MPT commit đã pin, cả hai patch và
`requirements.txt`. Smoke trong private Docker network với key giả xác nhận Redis `PONG`, health
check `/ping`, đọc task sentinel qua `/api/v1/tasks` sau khi restart cả MPT lẫn Redis, và giữ được
một queue marker qua Redis restart. Sentinel được ghi trực tiếp vào Redis; không gửi video job trả
phí. Chưa xác minh MPT tự resume một video đang chạy, callback Rails thật, VieNeu/Azure thật hoặc
MoviePy xử lý WAV.

## Cấu hình runtime

- `MPT_API_KEY`: bắt buộc để xác thực request Rails tới MPT.
- `MPT_APP_REDIS_HOST`: bắt buộc để bật Redis task queue/state. Có thể cấu hình thêm
  `MPT_APP_REDIS_PORT`, `MPT_APP_REDIS_DB` và `MPT_APP_REDIS_PASSWORD`.
- `MPT_TTS_FALLBACK_CALLBACK_URL`: URL Rails nội bộ, ví dụ
  `http://affihub/internal/mpt/tts_fallback` trên private application network.
- `MPT_TTS_CALLBACK_SECRET`: secret phải trùng với cấu hình Rails.
- `VIENEU_TTS_BASE_URL`, `VIENEU_TTS_API_KEY`, `VIENEU_TTS_MODEL_ID` và
  `VIENEU_TTS_VOICE`: tùy chọn khi giá trị mặc định không khớp với service VieNeu riêng.

Giữ Rails, MPT, Redis và VieNeu trên private application network. Entrypoint kiểm tra Redis
trước khi khởi động MPT và yêu cầu Redis bật AOF (`appendonly yes`). Mount volume bền cho Redis
tại `/data` và cho MPT tại `/MoneyPrinterTurbo/storage`; image tạo storage directory với owner
`mpt` để process non-root ghi được vào volume. Health check gọi endpoint `/ping`; không publish
cổng 8080 ra host.

Redis giữ task state và queued work qua lần restart đã smoke. Redis không tự tiếp tục tác vụ đang
chạy khi process MPT chết. AffiHub phải đối soát trạng thái MPT trước khi retry; chưa kiểm thử
resume/reconcile một tác vụ video đang chạy nên chưa coi đây là bảo đảm recovery runtime.

## Worker Rails

Production Rails dùng Solid Queue trên database `affihub_production_queue`. Docker image bật
Solid Queue supervisor trong Puma; schema queue được quản lý riêng với database chính. Có thể
kiểm tra cấu hình worker trước deploy bằng:

```sh
RAILS_ENV=production rtk bin/jobs check --skip-recurring
```

`--skip-recurring` validates worker and dispatcher settings without connecting to the production
database; run `rtk bin/jobs check` against the deployment environment to validate its recurring
schedule as well.

`RAILS_ENV=production rtk bin/jobs start` có thể dùng khi chạy worker tách khỏi Puma. Không chạy
đồng thời worker tách rời và plugin Puma trên cùng deployment nếu cấu hình process chưa được chủ
động phân chia.
