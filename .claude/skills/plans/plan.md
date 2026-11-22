# Skill: Planning Workflow (EVM System)

Trước khi viết Smart Contract hoặc code dApp, thực hiện theo 4 bước:
1. **Phân tích luồng tiền & trạng thái:** Xác định các vai trò (Admin, User, Operator), luồng nạp/rút tài sản, các trạng thái của hợp đồng (State Machine) và điều kiện chuyển trạng thái.
2. **Kiểm tra ngữ cảnh & thư viện:** Đọc `CLAUDE.md`, tài liệu trong `docs/`, và kiểm tra xem OpenZeppelin đã có sẵn module chuẩn chưa (tránh tự viết lại logic bảo mật cơ bản).
3. **Đề xuất kế hoạch:** Liệt kê danh sách Contract, Interface, Event, Test cases (bao gồm cả Fuzz test & Negative test) và các file Frontend/Indexer cần tạo/sửa.
4. **Xác nhận:** Chờ user duyệt kế hoạch trước khi viết code.
