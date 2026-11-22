# Đặc tả Quy trình Nghiệp vụ: EscrowVault

- **Tên tính năng / Quy trình:** EscrowVault — Ký quỹ thanh toán tự động P2P (ERC20 / ETH)
- **Trạng thái:** `Đã chốt` (phạm vi MVP)
- **Mạng triển khai dự kiến:** Base Sepolia (Chain ID 84532) → Base Mainnet (Chain ID 8453)
- **Tài liệu liên quan:** [Đặc tả kỹ thuật Smart Contract EscrowVault](../02-ky-thuat/escrow-vault-spec.md)

---

## 1. Mục tiêu & Tác nhân (Actors)

### 1.1. Mục tiêu nghiệp vụ
Người mua và người bán không tin nhau vẫn giao dịch được: người mua khóa tiền vào hợp đồng thông minh trước, người bán chỉ nhận tiền khi người mua xác nhận hoàn tất, khi hết thời gian khiếu nại, hoặc khi trọng tài phân xử nếu có tranh chấp. Không bên nào (kể cả quản trị viên) có thể tự ý lấy tiền đang ký quỹ.

### 1.2. Các vai trò tham gia
| Vai trò | Loại | Quyền chính |
| :--- | :--- | :--- |
| **Buyer** (Người mua) | Ví người dùng (EOA hoặc Smart Wallet) | Tạo và nạp escrow, xác nhận giải ngân, mở tranh chấp, nhận hoàn tiền khi quá hạn giao hàng |
| **Seller** (Người bán) | Ví người dùng | Đánh dấu đã giao hàng, chủ động hoàn tiền, mở tranh chấp, tự giải ngân khi hết thời gian khiếu nại |
| **Arbiter** (Trọng tài) | Ví do hai bên thống nhất, hoặc trọng tài mặc định của hệ thống | Chỉ phân xử escrow đang `Disputed` mà mình được chỉ định; quyết định tỷ lệ chia tiền giữa Buyer và Seller |
| **Admin Multisig** | Gnosis Safe, owner của contract (`Ownable2Step`) | Whitelist token, đặt phí (trần 5%), đặt ví nhận phí, đặt trọng tài mặc định, `pause`/`unpause`. **Không** có quyền rút tiền đang ký quỹ |
| **Indexer** | Off-chain (Ponder / The Graph) | Lắng nghe Event, lưu lịch sử, phục vụ tìm kiếm và phân trang cho Frontend |
| **Frontend dApp** | Next.js + Wagmi/Viem | Hiển thị, dẫn người dùng ký giao dịch, theo dõi `isPending` / `isConfirming` |

---

## 2. Thông số nghiệp vụ đã chốt (MVP)

| Thông số | Giá trị | Ghi chú |
| :--- | :--- | :--- |
| Phí giao thức mặc định | **1% (100 bps)** | Chỉ thu trên phần tiền giải ngân cho Seller |
| Trần phí (`MAX_FEE_BPS`) | **5% (500 bps)** | Hằng số trong code, Admin không vượt được |
| Thời điểm áp phí | Chốt theo phí hiện hành **tại lúc tạo escrow** | Admin đổi phí không ảnh hưởng escrow đang mở |
| Hoàn tiền 100% cho Buyer | **Không thu phí** | Áp dụng cho hủy, hoàn tiền và phán quyết 100% cho Buyer |
| Thời hạn giao hàng | Buyer tự đặt, **tối thiểu 1 giờ, tối đa 90 ngày** | Tính từ lúc tạo escrow |
| Thời gian khiếu nại (`DISPUTE_WINDOW`) | **3 ngày** sau khi Seller báo đã giao hàng, **nhưng không kết thúc trước `deliveryDeadline`** | Mốc kết thúc = `max(disputeDeadline, deliveryDeadline)`. Hết mốc mà không khiếu nại thì Seller tự giải ngân được (sửa theo audit M-1) |
| Trọng tài | Chỉ định lúc tạo escrow; để trống thì dùng **trọng tài mặc định của hệ thống** | Địa chỉ trọng tài được lưu cố định vào escrow |
| Thời hạn phân xử (`ARBITRATION_TIMEOUT`) | **14 ngày** kể từ lúc mở tranh chấp | Quá hạn mà trọng tài chưa phán quyết: Buyer gọi `claimTimeoutRefund` lấy lại 100% tiền gốc, không phí |
| Tỷ lệ phân xử | Trọng tài chọn phần trăm cho Buyer từ 0% đến 100% (đơn vị bps) | Phần còn lại cho Seller, trừ phí trên phần của Seller |
| Tài sản hỗ trợ | **ETH** và **ERC-20 trong whitelist** (USDC, USDT trên Base) | Không hỗ trợ token fee-on-transfer hoặc rebasing |
| Kiến trúc | **Immutable**, không dùng Proxy | Bản mới deploy contract mới; contract cũ vẫn cho rút tiền bình thường |

