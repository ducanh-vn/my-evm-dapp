# Checklist trước khi deploy EscrowVault lên Base Sepolia

- **Mạng:** Base Sepolia (Chain ID `84532`)
- **Contract:** `src/EscrowVault.sol` (không Proxy, không nâng cấp được)
- **Script:** `script/DeployEscrowVault.s.sol` (đọc tham số từ biến môi trường, không chứa private key)
- **Nhánh / commit:** ghi commit hash thực tế lúc deploy vào mục 7
- **Tài liệu liên quan:** [Đặc tả kỹ thuật](../02-ky-thuat/escrow-vault-spec.md), [Báo cáo audit nội bộ](../02-ky-thuat/audit-report-escrow-vault.md), [Danh sách địa chỉ contract](../02-ky-thuat/contract-addresses.md)

> Quy tắc an toàn: **không bao giờ** dùng `--private-key` hay dán private key / mnemonic vào terminal, file `.env` hay code. Chỉ ký bằng keystore đã mã hóa (`--account`) hoặc ví cứng (`--ledger` / `--trezor`). Người deploy tự chạy lệnh có `--broadcast`; trợ lý AI không chạy lệnh này.

---

## 1. Mã nguồn và kiểm thử

- [ ] Đang ở đúng commit đã review; `git status` sạch.
- [ ] `forge build` không lỗi. Các cảnh báo lint còn lại đều có chủ đích: `block-timestamp` (deadline tính theo giờ/ngày) và `revert` trong vòng lặp constructor.
- [ ] `forge test` pass 100%. Lần chạy gần nhất: **134/134 test** (unit, fuzz, invariant, test script deploy).
- [ ] `forge coverage --report summary --no-match-coverage "(test|script)/"`. Lần chạy gần nhất cho `src/EscrowVault.sol`: Lines **100%** (169/169), Statements 98,64%, Branches 94,64%, Funcs 100%.
- [ ] `forge fmt --check` sạch.
- [ ] `forge inspect EscrowVault storageLayout`: struct `Escrow` vẫn 5 slot.
- [ ] Đã xử lý hoặc chấp nhận các mục trong báo cáo audit. Trạng thái hiện tại: M-1, L-1, L-3, L-5 đã sửa (`pragma solidity 0.8.28;` đã ghim); L-2, L-4, L-6, G-1, G-2, G-3 chưa sửa.
- [ ] (Khuyến nghị) Cài và chạy Slither: `slither .`.

## 2. Tham số constructor

| Tham số | Biến môi trường | Kiểm tra |
| :--- | :--- | :--- |
| `initialOwner` | **`INITIAL_OWNER`** (không phải `ADMIN_SAFE_ADDRESS`; script chỉ đọc tên `INITIAL_OWNER`) | **Base Sepolia:** được phép là ví thường (EOA), ví dụ địa chỉ MetaMask của bạn; script in cảnh báo. **Mọi chain khác (đặc biệt Base Mainnet 8453): bắt buộc là Gnosis Safe**, script revert `OwnerNotContract` nếu địa chỉ không có code. Không có biến nào bỏ qua được quy tắc này (xem mục 2.1) |
| `feeRecipient_` | `FEE_RECIPIENT` | Ví nhận phí đã duyệt (nên là Safe) |
| `defaultArbiter_` | `DEFAULT_ARBITER` | Ví trọng tài hệ thống đã duyệt; người giữ ví phải sẵn sàng phân xử trong 14 ngày |
| `feeBps_` | `FEE_BPS` | Mặc định `100` (1%), tối đa `500` |
| `allowedTokens` | `ALLOWED_TOKENS` | Danh sách ERC-20 cách nhau bởi dấu phẩy. Script revert nếu có địa chỉ 0, địa chỉ không có code, hoặc trùng lặp |
| (kiểm tra mạng) | `EXPECTED_CHAIN_ID` | Mặc định `84532`. Script revert `WrongChain` nếu RPC trỏ sai mạng |

