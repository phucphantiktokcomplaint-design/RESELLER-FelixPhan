# RESELLER — GitHub Pages + Supabase

Bản website RESELLER đã gắn **nguyên bản** 3 ảnh bạn gửi: logo NOX Felix Phan, QR Techcombank và banner ACC CLONE FF. Các tệp ảnh được sao chép byte-for-byte, không crop, không chỉnh màu, không vẽ lại. GitHub Pages là nơi host giao diện; Supabase là backend cần thiết để xác thực, lưu kho, đơn hàng, ví, duyệt nạp và chat realtime.

## Chức năng trong mã nguồn

- Đăng nhập username/password; không có đăng ký Seller công khai.
- Admin tạo Seller qua Edge Function `admin-create-seller` (không đưa service-role key lên GitHub).
- Seller không thấy menu/quyền quản trị; các route Admin bị chặn ở giao diện và dữ liệu được bảo vệ bằng RLS.
- APP NOX: 7.000đ / 45.000đ / 115.000đ; ACC CLONE FF: 5.000đ / 32.000đ / 45.000đ.
- Admin thêm kho Key: mỗi dòng một Key; ACC: mỗi dòng `taikhoan|matkhau`.
- Admin tạo/sửa sản phẩm, giá, mô tả và ảnh; Seller nhận dữ liệu mới từ database.
- Mua hàng chạy bằng RPC transaction: kiểm tra ví và kho, cấp đúng số lượng, đánh dấu hàng đã bán, trừ ví và ghi đơn trong cùng giao dịch.
- Doanh thu được tính từ tổng `orders.total` (đơn mua đã thành công), **không cộng tiền nạp**.
- Nạp tiền có hóa đơn và nút “Đã nạp tiền”; thao tác này tạo yêu cầu để Admin đối soát, không tự cộng ví. Admin duyệt bằng RPC an toàn.
- Chat Seller ↔ Admin realtime, gửi ảnh/tệp qua Storage.
- QR và ảnh thương hiệu sử dụng đúng ảnh gốc người dùng gửi.

## A. Cấu hình Supabase (bắt buộc cho dữ liệu thật)

GitHub Pages không có máy chủ để giữ bí mật hoặc xử lý giao dịch. Vì vậy các chức năng nhiều tài khoản và đồng bộ dữ liệu phải kết nối Supabase. Không cần Render và không cần chạy CMD trên máy tính.

1. Tạo project tại https://supabase.com/dashboard.
2. Vào **SQL Editor → New query**, dán toàn bộ `supabase/schema.sql`, bấm **Run**.
3. Vào **Project Settings → API**, sao chép **Project URL** và **anon/public key**.
4. Mở `config.js`, thay hai giá trị placeholder:
   - `SUPABASE_URL`: Project URL.
   - `SUPABASE_ANON_KEY`: anon/public key.
   Chỉ đưa anon/public key vào frontend. Tuyệt đối không đưa `service_role` key vào GitHub.
5. Vào **Authentication → Users → Add user**, tạo Admin với email `phucphan@reseller.local`, đặt mật khẩu riêng, bật xác nhận email.
6. Chạy câu lệnh sau trong SQL Editor để gán quyền Admin cho user vừa tạo:

```sql
insert into public.profiles(id,username,display_name,role)
select id,'phucphan','Phuc Phan','admin'
from auth.users where email='phucphan@reseller.local'
on conflict(id) do update set username='phucphan',display_name='Phuc Phan',role='admin',active=true;
```

7. Tạo Edge Function `admin-create-seller` trong **Edge Functions**. Dùng nội dung `supabase/functions/admin-create-seller/index.ts`. Supabase Dashboard có thể tạo/deploy function qua giao diện; function dùng biến môi trường `SUPABASE_SERVICE_ROLE_KEY` ở máy chủ Supabase, không đưa key này vào repository.
8. Bật Realtime cho bảng `chat_messages` trong **Database → Replication** nếu chưa được bật.

## B. Đưa lên GitHub Pages

1. Giải nén ZIP.
2. Upload **toàn bộ nội dung bên trong** thư mục `RESELLER-PREMIUM` vào repository, sao cho `index.html`, `app.js`, `style.css`, `config.js` nằm ở root.
3. Vào **Settings → Pages**.
4. Chọn **Deploy from a branch**, branch `main`, folder `/ (root)`, bấm Save.
5. Đợi GitHub Pages deploy và mở URL được cấp.

Không dùng Render, không cần CMD.

## C. Đăng nhập và phân quyền

- Admin đăng nhập bằng username `phucphan`; password là mật khẩu bạn tự đặt trong Supabase Auth ở bước A5.
- Seller đăng nhập bằng username/password do Admin tạo trong mục **Quản lý Seller**.
- Seller không có quyền vào Admin. Admin có thể khóa/mở lại tài khoản Seller. Tài khoản bị khóa không đăng nhập được; lịch sử giao dịch vẫn được giữ để đối soát.
- Không có đăng ký Seller tự do.

## D. Nạp tiền và đối soát

Thông tin hiển thị: **PHAN LE THANH PHUC**, STK **19077609972010**, Techcombank. QR là ảnh gốc đã tải lên. Nội dung chuyển khoản là mã hóa đơn do hệ thống sinh. Nút “Đã nạp tiền” chỉ gửi yêu cầu; Admin cần kiểm tra tiền thực nhận trước khi duyệt. Chưa có kết nối API ngân hàng tự động trong gói này.

## E. Thư mục ảnh

- `assets/branding/`: logo NOX, QR Techcombank.
- `assets/products/app-nox/`: ảnh sản phẩm APP NOX.
- `assets/products/acc-clone-ff/`: banner ACC CLONE FF.
- `assets/status-hack/`: ảnh NOX ở STATUS HACK.

Bạn có thể thay ảnh trong các thư mục trên bằng cách thay tệp đúng tên hoặc cập nhật `image_url` của sản phẩm trong Admin.

## Lưu ý trước khi vận hành thật

Website đã được đóng gói theo kiến trúc GitHub Pages + Supabase, nhưng không thể hoạt động với nhiều Seller cho tới khi bạn tạo project Supabase, chạy SQL, tạo Admin và điền URL/anon key. Không có thông tin Supabase của bạn trong cuộc trò chuyện nên tôi không thể tự kết nối hoặc xác nhận giao dịch thật từ đây. QR là ảnh tĩnh nguyên bản; nếu QR không mã hóa sẵn số tiền/nội dung thì người chuyển khoản cần nhập nội dung hóa đơn hiển thị cạnh QR.
