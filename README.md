# EscrowVault

Giao thức ký quỹ P2P trên Base: người mua khóa ETH hoặc USDC vào smart contract. Người bán nhận tiền khi người mua xác nhận, khi hết hạn khiếu nại, hoặc theo phán quyết của trọng tài nếu có tranh chấp.

## 1. Tổng quan

**Đang hoạt động:**
- **Smart contract `EscrowVault`:**
  - tạo escrow bằng ETH hoặc ERC-20 trong whitelist; báo đã giao hàng; giải ngân; hoàn tiền;
  - mở tranh chấp; trọng tài phân xử theo tỷ lệ; người mua lấy lại tiền nếu trọng tài quá 14 ngày;
  - rút tiền chủ động (pull payment) bằng `withdraw` hoặc `withdrawTo`;
  - phí 1% chốt lúc tạo escrow, trần 5%; có `maxFeeBps` để chặn trường hợp admin đổi phí giữa chừng;
  - quản trị bằng `Ownable2Step` + `Pausable` (chỉ chặn tạo escrow mới).

  Contract bất biến (không Proxy). Admin không có hàm nào rút được tiền ký quỹ.
- **Base Sepolia:** [`0xEC01EeE5BEeA3Ab571F7aE31E70f9f479618560e`](https://sepolia.basescan.org/address/0xEC01EeE5BEeA3Ab571F7aE31E70f9f479618560e), đã verify (Exact Match). Owner là Gnosis Safe; USDC testnet nằm trong whitelist.
- **Giao diện web (`frontend/`):**
  - kết nối MetaMask, chuyển mạng Base Sepolia ↔ Anvil;
  - tạo escrow ETH/USDC (USDC có bước approve);
  - trang chi tiết với nút hiện theo vai trò (người mua / người bán / trọng tài);
  - số dư ví và số dư chờ rút; tua thời gian (chỉ trên Anvil).
- **Kiểm thử:** 130 test Foundry: unit, fuzz, invariant, reentrancy, và test cho script deploy.

**Không có backend, Auth hay Database.** Danh tính người dùng là địa chỉ ví (MetaMask). Mọi dữ liệu escrow nằm on-chain; giao diện đọc trực tiếp từ contract qua RPC. Chưa có Indexer.

## 2. Tech Stack

| Lớp | Công nghệ (phiên bản theo repo) |
| :--- | :--- |
| Smart contract | Solidity `0.8.28` (EVM `cancun`, optimizer 200 runs), OpenZeppelin Contracts `v5.7.0` |
| Công cụ contract | Foundry `1.10.0` (forge, cast, anvil), forge-std `v1.17.0` |
| Frontend | Next.js `15.5.29` (App Router), React `19.2.9`, TypeScript `5.9.3` |
| Web3 / state | wagmi `2.19.5`, viem `2.58.4`, TanStack Query `5.108.2`. Không dùng thư viện state riêng; trạng thái lấy từ chain qua các hooks |
| UI | CSS thuần (`src/app/globals.css`), không dùng thư viện UI |
| Ví | MetaMask (wagmi `injected` connector) |
| Mạng | Base Sepolia (84532), Anvil local (31337) |
| CI | GitHub Actions (`.github/workflows/test.yml`): `forge fmt --check`, `forge build`, `forge test` |

## 3. Cấu trúc thư mục

```
├── src/                      # Smart contract
│   ├── EscrowVault.sol
│   └── interfaces/IEscrowVault.sol   # enum, struct, events, errors, NatSpec
├── test/                     # Foundry tests
│   ├── EscrowVault.*.t.sol   # unit theo luồng: Create, Release, Refund, Dispute, Admin, Withdraw
│   ├── EscrowVault.Fuzz.t.sol, EscrowVault.invariant.t.sol, DeployEscrowVault.t.sol
│   ├── handlers/             # handler cho invariant test
│   ├── mocks/                # MockERC20 (6 decimals), FeeOnTransfer, Blacklist, RejectEther, ReentrancyAttacker
│   └── utils/BaseTest.sol    # setup dùng chung
├── script/
│   ├── DeployEscrowVault.s.sol   # deploy testnet/mainnet, tham số đọc từ env
│   └── DeployLocalDemo.s.sol     # chỉ Anvil: deploy USDC giả + vault, ghi địa chỉ cho frontend
├── lib/                      # git submodules: openzeppelin-contracts, forge-std
├── frontend/                 # Giao diện Next.js
│   ├── scripts/sync-abi.mjs  # copy ABI từ out/ sang src/constants
│   └── src/
│       ├── app/              # route: / (tạo escrow, danh sách, số dư), /escrow/[id]; layout, providers
│       ├── components/       # UI: WalletBar, CreateEscrowForm, EscrowDetail, EscrowActions, BalancesPanel...
│       ├── hooks/            # toàn bộ đọc/ghi contract (wagmi): useEscrow, useCreateEscrow, useWithdraw...
│       ├── lib/              # cấu hình wagmi, quy tắc nút theo vai trò, dịch lỗi contract, format
│       ├── constants/        # ABI, địa chỉ theo chainId, deployments/local.json (Anvil)
│       └── types/            # kiểu Escrow, Status, Role
├── docs/                     # tài liệu nghiệp vụ, kỹ thuật, audit, vận hành, thiết kế
└── foundry.toml              # solc, remappings, fuzz/invariant, rpc alias base_sepolia, fs_permissions
```

## 4. Cài đặt & chạy local

**Yêu cầu**
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (repo dùng `1.10.0`): `foundryup`.
- Node.js `>= 18.18` (yêu cầu của Next 15; đã chạy thử với Node 26) và **npm** (repo có `package-lock.json`).
- Git, MetaMask.

**Clone & kiểm tra contract**
```bash
git clone --recurse-submodules https://github.com/ducanh-vn/my-evm-dapp.git
cd my-evm-dapp
forge build
forge test
```
Nếu đã clone mà thiếu `lib/`: `git submodule update --init --recursive`.

**Chạy demo trên Anvil**, mỗi bước một terminal:
```bash
# 1. Blockchain local (giữ terminal này mở)
anvil
```
```bash
# 2. Deploy USDC giả + vault bằng tài khoản unlocked #0 của Anvil (không cần private key)
forge script script/DeployLocalDemo.s.sol --rpc-url http://127.0.0.1:8545 \
  --unlocked --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --broadcast
```
```bash
# 3. Giao diện tại http://localhost:3000
cd frontend
npm install
npm run dev
```
Tiếp theo, trong MetaMask: thêm mạng Anvil (RPC `http://127.0.0.1:8545`, Chain ID `31337`), rồi import ví test #1 (người mua), #2 (người bán), #3 (trọng tài). Chi tiết và các kịch bản thử: [docs/04-van-hanh/chay-local-anvil.md](docs/04-van-hanh/chay-local-anvil.md).

> Script ở bước 2 ghi đè `frontend/src/constants/deployments/local.json` trên máy. Không commit thay đổi đó.

## 5. Biến môi trường

Không có biến cho Auth hay Database. Mọi giá trị đều là địa chỉ công khai, URL hoặc API key. **Không bao giờ đặt private key hay mnemonic trong `.env`.**

**Script deploy** (`.env` ở thư mục gốc, đã bị `.gitignore` chặn; Foundry tự nạp file này):

| Biến | Bắt buộc | Ý nghĩa | Cách lấy |
| :--- | :--- | :--- | :--- |
| `INITIAL_OWNER` | ✓ | Owner của vault. Script yêu cầu địa chỉ có code (Gnosis Safe) | Tạo Safe tại app.safe.global trên đúng mạng |
| `FEE_RECIPIENT` | ✓ | Ví nhận phí | Ví/Safe của dự án |
| `DEFAULT_ARBITER` | ✓ | Trọng tài mặc định | Ví của người phân xử |
| `FEE_BPS` | | Phí khởi tạo (bps), mặc định `100`, tối đa `500` | — |
| `ALLOWED_TOKENS` | | ERC-20 whitelist, cách nhau bởi dấu phẩy; trống = chỉ ETH | Địa chỉ USDC lấy từ tài liệu chính thức của Circle |
| `EXPECTED_CHAIN_ID` | | Chặn deploy nhầm mạng, mặc định `84532` | — |
| `ALLOW_EOA_OWNER` | | `true` cho phép owner là ví thường; chỉ dùng khi thử local | — |
| `BASE_SEPOLIA_RPC_URL` | ✓ khi deploy | RPC Base Sepolia (alias `base_sepolia` trong `foundry.toml`) | RPC công khai `https://sepolia.base.org` hoặc nhà cung cấp RPC |
| `ETHERSCAN_API_KEY` | khi verify | API key để verify trên Basescan | Tài khoản Etherscan (API V2) |

**Script demo local** (tùy chọn): `LOCAL_DEMO_ARBITER` (mặc định ví Anvil #3), `LOCAL_DEMO_USERS` (danh sách nhận USDC giả; mặc định ví #1, #2, #3).

**Frontend** (`frontend/.env.local`, tùy chọn):

| Biến | Mặc định | Ý nghĩa |
| :--- | :--- | :--- |
| `NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL` | RPC công khai của Base | RPC cho trình duyệt. Biến `NEXT_PUBLIC_*` bị lộ ra trình duyệt: không dùng URL chứa API key bí mật |
| `NEXT_PUBLIC_LOCAL_RPC_URL` | `http://127.0.0.1:8545` | RPC Anvil |

Địa chỉ contract không lấy từ env. Base Sepolia nằm trong `frontend/src/constants/addresses.ts`; Anvil nằm trong `deployments/local.json`.

## 6. Scripts & triển khai

**Contract** (thư mục gốc):
```bash
forge build                          # biên dịch
forge test                           # 130 test
forge test --gas-report              # báo cáo gas
forge coverage --report summary --no-match-coverage "(test|script)/"
forge fmt                            # format (CI chạy forge fmt --check)
forge inspect EscrowVault storageLayout
```

**Frontend** (`frontend/`):
```bash
npm run dev        # dev server port 3000
npm run build      # build production
npm run start      # chạy bản build
npm run lint       # kiểm tra kiểu TypeScript (tsc --noEmit)
npm run sync-abi   # cập nhật ABI sau khi sửa contract và chạy forge build
```
Frontend chưa có test tự động.

**Deploy contract** (Base Sepolia đã deploy xong). Ký bằng keystore `--account` hoặc ví cứng `--ledger`, **không** dùng private key dạng chữ:
```bash
cast wallet import deployer --interactive        # một lần
forge script script/DeployEscrowVault.s.sol:DeployEscrowVault --rpc-url base_sepolia \
  --account deployer --sender <DEPLOYER_ADDRESS>                               # mô phỏng
# chạy lại lệnh trên, thêm: --broadcast --verify --etherscan-api-key "$ETHERSCAN_API_KEY"
```
Checklist đầy đủ: [docs/04-van-hanh/deploy-checklist-base-sepolia.md](docs/04-van-hanh/deploy-checklist-base-sepolia.md). Địa chỉ đã deploy: [docs/02-ky-thuat/contract-addresses.md](docs/02-ky-thuat/contract-addresses.md).

**Deploy frontend: chưa thực hiện.** Gợi ý khi làm với Vercel:
- Root Directory = `frontend`, Build Command `npm run build`.
- Chỉ dùng mạng Base Sepolia; nút Anvil và tua thời gian chỉ chạy được trên máy local.
- Nếu đặt `NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL`, đừng dùng URL có API key bí mật.

## Tài liệu

- Nghiệp vụ: [docs/03-san-pham/business-flows.md](docs/03-san-pham/business-flows.md)
- Đặc tả kỹ thuật: [docs/02-ky-thuat/escrow-vault-spec.md](docs/02-ky-thuat/escrow-vault-spec.md)
- Báo cáo audit nội bộ: [docs/02-ky-thuat/audit-report-escrow-vault.md](docs/02-ky-thuat/audit-report-escrow-vault.md). 0 Critical / 0 High; còn mở L-2, L-4, L-6, G-1..G-3.
- Thiết kế giao diện: [docs/06-design/escrow-ui.md](docs/06-design/escrow-ui.md)
- Mục lục: [docs/README.md](docs/README.md)
