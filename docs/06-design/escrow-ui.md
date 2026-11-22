# Thiết kế giao diện EscrowVault (MVP)

- **Mã nguồn:** `frontend/` (Next.js 15 App Router, wagmi 2, viem 2, TanStack Query 5)
- **Mạng hỗ trợ:** Base Sepolia (84532), Anvil local (31337)
- **Hướng dẫn chạy:** [chay-local-anvil.md](../04-van-hanh/chay-local-anvil.md)
- **Nghiệp vụ:** [business-flows.md](../03-san-pham/business-flows.md)

## 1. Bố cục

```
┌──────────────────────────────────────────────────────────────────┐
│ 🔒 EscrowVault        [Base Sepolia] [→ Anvil] 0xfc14…e053 [Ngắt] │
├──────────────────────────────────────────────────────────────────┤
│ (thông báo: chưa kết nối / sai mạng / chưa deploy local / pause)  │
├───────────────────────────────┬──────────────────────────────────┤
│ Tạo escrow (bạn là người mua) │ Escrow của tôi                   │
│ (•) ETH  ( ) USDC             │ [mã escrow____] [Mở]             │
│ Ví người bán  [0x…]           │ • Escrow #3  [Người bán]         │
│ Số tiền       [   ]           │ • Escrow #1  [Người mua]         │
│ Hạn giao (ngày) [7]           ├──────────────────────────────────┤
│ Trọng tài     [0x5A7E…]       │ Số dư của bạn                    │
│ Phí hiện hành: 1%             │ Tài sản | Trong ví | Chờ rút | ⬇ │
│ [Bước 1/2: approve] / [Nạp]   │ ETH     | 9 998.9  | 0.99 [Rút]  │
│ ⏳ chờ ký → ⛓️ chờ block → ✅  │ USDC    | 10 000   | 0    [Rút]  │
│                               │ Rút sang ví khác [0x…]           │
│                               ├──────────────────────────────────┤
│                               │ ⏩ Tua thời gian (chỉ Anvil)      │
│                               │ [+1 giờ][+1 ngày][+3 ngày][+14…] │
└───────────────────────────────┴──────────────────────────────────┘
```

Trang chi tiết `/escrow/[id]`: cột trái gồm bảng thông tin (số tiền, phí đã chốt, các bên, các mốc thời gian kèm đếm ngược theo **giờ chain**) và khung **Thao tác — bạn là …**; cột phải gồm Số dư và Tua thời gian.

## 2. Nút theo vai trò (khớp contract, xem `frontend/src/lib/escrowRules.ts`)

| Vai trò | Trạng thái / thời điểm | Nút |
| :--- | :--- | :--- |
| Người mua | Đã nạp tiền / Đã giao hàng | Xác nhận & giải ngân |
| Người mua | Đã nạp tiền, quá hạn giao | Lấy lại tiền (quá hạn giao hàng) |
| Người mua | Đang tranh chấp, quá 14 ngày | Lấy lại tiền (trọng tài quá hạn) |
| Người bán | Đã nạp tiền, trước hạn giao | Báo đã giao hàng |
| Người bán | Đã giao hàng, qua `max(hạn khiếu nại, hạn giao)` | Tự giải ngân |
| Người bán | Đã nạp / Đã giao / Tranh chấp | Hoàn toàn bộ tiền (có hộp xác nhận) |
| Người mua, Người bán | Đã nạp trước hạn giao; Đã giao trước `max(...)` | Mở tranh chấp |
| Trọng tài | Đang tranh chấp, trong 14 ngày | Thanh kéo tỷ lệ + Phân xử |

Khi không có nút nào, khung hiện lý do (ví dụ "Chờ người mua xác nhận…").

## 3. Trải nghiệm giao dịch (Wallet UX)

- Mỗi giao dịch có hai trạng thái tách biệt: **chờ ký trong MetaMask** (`isPending`) và **chờ block xác nhận** (`isConfirming`), sau đó là thành công kèm link Basescan (Base Sepolia).
- Lỗi được dịch sang tiếng Việt: người dùng từ chối ký (`UserRejectedRequestError`), và từng Custom Error của contract (ví dụ `FeeExceedsMax`, `DeadlineNotReached`).
- USDC: hai bước **approve**, rồi **Nạp tiền ký quỹ**.
- Tạo escrow luôn gửi `arbiter` tường minh và `maxFeeBps` = phí đang hiển thị (audit L-1).
- Tiền ra theo cơ chế pull payment: sau khi giải ngân hoặc hoàn tiền, số dư hiện ở cột "Chờ rút" và người nhận bấm **Rút tiền** (có tùy chọn rút sang ví khác, audit L-3).

## 4. Ranh giới On-chain / Off-chain

- Chưa có Indexer: danh sách "Escrow của tôi" đọc event `EscrowCreated` từ block deploy (chia đoạn 9.000 block cho RPC công khai). Khi dữ liệu lớn sẽ chuyển sang Ponder / The Graph.
- Mọi lệnh gọi contract nằm trong `src/hooks/`; component chỉ hiển thị (theo `code-standards.md`).