### 2.1. Owner trên testnet là ví thường (EOA) — quyết định tạm thời

- **Lý do:** tạo Gnosis Safe trên Base Sepolia qua giao diện Safe liên tục lỗi. Chủ dự án đồng ý **chỉ trên testnet** dùng ví thường (MetaMask) làm owner.
- **Cách script áp dụng:** quy tắc chỉ dựa vào `block.chainid` thực tế của RPC:
  - `84532` (Base Sepolia): owner EOA được chấp nhận, script in cảnh báo `owner la vi thuong (EOA)`.
  - Mọi chain khác (8453, 1, 31337...): owner **phải có code** (Safe), nếu không revert `OwnerNotContract`.
- **Biến cũ `ALLOW_EOA_OWNER` đã bị loại bỏ.** Nếu vẫn đặt, script bỏ qua và in cảnh báo; đặt `true` cũng không deploy được với owner EOA trên mainnet (có test). Đặt `EXPECTED_CHAIN_ID` khác cũng không giúp được, vì kiểm tra owner dùng chain thật.
- **Rủi ro chấp nhận ở testnet:** một private key duy nhất kiểm soát mọi hàm admin (`setFeeBps`, `setFeeRecipient`, `setDefaultArbiter`, `setTokenAllowed`, `pause`). Owner vẫn **không** rút được tiền ký quỹ (thiết kế contract). Bảo vệ ví MetaMask này như ví admin; không dùng chung cho việc khác nếu có thể.
- **Trước Base Mainnet: bắt buộc dùng Gnosis Safe.** Mainnet deploy mới với `INITIAL_OWNER` = Safe (script tự chặn EOA).
- **Tùy chọn: chuyển owner testnet sang Safe sau này** (khi tạo được Safe), theo `Ownable2Step` hai bước:
  1. Từ ví owner hiện tại (EOA) gọi `transferOwnership(<SAFE_ADDRESS>)`. Owner chưa đổi; `pendingOwner()` = Safe.
  2. Từ Safe gọi `acceptOwnership()` (tạo giao dịch trong Safe UI hoặc Transaction Builder). Lúc này `owner()` = Safe.
  3. Kiểm tra `owner()` và `pendingOwner()` = `0x0` bằng `cast call`. Nếu gửi nhầm địa chỉ ở bước 1, chỉ cần gọi lại `transferOwnership` với địa chỉ đúng; quyền chưa mất cho tới khi bên nhận `acceptOwnership`.

### Lấy địa chỉ USDC testnet
- **Không** chép địa chỉ từ blog, chat hay nguồn không rõ; tài liệu này cố ý **không** ghi sẵn địa chỉ nào.
- Lấy địa chỉ USDC trên Base Sepolia từ trang chính thức của Circle: tài liệu developer của Circle, mục địa chỉ hợp đồng USDC (USDC Contract Addresses → Testnet).
- Đối chiếu địa chỉ đó trên `sepolia.basescan.org`: contract đã verify, tên/symbol `USDC`, `decimals = 6`.
- Kiểm tra thêm bằng `cast` (chỉ đọc, không cần key):
  ```bash
  cast call <USDC_ADDRESS> "symbol()(string)" --rpc-url "$BASE_SEPOLIA_RPC_URL"
  cast call <USDC_ADDRESS> "decimals()(uint8)" --rpc-url "$BASE_SEPOLIA_RPC_URL"
  ```
- Lấy USDC testnet để chạy thử: faucet chính thức của Circle (chọn mạng Base Sepolia).
- USDT: chỉ thêm khi có địa chỉ chính thức từ Tether cho Base Sepolia. Nếu không có thì để trống; Admin thêm sau bằng `setTokenAllowed` qua Safe.
- Không whitelist token fee-on-transfer hoặc rebasing (contract sẽ revert `AmountMismatch` với token fee-on-transfer).

