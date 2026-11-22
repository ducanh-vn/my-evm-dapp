# Đặc tả Kỹ thuật Smart Contract: EscrowVault

- **Tên Contract:** `EscrowVault.sol`
- **Chuẩn kế thừa:** `Ownable2Step`, `ReentrancyGuard`, `Pausable` (OpenZeppelin); dùng `SafeERC20`, `Math` (OpenZeppelin). **Không** dùng Proxy / UUPS.
- **Trạng thái:** `Nháp`
- **Solidity:** `pragma solidity 0.8.28;` (ghim cố định trong mọi file `.sol` của dự án ở `src/`, `test/`, `script/`; khớp `solc_version` trong `foundry.toml`; audit L-5).
- **Mạng:** Base Sepolia (84532) → Base Mainnet (8453)
- **Nghiệp vụ gốc:** [business-flows.md](../03-san-pham/business-flows.md)
- **Mẫu tham chiếu:** `.claude/references/solidity-secure-pattern.sol`

> Tên hàm, biến và Event trong tài liệu này là thiết kế đề xuất cho lần viết code đầu tiên; chưa có mã nguồn. Địa chỉ deploy sẽ ghi vào [contract-addresses.md](./contract-addresses.md) sau khi triển khai.

---

## 1. Mục đích & Vai trò trong hệ thống
- Một contract duy nhất, bất biến, giữ tiền ký quỹ của mọi escrow (ETH và ERC-20 trong whitelist).
- Mỗi escrow là một bản ghi trong `mapping`, đi qua state machine `Funded → Delivered → Released / Refunded / Disputed → Resolved`.
- Mọi khoản tiền ra được **ghi có** vào `withdrawable[user][token]` (pull payment); người nhận tự gọi `withdraw` (về ví mình) hoặc `withdrawTo` (sang ví khác).
- Không gọi contract bên ngoài nào khác ngoài token ERC-20 trong whitelist và chuyển ETH cho người rút.
- Indexer (Ponder / The Graph) đọc Event để dựng danh sách, lịch sử; contract không có hàm trả về mảng.

Quy ước: `token == address(0)` nghĩa là ETH.

---

## 2. Biến trạng thái cốt lõi (Storage Variables)

### 2.1. Hằng số
| Tên | Kiểu | Giá trị | Mô tả |
| :--- | :--- | :--- | :--- |
| `MAX_FEE_BPS` | `uint16 constant` | `500` | Trần phí 5% |
| `BPS_DENOMINATOR` | `uint16 constant` | `10_000` | Mẫu số bps |
| `MIN_DELIVERY_DURATION` | `uint48 constant` | `1 days` | Thời hạn giao hàng tối thiểu (trước đây `MIN_DELIVERY_PERIOD = 1 hours`; nâng lên theo audit M-1 chiều ngược) |
| `MAX_DELIVERY_DURATION` | `uint48 constant` | `90 days` | Thời hạn giao hàng tối đa (đổi tên cho đồng bộ, giá trị không đổi) |
| `DISPUTE_WINDOW` | `uint48 constant` | `3 days` | Thời gian khiếu nại tối thiểu sau khi giao hàng; mốc kết thúc thực tế là `max(disputeDeadline, deliveryDeadline)` |
| `ARBITRATION_TIMEOUT` | `uint48 constant` | `14 days` | Thời hạn trọng tài phán quyết, tính từ lúc mở tranh chấp |
| `NATIVE_TOKEN` | `address constant` | `address(0)` | Ký hiệu ETH |

