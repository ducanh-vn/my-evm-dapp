# Báo cáo Audit nội bộ: EscrowVault

- **Phạm vi:** `src/EscrowVault.sol`, `src/interfaces/IEscrowVault.sol`
- **Commit được audit:** `1033f43` (nhánh `feat/escrow-vault-mvp`)
- **Đối chiếu với:** [escrow-vault-spec.md](./escrow-vault-spec.md), [business-flows.md](../03-san-pham/business-flows.md), `.claude/rules/smart-contract-security.md`
- **Ngày:** 2026-11-22
- **Người thực hiện:** Claude (vai trò Lead Smart Contract Security Auditor theo `.claude/agents/security-auditor.md`)
- **Loại audit:** Rà soát nội bộ trước audit chính thức. **Không thay thế** audit độc lập của bên thứ ba trước khi lên Mainnet.
- **Trạng thái:** M-1 **đã sửa** (cả hai chiều), L-1 **đã sửa** (phần phí), L-3 **đã sửa**, L-5 **đã sửa**. Các mục L-2, L-4, L-6, G-1, G-2, G-3 chưa sửa.

---

## 1. Tóm tắt

| Mức độ | Số lượng |
| :--- | :--- |
| `[CRITICAL]` | 0 |
| `[HIGH]` | 0 |
| `[MEDIUM]` | 1 (đã sửa) |
| `[LOW/GAS]` | 9 (6 Low / Info, 3 Gas) — L-1, L-3, L-5 đã sửa |

Không tìm thấy lỗ hổng cho phép đánh cắp tiền, rút tiền hai lần, khóa tiền vĩnh viễn, hay leo thang quyền admin. Phát hiện quan trọng nhất (M-1) là **rủi ro logic nghiệp vụ** về mốc thời gian, không phải lỗi code: contract chạy đúng đặc tả, nhưng đặc tả hiện cho phép Seller bắt đầu 3 ngày khiếu nại trước khi giao hàng thật.

### Công cụ đã chạy
| Công cụ | Kết quả |
| :--- | :--- |
| `forge build` (solc 0.8.28) | Biên dịch OK; 8 cảnh báo lint có chủ đích (7 × `block-timestamp`, 1 × `revert` trong vòng lặp constructor) |
| `forge test` | 88/88 test pass (unit, 4 fuzz × 1.000 lượt, 7 invariant × 256 lượt × 50 lệnh) |
| `forge test --gas-report` | Xem mục 4 |
| `forge inspect EscrowVault storageLayout` | Struct `Escrow` = 5 slot; không có xung đột storage (không Proxy) |
| Slither | **Không chạy** — máy chưa cài `slither`. Khuyến nghị chạy trước audit chính thức |
| PoC | Viết test tạm cho M-1, L-1 và đã xóa sau khi chạy (đều PASS, tức là kịch bản xảy ra được) |