---

## 3. Vòng đời Escrow (State Machine)

| Trạng thái | Ý nghĩa |
| :--- | :--- |
| `Funded` | Buyer đã tạo escrow và tiền đã nằm trong contract |
| `Delivered` | Seller báo đã giao hàng; Buyer được khiếu nại tới `max(disputeDeadline, deliveryDeadline)` |
| `Disputed` | Một bên mở tranh chấp; tiền bị khóa chờ Arbiter |
| `Released` | Tiền đã ghi có cho Seller (kết thúc) |
| `Refunded` | Toàn bộ tiền đã ghi có lại cho Buyer (kết thúc) |
| `Resolved` | Arbiter đã chia tiền theo phán quyết (kết thúc) |

### Bảng chuyển trạng thái
| Từ | Sang | Ai gọi | Điều kiện |
| :--- | :--- | :--- | :--- |
| — | `Funded` | Buyer | Token là ETH hoặc nằm trong whitelist, `amount > 0`, Seller hợp lệ và khác Buyer, thời hạn trong khoảng 1 giờ – 90 ngày, Arbiter khác Buyer/Seller, contract không `paused` |
| `Funded` | `Delivered` | Seller | Chưa qua `deliveryDeadline` |
| `Funded` / `Delivered` | `Released` | Buyer | Bất kỳ lúc nào khi chưa có tranh chấp |
| `Delivered` | `Released` | Seller | Đã qua **cả** `disputeDeadline` (3 ngày sau khi báo giao) **và** `deliveryDeadline` mà không có tranh chấp |
| `Funded` | `Refunded` | Buyer | Đã qua `deliveryDeadline` mà Seller chưa báo giao hàng |
| `Funded` / `Delivered` / `Disputed` | `Refunded` | Seller | Seller tự nguyện hoàn toàn bộ tiền |
| `Funded` | `Disputed` | Buyer hoặc Seller | Chưa qua `deliveryDeadline` |
| `Delivered` | `Disputed` | Buyer hoặc Seller | Chưa qua `max(disputeDeadline, deliveryDeadline)` |
| `Disputed` | `Resolved` | Arbiter của escrow | Chưa qua `arbitrationDeadline` (14 ngày từ lúc mở tranh chấp); tỷ lệ cho Buyer trong khoảng 0 – 10.000 bps |
| `Disputed` | `Refunded` | Buyer (`claimTimeoutRefund`) | Đã qua `arbitrationDeadline` mà Arbiter chưa phán quyết |

Mọi trạng thái kết thúc (`Released`, `Refunded`, `Resolved`) là bất biến: không hàm nào được thay đổi escrow sau đó.

Escrow ở `Disputed` kết thúc khi Arbiter phân xử trong 14 ngày, khi Seller tự nguyện hoàn tiền 100%, hoặc khi Buyer gọi `claimTimeoutRefund` sau 14 ngày. Tiền không bao giờ bị kẹt vĩnh viễn.

```
            markDelivered      (qua max(disputeDeadline, deliveryDeadline), Seller gọi)
 Funded ─────────────────▶ Delivered ─────────────────────────▶ Released
   │  ╲ release (Buyer)        │  ╲ release (Buyer) ───────────▶ Released
   │   ╲                       │
   │    refund (Seller bất kỳ lúc nào / Buyer khi quá deliveryDeadline) ─▶ Refunded
   │                           │
   └──── raiseDispute ─────────┴──▶ Disputed ── resolveDispute ─▶ Resolved
                                       └── refund (Seller) / claimTimeoutRefund (Buyer, sau 14 ngày) ─▶ Refunded
```

---

## 4. Luồng xử lý On-chain & Off-chain

