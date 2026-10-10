# Porting note: scheduling và claim khi publish

Ngày đối chiếu: 2026-10-09

Tài liệu này ghi nhận ranh giới kiến trúc cho task OpenSpec 9.1. Postiz chỉ là tài liệu tham khảo kiến trúc; Solid Queue là queue backend đang có trong AffiHub. PostgreSQL của AffiHub vẫn là nguồn trạng thái sản phẩm.

## Nguồn đã đọc

- Postiz `gitroomhq/postiz-app`, commit `86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6`:
  - `apps/backend/src/api/routes/posts.controller.ts`
  - `libraries/nestjs-libraries/src/database/prisma/posts/posts.service.ts`
  - `libraries/nestjs-libraries/src/database/prisma/posts/posts.repository.ts`
  - `apps/orchestrator/src/workflows/post-workflows/post.workflow.v1.1.2.ts`
  - `apps/orchestrator/src/activities/post.activity.ts`
  - `LICENSE`
- [Postiz `posts.controller.ts` tại SHA đã pin](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/apps/backend/src/api/routes/posts.controller.ts), [`posts.service.ts`](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/database/prisma/posts/posts.service.ts), [`posts.repository.ts`](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/database/prisma/posts/posts.repository.ts), [`post.workflow.v1.1.2.ts`](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/apps/orchestrator/src/workflows/post-workflows/post.workflow.v1.1.2.ts), [`post.activity.ts`](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/apps/orchestrator/src/activities/post.activity.ts), [`LICENSE`](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/LICENSE).
- AffiHub đang khóa `solid_queue (1.7.0)` trong `affihub/Gemfile.lock`. Đã đối chiếu `affihub/config/queue.yml`, `config/recurring.yml`, `config/database.yml` và `config/environments/production.rb`.
- Hợp đồng upstream: [Rails Active Job — Solid Queue](https://guides.rubyonrails.org/active_job_basics.html#default-backend-solid-queue) và [Solid Queue v1.7.0](https://github.com/rails/solid_queue/tree/v1.7.0).

Postiz ở SHA này dùng giấy phép AGPL-3.0. Ghi chú dưới đây chỉ mô tả hành vi bằng lời; không sao chép, vendoring hoặc dùng mã Postiz trong AffiHub. Các endpoint và hành vi nền tảng trong Postiz cũng không phải nguồn contract API cho AffiHub.

## Quan sát Postiz tại SHA đã pin

1. `POST /posts` đi qua `PostsController` tới `PostsService.createPost`. Service lưu từng post theo integration, với `publishDate` và trạng thái hàng đợi, rồi khởi chạy Temporal workflow có ID theo post. Luồng workflow đợi đến `publishDate` trước khi gọi các activity publish. `PUT /posts/:id/date` cập nhật lịch và khởi chạy lại workflow; cấu hình workflow ID xử lý workflow cũ khi reschedule.
2. Workflow tách việc gửi post khỏi việc kiểm tra trạng thái và hoàn tất upload bất đồng bộ. Sau khi provider nhận post, workflow không gửi lại chỉ vì bước cập nhật nội bộ hoặc thông báo gặp lỗi. Timeout có thể xảy ra sau khi activity đã chạy được đánh dấu là chưa xác nhận và cần người dùng kiểm tra để tránh đăng trùng.
3. Trong các file đã đọc, workflow ID và kiểm tra trạng thái `QUEUE` không cho thấy một transition claim nguyên tử trong DB sản phẩm kèm lease, heartbeat và fencing token trước side effect. Đây là ghi nhận có giới hạn theo danh sách file đã kiểm tra; không coi cơ chế workflow của Postiz là thay thế cho claim contract AffiHub.

## Solid Queue hiện có trong AffiHub

- `Gemfile.lock` khóa Solid Queue 1.7.0. Production chọn Solid Queue làm Active Job adapter và lưu queue trong database `affihub_production_queue`, tách khỏi primary database.
- `config/queue.yml` cấu hình dispatcher poll mỗi giây, batch 500; worker nghe mọi queue với ba threads, một process mặc định (có thể đổi qua `JOB_CONCURRENCY`) và poll mỗi giây. `config/recurring.yml` hiện khai báo tác vụ production dọn finished jobs theo giờ và hết hạn metadata discovery mỗi phút.
- Active Job hỗ trợ job chạy theo `wait_until`; dispatcher đưa job đến hạn sang hàng đợi sẵn sàng và worker thực thi. Solid Queue cũng có recurring tasks và concurrency controls dựa trên semaphore/database lock.
- Concurrency control của queue giới hạn việc chạy đồng thời theo job key; thời lượng khóa là failsafe. Với job hẹn giờ trong tương lai, concurrency được xét khi job đến hạn. Các cơ chế này giúp điều phối worker, nhưng tự chúng không xác lập trạng thái Publication, quota publish, idempotency provider hoặc kết quả của request đã rời app.
- Do database queue production tách khỏi primary, không giả định transaction của Publication đồng thời commit enqueue. Việc enqueue sau commit tránh job chạy trước khi bản ghi primary tồn tại; một đường reconcile/sweep vẫn cần phát hiện Publication đến hạn nhưng chưa có job tương ứng sau lỗi giữa hai bước.

## Contract cần giữ khi triển khai AffiHub

1. Schedule, occurrence, Publication và trạng thái attempt nằm trong PostgreSQL chính. Mỗi occurrence tạo Publication riêng cho từng destination với khóa idempotency ổn định. Lưu timezone đã chọn; mặc định lấy timezone local của máy tại thời điểm tạo. Lịch lặp tạo occurrence tương lai riêng, không biến một queue job lặp thành nguồn lịch authoritative.
2. Solid Queue chỉ đánh thức worker bằng ID bền vững của Publication/occurrence. Job có thể bị enqueue lại; không dựa vào việc queue chỉ giao job đúng một lần để bảo đảm không đăng trùng.
3. Trong một transaction nguyên tử ở primary DB, worker chỉ claim Publication đang đủ điều kiện, kiểm tra Schedule chưa pause, cấp lease và fencing token, đồng thời reservation quota chung cho manual/scheduled. Tranh chấp lượt cuối chỉ cấp cho một Publication. Reservation được tính khi request publish đầu tiên có thể đã được gửi; `OutcomeUnknown` vẫn giữ lượt.
4. Trước mỗi side effect, lưu attempt ID, stage và trạng thái `Submitting`; kiểm tra fencing token trước transition hoặc attempt mới. Lease mới không xóa attempt cũ: nếu request có thể đã ra ngoài thì reconcile cùng attempt hoặc chuyển `OutcomeUnknown`, không tạo request thứ hai cho đến khi kết quả được xác định.
5. Áp dụng jitter 5–30 phút sau giờ hẹn, không đăng trước giờ. Nếu máy, worker hoặc Scheduler dừng khi occurrence đến hạn, đánh dấu occurrence là missed/skipped và yêu cầu người dùng quyết định lịch lại hoặc đăng tay; không catch-up khi khởi động lại. Pause cũng không tự đăng bù occurrence đã lỡ.
6. Dùng queue concurrency để bảo vệ tài nguyên worker khi cần, không dùng semaphore hoặc thời lượng concurrency của Solid Queue thay cho Publication claim, fencing, quota reservation hay provider reconciliation.

Các điểm trên diễn giải contract hiện có trong `openspec/changes/affihub-mvp-video-workflow/specs/06-multi-platform-publishing/spec.md`, `specs/10-background-worker-reliability/spec.md` và `design.md`; ghi chú không tự thêm route hoặc hành vi sản phẩm.
