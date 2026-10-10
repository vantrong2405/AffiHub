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
phí.

Smoke bổ sung ngày 2026-10-07 lưu một `AiGeneration` ở trạng thái `processing` trong Rails trước khi
restart MPT. Một tiến trình Rails mới đọc generation đã lưu, reconcile task sentinel đã hoàn tất,
tải và attach đủ bốn output, tạo một `SourceAsset`, enqueue đúng một inspection job; poll lặp lại
không tạo output hoặc job trùng. Smoke dùng file sentinel và rollback dữ liệu Rails sau khi kiểm tra;
không gọi provider trả phí. Chưa xác minh MPT tự tiếp tục video đang chạy, callback Azure thật,
VieNeu/Azure thật hoặc MoviePy xử lý WAV.

Đã lặp lại phần recovery không phát sinh phí ngày 2026-10-11: task sentinel hoàn tất vẫn đọc được
qua API sau khi restart MPT và Redis; một Rails process mới reconcile generation trong test DB,
tải/attach đủ output và tạo đúng một `SourceAsset`. Poll lần nữa giữ nguyên attachment và source
asset. Test DB hiện dùng không có bảng Solid Queue nên lần lặp này không xác minh durable enqueue;
khẳng định enqueue đúng một inspection job ở trên thuộc smoke 2026-10-07. Không có video job trả
phí nào được gửi.

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

Redis giữ task state và queued work qua lần restart đã smoke. Recovery smoke xác minh Rails có thể
reconcile generation đã lưu với task MPT đã hoàn tất sau restart. Redis/MPT không tự tiếp tục một
provider task đang chạy khi process MPT chết; chưa xác minh recovery của task còn chạy hoặc video
được provider tạo thật, nên không coi đây là bảo đảm khôi phục một video đang chạy.

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