### 4.1. Luồng A — Tạo và nạp escrow
1. **Frontend:** Buyer nhập địa chỉ Seller, tài sản (ETH hoặc token trong whitelist), số tiền, thời hạn giao hàng (1 giờ – 90 ngày) và địa chỉ trọng tài đã thống nhất với Seller (bỏ trống nếu dùng trọng tài hệ thống). Frontend hiển thị phí 1% sẽ trừ vào tiền Seller nhận.
2. **Frontend:** Với ERC20, Buyer ký `approve` cho contract EscrowVault. Trạng thái tách riêng: chờ ký ví (`isPending`) và chờ xác nhận block (`isConfirming`).
3. **Smart Contract:** `createEscrow(...)` kiểm tra điều kiện (Checks) → lưu escrow, chốt phí và trọng tài, trạng thái `Funded` (Effects) → nhận token qua `safeTransferFrom` hoặc kiểm tra `msg.value == amount` với ETH (Interactions). Phát `EscrowCreated`.
4. **Indexer:** Bắt `EscrowCreated`, tạo bản ghi escrow, gắn với Buyer, Seller và Arbiter để mỗi bên thấy trong danh sách của mình.
5. **Frontend:** Hiển thị mã escrow và link chia sẻ cho Seller. Seller kiểm tra thông tin (số tiền, thời hạn, trọng tài); nếu không đồng ý, Seller dùng `refund` để trả lại tiền cho Buyer.

### 4.2. Luồng B — Giao hàng và giải ngân (Happy Path)
1. **Off-chain:** Seller giao hàng hoặc dịch vụ ngoài chuỗi.
2. **Smart Contract:** Seller gọi `markDelivered(escrowId)` → trạng thái `Delivered`, ghi `disputeDeadline = thời điểm hiện tại + 3 ngày`. Phát `EscrowDelivered`. Buyer được khiếu nại tới `max(disputeDeadline, deliveryDeadline)`.
3. **Smart Contract:** Buyer gọi `release(escrowId)` → trạng thái `Released`, ghi có `amount − phí` cho Seller và phí cho ví nhận phí. Phát `EscrowReleased`.
4. **Tự động giải ngân:** Nếu Buyer không khiếu nại cho tới khi qua **cả** `disputeDeadline` **và** `deliveryDeadline`, Seller gọi `release(escrowId)` để tự nhận tiền, tránh bị kẹt vốn.
   - Lý do (audit M-1): nếu chỉ chờ 3 ngày, Seller có thể báo "đã giao" ngay lúc tạo escrow khi chưa giao gì, và tự rút tiền sau 3 ngày trong khi Buyer vẫn nghĩ còn nhiều ngày nữa mới tới hạn giao hàng.
   - Ví dụ: hạn giao 30 ngày, Seller báo giao ở ngày 2 → Buyer khiếu nại được tới ngày 30, Seller tự rút từ ngày 30 + 1 giây. Seller báo giao ở ngày 29 → mốc là ngày 32.
   - Buyer vẫn `release` sớm được bất cứ lúc nào nếu hài lòng.
5. **Indexer / Frontend:** Cập nhật trạng thái, hiển thị số tiền Seller có thể rút.

### 4.3. Luồng C — Hoàn tiền (không thu phí)
1. **Seller tự hoàn:** Seller gọi `refund(escrowId)` khi không thể giao hàng, không đồng ý điều khoản, hoặc chấp nhận thua khi đang tranh chấp → `Refunded`, ghi có toàn bộ `amount` cho Buyer.
2. **Quá hạn giao hàng:** Escrow còn `Funded` và đã qua `deliveryDeadline` → Buyer gọi `refund(escrowId)`.
3. Phát `EscrowRefunded`.

### 4.4. Luồng D — Tranh chấp và phân xử
1. **Smart Contract:** Buyer hoặc Seller gọi `raiseDispute(escrowId)` trong thời hạn cho phép → `Disputed`, ghi `arbitrationDeadline = thời điểm hiện tại + 14 ngày`. Phát `DisputeRaised`.
2. **Off-chain:** Hai bên gửi bằng chứng cho Arbiter. Bằng chứng (ảnh, chat, vận đơn) lưu off-chain (IPFS/DB).
3. **Smart Contract:** Arbiter của escrow gọi `resolveDispute(escrowId, buyerBps)`:
   - Phần Buyer = `amount × buyerBps / 10.000` (không thu phí).
   - Phần Seller = `amount − phần Buyer`; phí = phần Seller × phí đã chốt.
   - Ví dụ: 100% Buyer thì không có phí; 100% Seller thì giống giải ngân thường; 60/40 thì phí chỉ tính trên 40% của Seller.