### 2.2. Enum và Struct
```solidity
enum Status { None, Funded, Delivered, Disputed, Released, Refunded, Resolved }

/// Sắp xếp để vừa 5 slot (32 bytes/slot)
struct Escrow {
    // slot 0: 20 + 6 + 2 + 1 = 29 bytes
    address buyer;
    uint48  deliveryDeadline;
    uint16  feeBps;           // phí chốt lúc tạo
    Status  status;
    // slot 1: 20 + 6 = 26 bytes
    address seller;
    uint48  disputeDeadline;  // = 0 cho tới khi markDelivered
    // slot 2: 20 + 6 = 26 bytes
    address arbiter;          // chốt lúc tạo, không đổi
    uint48  arbitrationDeadline; // = 0 cho tới khi raiseDispute
    // slot 3
    address token;            // address(0) = ETH
    // slot 4
    uint256 amount;
}
```

### 2.3. Biến storage
| Tên biến | Kiểu dữ liệu | Visibility | Mô tả |
| :--- | :--- | :--- | :--- |
| `owner` | `address` (kế thừa `Ownable2Step`) | `public` | Ví Gnosis Safe Multisig quản trị. Riêng testnet Base Sepolia được phép là ví thường (EOA); script deploy chặn EOA trên mọi chain khác |
| `_escrows` | `mapping(uint256 => Escrow)` | `internal` (đọc qua `getEscrow`) | Dữ liệu từng escrow |
| `withdrawable` | `mapping(address user => mapping(address token => uint256))` | `public` | Số dư chờ rút theo người và tài sản |
| `isTokenAllowed` | `mapping(address => bool)` | `public` | Whitelist ERC-20 (ETH luôn được phép, không nằm trong mapping) |
| `nextEscrowId` | `uint256` | `public` | Bộ đếm id, bắt đầu từ 1 |
| `feeRecipient` | `address` | `public` | Ví nhận phí (cùng slot với `feeBps`) |
| `feeBps` | `uint16` | `public` | Phí hiện hành cho escrow mới, mặc định `100` |
| `defaultArbiter` | `address` | `public` | Trọng tài hệ thống, dùng khi người tạo không chỉ định |

### 2.4. Constructor
```solidity
constructor(
    address initialOwner,     // Gnosis Safe
    address feeRecipient_,
    address defaultArbiter_,
    uint16  feeBps_,          // 100
    address[] memory allowedTokens // USDC, USDT trên mạng tương ứng
) Ownable(initialOwner)
```
- Revert nếu `initialOwner`, `feeRecipient_`, `defaultArbiter_` là `address(0)`, hoặc `feeBps_ > MAX_FEE_BPS`, hoặc có token `address(0)` trong danh sách.
- Phát `FeeUpdated`, `FeeRecipientUpdated`, `DefaultArbiterUpdated`, `TokenAllowlistUpdated` cho giá trị khởi tạo để Indexer có trạng thái ban đầu.
- Địa chỉ USDC/USDT **không** hardcode trong contract; truyền qua script deploy và kiểm tra trên explorer chính thức trước khi deploy.

---

## 3. Ma trận phân quyền các hàm (Access Control Matrix)