### Checklist đã rà soát
| Hạng mục | Kết quả |
| :--- | :--- |
| Reentrancy / CEI | Đạt. Mọi hàm chuyển tiền có `nonReentrant`; `withdraw` đặt số dư về 0 trước khi chuyển; `createEscrow` ghi state trước `safeTransferFrom`. Các hàm không có guard (`markDelivered`, `raiseDispute`) không chuyển tiền. Reentrancy chéo hàm từ `receive()` đã có test |
| Giá trị trả về của external call | Đạt. ETH: kiểm tra `ok`; ERC-20: `SafeERC20` (chịu được USDT không trả `bool`) |
| Access control | Đạt. Mọi hàm admin có `onlyOwner`; `Ownable2Step`; `renounceOwnership` bị vô hiệu; không dùng `tx.origin`; không Proxy/`initialize` |
| Quyền admin với tiền người dùng | Đạt. Không có hàm nào cho owner rút tiền, sửa `withdrawable`, `amount` hay `arbiter` của escrow đã tạo. `pause` không chặn rút tiền (có test) |
| Số học / làm tròn | Đạt. `Math.mulDiv`; phần dư làm tròn thuộc Seller; tổng ghi có luôn bằng `amount` (fuzz). Phí bị làm tròn về 0 với số tiền rất nhỏ (L-4, chấp nhận được) |
| Inflation / tỷ giá | Không áp dụng (không có share/LP) |
| DoS / vòng lặp | Đạt. Chỉ có một vòng lặp trong constructor. Pull payment cô lập ví nhận lỗi (ETH bị từ chối, USDC bị blacklist) |
| Phụ thuộc `balance` | Đạt. Logic không dựa vào `address(this).balance`; force-feed ETH không ảnh hưởng. `balanceOf` chỉ dùng để đo chênh lệch khi nhận token |
| Chuyển trạng thái / ranh giới thời gian | Đạt. Các mốc dùng `≤` và `>` bổ sung nhau, không có khoảng hai hành động xung đột cùng hợp lệ (`resolveDispute` ≤ deadline < `claimTimeoutRefund`). Trạng thái kết thúc không đổi được (invariant) |
| Event | Đạt. Mọi thay đổi trạng thái đều phát event; tối đa 3 `indexed` |
| Custom Error / NatSpec | Đạt. 18/18 error trong spec đều được dùng; NatSpec đủ trên interface |

---

## 2. Chi tiết phát hiện

### [MEDIUM] M-1: Seller có thể bắt đầu 3 ngày khiếu nại trước khi giao hàng thật; ngược lại Buyer có thể đặt thời hạn giao hàng quá ngắn

> **Trạng thái: ĐÃ SỬA (phần chính)** trên nhánh `feat/escrow-vault-mvp`. Chủ dự án chọn phương án 1, "Chờ cả hai hạn":
> - Seller tự `release` chỉ khi `now > max(disputeDeadline, deliveryDeadline)`.
> - Buyer `raiseDispute` ở `Delivered` khi `now ≤ max(disputeDeadline, deliveryDeadline)` (cùng một mốc, không có khoảng trống hay chồng lấn).
> - Buyer `release` không đổi.
> - Code: hàm nội bộ `_disputeWindowEnd` trong `src/EscrowVault.sol`, dùng ở `release` và `raiseDispute`.
> - Test mới: Seller revert khi qua `disputeDeadline` nhưng chưa qua `deliveryDeadline`; trường hợp giao muộn; biên đúng mốc / mốc + 1; tái hiện kịch bản M-1 cũ (giờ revert); fuzz "đúng một trong hai hành động hợp lệ"; invariant số 8 (`invariant_NoEarlySellerRelease`).
> - **Chiều ngược lại — ĐÃ XỬ LÝ** theo quyết định của chủ dự án:
>   - Thời hạn giao hàng tối thiểu nâng từ 1 giờ lên **1 ngày** (`MIN_DELIVERY_DURATION = 1 days`, đổi tên từ `MIN_DELIVERY_PERIOD`; `MAX_DELIVERY_PERIOD` đổi tên tương ứng thành `MAX_DELIVERY_DURATION`, vẫn 90 ngày). Seller luôn có ít nhất 1 ngày để `markDelivered`.
>   - Quy tắc được ghi rõ và có test: Buyer chỉ `refund` khi `Funded` (Seller chưa từng `markDelivered`) và `now > deliveryDeadline`. Khi đã `Delivered`, Buyer chỉ còn `release`/`raiseDispute` (fuzz test mọi thời điểm). Hành vi này đã có từ bản đầu; lần này bổ sung test tường minh.
>   - Rủi ro còn lại (vận hành, không phải contract): Seller phải `markDelivered` **trước** khi gửi hàng; Frontend cần nhắc rõ.

**Vị trí:** `markDelivered` (dòng 166–179), `release` nhánh Seller (dòng 188–190), `refund` nhánh Buyer (dòng 215–217).

