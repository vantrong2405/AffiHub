# VieNeu-TTS runtime spike

Ngày chạy: 2026-10-07. Đây là spike local để xác nhận contract và lấy sample, không phải benchmark production.

## Phiên bản và model

- VieNeu-TTS source: [`pnnbao97/VieNeu-TTS`](https://github.com/pnnbao97/VieNeu-TTS), commit `85344322b7258b4e25479b692e8e3396baf9db34`, package version `3.8.3`, Apache-2.0.
- TTS model: [`pnnbao-ump/VieNeu-TTS-v3-Turbo`](https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo), revision `61b85e3d937fbbacb387714180e8182823512523`; model và preset voices được công bố theo Apache-2.0.
- Audio tokenizer: [`OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX`](https://huggingface.co/OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX), revision `ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae`, Apache-2.0.
- Các license trên không cấp quyền cho voice bên ngoài model. Cần consent khi clone giọng và kiểm tra quyền sử dụng dữ liệu/voice riêng.

## Môi trường

- macOS 14.6, Intel x86_64, Python 3.11.6, 8 logical CPU.
- VieNeu chạy local với backend ONNX, FP32, `max_streams=1`, queue size 1.
- Test environment tối giản dùng `onnxruntime 1.23.2`, `fastapi 0.120.2`, `uvicorn 0.38.0`, `numpy 2.3.4`. Đây không phải lockfile hay hướng dẫn cài production. Full upstream dependency install không hoàn tất vì pip phải build `llvmlite` nhưng máy không có LLVM.
- Cold start tải model và khởi động mất 93.3 giây. Không tính thời gian cold start vào RTF.

## Request và kết quả

Request mẫu khớp payload `_openai_compatible_tts` của MPT được lưu tại [`request-mpt.json`](request-mpt.json). Với `response_format: "mp3"`, endpoint trả HTTP 400 sau 0.039809 giây. Body được lưu tại [`response-vieneu-mp3-400.json`](response-vieneu-mp3-400.json).

Đổi duy nhất `response_format` thành `wav` thì endpoint trả HTTP 200 và audio WAV 353,324 bytes. Tổng thời gian request là 2.960313 giây; audio dài 3.68 giây, nên RTF = 2.960313 / 3.68 = 0.804. WAV là PCM s16le, mono, 48 kHz. VieNeu log TTFA là 0.513 giây; `time_starttransfer` chỉ ghi thời điểm nhận response header.

Sample được giữ tại [`sample-vieneu-v3-turbo-cpu.wav`](sample-vieneu-v3-turbo-cpu.wav). FFprobe và FFmpeg giải mã được file sample kể cả khi bản sao tạm có đuôi `.mp3`, vì nội dung WAV được tự nhận diện. Chưa chạy trực tiếp decoder của MoviePy, vì vậy cần kiểm chứng lại trong adapter MPT.

## Kết luận cho adapter và fallback

MPT hiện hardcode MP3 và lưu nội dung response với đuôi `.mp3`, nên không gọi VieNeu nguyên trạng được. Adapter cần gửi `response_format: "wav"`, lưu file `.wav`, rồi kiểm tra bước MoviePy/assembly thực tế trước khi coi tích hợp hoàn tất.

Chọn Azure Speech làm fallback tự động duy nhất khi provider được cấu hình, có estimate giá hiện hành và người dùng đã xác nhận chi phí. Nếu thiếu một trong các điều kiện này thì không gọi Azure ngầm và không tự chuyển sang Edge TTS; chỉ đánh dấu TTS/job AI bị chặn với provider và lỗi rõ ràng. Edge TTS có thể là lựa chọn thủ công best-effort nếu sản phẩm hiển thị rõ provider được chọn.

Spike này không gọi Azure/Edge, MuAPI, LLM hay Pexels thật; không đánh giá chất lượng chủ quan hoặc độ ổn định production. Máy Intel local cũng không đại diện cho topology Docker triển khai.
