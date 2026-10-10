# MoneyPrinterTurbo, MuAPI và VieNeu-TTS — Porting Note

Ngày đối chiếu nguồn: 2026-10-07; xác minh recovery bổ sung: 2026-10-11  
Phạm vi: MPT v1.3.8, tạo script/terms/video, MuAPI text-to-video, LLM, stock Pexels, VieNeu-TTS và fallback giọng đọc. Ghi chú gồm contract/source research, kết quả RSpec dùng WebMock, kiểm tra hai patch trên source MPT đã pin, build image, smoke MPT/Redis và Rails reconciliation với task sentinel hoàn tất. Chưa chạy Azure thật hoặc xác minh toàn bộ topology triển khai.

## Nguồn đã đọc

- MoneyPrinterTurbo [commit `fafec0fbf3142ad5ad7212c2e17996bf247c360a`](https://github.com/harry0703/MoneyPrinterTurbo/tree/fafec0fbf3142ad5ad7212c2e17996bf247c360a), ngày commit 2026-10-03; `app/__init__.py` khai báo version `1.3.8`; `LICENSE` là MIT. Source đã đọc: `app/controllers/base.py`, `app/controllers/v1/llm.py`, `app/controllers/v1/video.py`, `app/controllers/manager/memory_manager.py`, `app/controllers/manager/redis_manager.py`, `app/models/llm_provider.py`, `app/models/schema.py`, `app/services/llm.py`, `app/services/material.py`, `app/services/muapi.py`, `app/services/state.py`, `app/services/voice.py`, `config.example.toml`.
- [MuAPI pricing API](https://muapi.ai/docs/pricing) và [MuAPI API examples](https://muapi.ai/playground/seedance-lite-t2v/api): contract submit/poll và cách lấy giá. Giá/mô hình động, phải đọc catalog và estimate hiện hành; không ghi giá cố định vào code.
- [Pexels API documentation](https://www.pexels.com/api/documentation/) và [Pexels license](https://www.pexels.com/license/): xác nhận auth, video search, yêu cầu attribution API và điều khoản media.
- VieNeu-TTS upstream [`docs/streaming.vi.md`](https://github.com/pnnbao97/VieNeu-TTS/blob/85344322b7258b4e25479b692e8e3396baf9db34/docs/streaming.vi.md), [`README.vi.md`](https://github.com/pnnbao97/VieNeu-TTS/blob/85344322b7258b4e25479b692e8e3396baf9db34/README.vi.md), [`pyproject.toml`](https://github.com/pnnbao97/VieNeu-TTS/blob/85344322b7258b4e25479b692e8e3396baf9db34/pyproject.toml) và [`LICENSE`](https://github.com/pnnbao97/VieNeu-TTS/blob/85344322b7258b4e25479b692e8e3396baf9db34/LICENSE), đọc ngày 2026-10-07. Source được pin ở commit `85344322b7258b4e25479b692e8e3396baf9db34`, package version `3.8.3`.
- Model [`VieNeu-TTS-v3-Turbo`](https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/tree/61b85e3d937fbbacb387714180e8182823512523) được pin ở revision `61b85e3d937fbbacb387714180e8182823512523`; tokenizer [`MOSS-Audio-Tokenizer-Nano-ONNX`](https://huggingface.co/OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX/tree/ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae) ở revision `ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae`.
- [Azure Speech REST TTS](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech) và [Azure language/voice support](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts): endpoint theo region, auth, voice list và chi phí phụ thuộc loại voice.

## MPT API và task state

MPT router dùng prefix `/api/v1`. Các route LLM và video cùng áp dụng `verify_token`; source ghi rõ API key rỗng thì bỏ qua xác thực. MPT cấu hình listen host mặc định là `0.0.0.0`, vì vậy AffiHub chỉ được gọi MPT trong private Docker network/loopback và phải bắt buộc API key khác rỗng.

| Route | Request chính | Response / dùng trong AffiHub |
|---|---|---|
| `POST /api/v1/scripts` | `video_subject`, `video_language`, `paragraph_number`, `video_script_prompt`, `custom_system_prompt` | `video_script`; người dùng phải duyệt script trước khi tạo scene. |
| `POST /api/v1/terms` | `video_subject`, `video_script`, `amount`, `match_materials_to_script` | `video_terms`; prompt scene được AffiHub quản lý/duyệt riêng theo scene. |
| `POST /api/v1/videos` | `TaskVideoRequest`, gồm subject/script/terms, aspect, clip duration, source, voice/subtitle settings và material data | Trả `task_id`; gọi nền, không phải file MP4 đồng bộ trong response. |
| `GET /api/v1/tasks?page=&page_size=` | Trang và số task/trang (tối đa 1000) | Trả task list có `task_id`, `request_id`, `state` và progress; dùng để reconcile submit timeout theo correlation ID. |
| `GET /api/v1/tasks/{task_id}` | task ID | `task_id`, integer `state`, `progress`, tùy chọn `videos`, `combined_videos`, `failed_stage`, `error`; các trường mở rộng được giữ lại. |
| `GET /api/v1/download/{file_path}` | Đường dẫn file tương đối với task directory | Tải artifact task sau khi hoàn tất; route kiểm tra file nằm trong task directory và trả `FileResponse`. |

MPT tạo output reference với prefix `tasks/{task_id}/{relative_path}`, trong khi route download
resolve `file_path` từ chính thư mục `storage/tasks`. Vì vậy adapter Rails xác nhận task ID trong
reference, bỏ đúng prefix `tasks/` rồi mới gọi endpoint download đã cấu hình; request gửi
`{task_id}/{relative_path}`. Nếu gửi nguyên prefix từ task response, route sẽ tìm nhầm
`storage/tasks/tasks/{task_id}/...`.

Contract Pydantic chi tiết nằm trong [pinned `schema.py`](https://github.com/harry0703/MoneyPrinterTurbo/blob/fafec0fbf3142ad5ad7212c2e17996bf247c360a/app/models/schema.py); controller và route trong [pinned `llm.py`](https://github.com/harry0703/MoneyPrinterTurbo/blob/fafec0fbf3142ad5ad7212c2e17996bf247c360a/app/controllers/v1/llm.py) và [pinned `video.py`](https://github.com/harry0703/MoneyPrinterTurbo/blob/fafec0fbf3142ad5ad7212c2e17996bf247c360a/app/controllers/v1/video.py). MPT response state là số nguyên; AffiHub cần map state theo constant/source của đúng phiên bản, không đoán ý nghĩa chỉ từ số.

Ở source đã pin, `app/controllers/base.py#get_task_id` đọc header `X-Task-ID` và normalize giá trị không hợp lệ thành UUID. `POST /api/v1/videos` lưu giá trị đó vào trường `request_id`; task-list trả lại trường này dù schema cho phép field mở rộng. Vì vậy Rails có thể gửi correlation ID ổn định qua `X-Task-ID` rồi tìm task đã nhận nếu response submit bị mất. Header không phải idempotency: nếu list chưa cho kết quả kết luận được thì Rails vẫn phải giữ `OutcomeUnknown` và chặn POST lần nữa. Các URL output task được tạo từ đường dẫn trong task directory; Rails cần tải artifact qua route MPT thay vì coi path nội bộ container là file local.

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

VieNeu-TTS v3 Turbo có OpenAI-compatible `POST /v1/audio/speech`, `GET /v1/models`, `GET /v1/voices`, `GET /health`; `Authorization: Bearer` được bật nếu cấu hình `VIENEU_API_KEY`. Request tương thích `input`, `model`, `voice`, `speed`, nhưng tài liệu upstream nói `speed` bị bỏ qua. VieNeu nhận `response_format=wav` hoặc `pcm`; `mp3` trả `400`. Spike local dùng đúng request body MPT xác nhận MP3 bị từ chối trong 0.039809 giây. Đổi sang WAV trả 200 với PCM s16le mono 48 kHz, audio 3.68 giây, request wall time 2.960313 giây và RTF 0.804. Sample, request, error body và môi trường được ghi tại [VieNeu runtime spike](spikes/vieneu-tts/README.md). FFmpeg nhận diện/giải mã được WAV khi file mang đuôi `.mp3`, nhưng MoviePy chưa được chạy trực tiếp.

AffiHub có image riêng tại `docker/mpt/` và hai patch cho đúng MPT commit đã pin. `0001-support-vieneu-wav.patch` cho phép cấu hình `response_format`, gửi `wav` tới Chatterbox/VieNeu và dùng `audio.wav` ở task pipeline; MP3 vẫn là mặc định cho provider khác. `0002-tts-fallback-callback.patch` thêm voice được duyệt vào schema, truyền MPT `request_id` tới pipeline và gọi callback Rails khi VieNeu không tạo được `SubMaker`. Hai patch đã được áp tuần tự bằng `git apply --check` lên source sạch từ pinned commit; các file Python sau patch biên dịch được bằng `py_compile`. Docker image đã build thành công từ pinned commit, hai patch và requirements trên Python 3.11 slim Bookworm. Container MPT khởi động với Redis trong private Docker network, Redis trả `PONG`, `/ping` trả `200` và healthcheck đạt `healthy`. Smoke này dùng key giả; chưa gọi callback Rails/Azure, chưa chạy VieNeu hoặc MoviePy với WAV, chưa kiểm chứng assembly và restart/reconcile.

Source VieNeu ở commit đã pin, model v3 Turbo và preset voices trong model card, cùng MOSS tokenizer ONNX được công bố theo Apache-2.0 tại các snapshot trên. Đây không phải quyền sử dụng mọi voice/dataset bên ngoài; voice cloning vẫn cần consent và quyền dùng dữ liệu tương ứng. Repo upstream công bố CPU/API Docker profile; benchmark local trong spike là số đo Intel Mac, không thay cho đo trên topology triển khai.

MPT đã có Edge TTS và Azure TTS path trong `app/services/voice.py` cùng config tương ứng. AffiHub chọn Azure Speech làm fallback tự động duy nhất khi provider được cấu hình, có estimate hiện hành và người dùng đã xác nhận chi phí; nếu thiếu điều kiện, không tự gọi Azure hoặc chuyển sang Edge, mà báo lỗi TTS/job AI. Edge TTS chỉ là lựa chọn thủ công best-effort, cần hiển thị rõ provider và không giả định SLA. Azure Speech cần resource key/region; REST dùng request SSML tới endpoint theo region, trả audio theo output format, voice phải lấy/kiểm tra theo resource/region. Azure tính phí theo loại standard/custom voice nên estimate phải dựa cấu hình và bảng giá hiện hành.

`AiGenerations::SubmitService` lưu generation, scene TTS index `0`, narration, Azure voice, quote và consent trước MPT POST; request gửi cùng correlation ID trong `X-Task-ID` và `tts_fallback_voice`. Route `POST /internal/mpt/tts_fallback` đi qua `Internal::Mpt::TtsFallbacksController` và `AiGenerations::TtsFallbackCallbackService`. Callback kiểm tra HMAC trên raw body, timestamp, generation/scene, narration/voice đã duyệt, quote Azure còn hạn/đúng currency và consent khớp trước khi tạo `WorkflowRun`/`OutboundAttempt` rồi gọi Azure. Thành công lưu WAV, xác nhận attempt và đánh dấu scene hoàn tất; replay trả WAV đã lưu. Lỗi có kết quả không rõ giữ `OutcomeUnknown` và không gọi Azure lần hai.

MPT gửi JSON `{ "correlation_id", "scene_index", "narration", "voice" }`, timestamp epoch seconds trong `X-MPT-Timestamp`, và `X-MPT-Signature` là HMAC-SHA256 của chuỗi `timestamp + "." + raw_body` bằng secret dùng chung từ environment. Correlation ID là `request_id` MPT lưu từ header `X-Task-ID`; scene index `0` đại diện toàn bộ `video_script`, vì pinned `task.py` gọi TTS một lần cho script này. Thành công trả raw WAV với `Content-Type: audio/wav`; lỗi trả non-2xx để MPT dừng TTS stage, không dùng Edge và không đánh dấu task hoàn tất. RSpec service/request bao phủ xác thực, quote/consent, replay và timeout; đã chạy xanh bằng `RAILS_ENV=test`. Bằng chứng này không thay cho build image hoặc kiểm tra runtime.

Image MPT yêu cầu Redis để bật Redis task manager/state và volume bền tại `/MoneyPrinterTurbo/storage`. Trong source của image đã kiểm tra, `app/asgi.py#application_lifespan` gọi `RedisTaskManager.resume_queued_tasks()`; hàm này chỉ dispatch các entry còn trong queue, không resume task record đã ở `state=processing`. Smoke ngày 2026-10-11 xác nhận giới hạn này ở tầng state/API: tạo Redis task sentinel `state=4`, `progress=47`, restart MPT, rồi `GET /api/v1/tasks/{task_id}` vẫn trả nguyên `state=4`, `progress=47`. Sentinel này không chạy worker hay provider; vì vậy nó chứng minh record processing cũ có thể tồn tại mà không có bằng chứng pipeline còn sống, chứ không phải smoke một tác vụ provider đang chạy. OpenSpec quyết định MPT MVP chạy một API process duy nhất trên Redis state; startup sẽ giữ lại task ID còn trong queue để dispatch lại và đánh dấu `processing` task không còn queue là interrupted, để Rails chuyển cùng attempt đã xác nhận sang `OutcomeUnknown`. Không triển khai nhiều MPT process dùng chung Redis vì một process không thể kết luận task đã mất owner nếu worker còn chạy ở process khác.

Smoke task hoàn tất cùng ngày ghi sentinel vào Redis/storage riêng, restart MPT và Redis, rồi xác nhận task/output còn đọc được. Một Rails process mới dùng `AiGenerations::PollService` reconcile generation `processing` từ task đó, tải/attach đủ output, tạo đúng một `SourceAsset`; lần poll tiếp theo không tạo bản ghi hoặc attachment trùng. Các smoke không gửi video job trả phí; DB test không có bảng Solid Queue nên lần lặp Rails này không xác minh enqueue bền vững. Kết quả hiện tại cho thấy Rails polling `state=4` không đủ để kết luận MPT task còn chạy; cần recovery signal để chuyển tác vụ mất owner sang `OutcomeUnknown` mà không retry MuAPI. Không tự thêm timeout/ngưỡng progress vì contract MPT không đưa ra giới hạn thời gian; paid flow vẫn bị preflight gate. OpenSpec task 13.4 vẫn mở cho tới khi hoàn tất các kịch bản reliability còn lại (worker/sender, checkpoint upload, Google timeout, Telegram outage, local export và lịch missed).

## License, giá và mức tin cậy

| Thành phần | License/giá đã xác minh | Giới hạn bằng chứng |
|---|---|---|
| MoneyPrinterTurbo source v1.3.8 | MIT | Điều khoản API/nhà cung cấp vẫn áp dụng riêng. |
| MuAPI | Trả theo lần generation/model; dynamic quote qua estimate API | Chưa có quote runtime cho model/cấu hình AffiHub; không giữ chỗ giá. |
| LLM | Theo provider/model/account | MPT không trả giá chuẩn hóa cho AffiHub; có thể là `unknown`. |
| Pexels API/video | API và media miễn phí theo tài liệu; Pexels License | API key/rate-limit và attribution guideline vẫn phải tuân thủ. |
| VieNeu-TTS | Source commit `85344322b7258b4e25479b692e8e3396baf9db34`, model revision `61b85e3d937fbbacb387714180e8182823512523`, và MOSS tokenizer revision `ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae` được công bố Apache-2.0 | Phải giữ attribution; license không thay thế consent/quyền dùng voice bên ngoài. |
| Edge TTS | Không có mức giá/SLA chính thức được pin trong MPT | Dùng best-effort sau khi rà soát điều khoản/service availability. |
| Azure Speech TTS | Theo region và voice tier | Giá thay đổi theo tier; cần model/voice/region cụ thể để estimate. |

## Giả định cần spike trước khi mở nhánh AI tính phí

1. Gọi MuAPI catalog + `estimate-cost` cho đúng model và payload; ghi quote/charge/runtime response, provider ID, poll transition, output URL và xử lý timeout sau submit.
2. Đã chạy VieNeu local với model revision đã pin; MP3 đúng nguyên trạng MPT trả 400, WAV trả 200 và sample/RTF được ghi trong [runtime spike](spikes/vieneu-tts/README.md). Patch WAV và callback đã áp/biên dịch source-level; còn cần build image, kiểm chứng MoviePy/assembly và restart trên topology triển khai.
3. So sánh chất lượng/duration/subtitle với Azure Speech, lấy estimate hiện hành và kiểm tra voice tiếng Việt trước khi bật fallback tự động có consent. Edge chỉ là lựa chọn thủ công best-effort.
4. Restart MPT trong lúc task queued, processing và sau provider acceptance; xác nhận task state/queue có thể lookup/reconcile từ Rails DB mà không tạo MuAPI task thứ hai.
5. Xác minh LLM provider/model thực tế, cơ chế báo/ước lượng chi phí và cách ghi phần `unknown`; test Pexels key, rate limit, attribution UI và rendition tải được.
6. Pin MPT image digest, VieNeu commit/image digest và model ID/license; cấu hình API key bắt buộc, private network và healthcheck trong đúng topology Docker.

Chưa gửi request tính phí MuAPI/LLM/Pexels/Azure thật. VieNeu runtime spike đã tạo sample local; kết quả trên máy Intel không đại diện benchmark production.
