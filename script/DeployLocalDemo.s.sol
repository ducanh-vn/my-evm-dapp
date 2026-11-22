// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {EscrowVault} from "../src/EscrowVault.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/**
 * @title DeployLocalDemo
 * @notice CHỈ dùng cho Anvil local (chain 31337): deploy USDC giả (6 decimals) + EscrowVault,
 *         mint USDC cho các ví demo và ghi địa chỉ vào `frontend/src/constants/deployments/local.json`
 *         để giao diện tự nhận.
 * @dev Không có private key: chạy với tài khoản đã mở khóa sẵn của Anvil.
 *        anvil
 *        forge script script/DeployLocalDemo.s.sol --rpc-url http://127.0.0.1:8545 \
 *          --unlocked --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --broadcast
 *      Vai trò mặc định (các ví test công khai của Anvil, chỉ có trên máy local):
 *        #0 = owner + ví nhận phí, #1 = người mua, #2 = người bán, #3 = trọng tài mặc định.
 *      Đổi bằng env: LOCAL_DEMO_ARBITER, LOCAL_DEMO_USERS (danh sách nhận USDC, cách nhau bởi dấu phẩy).
 */
contract DeployLocalDemo is Script {
    uint256 internal constant ANVIL_CHAIN_ID = 31_337;
    string internal constant OUT_FILE = "./frontend/src/constants/deployments/local.json";
    uint256 internal constant MINT_PER_USER = 10_000e6; // 10.000 USDC giả

    // Ví test mặc định của Anvil (mnemonic công khai "test test ... junk"), KHÔNG dùng ngoài local.
    address internal constant ANVIL_1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address internal constant ANVIL_2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address internal constant ANVIL_3 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    error NotAnvil(uint256 chainId);

    function run() external returns (EscrowVault vault, MockERC20 usdc) {
        if (block.chainid != ANVIL_CHAIN_ID) revert NotAnvil(block.chainid);

        address admin = msg.sender;
        address arbiter = vm.envOr("LOCAL_DEMO_ARBITER", ANVIL_3);
        address[] memory defaults = new address[](3);
        defaults[0] = ANVIL_1;
        defaults[1] = ANVIL_2;
        defaults[2] = ANVIL_3;
        address[] memory users = vm.envOr("LOCAL_DEMO_USERS", ",", defaults);
        uint256 startBlock = vm.getBlockNumber();

        vm.startBroadcast();
        usdc = new MockERC20();
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        vault = new EscrowVault(admin, admin, arbiter, 100, tokens);
        for (uint256 i; i < users.length; ++i) {
            usdc.mint(users[i], MINT_PER_USER);
        }
        vm.stopBroadcast();

        string memory key = "local";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeAddress(key, "escrowVault", address(vault));
        vm.serializeAddress(key, "usdc", address(usdc));
        string memory json = vm.serializeUint(key, "deployBlock", startBlock);
        vm.writeJson(json, OUT_FILE);

        console2.log("EscrowVault :", address(vault));
        console2.log("USDC (mock) :", address(usdc));
        console2.log("Owner/fee   :", admin);
        console2.log("Arbiter     :", arbiter);
        console2.log("Da ghi dia chi vao", OUT_FILE);
    }
}
