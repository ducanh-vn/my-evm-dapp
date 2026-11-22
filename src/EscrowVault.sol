// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IEscrowVault} from "./interfaces/IEscrowVault.sol";

/**
 * @title EscrowVault
 * @notice Ký quỹ thanh toán P2P: Buyer khóa ETH/ERC-20, Seller nhận tiền khi Buyer xác nhận,
 *         khi hết thời gian khiếu nại, hoặc theo phán quyết của Arbiter.
 * @dev Bất biến (không Proxy). Owner (Gnosis Safe) chỉ quản lý tham số cho escrow mới và `pause`;
 *      không có hàm nào cho owner chạm vào tiền ký quỹ hay số dư chờ rút.
 *      Mọi khoản tiền ra đi qua `withdrawable` (pull payment).
 */
contract EscrowVault is IEscrowVault, Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Trần phí 5%.
    uint16 public constant MAX_FEE_BPS = 500;
    /// @notice Mẫu số bps.
    uint16 public constant BPS_DENOMINATOR = 10_000;
    /// @notice Thời hạn giao hàng tối thiểu.
    uint48 public constant MIN_DELIVERY_PERIOD = 1 hours;
    /// @notice Thời hạn giao hàng tối đa.
    uint48 public constant MAX_DELIVERY_PERIOD = 90 days;
    /// @notice Thời gian khiếu nại sau khi Seller báo giao hàng.
    uint48 public constant DISPUTE_WINDOW = 3 days;
    /// @notice Thời hạn Arbiter phán quyết, tính từ lúc mở tranh chấp.
    uint48 public constant ARBITRATION_TIMEOUT = 14 days;
    /// @notice Ký hiệu ETH.
    address public constant NATIVE_TOKEN = address(0);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 id => Escrow) internal _escrows;

    /// @notice Số dư chờ rút theo người dùng và tài sản.
    mapping(address user => mapping(address token => uint256)) public withdrawable;

    /// @notice Whitelist ERC-20 (ETH luôn được phép, không nằm trong mapping).
    mapping(address token => bool) public isTokenAllowed;

    /// @notice Id của escrow tạo gần nhất (escrow đầu tiên có id 1).
    uint256 public nextEscrowId;

    /// @notice Ví nhận phí (cùng slot với `feeBps`).
    address public feeRecipient;
    /// @notice Phí hiện hành cho escrow mới.
    uint16 public feeBps;

    /// @notice Trọng tài hệ thống, dùng khi người tạo không chỉ định.
    address public defaultArbiter;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param initialOwner Ví Gnosis Safe quản trị.
     * @param feeRecipient_ Ví nhận phí.
     * @param defaultArbiter_ Trọng tài mặc định.
     * @param feeBps_ Phí khởi tạo (≤ 500).
     * @param allowedTokens Danh sách ERC-20 ban đầu (truyền từ script deploy, không hardcode).
     */
    constructor(
        address initialOwner,
        address feeRecipient_,
        address defaultArbiter_,
        uint16 feeBps_,
        address[] memory allowedTokens
    ) Ownable(initialOwner) {
        if (feeRecipient_ == address(0) || defaultArbiter_ == address(0)) revert ZeroAddress();
        if (feeBps_ > MAX_FEE_BPS) revert FeeTooHigh(feeBps_);

        feeRecipient = feeRecipient_;
        feeBps = feeBps_;
        defaultArbiter = defaultArbiter_;
        emit FeeRecipientUpdated(address(0), feeRecipient_);
        emit FeeUpdated(0, feeBps_);
        emit DefaultArbiterUpdated(address(0), defaultArbiter_);

        // Vòng lặp chỉ chạy một lần lúc deploy, trên danh sách do admin cung cấp.
        uint256 len = allowedTokens.length;
        for (uint256 i; i < len; ++i) {
            address token = allowedTokens[i];
            if (token == address(0)) revert ZeroAddress();
            isTokenAllowed[token] = true;
            emit TokenAllowlistUpdated(token, true);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEscrowVault
    function createEscrow(address seller, address token, uint256 amount, uint48 deliveryPeriod, address arbiter)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 id)
    {
        // Checks
        if (seller == address(0)) revert ZeroAddress();
        if (seller == msg.sender) revert InvalidSeller();
        if (amount == 0) revert ZeroAmount();
        if (deliveryPeriod < MIN_DELIVERY_PERIOD || deliveryPeriod > MAX_DELIVERY_PERIOD) {
            revert InvalidDeliveryPeriod(deliveryPeriod);
        }
        address arbiterFinal = arbiter == address(0) ? defaultArbiter : arbiter;
        if (arbiterFinal == msg.sender || arbiterFinal == seller) revert InvalidArbiter();

        bool isNative = token == NATIVE_TOKEN;
        if (isNative) {
            if (msg.value != amount) revert InvalidMsgValue(amount, msg.value);
        } else {
            if (msg.value != 0) revert InvalidMsgValue(0, msg.value);
            if (!isTokenAllowed[token]) revert TokenNotAllowed(token);
        }

        // Effects
        id = ++nextEscrowId;
        uint16 lockedFee = feeBps;
        // casting to 'uint48' is safe: uint48 seconds overflow in year ~8.9 million
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 deliveryDeadline = uint48(block.timestamp) + deliveryPeriod;
        _escrows[id] = Escrow({
            buyer: msg.sender,
            deliveryDeadline: deliveryDeadline,
            feeBps: lockedFee,
            status: Status.Funded,
            seller: seller,
            disputeDeadline: 0,
            arbiter: arbiterFinal,
            arbitrationDeadline: 0,
            token: token,
            amount: amount
        });

        // Interactions (ERC-20): đo số tiền thực nhận để chặn token fee-on-transfer.
        if (!isNative) {
            IERC20 erc20 = IERC20(token);
            uint256 balanceBefore = erc20.balanceOf(address(this));
            erc20.safeTransferFrom(msg.sender, address(this), amount);
            uint256 received = erc20.balanceOf(address(this)) - balanceBefore;
            if (received != amount) revert AmountMismatch(amount, received);
        }

        emit EscrowCreated(id, msg.sender, seller, token, arbiterFinal, amount, lockedFee, deliveryDeadline);
    }

    /// @inheritdoc IEscrowVault
    function markDelivered(uint256 id) external {
        Escrow storage e = _load(id);
        if (msg.sender != e.seller) revert Unauthorized();
        _requireStatus(id, e, Status.Funded);
        if (block.timestamp > e.deliveryDeadline) revert DeadlinePassed();

        // casting to 'uint48' is safe: uint48 seconds overflow in year ~8.9 million
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 disputeDeadline = uint48(block.timestamp) + DISPUTE_WINDOW;
        e.status = Status.Delivered;
        e.disputeDeadline = disputeDeadline;

        emit EscrowDelivered(id, disputeDeadline);
    }

    /// @inheritdoc IEscrowVault
    function release(uint256 id) external nonReentrant {
        Escrow storage e = _load(id);
        Status status = e.status;

        if (msg.sender == e.buyer) {
            if (status != Status.Funded && status != Status.Delivered) revert InvalidStatus(id, status);
        } else if (msg.sender == e.seller) {
            _requireStatus(id, e, Status.Delivered);
            // Audit M-1: Seller chỉ tự giải ngân khi đã qua CẢ disputeDeadline VÀ deliveryDeadline.
            if (block.timestamp <= _disputeWindowEnd(e)) revert DeadlineNotReached();
        } else {
            revert Unauthorized();
        }

        e.status = Status.Released;
        uint256 amount = e.amount;
        address token = e.token;
        uint256 fee = Math.mulDiv(amount, e.feeBps, BPS_DENOMINATOR);
        uint256 sellerAmount = amount - fee;
        _credit(e.seller, token, sellerAmount);
        _credit(feeRecipient, token, fee);

        emit EscrowReleased(id, msg.sender, sellerAmount, fee);
    }

    /// @inheritdoc IEscrowVault
    function refund(uint256 id) external nonReentrant {
        Escrow storage e = _load(id);
        Status status = e.status;

        if (msg.sender == e.seller) {
            if (status != Status.Funded && status != Status.Delivered && status != Status.Disputed) {
                revert InvalidStatus(id, status);
            }
        } else if (msg.sender == e.buyer) {
            _requireStatus(id, e, Status.Funded);
            if (block.timestamp <= e.deliveryDeadline) revert DeadlineNotReached();
        } else {
            revert Unauthorized();
        }

        _refundBuyer(id, e);
    }

    /// @inheritdoc IEscrowVault
    function raiseDispute(uint256 id) external {
        Escrow storage e = _load(id);
        if (msg.sender != e.buyer && msg.sender != e.seller) revert Unauthorized();

        Status status = e.status;
        if (status == Status.Funded) {
            if (block.timestamp > e.deliveryDeadline) revert DeadlinePassed();
        } else if (status == Status.Delivered) {
            // Cùng mốc với Seller tự giải ngân: không có khoảng trống, không chồng lấn.
            if (block.timestamp > _disputeWindowEnd(e)) revert DeadlinePassed();
        } else {
            revert InvalidStatus(id, status);
        }

        // casting to 'uint48' is safe: uint48 seconds overflow in year ~8.9 million
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 arbitrationDeadline = uint48(block.timestamp) + ARBITRATION_TIMEOUT;
        e.status = Status.Disputed;
        e.arbitrationDeadline = arbitrationDeadline;

        emit DisputeRaised(id, msg.sender, arbitrationDeadline);
    }

    /// @inheritdoc IEscrowVault
    function resolveDispute(uint256 id, uint16 buyerBps) external nonReentrant {
        Escrow storage e = _load(id);
        if (msg.sender != e.arbiter) revert Unauthorized();
        _requireStatus(id, e, Status.Disputed);
        if (block.timestamp > e.arbitrationDeadline) revert DeadlinePassed();
        if (buyerBps > BPS_DENOMINATOR) revert InvalidBps(buyerBps);

        e.status = Status.Resolved;
        uint256 amount = e.amount;
        address token = e.token;
        uint256 buyerAmount = Math.mulDiv(amount, buyerBps, BPS_DENOMINATOR);
        uint256 sellerGross = amount - buyerAmount; // phần dư làm tròn thuộc Seller
        uint256 fee = Math.mulDiv(sellerGross, e.feeBps, BPS_DENOMINATOR);
        uint256 sellerAmount = sellerGross - fee;
        _credit(e.buyer, token, buyerAmount);
        _credit(e.seller, token, sellerAmount);
        _credit(feeRecipient, token, fee);

        emit DisputeResolved(id, msg.sender, buyerBps, buyerAmount, sellerAmount, fee);
    }

    /// @inheritdoc IEscrowVault
    function claimTimeoutRefund(uint256 id) external nonReentrant {
        Escrow storage e = _load(id);
        if (msg.sender != e.buyer) revert Unauthorized();
        _requireStatus(id, e, Status.Disputed);
        if (block.timestamp <= e.arbitrationDeadline) revert DeadlineNotReached();

        _refundBuyer(id, e);
    }

    /// @inheritdoc IEscrowVault
    function withdraw(address token) external nonReentrant {
        // Checks
        uint256 bal = withdrawable[msg.sender][token];
        if (bal == 0) revert NothingToWithdraw();

        // Effects
        withdrawable[msg.sender][token] = 0;

        // Event phát trước Interaction; nếu chuyển tiền revert thì log cũng bị hủy.
        emit Withdrawn(msg.sender, token, bal);

        // Interactions
        if (token == NATIVE_TOKEN) {
            (bool ok,) = msg.sender.call{value: bal}("");
            if (!ok) revert EthTransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, bal);
        }
    }

    /// @inheritdoc IEscrowVault
    function getEscrow(uint256 id) external view returns (Escrow memory) {
        return _escrows[id];
    }

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEscrowVault
    function setFeeBps(uint16 newBps) external onlyOwner {
        if (newBps > MAX_FEE_BPS) revert FeeTooHigh(newBps);
        uint16 oldBps = feeBps;
        feeBps = newBps;
        emit FeeUpdated(oldBps, newBps);
    }

    /// @inheritdoc IEscrowVault
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        address old = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(old, newRecipient);
    }

    /// @inheritdoc IEscrowVault
    function setDefaultArbiter(address newArbiter) external onlyOwner {
        if (newArbiter == address(0)) revert ZeroAddress();
        address old = defaultArbiter;
        defaultArbiter = newArbiter;
        emit DefaultArbiterUpdated(old, newArbiter);
    }

    /// @inheritdoc IEscrowVault
    function setTokenAllowed(address token, bool allowed) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        isTokenAllowed[token] = allowed;
        emit TokenAllowlistUpdated(token, allowed);
    }

    /// @inheritdoc IEscrowVault
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IEscrowVault
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Vô hiệu hóa: contract luôn phải có owner (Multisig).
     * @dev Luôn revert `RenounceDisabled`.
     */
    function renounceOwnership() public pure override {
        revert RenounceDisabled();
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Trả về con trỏ storage của escrow; revert nếu không tồn tại.
    function _load(uint256 id) private view returns (Escrow storage e) {
        e = _escrows[id];
        if (e.status == Status.None) revert EscrowNotFound(id);
    }

    /// @dev Revert `InvalidStatus` nếu escrow không ở trạng thái `expected`.
    function _requireStatus(uint256 id, Escrow storage e, Status expected) private view {
        Status current = e.status;
        if (current != expected) revert InvalidStatus(id, current);
    }

    /**
     * @dev Mốc kết thúc thời gian khiếu nại của escrow `Delivered`: `max(disputeDeadline, deliveryDeadline)`.
     *      Buyer mở tranh chấp được khi `now <= mốc`; Seller tự giải ngân được khi `now > mốc` (audit M-1).
     */
    function _disputeWindowEnd(Escrow storage e) private view returns (uint256) {
        return Math.max(e.disputeDeadline, e.deliveryDeadline);
    }

    /// @dev Ghi có toàn bộ `amount` cho Buyer, không phí, `status = Refunded`.
    function _refundBuyer(uint256 id, Escrow storage e) private {
        e.status = Status.Refunded;
        uint256 amount = e.amount;
        _credit(e.buyer, e.token, amount);
        emit EscrowRefunded(id, msg.sender, amount);
    }

    /// @dev Cộng `amount` vào số dư chờ rút; bỏ qua khoản bằng 0.
    function _credit(address user, address token, uint256 amount) private {
        if (amount != 0) withdrawable[user][token] += amount;
    }
}