### Mẫu file `.env`
Tạo `.env` ở thư mục gốc. File này đã bị `.gitignore` chặn, và Foundry tự nạp nó khi chạy `forge script`. Chỉ điền **địa chỉ công khai**, không bao giờ điền key. Tên biến owner là **`INITIAL_OWNER`** (nếu bạn đang có `ADMIN_SAFE_ADDRESS` trong `.env`, hãy đổi tên hoặc thêm dòng `INITIAL_OWNER=<cùng địa chỉ>`):
```dotenv
# Tham số constructor (bắt buộc)
INITIAL_OWNER=
FEE_RECIPIENT=
DEFAULT_ARBITER=
# Tùy chọn
FEE_BPS=
ALLOWED_TOKENS=
EXPECTED_CHAIN_ID=
# Dùng trong lệnh CLI
BASE_SEPOLIA_RPC_URL=
ETHERSCAN_API_KEY=
```
Có thể lưu mẫu này thành `.env.example` (không có giá trị) để commit.

## 3. Ví deploy (deployer)

- [ ] Dùng một ví deploy riêng, chỉ chứa ít ETH Base Sepolia đủ trả gas. Gas deploy đo được khoảng **2,14 triệu gas**.
- [ ] Ví deploy **không** cần quyền gì sau khi deploy: owner được đặt thẳng trong constructor (`INITIAL_OWNER`). Trên testnet có thể dùng chính ví MetaMask owner làm ví deploy; khi đó ví này vừa trả gas vừa là admin.
- [ ] Nạp ví vào keystore mã hóa (chỉ làm một lần; lệnh hỏi key ở chế độ ẩn, không lưu vào lịch sử shell):
  ```bash
  cast wallet import deployer --interactive
  cast wallet address --account deployer
  ```
  Hoặc dùng ví cứng: thay `--account deployer` bằng `--ledger` (hoặc `--trezor`) và thêm `--sender <địa chỉ ví cứng>`.

## 4. Mô phỏng (không gửi giao dịch)

```bash
forge script script/DeployEscrowVault.s.sol:DeployEscrowVault \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --account deployer --sender <DEPLOYER_ADDRESS>
```
- [ ] Log in ra đúng `chainId`, `initialOwner`, `feeRecipient`, `defaultArbiter`, `feeBps`, danh sách token.
- [ ] Không có lỗi `WrongChain`, `OwnerNotContract`, `TokenNotContract`, `DuplicateToken`, `DeploymentMismatch`.
- [ ] Người thứ hai trong team đối chiếu lại các địa chỉ trong log.

## 5. Deploy và verify (người deploy tự chạy)

```bash
forge script script/DeployEscrowVault.s.sol:DeployEscrowVault \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --account deployer --sender <DEPLOYER_ADDRESS> \
  --broadcast --verify --etherscan-api-key "$ETHERSCAN_API_KEY"
```
- Nếu verify tự động lỗi, verify thủ công:
  ```bash
  forge verify-contract <VAULT_ADDRESS> src/EscrowVault.sol:EscrowVault \
    --chain base-sepolia \
    --constructor-args $(cast abi-encode "constructor(address,address,address,uint16,address[])" \
        <INITIAL_OWNER> <FEE_RECIPIENT> <DEFAULT_ARBITER> <FEE_BPS> "[<TOKEN_1>,<TOKEN_2>]") \
    --etherscan-api-key "$ETHERSCAN_API_KEY" --watch
  ```
- [ ] Source đã verify trên `sepolia.basescan.org`; compiler `0.8.28`, optimizer 200 runs, EVM `cancun` (khớp `foundry.toml`).
- [ ] Lưu lại file `broadcast/DeployEscrowVault.s.sol/84532/run-latest.json` ở nơi an toàn nội bộ (thư mục `broadcast/` bị `.gitignore` chặn).

## 6. Kiểm tra sau deploy