4. Trạng thái `Resolved`, phát `DisputeResolved`.
5. **Trọng tài quá hạn:** Nếu qua `arbitrationDeadline` mà Arbiter chưa phán quyết, Arbiter không còn gọi được `resolveDispute`; Buyer gọi `claimTimeoutRefund(escrowId)` → `Refunded`, ghi có 100% tiền gốc cho Buyer, không thu phí. Phát `EscrowRefunded`.
6. **Frontend / Indexer:** Hiển thị đếm ngược 14 ngày cho cả ba bên; khi quá hạn, hiện nút "Rút lại tiền" cho Buyer.

#### Quyết định: xử lý trọng tài mất liên lạc
Hai phương án đã được cân nhắc cho trường hợp quá `ARBITRATION_TIMEOUT` (14 ngày kể từ lúc mở tranh chấp) mà trọng tài chưa phán quyết:

| Phương án | Kết luận | Lý do |
| :--- | :--- | :--- |
| **A.** Admin Multisig thay địa chỉ trọng tài của escrow | **Không áp dụng** ở MVP | Admin chọn được người chia tiền nghĩa là Admin gián tiếp kiểm soát tiền ký quỹ, trái nguyên tắc "Admin không chạm được tiền của escrow". Ngoài ra trọng tài mới là người hai bên chưa đồng ý từ đầu, và vẫn cần thêm một mốc hết hạn mới (lại có thể bị kẹt) |
| **B.** Buyer gọi `claimTimeoutRefund` lấy lại 100% tiền gốc | **Áp dụng** | Không cần bên thứ ba, không cần tin Admin, luôn kết thúc được escrow; không thu phí |

- Admin Multisig chỉ đổi được `defaultArbiter` cho **escrow mới**; không có hàm thay trọng tài của escrow đã tạo.
- `claimTimeoutRefund` không bị chặn bởi `pause`.
- Từ lúc mở tranh chấp tới khi Buyer gọi `claimTimeoutRefund`, Seller vẫn có thể tự nguyện `refund`.

### 4.5. Luồng E — Rút tiền (Pull Payment)
Kết quả của các luồng B, C, D **không chuyển tiền trực tiếp** mà ghi có vào số dư rút được của từng người theo từng tài sản. Người nhận tự gọi `withdraw(token)`:
- Checks: số dư > 0 → Effects: đặt số dư về 0 → Interactions: `safeTransfer`, hoặc `call{value: ...}` với ETH và kiểm tra kết quả.
- Phát `Withdrawn`.
- Lý do: tránh một ví nhận lỗi (contract revert khi nhận ETH, ví bị USDC/USDT blacklist) làm kẹt việc kết thúc escrow, và giảm rủi ro reentrancy.
- `withdraw` **không bao giờ bị chặn** bởi `pause`.

### 4.6. Luồng F — Quản trị
| Hành động | Ai | Event |
| :--- | :--- | :--- |
| Thêm/bỏ token trong whitelist | Admin Multisig | `TokenAllowlistUpdated` |
| Đặt phí (0 – 500 bps) | Admin Multisig | `FeeUpdated` |
| Đặt ví nhận phí | Admin Multisig | `FeeRecipientUpdated` |
| Đặt trọng tài mặc định của hệ thống | Admin Multisig | `DefaultArbiterUpdated` |
| `pause` / `unpause` | Admin Multisig | `Paused` / `Unpaused` |
| Chuyển quyền owner (2 bước) | Admin Multisig | `OwnershipTransferStarted` / `OwnershipTransferred` |

- Bỏ token khỏi whitelist chỉ chặn escrow mới; escrow cũ dùng token đó vẫn hoàn tất và rút bình thường.
- Đổi trọng tài mặc định không ảnh hưởng escrow đã tạo (trọng tài được lưu cố định trong escrow).
- Khi `paused`: **chỉ chặn tạo escrow mới**. Các thao tác `markDelivered`, `release`, `refund`, `raiseDispute`, `resolveDispute`, `claimTimeoutRefund`, `withdraw` vẫn hoạt động để người dùng không bị kẹt tiền.

