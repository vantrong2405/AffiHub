# Image MoneyPrinterTurbo

Image này build MoneyPrinterTurbo từ commit v1.3.8 đã pin và áp dụng hai patch:

- `0001-support-vieneu-wav.patch` cấu hình Chatterbox gửi WAV tới VieNeu-TTS và lưu file
  thành `audio.wav`.
- `0002-tts-fallback-callback.patch` gửi narration cùng Azure voice đã duyệt tới callback Rails
  có chữ ký khi VieNeu-TTS không tạo được `SubMaker`. MPT đánh dấu task lỗi nếu Rails không trả WAV hợp lệ.

Build từ thư mục `affihub/`:

```sh
docker build -f docker/mpt/Dockerfile -t affihub-mpt-wav .
```

Build đã được kiểm tra thành công với command trên, MPT commit đã pin, cả hai patch và
`requirements.txt`. Smoke local trong private Docker network xác nhận MPT khởi động với Redis,
Redis trả `PONG` và endpoint `/ping` trả `200`/healthy. Smoke dùng key giả; chưa chạy Rails callback,
VieNeu/Azure thật, MoviePy với WAV hoặc kiểm tra restart/reconcile.

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
trước khi khởi động MPT. Mount volume bền tại `/MoneyPrinterTurbo/storage` để giữ audio, video
và artifact của task qua lần restart. Health check gọi endpoint `/ping`; không publish cổng
8080 ra host.

Redis giữ task state và queued work, nhưng không tự tiếp tục tác vụ đang chạy khi process MPT
chết. AffiHub phải đối soát trạng thái MPT trước khi retry; chưa kiểm thử restart/reconcile trên
Docker topology thật nên chưa coi đây là bảo đảm recovery runtime.