### 3.1. Hàm người dùng
| Tên hàm | Visibility | Modifier / Quyền | Mô tả hành động | Event phát ra |
| :--- | :--- | :--- | :--- | :--- |
| `createEscrow(address seller, address token, uint256 amount, uint48 deliveryPeriod, address arbiter, uint16 maxFeeBps) returns (uint256 id)` | `external payable` | `nonReentrant`, `whenNotPaused`; ai cũng gọi được (người gọi là Buyer) | Tạo escrow, chốt `feeBps` (revert `FeeExceedsMax` nếu `feeBps > maxFeeBps`) và `arbiter` (`address(0)` → `defaultArbiter`), nhận tiền | `EscrowCreated` |
| `markDelivered(uint256 id)` | `external` | Chỉ Seller của escrow; `now ≤ deliveryDeadline` | `Funded` → `Delivered`, đặt `disputeDeadline = now + DISPUTE_WINDOW` | `EscrowDelivered` |
| `release(uint256 id)` | `external` | `nonReentrant`; Buyer (khi `Funded`/`Delivered`) hoặc Seller (khi `Delivered` và `now > max(disputeDeadline, deliveryDeadline)`) | Ghi có `amount − fee` cho Seller, `fee` cho `feeRecipient` | `EscrowReleased` |
| `refund(uint256 id)` | `external` | `nonReentrant`; Seller (khi `Funded`/`Delivered`/`Disputed`) hoặc Buyer (**chỉ** khi `Funded` — Seller chưa từng `markDelivered` — và `now > deliveryDeadline`; khi đã `Delivered` Buyer chỉ còn `release`/`raiseDispute`) | Ghi có toàn bộ `amount` cho Buyer, không phí | `EscrowRefunded` |
| `raiseDispute(uint256 id)` | `external` | Buyer hoặc Seller; `Funded` và `now ≤ deliveryDeadline`, hoặc `Delivered` và `now ≤ max(disputeDeadline, deliveryDeadline)` | Chuyển sang `Disputed`, đặt `arbitrationDeadline = now + ARBITRATION_TIMEOUT` | `DisputeRaised` |
| `resolveDispute(uint256 id, uint16 buyerBps)` | `external` | `nonReentrant`; chỉ `arbiter` của escrow; trạng thái `Disputed` và `now ≤ arbitrationDeadline` | Chia tiền theo `buyerBps`, phí chỉ trên phần Seller | `DisputeResolved` |
| `claimTimeoutRefund(uint256 id)` | `external` | `nonReentrant`; chỉ Buyer; trạng thái `Disputed` và `now > arbitrationDeadline` | Ghi có 100% `amount` cho Buyer, không phí, `status = Refunded` | `EscrowRefunded` |
| `withdraw(address token)` | `external` | `nonReentrant`; **không** có `whenNotPaused` | Rút toàn bộ số dư của `msg.sender` theo tài sản về chính `msg.sender` | `Withdrawn` |
| `withdrawTo(address token, address to)` | `external` | `nonReentrant`; **không** có `whenNotPaused`; `to != address(0)` | Rút toàn bộ số dư của `msg.sender` theo tài sản, chuyển tới `to` (audit L-3: ví không nhận được ETH / bị blacklist) | `Withdrawn` |
| `getEscrow(uint256 id) returns (Escrow memory)` | `external view` | Ai cũng gọi được | Đọc một escrow | — |

### 3.2. Hàm quản trị
| Tên hàm | Visibility | Modifier quyền | Mô tả hành động | Event phát ra |
| :--- | :--- | :--- | :--- | :--- |
| `setFeeBps(uint16 newBps)` | `external` | `onlyOwner` | Đổi phí cho escrow mới; revert nếu `> MAX_FEE_BPS` | `FeeUpdated` |
| `setFeeRecipient(address)` | `external` | `onlyOwner` | Đổi ví nhận phí; revert nếu `address(0)`. Phí đã ghi có cho ví cũ vẫn thuộc ví cũ | `FeeRecipientUpdated` |
| `setDefaultArbiter(address)` | `external` | `onlyOwner` | Đổi trọng tài mặc định cho escrow mới; revert nếu `address(0)` | `DefaultArbiterUpdated` |
| `setTokenAllowed(address token, bool allowed)` | `external` | `onlyOwner` | Thêm/bỏ ERC-20 khỏi whitelist; revert nếu `token == address(0)` | `TokenAllowlistUpdated` |
| `pause()` / `unpause()` | `external` | `onlyOwner` | Chỉ chặn `createEscrow` | `Paused` / `Unpaused` |
| `transferOwnership` / `acceptOwnership` | `public` | `Ownable2Step` | Chuyển owner 2 bước | `OwnershipTransferStarted` / `OwnershipTransferred` |
| `renounceOwnership()` | `public` | `onlyOwner` | **Override để luôn revert** (`RenounceDisabled`) | — |

Không có hàm nào cho owner rút tiền khỏi contract.

