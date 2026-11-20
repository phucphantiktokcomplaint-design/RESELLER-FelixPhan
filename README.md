# RESELLER — GitHub Pages + Supabase

Bản source đã được rà soát và cập nhật cấu hình Supabase theo Project URL và Publishable key bạn cung cấp. Giao diện chạy trên GitHub Pages; xác thực, dữ liệu, kho, ví, đơn hàng, duyệt nạp và chat dùng Supabase.

## Thành phần

- `index.html`, `style.css`, `app.js`: giao diện và logic website.
- `config.js`: Project URL + Publishable key công khai (được phép dùng ở trình duyệt).
- `supabase/schema.sql`: schema cho phiên bản RESELLER hiện tại.
- `supabase/00_prepare_previous_schema.sql`: giữ lại và đổi tên schema cũ nếu bạn đã chạy bộ SQL RESELLER trước đó.
- `supabase/02_import_previous_data.sql`: chuyển hồ sơ, sản phẩm, kho, yêu cầu nạp, lịch sử ví và tin nhắn từ schema cũ.
- `supabase/functions/admin-create-seller/index.ts`: Edge Function tạo tài khoản Seller an toàn.

## QUAN TRỌNG — database hiện tại của bạn

Trước đó bạn đã chạy một bộ SQL có các cột `profiles.email`, `profiles.wallet_balance`, `profiles.is_active` và bảng `key_stock`, `acc_stock`, `deposits`, `transactions`, `messages`. Source trong ZIP dùng cấu trúc mới (`wallet`, `active`, `inventory`, `deposit_requests`, `wallet_transactions`, `chat_messages`). Chỉ chạy `schema.sql` trực tiếp trên database cũ sẽ không tự đổi cấu trúc vì `CREATE TABLE IF NOT EXISTS` không sửa cột cũ.

Nếu đúng là bạn đã chạy bộ SQL cũ, hãy làm theo thứ tự dưới đây để giữ dữ liệu cũ:

1. Supabase → **SQL Editor** → **New query**.
2. Mở `supabase/00_prepare_previous_schema.sql`, sao chép toàn bộ và bấm **Run**. Script đổi tên các bảng cũ thành `legacy_*`, không xóa dữ liệu.
3. Mở `supabase/schema.sql`, sao chép toàn bộ và bấm **Run**.
4. Mở `supabase/02_import_previous_data.sql`, sao chép toàn bộ và bấm **Run** một lần. Script chuyển hồ sơ, sản phẩm, kho, nạp tiền, lịch sử ví và tin nhắn. Đơn hàng cũ vẫn được giữ nguyên trong `legacy_orders` và `legacy_order_items`; chưa chuyển vào màn hình lịch sử mới do cấu trúc đơn cũ hỗ trợ nhiều sản phẩm trong một đơn.
5. Nếu database của bạn là project mới, chưa chạy SQL cũ, chỉ cần chạy `schema.sql`.

Không xóa các bảng `legacy_*` cho tới khi bạn đã kiểm tra dữ liệu và xác nhận không cần lưu trữ nữa.

## Tạo / gán Admin

1. Trong Supabase → **Authentication → Users**, tạo hoặc xác nhận tài khoản Auth với email `phucphanmedia@gmail.com` và mật khẩu bạn tự đặt.
2. Trong SQL Editor chạy:

```sql
insert into public.profiles(id,username,display_name,role)
select id,'phucphan','Phuc Phan','admin'
from auth.users
where email='phucphanmedia@gmail.com'
on conflict(id) do update
set username='phucphan',display_name='Phuc Phan',role='admin',active=true;
```

3. Đăng nhập website bằng username `phucphan` và mật khẩu Auth ở bước 1.

## Cấu hình Supabase đã điền

`config.js` hiện dùng:

- Project URL: `https://xzjiyhchujeddupjinho.supabase.co`
- Publishable key: key công khai `sb_publishable_...` bạn gửi.

Publishable key được thiết kế để xuất hiện trong trình duyệt; quyền truy cập dữ liệu vẫn phải được kiểm soát bằng RLS. **Không bao giờ** đưa `service_role` key, JWT secret hoặc database password vào `config.js`, HTML, JavaScript hay GitHub.

## Deploy Edge Function tạo Seller

1. Supabase → **Edge Functions** → tạo function tên `admin-create-seller`.
2. Dùng nội dung `supabase/functions/admin-create-seller/index.ts`.
3. Deploy function. Giữ `SUPABASE_SERVICE_ROLE_KEY` trong secrets phía Supabase Function; tuyệt đối không đưa key đó vào GitHub.
4. Bật Realtime cho bảng `chat_messages` nếu project chưa bật publication này.

## Đưa website lên GitHub Pages

1. Giải nén ZIP.
2. Mở thư mục `RESELLER-PREMIUM` (hoặc thư mục gốc đã giải nén bản FIXED).
3. Upload **các nội dung bên trong thư mục** lên root repository: `index.html`, `app.js`, `style.css`, `config.js`, `assets/`, `supabase/`, `.nojekyll`, `README.md`.
4. GitHub repository → **Settings → Pages**.
5. Chọn **Deploy from a branch** → branch `main` → folder `/(root)` → **Save**.
6. Chờ GitHub Pages hoàn tất deployment rồi mở URL GitHub Pages hiển thị.

Repository hiện tại của bạn là Private. GitHub Pages có thể yêu cầu gói/tổ chức hỗ trợ Pages cho repository Private; nếu không bật được Pages, đổi repository sang Public hoặc dùng hosting static phù hợp. Không để bất kỳ secret backend nào trong repository.

## Luồng chức năng

- Không có đăng ký Seller công khai. Admin tạo Seller trong mục **Quản lý Seller**.
- Seller đăng nhập bằng username và mật khẩu do Admin cấp.
- Admin có thể khóa/mở Seller.
- Admin thêm kho: mỗi dòng một Key; ACC theo định dạng `taikhoan|matkhau`.
- Mua hàng gọi RPC giao dịch nguyên tử: kiểm tra số dư và kho, cấp phát, trừ ví và ghi đơn trong cùng transaction.
- Nạp tiền chỉ tạo yêu cầu. Admin phải kiểm tra tiền thực nhận rồi mới duyệt; RPC mới cộng số dư.
- Chat Seller ↔ Admin hỗ trợ tin nhắn và tệp đính kèm.
- Doanh thu lấy từ đơn hàng, không cộng tiền nạp.

## Thanh toán

Thông tin Techcombank đang hiển thị trong giao diện: PHAN LE THANH PHUC, STK `19077609972010`. QR trong thư mục assets là ảnh tĩnh. Hệ thống hiện **chưa tích hợp API ngân hàng/webhook tự động**. Nội dung chuyển khoản là mã hóa đơn; Seller gửi bill qua chat và Admin tự đối soát trước khi duyệt.

## Kiểm tra trước khi bán thật

- Đã chạy đúng bộ SQL theo trạng thái database.
- Đã tạo profile Admin và đăng nhập thành công.
- Đã deploy Edge Function `admin-create-seller`.
- Đã thử tạo Seller, khóa Seller, thêm kho thử, mua thử, tạo yêu cầu nạp và duyệt thử.
- Đã xác nhận RLS ngăn Seller đọc kho thô và dữ liệu Seller khác.
- Không dùng key bí mật trong frontend.
