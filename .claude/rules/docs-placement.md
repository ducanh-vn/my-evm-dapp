# Quy tắc đặt và quản lý tài liệu trong `docs/`

Mọi file `.md` mới tạo ra phải được đặt đúng nhóm trong thư mục `docs/` ở gốc dự án:
- `01-tong-quan/`: Tầm nhìn, giới thiệu dự án, kiến trúc tổng thể On-chain & Off-chain.
- `02-ky-thuat/`: Contract Architecture, ABI, Event Indexer Schema, danh sách địa chỉ contract theo mạng.
- `03-san-pham/`: Tokenomics, cơ chế kinh tế, Business Flows, User Stories, tiêu chí nghiệm thu.
- `04-van-hanh/`: Hướng dẫn chạy Local Node (Anvil), kịch bản Deploy, Verify Explorer, Multisig SOP.
- `05-mau/`: Các file template chuẩn (mẫu đặc tả Smart Contract, mẫu quy trình nghiệp vụ).
- `06-design/`: Wireframe, UI/UX spec, luồng kết nối ví (Wallet UX).
- `99-ghi-chu/`: Ghi chú họp, nháp ý tưởng, nghiên cứu EIP/ERC.

## Quy định bắt buộc:
1. Sau khi thêm, sửa hoặc di chuyển tài liệu, **bắt buộc** phải cập nhật lại `README.md` của thư mục nhóm đó VÀ file `docs/README.md` ở gốc.
2. Không tự ý di chuyển các file đang nằm sai vị trí nếu chưa được user duyệt.
3. Không tự bịa đường dẫn nội bộ hoặc địa chỉ contract; luôn kiểm tra file tồn tại trước khi gắn link.
