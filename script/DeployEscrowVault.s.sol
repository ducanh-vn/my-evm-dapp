// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {EscrowVault} from "../src/EscrowVault.sol";

/**
 * @title DeployEscrowVault
 * @notice Script deploy EscrowVault. Mọi tham số đọc từ biến môi trường; không có private key,
 *         không hardcode địa chỉ token hay ví trong code.
 * @dev Biến môi trường (xem `.env.example`):
 *      - `INITIAL_OWNER`     (bắt buộc) Gnosis Safe multisig, phải là contract trừ khi `ALLOW_EOA_OWNER=true`.
 *      - `FEE_RECIPIENT`     (bắt buộc) ví nhận phí.
 *      - `DEFAULT_ARBITER`   (bắt buộc) trọng tài mặc định.
 *      - `FEE_BPS`           (tùy chọn, mặc định 100) phí khởi tạo, ≤ 500.
 *      - `ALLOWED_TOKENS`    (tùy chọn) danh sách ERC-20 cách nhau bởi dấu phẩy; để trống = chỉ ETH.
 *      - `EXPECTED_CHAIN_ID` (tùy chọn, mặc định 84532 Base Sepolia) chặn deploy nhầm mạng.
 *      - `ALLOW_EOA_OWNER`   (tùy chọn, mặc định false) chỉ dùng khi thử nghiệm local.
 *
 *      Ký giao dịch bằng `--account <keystore>` hoặc `--ledger`/`--trezor`; KHÔNG dùng `--private-key`.
 *      Mô phỏng (không gửi giao dịch):
 *        forge script script/DeployEscrowVault.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --account <name>
 */
contract DeployEscrowVault is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84_532;
    uint16 internal constant DEFAULT_FEE_BPS = 100;

    struct Config {
        address initialOwner;
        address feeRecipient;
        address defaultArbiter;
        uint16 feeBps;
        address[] allowedTokens;
        uint256 expectedChainId;
        bool allowEoaOwner;
    }

    error WrongChain(uint256 expected, uint256 actual);
    error ZeroAddressParam(string name);
    error FeeBpsTooHigh(uint256 bps);
    error OwnerNotContract(address owner);
    error TokenNotContract(address token);
    error DuplicateToken(address token);
    error DeploymentMismatch(string field);

    /// @notice Điểm vào của `forge script`: đọc env, kiểm tra, deploy, kiểm tra sau deploy.
    function run() external returns (EscrowVault vault) {
        vault = deploy(readConfig());
    }

    /// @notice Đọc cấu hình từ biến môi trường.
    function readConfig() public view returns (Config memory cfg) {
        cfg.initialOwner = vm.envAddress("INITIAL_OWNER");
        cfg.feeRecipient = vm.envAddress("FEE_RECIPIENT");
        cfg.defaultArbiter = vm.envAddress("DEFAULT_ARBITER");

        uint256 fee = vm.envOr("FEE_BPS", uint256(DEFAULT_FEE_BPS));
        if (fee > 500) revert FeeBpsTooHigh(fee);
        // forge-lint: disable-next-line(unsafe-typecast)
        cfg.feeBps = uint16(fee); // an toàn: đã kiểm tra fee <= 500

        string memory rawTokens = vm.envOr("ALLOWED_TOKENS", string(""));
        cfg.allowedTokens = bytes(rawTokens).length == 0 ? new address[](0) : vm.envAddress("ALLOWED_TOKENS", ",");

        cfg.expectedChainId = vm.envOr("EXPECTED_CHAIN_ID", BASE_SEPOLIA_CHAIN_ID);
        cfg.allowEoaOwner = vm.envOr("ALLOW_EOA_OWNER", false);
    }

    /// @notice Kiểm tra cấu hình trước khi deploy.
    function validate(Config memory cfg) public view {
        if (block.chainid != cfg.expectedChainId) revert WrongChain(cfg.expectedChainId, block.chainid);
        if (cfg.initialOwner == address(0)) revert ZeroAddressParam("INITIAL_OWNER");
        if (cfg.feeRecipient == address(0)) revert ZeroAddressParam("FEE_RECIPIENT");
        if (cfg.defaultArbiter == address(0)) revert ZeroAddressParam("DEFAULT_ARBITER");
        if (cfg.feeBps > 500) revert FeeBpsTooHigh(cfg.feeBps);
        if (!cfg.allowEoaOwner && cfg.initialOwner.code.length == 0) revert OwnerNotContract(cfg.initialOwner);

        uint256 n = cfg.allowedTokens.length;
        for (uint256 i; i < n; ++i) {
            address token = cfg.allowedTokens[i];
            if (token == address(0)) revert ZeroAddressParam("ALLOWED_TOKENS");
            if (token.code.length == 0) revert TokenNotContract(token);
            for (uint256 j; j < i; ++j) {
                if (cfg.allowedTokens[j] == token) revert DuplicateToken(token);
            }
        }
    }

    /// @notice Kiểm tra, deploy và xác nhận trạng thái sau deploy.
    function deploy(Config memory cfg) public returns (EscrowVault vault) {
        validate(cfg);
        _logConfig(cfg);

        vm.startBroadcast();
        vault = new EscrowVault(cfg.initialOwner, cfg.feeRecipient, cfg.defaultArbiter, cfg.feeBps, cfg.allowedTokens);
        vm.stopBroadcast();

        verifyDeployment(vault, cfg);
        console2.log("EscrowVault deployed at:", address(vault));
    }

    /// @notice Xác nhận trạng thái contract vừa deploy khớp cấu hình.
    function verifyDeployment(EscrowVault vault, Config memory cfg) public view {
        if (address(vault).code.length == 0) revert DeploymentMismatch("code");
        if (vault.owner() != cfg.initialOwner) revert DeploymentMismatch("owner");
        if (vault.pendingOwner() != address(0)) revert DeploymentMismatch("pendingOwner");
        if (vault.feeRecipient() != cfg.feeRecipient) revert DeploymentMismatch("feeRecipient");
        if (vault.defaultArbiter() != cfg.defaultArbiter) revert DeploymentMismatch("defaultArbiter");
        if (vault.feeBps() != cfg.feeBps) revert DeploymentMismatch("feeBps");
        if (vault.paused()) revert DeploymentMismatch("paused");
        if (vault.nextEscrowId() != 0) revert DeploymentMismatch("nextEscrowId");
        uint256 n = cfg.allowedTokens.length;
        for (uint256 i; i < n; ++i) {
            if (!vault.isTokenAllowed(cfg.allowedTokens[i])) revert DeploymentMismatch("allowedTokens");
        }
    }

    function _logConfig(Config memory cfg) internal pure {
        console2.log("== EscrowVault deploy config ==");
        console2.log("chainId (expected):", cfg.expectedChainId);
        console2.log("initialOwner      :", cfg.initialOwner);
        console2.log("feeRecipient      :", cfg.feeRecipient);
        console2.log("defaultArbiter    :", cfg.defaultArbiter);
        console2.log("feeBps            :", uint256(cfg.feeBps));
        console2.log("allowedTokens     :", cfg.allowedTokens.length);
        for (uint256 i; i < cfg.allowedTokens.length; ++i) {
            console2.log("  token:", cfg.allowedTokens[i]);
        }
        if (cfg.allowedTokens.length == 0) console2.log("  (khong co ERC-20, chi ETH)");
        if (cfg.allowEoaOwner) console2.log("CANH BAO: ALLOW_EOA_OWNER=true, owner co the la EOA");
    }
}