**Mô tả:** `markDelivered` chỉ là lời tự khai của Seller, gọi được ngay sau khi tạo escrow. Nó đặt `disputeDeadline = now + 3 ngày` bất kể `deliveryDeadline` Buyer đã đặt. Nếu Buyer không theo dõi trong 3 ngày đó, Seller tự giải ngân được. Contract không có cơ chế thông báo; Buyer chỉ biết nếu Frontend hoặc Indexer báo.

Chiều ngược lại: Buyer tự chọn `deliveryPeriod` (tối thiểu 1 giờ). Nếu Seller giao hàng off-chain trước khi gọi `markDelivered` (đúng như luồng 4.2 mô tả), Buyer chỉ cần chờ qua hạn rồi gọi `refund`.

Contract làm đúng spec; đây là rủi ro của **thiết kế nghiệp vụ**. Xếp MEDIUM vì dẫn tới mất tiền hoặc mất hàng thật mà nạn nhân không làm sai gì, chỉ không theo dõi kịp.

**Kịch bản tấn công (PoC đã chạy, PASS):**
```solidity
// Buyer đặt hạn giao hàng 30 ngày
vm.prank(buyer);
uint256 id = vault.createEscrow(seller, address(usdc), AMOUNT, 30 days, arbiter);
// Seller khai "đã giao" ngay lập tức, chưa giao gì
vm.prank(seller);
vault.markDelivered(id);
// Buyer không để ý trong 3 ngày (vẫn nghĩ còn 27 ngày)
vm.warp(block.timestamp + 3 days + 1);
vm.prank(seller);
vault.release(id);           // Seller lấy 99% tiền
```
```solidity
// Chiều ngược: Buyer đặt hạn 1 giờ, Seller đã gửi hàng nhưng chưa kịp markDelivered
vm.prank(buyer);
uint256 id = vault.createEscrow(seller, address(usdc), AMOUNT, 1 hours, arbiter);
vm.warp(block.timestamp + 1 hours + 1);
vm.prank(buyer);
vault.refund(id);            // Buyer lấy lại 100%, vẫn giữ hàng
```

**Đề xuất khắc phục (cần chủ dự án chọn, sẽ phải sửa spec):**
1. **(Khuyến nghị)** Seller chỉ tự giải ngân khi đã qua **cả** `disputeDeadline` **và** `deliveryDeadline`:
   ```solidity
   uint256 unlockAt = Math.max(e.disputeDeadline, e.deliveryDeadline);
   if (block.timestamp <= unlockAt) revert DeadlineNotReached();
   ```
   Seller trung thực không bị thiệt nhiều: Buyer vẫn `release` sớm được. Đồng thời Buyer giữ quyền mở tranh chấp tới `max(disputeDeadline, deliveryDeadline)` (sửa điều kiện tương ứng trong `raiseDispute`).
2. Hoặc thêm bước Buyer xác nhận đã nhận hàng (`confirmReceived`), và chỉ bắt đầu 3 ngày khiếu nại từ đó. Cách này phức tạp hơn và có thể làm kẹt Seller nếu Buyer im lặng.
3. Chiều ngược: Frontend cảnh báo Seller **không giao hàng trước khi gọi `markDelivered`**, và hiển thị rõ `deliveryDeadline`. Có thể nâng `MIN_DELIVERY_PERIOD` (ví dụ 24 giờ).
4. Bắt buộc với mọi phương án: Indexer gửi thông báo (email, push, Telegram) cho Buyer ngay khi có `EscrowDelivered`.

**Test cần thêm sau khi sửa:** Seller `release` thất bại khi `disputeDeadline < now ≤ deliveryDeadline`; fuzz các mốc `markDelivered`.

---

### [LOW] L-1: Thay đổi tham số admin có thể "chen ngang" giao dịch `createEscrow` đang chờ

