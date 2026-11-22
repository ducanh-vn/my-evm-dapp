# Chạy thử EscrowVault + giao diện trên Anvil local

Mục tiêu: tự đóng vai **Người mua / Người bán / Trọng tài** bằng nhiều ví MetaMask trên một blockchain chạy ngay trên máy, quan sát số dư thay đổi, và tua thời gian để thử các hạn (1 ngày giao hàng, 3 ngày khiếu nại, 14 ngày trọng tài).

- **Blockchain local:** Anvil (cài sẵn cùng Foundry). Không dùng Ganache: Ganache đã ngừng phát triển và không hỗ trợ EVM `cancun` mà contract dùng.
- **Contract:** `src/EscrowVault.sol` + USDC giả (`test/mocks/MockERC20.sol`, 6 decimals).
- **Giao diện:** `frontend/` (Next.js 15 + wagmi 2 + viem 2), hỗ trợ cả Anvil (31337) và Base Sepolia (84532).
- Không có private key nào trong code, script hay tài liệu.

---

## 1. Chuẩn bị (một lần)

Mở **Git Bash / UCRT64** tại thư mục dự án:
```bash
export PATH="/c/Users/Ying/.foundry/bin:$PATH"
cd frontend && npm install && cd ..
```

## 2. Chạy Anvil (terminal 1, để mở suốt buổi thử)

```bash
anvil
```
- Anvil in ra **10 tài khoản test**, mỗi tài khoản 10.000 ETH, kèm private key của chúng. Đây là ví test công khai, ai cũng biết key. **Chỉ dùng trên Anvil; tuyệt đối không gửi tiền thật vào các địa chỉ này.**
- Vai trò mặc định dùng trong tài liệu này:

| # | Vai trò | Ghi chú |
| :--- | :--- | :--- |
| 0 | Owner vault + ví nhận phí | Ví chạy script deploy |
| 1 | Người mua | Được mint 10.000 USDC giả |
| 2 | Người bán | Được mint 10.000 USDC giả |
| 3 | Trọng tài mặc định | Được mint 10.000 USDC giả |

## 3. Deploy vault + USDC giả (terminal 2)

```bash
forge script script/DeployLocalDemo.s.sol --rpc-url http://127.0.0.1:8545 \
  --unlocked --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --broadcast
```
- `--unlocked` dùng tài khoản #0 đã mở khóa sẵn của Anvil: **không cần nhập private key**.
- Script từ chối chạy nếu không phải chain 31337.
- Script ghi địa chỉ vào `frontend/src/constants/deployments/local.json`, giao diện tự đọc file này. File trong git chỉ chứa địa chỉ `0x0` (chưa deploy). Sau khi chạy script, **không commit** file này.
- Mỗi lần khởi động lại Anvil, chain bị xóa sạch: chạy lại bước 3.

## 4. Chạy giao diện (terminal 3)

```bash
cd frontend
npm run dev
```
Mở http://localhost:3000.

## 5. Cấu hình MetaMask

1. **Thêm mạng Anvil:** Settings → Networks → Add network manually:
   - Network name: `Anvil local`
   - RPC URL: `http://127.0.0.1:8545`
   - Chain ID: `31337`
   - Currency symbol: `ETH`
2. **Import ví test:** Add account → Import account → dán private key của tài khoản #1, #2, #3 (lấy từ màn hình terminal Anvil). Nên đặt tên ví theo vai trò: "Anvil Buyer", "Anvil Seller", "Anvil Arbiter".
3. **Thêm token USDC giả** (để thấy số dư trong MetaMask): Import tokens → dán địa chỉ `usdc` trong `local.json`.
4. Sau mỗi lần khởi động lại Anvil: MetaMask → Settings → Advanced → **Clear activity tab data** cho từng ví test. Nếu không, MetaMask giữ nonce cũ và giao dịch sẽ lỗi.

> Không import các ví test này vào ví MetaMask đang giữ tài sản thật nếu bạn không chắc. Có thể tạo một profile trình duyệt riêng cho việc thử.

## 6. Kịch bản thử

