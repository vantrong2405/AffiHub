# FFmpeg media workflow — Porting Note

Ngày đối chiếu: 2026-10-06
Phạm vi: local `ffprobe` inspection, trim/retime, khung dọc, background blur, audio, overlay, subtitle và gỡ logo tĩnh. Note này mô tả contract để implement; chưa có worker FFmpeg của AffiHub.

## Nguồn đã đọc

- [FFmpeg Filters Documentation](https://ffmpeg.org/ffmpeg-filters.html): `trim`, `atrim`, `setpts`, `asetpts`, `atempo`, `crop`, `scale`, `pad`, `boxblur`, `overlay`, `volume`, `amix`, `delogo`, `drawtext`, `subtitles`.
- [ffprobe Documentation](https://ffmpeg.org/ffprobe.html): đọc container/stream metadata và xuất JSON có thể parse bằng chương trình.
- [FFmpeg License and Legal Considerations](https://ffmpeg.org/legal.html): phân biệt cấu hình LGPL, `--enable-gpl`, `--enable-nonfree` và nghĩa vụ khi phân phối binary.
- Source release `n9.0.1`, đọc ngày 2026-10-06; annotated tag resolve tới commit `bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa` của [FFmpeg source](https://github.com/FFmpeg/FFmpeg/tree/bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa): `libavfilter/trim.c`, `af_atempo.c`, `vf_crop.c`, `vf_scale.c`, `vf_boxblur.c`, `vf_overlay.c`, `af_volume.c`, `af_amix.c`, `vf_delogo.c`, `vf_drawtext.c`, `vf_subtitles.c`.
- Local developer binary được kiểm tra bằng `ffmpeg -version`, `ffmpeg -L`, `ffmpeg -filters` và `ffprobe -version`: FFmpeg/ffprobe `9.0.1`, Homebrew build có `--enable-gpl`, `--enable-version3`, `--enable-libx264` và hiển thị GPLv3-or-later trong `ffmpeg -L`. Đây là đặc điểm của binary trên máy hiện tại, không phải quyết định license hay runtime build để phân phối.
- `affihub/Dockerfile` hiện chưa cài `ffmpeg`/`ffprobe`. Build local trên host không chứng minh production image hoặc worker container có các binary/filter tương ứng.

## Mapping behavior

| Nhu cầu | Filter/API | Quyết định khi port và cách kiểm chứng |
|---|---|---|
| Trim clip | `trim` + `setpts`; `atrim` + `asetpts` | Cắt theo timecode; reset timestamp cho video/audio sau trim. Re-encode để giữ chính xác đoạn 1–2 giây thay vì giả định mọi điểm cắt trùng keyframe. Dùng `ffprobe` xác nhận duration đầu ra và so với source. |
| Retime video/audio | `setpts` và `atempo` | 2× video dùng PTS divisor tương ứng và 2× audio tempo; 1× giữ timeline gốc. Preview playback speed là control khác, không được coi là retime file. So duration và audio stream bằng `ffprobe`. |
| Khung dọc 9:16 | `scale`, `crop`, `pad` | Dùng mode fit/crop đã lưu trong edit config; chốt 1080×1920, 30 fps ở output profile. Kiểm tra width/height, aspect ratio, frame rate sau render. |
| Nền blur | `split`, `scale`, `boxblur`, `overlay` | Tách bản nền để phóng/crop/làm mờ rồi phủ source ở lớp trước; giữ nguyên file source. Kiểm tra frame mẫu để nền blur không che nội dung chính. |
| Âm thanh | `volume`, `amix`, `atrim`, `asetpts` | Hỗ trợ giữ/tắt source audio, chỉnh âm lượng và trộn voiceover; chỉ tạo audio output khi có stream được chọn. Kiểm tra stream count, codec, duration và nghe mẫu. |
| Logo/ảnh overlay | `overlay` | Chỉ đọc asset nội bộ đã xác thực; overlay và caption phải nằm đúng canvas 9:16. Kiểm tra frame mẫu ở đúng timestamp. |
| Subtitle/text | `subtitles` hoặc `drawtext` | Cả hai phụ thuộc build: `subtitles` cần libass; `drawtext` cần libfreetype/libharfbuzz (font fallback/text shaping có thêm dependency). Binary local hiện không liệt kê hai filter này. Khi dựng worker image phải pin build có dependency/font cần thiết rồi xác minh qua `ffmpeg -filters`; không tuyên bố tính năng subtitle sẵn sàng trước gate này. |
| Gỡ logo tĩnh | `delogo` | Chỉ áp dụng vùng chữ nhật cố định do người dùng chọn; FFmpeg nội suy vùng từ pixel xung quanh, không phải content-aware object removal. Preview vùng xử lý và giữ source nguyên để có thể hoàn tác bằng render version mới. |
| Đọc metadata | `ffprobe -v error -show_format -show_streams -of json` | Parse JSON cho duration, dimensions, codec, frame rate và audio stream. Exit code lỗi hoặc thiếu video stream phải đưa source sang lỗi có hướng dẫn, không nhận metadata từ tên file. |

## Ranh giới an toàn và vận hành

- Worker gọi binary với argv tách phần tử, không ghép đường dẫn hoặc giá trị người dùng vào shell command. Filtergraph chỉ được dựng từ cấu trúc edit config đã validate; caption/font/path không được nội suy thành lệnh shell.
- Mỗi render ghi sang file/version mới. Lỗi encode không sửa source hoặc file version trước.
- Task render phải kiểm tra binary/version/filter capabilities lúc worker khởi động; thiếu `ffmpeg`, `ffprobe`, encoder hoặc subtitle filter là lỗi cấu hình riêng của worker.
- Trước khi phân phối binary, cần chọn/pin build và rà license theo đúng cấu hình compile cùng thư viện đi kèm. Binary local hiện bật GPL và `libx264`; không dùng kết quả này để kết luận giấy phép của bản build khác.
- Kiểm chứng đầu ra bằng `ffprobe` trên file render thật; sample-frame comparison kiểm tra crop, blur, overlay, subtitle và `delogo`. RSpec cover behavior/command arguments với process boundary được stub; không giả lập `ffprobe` metadata ở kiểm tra output cuối.

## Giới hạn và việc còn phải xác minh

- Chưa có container/worker FFmpeg trong AffiHub; cần thêm binary vào đúng worker image và pin version/build khi implement render.
- Cần chọn font tiếng Việt có license phù hợp và kiểm tra font fallback, glyph dấu, line wrapping và rendering cùng browser preview.
- `delogo` chỉ làm nội suy vùng tĩnh, có thể để lại artifacts; không cam kết xóa logo chuyển động hoặc tái tạo nền hoàn hảo.
- Codec profile, pixel format, audio mapping và metadata của output phải được kiểm tra bằng `ffprobe` trong task render, không dựa riêng trên command thành công.