> **Trạng thái: ĐÃ SỬA (phần phí).** `createEscrow` có thêm tham số `uint16 maxFeeBps`; revert `FeeExceedsMax(current, max)` nếu `feeBps > maxFeeBps`, trước khi ghi state hay kéo tiền. Test: biên bằng nhau, nhỏ hơn 1, phí 0, ETH, và kịch bản admin đổi 1% → 5% ngay trước giao dịch của Buyer. Phần trọng tài mặc định **không** thêm tham số on-chain: Frontend phải truyền `arbiter` tường minh (đã ghi vào business-flows luồng A).

**Vị trí:** `createEscrow` dòng 123, 136; `setFeeBps`, `setDefaultArbiter`.

**Mô tả:** `feeBps` và `defaultArbiter` được đọc tại thời điểm giao dịch được đưa vào block. Nếu Multisig đổi phí hoặc trọng tài mặc định trong lúc giao dịch của Buyer đang chờ, escrow bị chốt giá trị mới: phí lên tới 5% thay vì 1% đã hiển thị, hoặc một trọng tài khác. Trên Base, sequencer không có mempool công khai, nên rủi ro chủ yếu là trùng thời điểm ngẫu nhiên hoặc lạm quyền tập trung, không phải bot front-run.

**PoC (đã chạy, PASS):** owner gọi `setFeeBps(500)` → Buyer `createEscrow` với UI vẫn hiện 1% → `getEscrow(id).feeBps == 500`.

**Khắc phục:**
- Thêm tham số bảo vệ kiểu "slippage" `uint16 maxFeeBps` vào `createEscrow`, revert nếu `feeBps > maxFeeBps`.
- Frontend luôn truyền `arbiter` tường minh (đọc `defaultArbiter` rồi truyền vào), không truyền `address(0)`. Hoặc thêm `expectedArbiter`.
- Vận hành: thay đổi phí hay trọng tài mặc định nên công bố trước (có thể dùng Timelock trên Safe).

---

### [LOW] L-2: Trọng tài do Buyer tự chọn; Seller phải tự kiểm tra trước khi giao hàng

**Vị trí:** `createEscrow` dòng 123–124.

**Mô tả:** Buyer có thể đặt `arbiter` là ví phụ của chính mình, hoặc một địa chỉ không bao giờ phản hồi. Khi tranh chấp:
- trọng tài là ví phụ của Buyer → `resolveDispute(id, 10_000)`;
- trọng tài không phản hồi → sau 14 ngày Buyer `claimTimeoutRefund`.

Seller mất hàng nếu đã giao. Seller **có** cơ hội từ chối: thông tin trọng tài công khai on-chain, và `markDelivered` là hành động Seller tự ký. Rủi ro này cũng đã ghi ở mục 8 của business-flows. Xếp LOW vì cần Seller bất cẩn.

**Khắc phục:**
- Frontend: cảnh báo nổi bật khi `arbiter != defaultArbiter`; hiển thị trọng tài trên màn hình `markDelivered` và yêu cầu Seller xác nhận.
- Tùy chọn on-chain: danh sách trọng tài được duyệt (`isArbiterApproved`), hoặc Seller ký chấp nhận (`acceptEscrow`) trước khi `markDelivered`.

---

### [LOW] L-3: Không có `withdrawTo`; ví không nhận được ETH hoặc bị blacklist USDC sẽ mất quyền rút vĩnh viễn

> **Trạng thái: ĐÃ SỬA.** Thêm `withdrawTo(address token, address to)` (`nonReentrant`, không bị `pause`, revert `ZeroAddress` khi `to = 0`), dùng chung logic `_withdraw` với `withdraw`. Event đổi thành `Withdrawn(address indexed user, address indexed token, address indexed to, uint256 amount)` — **đổi ABI/topic, Indexer phải dùng chữ ký mới**. Test: ETH/ERC-20, `to = 0`, số dư 0, ví nhận từ chối ETH, cứu tiền cho Seller là contract không nhận ETH, cứu tiền cho Seller bị blacklist (mock `BlacklistERC20`), khi `paused`, không rút được của người khác, reentrancy qua `withdrawTo`.