Script đã tự kiểm tra các điểm dưới đây ngay sau deploy (`verifyDeployment`). Đối chiếu lại thủ công bằng lệnh chỉ đọc:
```bash
cast call <VAULT_ADDRESS> "owner()(address)" --rpc-url "$BASE_SEPOLIA_RPC_URL"
cast call <VAULT_ADDRESS> "pendingOwner()(address)" --rpc-url "$BASE_SEPOLIA_RPC_URL"
cast call <VAULT_ADDRESS> "feeRecipient()(address)" --rpc-url "$BASE_SEPOLIA_RPC_URL"
cast call <VAULT_ADDRESS> "defaultArbiter()(address)" --rpc-url "$BASE_SEPOLIA_RPC_URL"
cast call <VAULT_ADDRESS> "feeBps()(uint16)" --rpc-url "$BASE_SEPOLIA_RPC_URL"
cast call <VAULT_ADDRESS> "isTokenAllowed(address)(bool)" <USDC_ADDRESS> --rpc-url "$BASE_SEPOLIA_RPC_URL"
cast call <VAULT_ADDRESS> "paused()(bool)" --rpc-url "$BASE_SEPOLIA_RPC_URL"
```
- [ ] `owner()` = `INITIAL_OWNER` (testnet: ví EOA; mainnet: Safe); `pendingOwner()` = `0x0`. Owner được đặt trong constructor nên **không cần** `transferOwnership`.
- [ ] Từ ví owner, thử một giao dịch quản trị vô hại để chắc owner điều khiển được contract, ví dụ `setFeeBps(100)` (giữ nguyên giá trị). Event `FeeUpdated` phải xuất hiện. Testnet EOA: gửi qua MetaMask hoặc `cast send ... --account <owner>`; Safe: Transaction Builder.
- [ ] `renounceOwnership()` luôn revert (thiết kế). Nếu sau này cần đổi Safe: Safe cũ gọi `transferOwnership(newSafe)`, Safe mới gọi `acceptOwnership()`.
- [ ] Chạy thử một vòng nhỏ với USDC testnet: `approve` → `createEscrow` (truyền `maxFeeBps` = phí hiện hành và `arbiter` tường minh) → `markDelivered` → `release` → `withdraw`. Kiểm tra event trên Basescan.
- [ ] Thử `pause()` / `unpause()` từ ví owner: khi pause chỉ `createEscrow` bị chặn.
- [ ] (Tùy chọn, testnet) Khi đã có Safe: chuyển owner theo mục 2.1 (`transferOwnership` → Safe `acceptOwnership`).

## 7. Cập nhật tài liệu sau deploy

- [ ] Ghi vào [contract-addresses.md](../02-ky-thuat/contract-addresses.md), mục Base Sepolia:
  - địa chỉ `EscrowVault` (link Basescan), block deploy, tx hash;
  - commit hash của mã nguồn;
  - tham số constructor (owner — ghi rõ là EOA testnet hay Safe, feeRecipient, defaultArbiter, feeBps, token).
- [ ] Cập nhật `docs/02-ky-thuat/README.md` và `docs/README.md` nếu thêm tài liệu mới.
- [ ] Cung cấp địa chỉ + ABI (`out/EscrowVault.sol/EscrowVault.json`) cho Frontend (`src/constants/`) và Indexer (start block = block deploy). Lưu ý event `Withdrawn` đã có thêm tham số `to` (indexed).

## 8. Trước khi lên Base Mainnet (8453)

- [ ] **Owner bắt buộc là Gnosis Safe** (script tự chặn EOA ngoài Base Sepolia).
- [ ] Audit độc lập bên thứ ba.
- [ ] Xem lại L-2 và G-1 (L-5 đã ghim `pragma solidity 0.8.28;`).
- [ ] Chạy lại toàn bộ checklist này với `EXPECTED_CHAIN_ID=8453` và địa chỉ token mainnet lấy từ nguồn chính thức của Circle/Tether.