### 4.7. Luồng G — Nâng cấp phiên bản
Contract không có Proxy. Khi có phiên bản mới: deploy contract mới, Frontend chuyển sang contract mới cho escrow mới, Admin `pause` contract cũ để chặn tạo mới. Escrow trên contract cũ tiếp tục hoàn tất và rút tiền như bình thường.

---

## 5. Ranh giới On-chain vs Off-chain

| On-chain (contract) | Off-chain (Indexer / DB / IPFS) |
| :--- | :--- |
| Buyer, Seller, Arbiter, tài sản, số tiền, phí đã chốt, trạng thái, các deadline | Mô tả đơn hàng, ảnh, file đính kèm, chat, bằng chứng tranh chấp |
| Số dư rút được của từng người theo từng tài sản | Lịch sử giao dịch, phân trang, tìm kiếm, lọc theo trạng thái |
| Event cho mọi thay đổi trạng thái (tối đa 3 `indexed`) | Thống kê, uy tín người bán |

Contract **không** có hàm `view` trả về danh sách escrow của một người dùng; Frontend lấy danh sách qua Indexer.

---

## 6. Yêu cầu bảo mật nghiệp vụ

- Với mỗi tài sản, tổng tiền đang ký quỹ + tổng số dư rút được luôn ≤ số dư thực của contract (invariant).
- Admin không có hàm nào chuyển được tiền của escrow hoặc tiền chờ rút của người dùng.
- Arbiter chỉ chia được tiền của escrow mình được chỉ định, chỉ giữa Buyer và Seller; không chuyển được cho ví thứ ba.
- Một escrow chỉ được kết thúc một lần (chặn double release / double refund).
- Chỉ whitelist token chuẩn; contract vẫn kiểm tra số tiền thực nhận bằng `amount` như lớp phòng thủ thứ hai.
- Tính phí và chia tỷ lệ bằng `Math.mulDiv`; phí không thể vượt 500 bps.

---

## 7. Tiêu chí nghiệm thu (Acceptance Criteria)

### Frontend & trải nghiệm
- [ ] Giao dịch hiển thị đúng ước tính phí gas và trạng thái chờ xác nhận.
- [ ] Tách rõ trạng thái chờ ký ví (`isPending`) và chờ xác nhận block (`isConfirming`); xử lý `UserRejectedRequestError` và revert có Custom Error dễ hiểu.
- [ ] Cảnh báo khi người dùng đang ở sai mạng (không phải Base Sepolia / Base).
- [ ] Hiển thị phí 1% và số tiền Seller thực nhận trước khi Buyer ký.
- [ ] Hiển thị đếm ngược `deliveryDeadline` và mốc hết khiếu nại `max(disputeDeadline, deliveryDeadline)`.
- [ ] Gửi thông báo cho Buyer ngay khi có `EscrowDelivered` (qua Indexer).

### Indexer
- [ ] Indexer đồng bộ dữ liệu chính xác sau khi giao dịch đạt finality.
- [ ] Mỗi Event cập nhật đúng trạng thái escrow và số dư chờ rút trong DB.

### Smart Contract
- [ ] Toàn bộ test plan trong [đặc tả kỹ thuật](../02-ky-thuat/escrow-vault-spec.md#4-kịch-bản-kiểm-thử-bắt-buộc-test-plan) pass.

---

## 8. Rủi ro đã chấp nhận ở MVP
- **Trọng tài không phản hồi:** đã xử lý bằng `ARBITRATION_TIMEOUT` 14 ngày; quá hạn thì Buyer lấy lại tiền gốc. Hệ quả: nếu Arbiter cố tình im lặng, kết quả nghiêng về Buyer, nên Seller cần đồng ý chọn trọng tài tin cậy ngay lúc tạo escrow (nếu không đồng ý, Seller dùng `refund` trước khi giao hàng).
- **Token có quyền đóng băng (USDC, USDT):** nhà phát hành có thể blacklist contract hoặc ví người dùng; nằm ngoài khả năng kiểm soát của giao thức.
- **Không nâng cấp được:** lỗi phát hiện sau deploy chỉ xử lý bằng `pause` (chặn tạo mới) và deploy phiên bản mới.