**Vị trí:** `withdraw` dòng 281–299.

**Mô tả:** Tiền luôn được chuyển về `msg.sender`. Contract không nhận ETH (ví dụ một số smart wallet cũ hoặc contract tùy biến), hoặc địa chỉ bị Circle/Tether blacklist, sẽ không bao giờ rút được. Số dư không mất khỏi contract, nhưng bị khóa với chính chủ. Pull payment đã cô lập rủi ro này để không ảnh hưởng người khác (đúng thiết kế).

**PoC:** đã có test `test_RevertWhen_EthRecipientRejects_BalanceKept`.

**Khắc phục:** thêm `withdrawTo(address token, address to)`. Hàm này trừ số dư của `msg.sender`, chuyển tới `to`, revert khi `to == address(0)`, gắn `nonReentrant`, và phát `Withdrawn(msg.sender, token, amount)` (hoặc event mới có thêm `to`).

---

### [LOW] L-4: Phí làm tròn về 0 với số tiền rất nhỏ

**Vị trí:** `release` dòng 198, `resolveDispute` dòng 261.

**Mô tả:** Với phí 1%, `amount < 100` đơn vị nhỏ nhất (USDC: < 0,0001 USDC) thì `fee = 0`. Chia nhỏ escrow để né phí không có lợi vì gas trên Base lớn hơn nhiều so với phí được né. Chỉ để ghi nhận.

**Khắc phục:** không cần. Nếu muốn, đặt số tiền tối thiểu cho mỗi token.

---

### [LOW] L-5: `pragma` còn dùng `^0.8.20`

> **Trạng thái: ĐÃ SỬA.** Mọi file `.sol` của dự án (`src/`, `test/`, `script/`; không gồm `lib/`) đều dùng `pragma solidity 0.8.28;`, khớp `solc_version = "0.8.28"` trong `foundry.toml`.

**Vị trí:** `src/EscrowVault.sol:2`, `src/interfaces/IEscrowVault.sol:2`.

**Mô tả:** Rule bảo mật yêu cầu ghim phiên bản cố định khi chuẩn bị audit. `foundry.toml` đã ghim `solc = 0.8.28`, nhưng người verify hoặc build bằng công cụ khác có thể dùng phiên bản khác.

**Khắc phục:** đổi thành `pragma solidity 0.8.28;` trong `src/` trước audit chính thức (test có thể giữ `^`).

---

### [LOW / INFO] L-6: Lệch nhỏ so với spec

| Mục | Spec | Code | Đề xuất |
| :--- | :--- | :--- | :--- |
| Constructor với `initialOwner = 0` | Revert `ZeroAddress` | Revert `OwnableInvalidOwner(address(0))` của OpenZeppelin (constructor cha chạy trước) | Cập nhật spec; hành vi an toàn như nhau |
| `refund` / `claimTimeoutRefund` | Cùng phát `EscrowRefunded` | Đúng như spec | Indexer phân biệt bằng `caller` (Buyer/Seller) và trạng thái trước đó. Có thể thêm trường `reason` nếu Indexer cần |

Ngoài ra, ghi nhận (không phải lỗi): nếu USDC/USDT (là proxy có thể nâng cấp) sau này bật phí chuyển, `createEscrow` sẽ revert `AmountMismatch`. Đây là hành vi an toàn; escrow cũ vẫn rút được.

---

### [GAS] G-1: Gộp `token` và `amount` vào một slot (5 → 4 slot)

**Mô tả:** `token` (20 byte) chiếm riêng slot 3. Nếu `amount` đổi sang `uint96` (tối đa ≈ 7,9 × 10²⁸; với 18 decimals là ≈ 79 tỷ ETH, với USDC 6 decimals còn lớn hơn rất nhiều), `token` và `amount` vừa một slot.

**Ước tính:** tiết kiệm khoảng 22.100 gas cho mỗi `createEscrow` (bớt một lần ghi slot mới) và khoảng 2.100 gas cho mỗi lần đọc. Chưa đo thực tế.

