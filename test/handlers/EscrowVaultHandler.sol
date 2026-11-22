// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {EscrowVault} from "../../src/EscrowVault.sol";
import {IEscrowVault} from "../../src/interfaces/IEscrowVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Handler cho invariant test: gọi ngẫu nhiên mọi hàm với nhiều Buyer/Seller/Arbiter.
/// @dev Mảng `ids` chỉ tồn tại trong test để duyệt escrow khi kiểm tra invariant.
contract EscrowVaultHandler is Test {
    EscrowVault public immutable vault;
    MockERC20 public immutable usdc;
    address public immutable owner;
    address public immutable initialFeeRecipient;

    address[] public actors;
    uint256 public ghostEthEscrows;
    address[] public arbiters;
    uint256[] public ids;

    mapping(uint256 id => address) public ghostArbiter;
    mapping(uint256 id => IEscrowVault.Status) public ghostTerminal;
    bool public ghostTimeoutClaimFailed;
    bool public ghostAdminReducedFunds;
    bool public ghostEarlySellerRelease;

    mapping(bytes32 => uint256) public calls;

    constructor(EscrowVault vault_, MockERC20 usdc_, address owner_) {
        vault = vault_;
        usdc = usdc_;
        owner = owner_;
        initialFeeRecipient = vault_.feeRecipient();
        for (uint256 i; i < 4; ++i) {
            address a = makeAddr(string.concat("actor", vm.toString(i)));
            actors.push(a);
            vm.deal(a, 1e30);
            usdc.mint(a, 1e30);
            vm.prank(a);
            usdc.approve(address(vault), type(uint256).max);
        }
        // Handler tự gửi ETH khi gọi createEscrow (vm.prank chỉ đổi msg.sender).
        vm.deal(address(this), 1e30);
        arbiters.push(vault.defaultArbiter());
        arbiters.push(makeAddr("arb1"));
        arbiters.push(makeAddr("arb2"));
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function idsLength() external view returns (uint256) {
        return ids.length;
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function arbitersLength() external view returns (uint256) {
        return arbiters.length;
    }

    function _pickId(uint256 seed) internal view returns (uint256) {
        if (ids.length == 0) return 0;
        return ids[seed % ids.length];
    }

    /// @dev Tìm escrow Disputed đầu tiên kể từ vị trí ngẫu nhiên (mảng chỉ có trong test, kích thước ≤ depth).
    function _findDisputed(uint256 seed) internal view returns (uint256) {
        uint256 n = ids.length;
        for (uint256 k; k < n; ++k) {
            uint256 candidate = ids[(seed % n + k) % n];
            if (vault.getEscrow(candidate).status == IEscrowVault.Status.Disputed) return candidate;
        }
        return 0;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    enum Role {
        Buyer,
        Seller,
        Arbiter
    }

    /// @dev 50% gọi bằng vai trò hợp lệ chính của hàm; còn lại chọn ngẫu nhiên Buyer/Seller/Arbiter/actor bất kỳ.
    function _caller(uint256 id, uint256 seed, Role intended) internal view returns (address) {
        IEscrowVault.Escrow memory e = vault.getEscrow(id);
        uint256 r = seed % 8;
        if (r < 4) r = uint256(intended);
        else r -= 4;
        if (r == 0) return e.buyer;
        if (r == 1) return e.seller;
        if (r == 2) return e.arbiter;
        return _actor(seed >> 8);
    }

    function _recordTerminal(uint256 id) internal {
        IEscrowVault.Status s = vault.getEscrow(id).status;
        if (s == IEscrowVault.Status.Released || s == IEscrowVault.Status.Refunded || s == IEscrowVault.Status.Resolved)
        {
            if (ghostTerminal[id] == IEscrowVault.Status.None) ghostTerminal[id] = s;
        }
    }

    function _sumWithdrawable() internal view returns (uint256 total) {
        address[2] memory tokens = [address(0), address(usdc)];
        for (uint256 t; t < 2; ++t) {
            for (uint256 i; i < actors.length; ++i) {
                total += vault.withdrawable(actors[i], tokens[t]);
            }
            total += vault.withdrawable(initialFeeRecipient, tokens[t]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             USER ACTIONS
    //////////////////////////////////////////////////////////////*/

    function createEscrow(
        uint256 buyerSeed,
        uint256 sellerSeed,
        uint256 arbSeed,
        bool useEth,
        uint256 amount,
        uint48 period
    ) external {
        address buyer = _actor(buyerSeed);
        address seller = _actor(sellerSeed);
        if (buyer == seller) seller = _actor(sellerSeed + 1);
        address arb = arbSeed % 4 == 3 ? address(0) : arbiters[arbSeed % arbiters.length];
        amount = bound(amount, 1, 1e24);
        period = uint48(bound(period, 1 days, 90 days));
        address token = useEth ? address(0) : address(usdc);

        vm.prank(buyer);
        try vault.createEscrow{value: useEth ? amount : 0}(seller, token, amount, period, arb, 500) returns (
            uint256 id
        ) {
            ids.push(id);
            ghostArbiter[id] = vault.getEscrow(id).arbiter;
            if (useEth) ghostEthEscrows++;
            calls["create"]++;
        } catch {}
    }

    function markDelivered(uint256 idSeed, uint256 callerSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        vm.prank(_caller(id, callerSeed, Role.Seller));
        try vault.markDelivered(id) {
            calls["deliver"]++;
        } catch {}
    }

    function release(uint256 idSeed, uint256 callerSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        IEscrowVault.Escrow memory e = vault.getEscrow(id);
        address caller = _caller(id, callerSeed, Role.Buyer);
        vm.prank(caller);
        try vault.release(id) {
            calls["release"]++;
            // Audit M-1: Seller tự giải ngân chỉ hợp lệ khi đã qua cả disputeDeadline và deliveryDeadline.
            if (caller == e.seller) {
                uint256 end = e.disputeDeadline > e.deliveryDeadline ? e.disputeDeadline : e.deliveryDeadline;
                if (vm.getBlockTimestamp() <= end) ghostEarlySellerRelease = true;
            }
        } catch {}
        _recordTerminal(id);
    }

    function refund(uint256 idSeed, uint256 callerSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        vm.prank(_caller(id, callerSeed, Role.Seller));
        try vault.refund(id) {
            calls["refund"]++;
        } catch {}
        _recordTerminal(id);
    }

    function raiseDispute(uint256 idSeed, uint256 callerSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        vm.prank(_caller(id, callerSeed, Role.Buyer));
        try vault.raiseDispute(id) {
            calls["dispute"]++;
        } catch {}
    }

    function resolveDispute(uint256 idSeed, uint256 callerSeed, uint16 buyerBps) external {
        uint256 id = _findDisputed(idSeed);
        if (id == 0) return;
        buyerBps = uint16(bound(buyerBps, 0, 10_000));
        vm.prank(_caller(id, callerSeed, Role.Arbiter));
        try vault.resolveDispute(id, buyerBps) {
            calls["resolve"]++;
        } catch {}
        _recordTerminal(id);
    }

    function claimTimeoutRefund(uint256 idSeed, uint256 callerSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        vm.prank(_caller(id, callerSeed, Role.Buyer));
        try vault.claimTimeoutRefund(id) {
            calls["timeout"]++;
        } catch {}
        _recordTerminal(id);
    }

    /// @dev Invariant 6: escrow `Disputed` quá hạn thì Buyer luôn claim được.
    function forceTimeoutClaim(uint256 idSeed) external {
        uint256 id = _findDisputed(idSeed);
        if (id == 0) return;
        IEscrowVault.Escrow memory e = vault.getEscrow(id);
        if (block.timestamp <= e.arbitrationDeadline) vm.warp(uint256(e.arbitrationDeadline) + 1);
        vm.prank(e.buyer);
        try vault.claimTimeoutRefund(id) {
            calls["forceTimeout"]++;
        } catch {
            ghostTimeoutClaimFailed = true;
        }
        _recordTerminal(id);
    }

    function withdraw(uint256 actorSeed, bool eth) external {
        address who = actorSeed % 5 == 4 ? vault.feeRecipient() : _actor(actorSeed);
        address token = eth ? address(0) : address(usdc);
        vm.prank(who);
        if (actorSeed % 3 == 0) {
            // Audit L-3: rút hộ sang một actor khác (vẫn là ví được theo dõi).
            try vault.withdrawTo(token, _actor(actorSeed >> 8)) {
                calls["withdrawTo"]++;
            } catch {}
        } else {
            try vault.withdraw(token) {
                calls["withdraw"]++;
            } catch {}
        }
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, 4 days));
        calls["warp"]++;
    }

    /*//////////////////////////////////////////////////////////////
                             ADMIN ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Invariant 5: mọi thao tác admin không làm giảm số dư chờ rút của ai.
    function adminAction(uint256 seed, uint16 newFee) external {
        uint256 before = _sumWithdrawable();
        uint256 r = seed % 5;
        vm.startPrank(owner);
        // Trạng thái pause chỉ kéo dài tới lần gọi admin kế tiếp, để phần lớn thời gian vẫn tạo được escrow.
        if (vault.paused()) vault.unpause();
        if (r == 0) {
            try vault.setFeeBps(uint16(bound(newFee, 0, 500))) {} catch {}
        } else if (r == 1) {
            vault.setDefaultArbiter(arbiters[1 + (seed >> 8) % 2]);
        } else if (r == 2) {
            vault.pause();
        } else if (r == 3) {
            // Dùng hash vì fuzzer hay sinh seed nhỏ (0, 1...), tránh whitelist bị tắt gần như mọi lúc.
            vault.setTokenAllowed(address(usdc), uint256(keccak256(abi.encode(seed))) % 4 != 0);
        } else {
            // feeRecipient chỉ đổi giữa các ví đã được theo dõi trong _sumWithdrawable.
            vault.setFeeRecipient(_actor(seed >> 8));
        }
        vm.stopPrank();
        if (_sumWithdrawable() < before) ghostAdminReducedFunds = true;
        calls["admin"]++;
    }
}