**Trọng tài mất liên lạc:** không có hàm cho owner thay `arbiter` của escrow đã tạo (đã cân nhắc và loại, xem [business-flows.md — Quyết định: xử lý trọng tài mất liên lạc](../03-san-pham/business-flows.md#quyết-định-xử-lý-trọng-tài-mất-liên-lạc)). Quá `ARBITRATION_TIMEOUT` (14 ngày từ `raiseDispute`), Buyer gọi `claimTimeoutRefund` để lấy lại tiền gốc. `setDefaultArbiter` chỉ áp dụng cho escrow mới.

### 3.3. Chi tiết kiểm tra và tính toán

**`createEscrow`**
1. Checks: `seller != address(0)`, `seller != msg.sender`; `amount > 0`; `MIN_DELIVERY_DURATION ≤ deliveryPeriod ≤ MAX_DELIVERY_DURATION`; `feeBps ≤ maxFeeBps` (nếu không, revert `FeeExceedsMax(feeBps, maxFeeBps)`); `arbiterFinal = arbiter == address(0) ? defaultArbiter : arbiter`, và `arbiterFinal` khác Buyer và Seller.
   - ETH: `msg.value == amount`.
   - ERC-20: `msg.value == 0`, `isTokenAllowed[token]`.
2. Effects: `id = ++nextEscrowId` (id bắt đầu từ 1); ghi struct với `feeBps` hiện hành, `deliveryDeadline = block.timestamp + deliveryPeriod`, `status = Funded`.
3. Interactions (ERC-20): đo `balanceOf(this)` trước và sau `safeTransferFrom(msg.sender, this, amount)`; revert `AmountMismatch` nếu chênh lệch khác `amount` (phòng thủ token lạ dù đã có whitelist).
4. Emit `EscrowCreated`.

**`release`** — `fee = Math.mulDiv(amount, e.feeBps, BPS_DENOMINATOR)`; `withdrawable[seller][token] += amount − fee`; `withdrawable[feeRecipient][token] += fee`; `status = Released`.

**`refund`** — `withdrawable[buyer][token] += amount`; `status = Refunded`.

**`raiseDispute`** — `arbitrationDeadline = block.timestamp + ARBITRATION_TIMEOUT`; `status = Disputed`.

**Mốc kết thúc khiếu nại của escrow `Delivered` (audit M-1)** — `windowEnd = max(disputeDeadline, deliveryDeadline)` (hàm nội bộ `_disputeWindowEnd`).
- Buyer/Seller `raiseDispute` được khi `now ≤ windowEnd`; Seller tự `release` được khi `now > windowEnd`.
- Hai điều kiện bổ sung nhau, nên tại mọi thời điểm có **đúng một** trong hai hành động hợp lệ: không có khoảng Seller chưa rút được mà Buyer cũng không khiếu nại được, và không có khoảng chồng lấn.
- Buyer `release` không bị ảnh hưởng (gọi được bất cứ lúc nào khi `Funded`/`Delivered`).

**`resolveDispute`** — revert `DeadlinePassed` nếu `block.timestamp > arbitrationDeadline` (tránh tranh chấp giao dịch với `claimTimeoutRefund`); revert nếu `buyerBps > BPS_DENOMINATOR`.
- `buyerAmount = Math.mulDiv(amount, buyerBps, BPS_DENOMINATOR)`
- `sellerGross = amount − buyerAmount` (phần dư do làm tròn thuộc Seller, không mất wei)
- `fee = Math.mulDiv(sellerGross, e.feeBps, BPS_DENOMINATOR)`
- Ghi có `buyerAmount` cho Buyer, `sellerGross − fee` cho Seller, `fee` cho `feeRecipient` (bỏ qua các khoản bằng 0); `status = Resolved`.

`feeRecipient` được đọc tại thời điểm kết thúc escrow (không chốt theo escrow).

**`withdraw` / `withdrawTo`** — cùng dùng `_withdraw(token, to)` với `to = msg.sender` (withdraw) hoặc `to` do người gọi chọn (withdrawTo, revert `ZeroAddress` nếu `to == 0`): `bal = withdrawable[msg.sender][token]`; revert `NothingToWithdraw` nếu `0`; đặt về `0`; phát `Withdrawn`; ETH: `(bool ok,) = to.call{value: bal}("")`, revert `EthTransferFailed` nếu `!ok`; ERC-20: `safeTransfer(to, bal)`. Chỉ trừ số dư của `msg.sender`, không ai rút được tiền của người khác.

Mọi hàm đổi trạng thái escrow revert `EscrowNotFound` khi `status == None`, `InvalidStatus` khi sai trạng thái, `Unauthorized` khi sai người gọi, `DeadlinePassed` / `DeadlineNotReached` khi sai thời điểm.

### 3.4. Events
| Event | Tham số (`indexed` tối đa 3) |
| :--- | :--- |
| `EscrowCreated` | `uint256 indexed id, address indexed buyer, address indexed seller, address token, address arbiter, uint256 amount, uint16 feeBps, uint48 deliveryDeadline` |
| `EscrowDelivered` | `uint256 indexed id, uint48 disputeDeadline` |
| `EscrowReleased` | `uint256 indexed id, address indexed caller, uint256 sellerAmount, uint256 fee` |
| `EscrowRefunded` | `uint256 indexed id, address indexed caller, uint256 amount` |
| `DisputeRaised` | `uint256 indexed id, address indexed raisedBy, uint48 arbitrationDeadline` |
| `DisputeResolved` | `uint256 indexed id, address indexed arbiter, uint16 buyerBps, uint256 buyerAmount, uint256 sellerAmount, uint256 fee` |
| `Withdrawn` | `address indexed user, address indexed token, address indexed to, uint256 amount` |
| `FeeUpdated` | `uint16 oldBps, uint16 newBps` |
| `FeeRecipientUpdated` | `address indexed oldRecipient, address indexed newRecipient` |
| `DefaultArbiterUpdated` | `address indexed oldArbiter, address indexed newArbiter` |
| `TokenAllowlistUpdated` | `address indexed token, bool allowed` |

### 3.5. Custom Errors
`ZeroAddress()`, `ZeroAmount()`, `InvalidSeller()`, `InvalidArbiter()`, `InvalidDeliveryPeriod(uint48 period)`, `TokenNotAllowed(address token)`, `InvalidMsgValue(uint256 expected, uint256 actual)`, `AmountMismatch(uint256 expected, uint256 received)`, `EscrowNotFound(uint256 id)`, `InvalidStatus(uint256 id, Status current)`, `Unauthorized()`, `DeadlinePassed()`, `DeadlineNotReached()`, `InvalidBps(uint256 bps)`, `FeeTooHigh(uint16 bps)`, `FeeExceedsMax(uint16 current, uint16 max)`, `NothingToWithdraw()`, `EthTransferFailed()`, `RenounceDisabled()`.

### 3.6. Invariants
1. Với mỗi `token`: `số dư thực của contract ≥ Σ amount của escrow ở Funded/Delivered/Disputed + Σ withdrawable[*][token]`. Chỉ yêu cầu `≥` vì ai cũng có thể gửi thẳng token hoặc force-feed ETH (qua `selfdestruct`) vào contract; logic **không** được dựa vào `balanceOf(this)` hay `address(this).balance` (trừ phép đo chênh lệch khi nhận ERC-20 trong `createEscrow`).
2. Escrow ở trạng thái kết thúc không bao giờ đổi trạng thái.
3. `e.feeBps ≤ MAX_FEE_BPS` cho mọi escrow; `feeBps ≤ MAX_FEE_BPS` mọi lúc.
4. Hoàn tiền 100% cho Buyer (qua `refund`, `claimTimeoutRefund` hoặc `buyerBps = 10_000`) không phát sinh phí.
5. Owner không thể làm giảm `withdrawable` hay `amount` của bất kỳ ai.
6. Mọi escrow ở `Disputed` đều kết thúc được: sau `arbitrationDeadline`, Buyer luôn gọi được `claimTimeoutRefund` (kể cả khi `paused`).
7. `e.arbiter` không đổi sau khi tạo escrow; không hàm nào (kể cả của owner) ghi lại trường này.
8. Seller không bao giờ tự `release` khi `now ≤ max(disputeDeadline, deliveryDeadline)` (audit M-1).

---

## 4. Kịch bản kiểm thử bắt buộc (Test Plan)

Viết bằng Foundry (`test/EscrowVault.t.sol`, `test/EscrowVault.invariant.t.sol`) sau khi khởi tạo dự án; dùng một ERC-20 mock 6 decimals giống USDC và một ERC-20 mock fee-on-transfer cho test phòng thủ.

### Happy Path
- [ ] ETH và ERC-20: tạo → `markDelivered` → Buyer `release` → Seller rút `amount − 1%`, `feeRecipient` rút `1%`.
- [ ] Buyer `release` ngay khi còn `Funded`.
- [ ] Tự động giải ngân: Seller `release` sau `max(disputeDeadline, deliveryDeadline)`.
- [ ] Audit M-1: Seller `release` revert khi đã qua `disputeDeadline` nhưng chưa qua `deliveryDeadline`; thành công khi qua cả hai. Giao muộn (`disputeDeadline > deliveryDeadline`) thì mốc là `disputeDeadline`.
- [ ] Audit M-1: Buyer vẫn `raiseDispute` được khi `disputeDeadline < now ≤ deliveryDeadline`.
- [ ] Biên `windowEnd`: tại đúng mốc chỉ `raiseDispute` hợp lệ; tại mốc + 1 chỉ Seller `release` hợp lệ (unit test và fuzz).
- [ ] Seller `refund` ở `Funded`, `Delivered`, `Disputed`: Buyer nhận đủ 100%, không phí.
- [ ] Buyer `refund` sau `deliveryDeadline` khi còn `Funded`.
- [ ] Tranh chấp: `buyerBps` = 10.000 (không phí), 0 (phí như giải ngân), 6.000 (phí chỉ trên 40%).
- [ ] Trọng tài quá hạn: `vm.warp` qua 14 ngày → Buyer `claimTimeoutRefund` nhận đủ 100%, không phí.
- [ ] Biên thời gian: tại đúng `arbitrationDeadline` Arbiter vẫn `resolveDispute` được và `claimTimeoutRefund` revert; tại `arbitrationDeadline + 1` thì ngược lại.
- [ ] `arbiter = address(0)` → escrow dùng `defaultArbiter`; đổi `defaultArbiter` sau đó không ảnh hưởng escrow cũ.
- [ ] Đổi `feeBps` sau khi tạo không ảnh hưởng escrow cũ.

### Revert Cases
- [ ] `createEscrow`: `amount = 0`, `seller = 0` hoặc `= buyer`, `deliveryPeriod` < 1 ngày (kiểm tra biên `1 days - 1` revert, `1 days` OK) hoặc > 90 ngày, arbiter trùng Buyer/Seller, token ngoài whitelist, ETH sai `msg.value`, ERC-20 kèm `msg.value > 0`, khi `paused`.
- [ ] `createEscrow` với `maxFeeBps < feeBps` → `FeeExceedsMax`; `maxFeeBps == feeBps` OK; kịch bản admin đổi phí 1% → 5% ngay trước giao dịch của Buyer (`maxFeeBps = 100`) → revert, không kéo tiền.
- [ ] Buyer `refund` khi `Delivered` ở mọi thời điểm (trước/giữa/sau các mốc, fuzz) và khi `Disputed` → `InvalidStatus`; biên `deliveryDeadline` (revert) / `deliveryDeadline + 1` (OK) khi `Funded`.
- [ ] `markDelivered` bởi người không phải Seller, sau `deliveryDeadline`, khi không ở `Funded`.
- [ ] Seller `release` khi `now ≤ max(disputeDeadline, deliveryDeadline)` hoặc khi còn `Funded`; người lạ `release`.
- [ ] Buyer `refund` trước `deliveryDeadline` hoặc khi đã `Delivered`.
- [ ] `raiseDispute` bởi người lạ, sau hạn, hoặc khi đã `Disputed`.
- [ ] `resolveDispute` bởi người không phải arbiter của escrow (kể cả owner, kể cả `defaultArbiter` khi escrow có arbiter riêng), `buyerBps > 10.000`, khi không ở `Disputed`.
- [ ] `resolveDispute` sau `arbitrationDeadline`; `claimTimeoutRefund` trước hạn, bởi người không phải Buyer, hoặc khi không ở `Disputed`.
- [ ] Mọi thao tác trên escrow đã kết thúc hoặc id không tồn tại.
- [ ] Hàm admin gọi từ ví thường; `setFeeBps(501)`; `renounceOwnership`.
- [ ] `withdraw` khi số dư bằng 0; ETH tới contract từ chối nhận (`EthTransferFailed`, số dư được giữ nguyên).
- [ ] `withdrawTo`: chuyển đúng ví nhận (ETH, ERC-20), `to = 0` → `ZeroAddress`, số dư 0 → `NothingToWithdraw`, ví nhận từ chối ETH → `EthTransferFailed` (giữ số dư), cứu tiền cho Seller là contract không nhận ETH và cho Seller bị token blacklist, chạy được khi `paused`, không rút được số dư người khác.
- [ ] Token fee-on-transfer (nếu lỡ whitelist) → `AmountMismatch`.

### Pause
- [ ] Khi `paused`: `createEscrow` revert; `markDelivered`, `release`, `refund`, `raiseDispute`, `resolveDispute`, `claimTimeoutRefund`, `withdraw`, `withdrawTo` vẫn chạy.

### Fuzz Test
- [ ] 1.000+ lượt ngẫu nhiên cho `amount`, `feeBps ∈ [0, 500]`, `buyerBps ∈ [0, 10.000]`, `deliveryPeriod`, mốc `vm.warp`: tổng ghi có luôn bằng `amount`, không mất wei.

### Invariant Test
- [ ] Handler gọi ngẫu nhiên mọi hàm với nhiều Buyer/Seller/Arbiter; kiểm tra các invariant ở mục 3.6 sau mỗi lượt.

### Reentrancy Test
- [ ] Contract tấn công nhận ETH rồi gọi lại `withdraw`, `withdrawTo`, `release`, `refund`, `claimTimeoutRefund`, `createEscrow` trong `receive()` → bị chặn bởi `nonReentrant`, số dư đúng.

### Gas
- [ ] Chạy `forge test --gas-report` và `forge inspect EscrowVault storage-layout` để xác nhận `Escrow` chiếm 5 slot.

---

## 5. Checklist trước khi deploy (tóm tắt)
- [ ] Toàn bộ test trên pass; có báo cáo coverage.
- [ ] Địa chỉ USDC/USDT cho từng mạng đã kiểm tra trên nguồn chính thức, ghi vào script deploy (không hardcode trong contract).
- [ ] `initialOwner` là Gnosis Safe (Base Sepolia: chấp nhận EOA tạm thời, xem [checklist deploy](../04-van-hanh/deploy-checklist-base-sepolia.md) mục 2.1); `feeRecipient`, `defaultArbiter` đúng ví đã duyệt.
- [ ] Verify source trên Basescan.
- [ ] Ghi địa chỉ vào [contract-addresses.md](./contract-addresses.md).
- [ ] Chi tiết đầy đủ: chạy `/gen-deploy-checklist` khi đã có mã nguồn.