**Đánh đổi:** phải kiểm tra `amount <= type(uint96).max` (thêm custom error), đổi ABI của `getEscrow`/struct, và Frontend/Indexer phải cập nhật kiểu.

### [GAS] G-2: `nonReentrant` trên các hàm không gọi ra ngoài

**Mô tả:** `release`, `refund`, `resolveDispute`, `claimTimeoutRefund` chỉ ghi state, không có external call. Guard ở đây tốn khoảng vài nghìn gas mỗi lần gọi (chưa đo), và chỉ có tác dụng phòng thủ nhiều lớp.

**Đề xuất:** **giữ nguyên** vì rule dự án bắt buộc guard cho mọi hàm liên quan rút tiền/claim, và chi phí trên Base thấp. Chỉ ghi nhận.

### [GAS] G-3: Đọc lặp `e.status` / `e.amount`

**Mô tả:** `_load` và `_requireStatus` đọc lại `status` (SLOAD warm, khoảng 100 gas). Không đáng tối ưu nếu đánh đổi tính dễ đọc.

---

## 3. Những điểm đã kiểm tra và không phải lỗi

- **Ranh giới thời gian:** tại đúng `arbitrationDeadline` chỉ Arbiter hành động được; từ `+1` giây chỉ Buyer `claimTimeoutRefund` được (có test biên và fuzz). Tương tự với `deliveryDeadline` và `disputeDeadline`.
- **Seller mở tranh chấp ở `Funded`** chỉ làm chậm được tối đa 14 ngày, và nếu Arbiter im lặng thì kết quả có lợi cho Buyer. Seller không thu lợi gì.
- **Admin đổi `feeRecipient`** chỉ áp dụng cho các escrow kết thúc sau đó; phí đã ghi có cho ví cũ vẫn giữ nguyên (đúng spec).
- **Bỏ token khỏi whitelist** không ảnh hưởng escrow cũ (có test).
- **Contract không có `receive`/`fallback`:** ETH gửi thẳng bị từ chối; force-feed qua `selfdestruct` chỉ làm `balance` lớn hơn nghĩa vụ, không phá logic.
- **Reentrancy qua hook của token:** chỉ token admin whitelist (USDC/USDT không có hook). Kể cả khi có hook, `createEscrow` có guard; `markDelivered`/`raiseDispute` gọi lại cũng không chuyển tiền.
- **Ép kiểu `uint48(block.timestamp)`:** an toàn tới khoảng năm 8,9 triệu.

---

## 4. Gas (trích `forge test --gas-report`, các test không phải invariant)

| Hàm | Trung vị | Max |
| :--- | :--- | :--- |
| Deploy | 2.065.672 (10.008 byte) | — |
| `createEscrow` | 209.917 | 217.364 |
| `markDelivered` | 34.005 | 34.005 |
| `raiseDispute` | 34.333 | 36.525 |
| `release` | 88.203 | 88.667 |
| `refund` | 62.996 | 63.428 |
| `resolveDispute` | 91.928 | 114.325 |
| `claimTimeoutRefund` | 63.189 | 63.189 |
| `withdraw` | 50.025 | 67.125 |

Khi tính cả invariant test, trung vị thấp hơn vì có rất nhiều lệnh gọi bị revert sớm.

---

## 5. Khuyến nghị trước Mainnet

1. Quyết định phương án cho M-1 và cập nhật `business-flows.md` cùng spec trước khi sửa code.
2. Quyết định L-1 (thêm `maxFeeBps`), L-3 (`withdrawTo`), G-1 (`uint96`). Các thay đổi này làm đổi ABI, nên làm trước khi Frontend/Indexer bắt đầu.
3. ~~Ghim `pragma` (L-5)~~ (đã làm); cài và chạy Slither, chạy `forge coverage`.
4. Audit độc lập bên thứ ba trước Base Mainnet.
