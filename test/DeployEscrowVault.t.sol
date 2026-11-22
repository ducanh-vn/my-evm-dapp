// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {EscrowVault} from "../src/EscrowVault.sol";
import {DeployEscrowVault} from "../script/DeployEscrowVault.s.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Chạy logic của script deploy trên EVM local của forge test (không RPC, không broadcast thật).
/// @dev Chỉ `test_Run_FromEnv` đụng tới biến môi trường (env là toàn cục cho cả tiến trình,
///      các test khác dùng `deploy(Config)` trực tiếp để tránh chạy song song bị lẫn).
contract DeployEscrowVaultTest is Test {
    DeployEscrowVault internal script;
    MockERC20 internal usdc;
    MockERC20 internal usdt;

    address internal safe = makeAddr("safe");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal arbiter = makeAddr("arbiter");

    function setUp() public {
        script = new DeployEscrowVault();
        usdc = new MockERC20();
        usdt = new MockERC20();
        vm.etch(safe, hex"00"); // giả lập Safe: địa chỉ có code
        vm.chainId(84_532);
    }

    function _cfg() internal view returns (DeployEscrowVault.Config memory cfg) {
        cfg.initialOwner = safe;
        cfg.feeRecipient = feeRecipient;
        cfg.defaultArbiter = arbiter;
        cfg.feeBps = 100;
        cfg.allowedTokens = new address[](2);
        cfg.allowedTokens[0] = address(usdc);
        cfg.allowedTokens[1] = address(usdt);
        cfg.expectedChainId = 84_532;
        cfg.allowEoaOwner = false;
    }

    function test_Run_FromEnv() public {
        vm.setEnv("INITIAL_OWNER", vm.toString(safe));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        vm.setEnv("DEFAULT_ARBITER", vm.toString(arbiter));
        vm.setEnv("FEE_BPS", "150");
        vm.setEnv("ALLOWED_TOKENS", string.concat(vm.toString(address(usdc)), ",", vm.toString(address(usdt))));
        vm.setEnv("EXPECTED_CHAIN_ID", "84532");
        vm.setEnv("ALLOW_EOA_OWNER", "false");

        DeployEscrowVault.Config memory cfg = script.readConfig();
        assertEq(cfg.initialOwner, safe);
        assertEq(cfg.feeBps, 150);
        assertEq(cfg.allowedTokens.length, 2);
        assertEq(cfg.allowedTokens[1], address(usdt));

        EscrowVault vault = script.run();
        assertEq(vault.owner(), safe);
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.defaultArbiter(), arbiter);
        assertEq(vault.feeBps(), 150);
        assertTrue(vault.isTokenAllowed(address(usdc)));
        assertTrue(vault.isTokenAllowed(address(usdt)));
        assertFalse(vault.paused());

        // Danh sách token rỗng = chỉ ETH; FEE_BPS quá trần bị chặn khi đọc env.
        vm.setEnv("ALLOWED_TOKENS", "");
        assertEq(script.readConfig().allowedTokens.length, 0);
        vm.setEnv("FEE_BPS", "501");
        vm.expectRevert(abi.encodeWithSelector(DeployEscrowVault.FeeBpsTooHigh.selector, 501));
        script.readConfig();
    }

    function test_Deploy_Succeeds() public {
        EscrowVault vault = script.deploy(_cfg());
        assertEq(vault.owner(), safe);
        assertEq(vault.nextEscrowId(), 0);
        script.verifyDeployment(vault, _cfg());
    }

    function test_Deploy_EthOnly() public {
        DeployEscrowVault.Config memory cfg = _cfg();
        cfg.allowedTokens = new address[](0);
        EscrowVault vault = script.deploy(cfg);
        assertFalse(vault.isTokenAllowed(address(usdc)));
    }

    function test_RevertWhen_WrongChain() public {
        vm.chainId(8453); // Base Mainnet
        vm.expectRevert(abi.encodeWithSelector(DeployEscrowVault.WrongChain.selector, 84_532, 8453));
        script.deploy(_cfg());
    }

    function test_ChainOverride() public {
        vm.chainId(31_337);
        DeployEscrowVault.Config memory cfg = _cfg();
        cfg.expectedChainId = 31_337;
        script.deploy(cfg);
    }

    function test_RevertWhen_ZeroAddresses() public {
        DeployEscrowVault.Config memory cfg = _cfg();
        cfg.initialOwner = address(0);
        vm.expectRevert(abi.encodeWithSelector(DeployEscrowVault.ZeroAddressParam.selector, "INITIAL_OWNER"));
        script.deploy(cfg);

        cfg = _cfg();
        cfg.feeRecipient = address(0);
        vm.expectRevert(abi.encodeWithSelector(DeployEscrowVault.ZeroAddressParam.selector, "FEE_RECIPIENT"));
        script.deploy(cfg);

        cfg = _cfg();
        cfg.defaultArbiter = address(0);
        vm.expectRevert(abi.encodeWithSelector(DeployEscrowVault.ZeroAddressParam.selector, "DEFAULT_ARBITER"));
        script.deploy(cfg);

        cfg = _cfg();
        cfg.allowedTokens[0] = address(0);
        vm.expectRevert(abi.encodeWithSelector(DeployEscrowVault.ZeroAddressParam.selector, "ALLOWED_TOKENS"));
        script.deploy(cfg);
    }

    function test_RevertWhen_FeeTooHigh() public {
        DeployEscrowVault.Config memory cfg = _cfg();
        cfg.feeBps = 501;
        vm.expectRevert(abi.encodeWithSelector(DeployEscrowVault.FeeBpsTooHigh.selector, 501));
        script.deploy(cfg);
    }

    function test_RevertWhen_OwnerIsEoa_UnlessAllowed() public {
        DeployEscrowVault.Config memory cfg = _cfg();
        address eoa = makeAddr("eoa");
        cfg.initialOwner = eoa;
        vm.expectRevert(abi.encodeWithSelector(DeployEscrowVault.OwnerNotContract.selector, eoa));
        script.deploy(cfg);

        cfg.allowEoaOwner = true;
        assertEq(script.deploy(cfg).owner(), eoa);
    }

    function test_RevertWhen_TokenHasNoCode() public {
        DeployEscrowVault.Config memory cfg = _cfg();
        address fake = makeAddr("fakeToken");
        cfg.allowedTokens[1] = fake;
        vm.expectRevert(abi.encodeWithSelector(DeployEscrowVault.TokenNotContract.selector, fake));
        script.deploy(cfg);
    }

    function test_RevertWhen_DuplicateToken() public {
        DeployEscrowVault.Config memory cfg = _cfg();
        cfg.allowedTokens[1] = address(usdc);
        vm.expectRevert(abi.encodeWithSelector(DeployEscrowVault.DuplicateToken.selector, address(usdc)));
        script.deploy(cfg);
    }

    function test_RevertWhen_VerifyDetectsMismatch() public {
        EscrowVault vault = script.deploy(_cfg());
        DeployEscrowVault.Config memory other = _cfg();
        other.feeBps = 200;
        vm.expectRevert(abi.encodeWithSelector(DeployEscrowVault.DeploymentMismatch.selector, "feeBps"));
        script.verifyDeployment(vault, other);
    }
}
