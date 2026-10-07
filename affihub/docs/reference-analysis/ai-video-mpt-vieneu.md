# MoneyPrinterTurbo, MuAPI và VieNeu-TTS — Porting Note

Ngày đối chiếu: 2026-10-07  
Phạm vi: MPT v1.3.8, tạo script/terms/video, MuAPI text-to-video, LLM, stock Pexels, VieNeu-TTS và fallback giọng đọc. Đây là contract và kết quả đọc source; chưa chứng minh các service đã chạy trong AffiHub.

## Nguồn đã đọc

- MoneyPrinterTurbo [commit `fafec0fbf3142ad5ad7212c2e17996bf247c360a`](https://github.com/harry0703/MoneyPrinterTurbo/tree/fafec0fbf3142ad5ad7212c2e17996bf247c360a), ngày commit 2026-10-03; `app/__init__.py` khai báo version `1.3.8`; `LICENSE` là MIT. Source đã đọc: `app/controllers/v1/base.py`, `app/controllers/v1/llm.py`, `app/controllers/v1/video.py`, `app/controllers/manager/memory_manager.py`, `app/controllers/manager/redis_manager.py`, `app/models/llm_provider.py`, `app/models/schema.py`, `app/services/llm.py`, `app/services/material.py`, `app/services/muapi.py`, `app/services/state.py`, `app/services/voice.py`, `config.example.toml`.
- [MuAPI pricing API](https://muapi.ai/docs/pricing) và [MuAPI API examples](https://muapi.ai/playground/seedance-lite-t2v/api): contract submit/poll và cách lấy giá. Giá/mô hình động, phải đọc catalog và estimate hiện hành; không ghi giá cố định vào code.
- [Pexels API documentation](https://www.pexels.com/api/documentation/) và [Pexels license](https://www.pexels.com/license/): xác nhận auth, video search, yêu cầu attribution API và điều khoản media.
- VieNeu-TTS upstream [`docs/streaming.vi.md`](https://github.com/pnnbao97/VieNeu-TTS/blob/main/docs/streaming.vi.md), [`README.vi.md`](https://github.com/pnnbao97/VieNeu-TTS/blob/main/README.vi.md), `pyproject.toml` và `LICENSE`, đọc ngày 2026-10-07. Các đường dẫn này đang ở nhánh `main`, chưa pin commit/image trong OpenSpec; phải pin trước khi dùng lâu dài.
- [Azure Speech REST TTS](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech) và [Azure language/voice support](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts): endpoint theo region, auth, voice list và chi phí phụ thuộc loại voice.

## MPT API và task state

MPT router dùng prefix `/api/v1`. Các route LLM và video cùng áp dụng `verify_token`; source ghi rõ API key rỗng thì bỏ qua xác thực. MPT cấu hình listen host mặc định là `0.0.0.0`, vì vậy AffiHub chỉ được gọi MPT trong private Docker network/loopback và phải bắt buộc API key khác rỗng.

| Route | Request chính | Response / dùng trong AffiHub |
|---|---|---|
| `POST /api/v1/scripts` | `video_subject`, `video_language`, `paragraph_number`, `video_script_prompt`, `custom_system_prompt` | `video_script`; người dùng phải duyệt script trước khi tạo scene. |
| `POST /api/v1/terms` | `video_subject`, `video_script`, `amount`, `match_materials_to_script` | `video_terms`; prompt scene được AffiHub quản lý/duyệt riêng theo scene. |
| `POST /api/v1/videos` | `TaskVideoRequest`, gồm subject/script/terms, aspect, clip duration, source, voice/subtitle settings và material data | Trả `task_id`; gọi nền, không phải file MP4 đồng bộ trong response. |
| `GET /api/v1/tasks/{task_id}` | task ID | `task_id`, integer `state`, `progress`, tùy chọn `videos`, `combined_videos`, `failed_stage`, `error`; các trường mở rộng được giữ lại. |

Contract Pydantic chi tiết nằm trong [pinned `schema.py`](https://github.com/harry0703/MoneyPrinterTurbo/blob/fafec0fbf3142ad5ad7212c2e17996bf247c360a/app/models/schema.py); controller và route trong [pinned `llm.py`](https://github.com/harry0703/MoneyPrinterTurbo/blob/fafec0fbf3142ad5ad7212c2e17996bf247c360a/app/controllers/v1/llm.py) và [pinned `video.py`](https://github.com/harry0703/MoneyPrinterTurbo/blob/fafec0fbf3142ad5ad7212c2e17996bf247c360a/app/controllers/v1/video.py). MPT response state là số nguyên; AffiHub cần map state theo constant/source của đúng phiên bản, không đoán ý nghĩa chỉ từ số.

MPT mặc định dùng `MemoryState`; task record sẽ mất khi tiến trình khởi động lại. Có thể bật Redis cho state và queue. Queue Redis ghi chú hỗ trợ giữ queued item qua restart, nhưng điều này chưa chứng minh job đang chạy/side effect MuAPI có thể reconcile sau restart. AffiHub phải lưu provider task ID, estimate, request snapshot, outbound attempt và checkpoint riêng trong Rails DB; cần chạy restart test trước khi bật paid flow.

## MuAPI: video generation và giá

Pinned MPT source có `app/services/muapi.py` riêng:

- Base URL mặc định `https://api.muapi.ai/api/v1`; endpoint mặc định `seedance-lite-t2v`, có cấu hình override dưới dạng path tương đối.
- Gửi `POST /api/v1/{model}` với `x-api-key` và JSON gồm `prompt`, `aspect_ratio`, `resolution`, `duration`. MPT clamp duration theo cấu hình (mặc định 3–12 giây).
- Response submit cần `request_id` hoặc `id`. Poll `GET /api/v1/predictions/{request_id}/result`; chờ `queued`/`pending`/`processing`, kết thúc ở `completed` hoặc trạng thái lỗi; thành công cần URL trong `outputs`.
- Nếu POST timeout/5xx hoặc response không có ID, có thể job tính phí đã được nhận. Không tự submit lần hai; giữ `OutcomeUnknown` và reconcile.
- MuAPI `/api/v1/models` cung cấp model catalog; lookup từng model có `input_schema`/`output_schema`. Với `dynamic_pricing`, gọi `POST /api/v1/models/{model}/estimate-cost` bằng đúng generation payload (`prompt`, `aspect_ratio`, `resolution`, `duration`) trước khi xin consent. Response có `cost`, `currency`, `dynamic_pricing`, `cost_strategy`; endpoint estimate không chạy inference. Generation response cũng có `cost` thực thu. Ghi lại estimate timestamp/model/payload và so sánh với charge thật.

Giá và model list là dữ liệu live. Chưa gọi API thật trong lượt đối chiếu này; cần xác nhận endpoint `seedance-lite-t2v`, schema và giá trả về từ catalog hiện hành bằng cấu hình/dev credential, không giả lập một mức giá.

## LLM và stock video

- LLM source mặc định provider ID `moonshot`; `llm_provider.py` đăng ký nhiều provider/model, còn `llm.py` gọi qua OpenAI SDK/adapters. Cấu hình provider/model/API key nằm trong config MPT; lựa chọn model và giá token là phụ thuộc account/configuration, không có một license hoặc đơn giá chung.
- MPT `/scripts` và `/terms` chỉ trả nội dung. Trong source đã đọc không thấy contract để AffiHub lấy chi phí LLM chính xác từ MPT. Khi provider không hỗ trợ quote đáng tin cậy, phải hiện phần LLM là ước tính hoặc `unknown`; không trình bày thành giá chắc chắn.
- `config.example.toml` chọn `video_source = "pexels"` làm mặc định. `search_videos_pexels` gọi `GET https://api.pexels.com/v1/videos/search` với `Authorization`, `query`, `per_page=20` và `orientation`; response cần `videos`, mỗi video có `duration` và `video_files` để lọc rendition/tải file. Cần Pexels API key. Pexels không tính phí API theo tài liệu hiện hành và media theo Pexels License dùng được cho mục đích thương mại; API guideline vẫn yêu cầu hiển thị link nổi bật về Pexels và khuyến nghị credit photographer khi có thể. MPT source đã đọc không đủ để kết luận UI AffiHub đáp ứng attribution; phần này phải được implement/review riêng.
- Pexels có hạn mức theo API account. Theo dõi response rate-limit headers và xử lý `429`; không retry dồn hoặc vượt hạn mức.

## VieNeu-TTS và fallback

MPT `_openai_compatible_tts` gửi `POST {base_url}/audio/speech` với Bearer key tùy chọn và JSON `model`, `input`, `voice`, `response_format: "mp3"`, `speed`. MPT tải toàn bộ response, ghi thành MP3 và dùng MoviePy decode để lấy duration; adapter không nhận word-level timestamps nên subtitle cần Whisper hoặc cách đồng bộ khác.

VieNeu-TTS v3 Turbo có OpenAI-compatible `POST /v1/audio/speech`, `GET /v1/models`, `GET /v1/voices`, `GET /health`; `Authorization: Bearer` được bật nếu cấu hình `VIENEU_API_KEY`. Request tương thích `input`, `model`, `voice`, `speed`, nhưng tài liệu upstream nói `speed` bị bỏ qua. Quan trọng: VieNeu hiện nhận `response_format=wav` hoặc `pcm`; `mp3` trả `400`. Vì MPT hardcode `mp3`, hai API **chưa tương thích nguyên trạng** dù cùng path và phần lớn field trùng nhau. Cần spike đúng payload của MPT để lưu bằng chứng `400`, sau đó thử adapter/config đã đổi sang `wav` (hoặc đổi fallback) và decode ra MP4 pipeline trước khi chốt.

Upstream `pyproject.toml` khai báo package code Apache-2.0; license của weight/model cần kiểm tra riêng theo đúng model ID được chọn. Không suy rộng license của source sang mọi model weight. Repo upstream công bố cả CPU/API Docker profile; số đo benchmark của maintainer là dữ liệu tham khảo, không thay cho đo trên máy triển khai.

MPT đã có Edge TTS và Azure TTS path trong `app/services/voice.py` cùng config tương ứng. Tuy nhiên pinned source không định nghĩa thứ tự failover theo yêu cầu sản phẩm, cũng không tính trước chi phí fallback. AffiHub cần điều phối fallback tường minh, lưu provider thực dùng, voice/model/format, lỗi provider trước đó và chi phí/unknown. Edge TTS là lựa chọn best-effort qua client `edge_tts`; cần xác nhận chính sách/độ ổn định và không giả định SLA. Azure Speech cần resource key/region; REST dùng request SSML tới endpoint theo region, trả audio theo output format, voice phải lấy/kiểm tra theo resource/region. Azure tính phí theo loại standard/custom voice nên quote phải dựa cấu hình và bảng giá hiện hành.

## License, giá và mức tin cậy

| Thành phần | License/giá đã xác minh | Giới hạn bằng chứng |
|---|---|---|
| MoneyPrinterTurbo source v1.3.8 | MIT | Điều khoản API/nhà cung cấp vẫn áp dụng riêng. |
| MuAPI | Trả theo lần generation/model; dynamic quote qua estimate API | Chưa có quote runtime cho model/cấu hình AffiHub; không giữ chỗ giá. |
| LLM | Theo provider/model/account | MPT không trả giá chuẩn hóa cho AffiHub; có thể là `unknown`. |
| Pexels API/video | API và media miễn phí theo tài liệu; Pexels License | API key/rate-limit và attribution guideline vẫn phải tuân thủ. |
| VieNeu-TTS | Package/source Apache-2.0; license model weight theo model ID | Chưa pin upstream commit/model digest; cần kiểm tra weight trước phát hành. |
| Edge TTS | Không có mức giá/SLA chính thức được pin trong MPT | Dùng best-effort sau khi rà soát điều khoản/service availability. |
| Azure Speech TTS | Theo region và voice tier | Giá thay đổi theo tier; cần model/voice/region cụ thể để estimate. |

## Giả định cần spike trước khi mở nhánh AI tính phí

1. Gọi MuAPI catalog + `estimate-cost` cho đúng model và payload; ghi quote/charge/runtime response, provider ID, poll transition, output URL và xử lý timeout sau submit.
2. Chạy VieNeu bằng image/model đã pin; gửi request MP3 đúng nguyên trạng MPT để xác nhận incompatibility, rồi thử WAV adapter. Lưu input tiếng Việt, response/audio sample, decoder result, duration, wall time và RTF trên máy mục tiêu.
3. So sánh chất lượng/duration/subtitle với Edge TTS và Azure Speech; chọn fallback tường minh, xác nhận chi phí và voice tiếng Việt.
4. Restart MPT trong lúc task queued, processing và sau provider acceptance; xác nhận task state/queue có thể lookup/reconcile từ Rails DB mà không tạo MuAPI task thứ hai.
5. Xác minh LLM provider/model thực tế, cơ chế báo/ước lượng chi phí và cách ghi phần `unknown`; test Pexels key, rate limit, attribution UI và rendition tải được.
6. Pin MPT image digest, VieNeu commit/image digest và model ID/license; cấu hình API key bắt buộc, private network và healthcheck trong đúng topology Docker.

Chưa gửi request tính phí MuAPI/LLM/TTS/Pexels thật, chưa tạo audio sample và chưa có benchmark runtime trong lần đối chiếu tài liệu này.