### A. Luồng thành công (ETH)
1. Chọn ví **Buyer** trong MetaMask → bấm **Kết nối MetaMask** → bấm **→ Anvil** nếu đang ở mạng khác.
2. Form **Tạo escrow**: chọn ETH, dán địa chỉ ví Seller, số tiền `1`, thời hạn `7` ngày, giữ trọng tài mặc định (#3) → **Nạp tiền ký quỹ** → ký trong MetaMask. Giao diện hiện lần lượt "chờ bạn ký" rồi "chờ block xác nhận", cuối cùng là link tới escrow vừa tạo.
3. Đổi MetaMask sang ví **Seller** → mở escrow → **Báo đã giao hàng**.
4. Đổi về ví **Buyer** → **Xác nhận & giải ngân cho người bán**.
5. Đổi sang ví **Seller** → khung **Số dư của bạn**: cột "Chờ rút trong vault" hiện `0.99` ETH (phí 1% được ghi cho ví #0). Bấm **Rút tiền** → số dư ví Seller tăng thêm 0,99 ETH.

### B. USDC (thử bước approve)
Như luồng A nhưng chọn **USDC**: nút đầu tiên là **Bước 1/2: approve**, ký xong bấm lại nút để **Nạp tiền ký quỹ**.

### C. Người bán tự giải ngân (cần tua thời gian)
Tạo escrow hạn 1 ngày → Seller báo đã giao → ở khung **⏩ Tua thời gian** bấm **+3 ngày** (và thêm nếu chưa qua hạn giao) → ví Seller thấy nút **Tự giải ngân**. Contract chỉ cho phép sau khi qua **cả** hạn khiếu nại lẫn hạn giao hàng.

### D. Tranh chấp và trọng tài
- Buyer bấm **Mở tranh chấp** → đổi sang ví **Arbiter** (#3) → kéo thanh tỷ lệ (ví dụ 60% cho người mua) → **Phân xử**.
- Thử quá hạn: mở tranh chấp → bấm **+14 ngày** hai lần → ví Buyer thấy **Lấy lại tiền (trọng tài quá 14 ngày)**.

### E. Người bán không giao hàng
Tạo escrow hạn 1 ngày → **+1 ngày** rồi **+1 giờ** → ví Buyer thấy **Lấy lại tiền (quá hạn giao hàng)**.

## 7. Kiểm tra bằng dòng lệnh (tùy chọn)

```bash
cast balance <ADDRESS> --rpc-url http://127.0.0.1:8545 --ether
cast call <ESCROW_VAULT> "getEscrow(uint256)((address,uint48,uint16,uint8,address,uint48,address,uint48,address,uint256))" 1 --rpc-url http://127.0.0.1:8545
```

## 8. Dùng giao diện với Base Sepolia

- Giao diện có sẵn địa chỉ vault Base Sepolia (`frontend/src/constants/addresses.ts`). Chỉ cần bấm **→ Base Sepolia** trong giao diện.
- RPC mặc định là RPC công khai của Base. Nếu muốn dùng RPC riêng, tạo `frontend/.env.local` với `NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL=...`. **Biến `NEXT_PUBLIC_*` bị lộ ra trình duyệt: không dùng URL có API key bí mật.**
- Trên Base Sepolia không có nút tua thời gian; các hạn chạy theo thời gian thật.

## 9. Sự cố thường gặp

| Hiện tượng | Cách xử lý |
| :--- | :--- |
| "Chưa có contract trên Anvil local" | Chạy bước 3 rồi tải lại trang |
| MetaMask báo nonce sai / giao dịch treo | Clear activity tab data (bước 5.4) |
| Nút không hiện như mong đợi | Kiểm tra đang dùng đúng ví (Buyer/Seller/Arbiter) và đúng thời điểm (xem các mốc trong trang chi tiết) |
| `forge`/`cast` không tìm thấy | `export PATH="/c/Users/Ying/.foundry/bin:$PATH"` |
| Sau khi sửa contract | `forge build` rồi `cd frontend && npm run sync-abi` để cập nhật ABI |
