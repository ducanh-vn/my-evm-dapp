// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IEscrowVault
 * @notice Interface của EscrowVault — ký quỹ thanh toán P2P cho ETH và ERC-20 trong whitelist.
 * @dev Quy ước `token == address(0)` là ETH. Mọi khoản tiền ra được ghi có vào `withdrawable`
 *      (pull payment); người nhận tự gọi `withdraw`. Đặc tả: docs/02-ky-thuat/escrow-vault-spec.md
 */
interface IEscrowVault {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Trạng thái vòng đời của một escrow.
    enum Status {
        None,
        Funded,
        Delivered,
        Disputed,
        Released,
        Refunded,
        Resolved
    }

    /// @notice Dữ liệu một escrow, đóng gói vừa 5 storage slot.
    struct Escrow {
        // slot 0: 20 + 6 + 2 + 1 = 29 bytes
        address buyer;
        uint48 deliveryDeadline;
        uint16 feeBps;
        Status status;
        // slot 1: 20 + 6 = 26 bytes
        address seller;
        uint48 disputeDeadline;
        // slot 2: 20 + 6 = 26 bytes
        address arbiter;
        uint48 arbitrationDeadline;
        // slot 3
        address token;
        // slot 4
        uint256 amount;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Phát khi Buyer tạo và nạp tiền cho escrow mới.
    event EscrowCreated(
        uint256 indexed id,
        address indexed buyer,
        address indexed seller,
        address token,
        address arbiter,
        uint256 amount,
        uint16 feeBps,
        uint48 deliveryDeadline
    );

    /// @notice Phát khi Seller báo đã giao hàng.
    event EscrowDelivered(uint256 indexed id, uint48 disputeDeadline);

    /// @notice Phát khi tiền được giải ngân cho Seller.
    event EscrowReleased(uint256 indexed id, address indexed caller, uint256 sellerAmount, uint256 fee);

    /// @notice Phát khi toàn bộ tiền được hoàn cho Buyer (refund hoặc claimTimeoutRefund).
    event EscrowRefunded(uint256 indexed id, address indexed caller, uint256 amount);

    /// @notice Phát khi Buyer hoặc Seller mở tranh chấp.
    event DisputeRaised(uint256 indexed id, address indexed raisedBy, uint48 arbitrationDeadline);

    /// @notice Phát khi Arbiter phân xử tranh chấp.
    event DisputeResolved(
        uint256 indexed id,
        address indexed arbiter,
        uint16 buyerBps,
        uint256 buyerAmount,
        uint256 sellerAmount,
        uint256 fee
    );

    /// @notice Phát khi người dùng rút số dư.
    event Withdrawn(address indexed user, address indexed token, uint256 amount);

    /// @notice Phát khi phí cho escrow mới thay đổi.
    event FeeUpdated(uint16 oldBps, uint16 newBps);

    /// @notice Phát khi ví nhận phí thay đổi.
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    /// @notice Phát khi trọng tài mặc định thay đổi.
    event DefaultArbiterUpdated(address indexed oldArbiter, address indexed newArbiter);

    /// @notice Phát khi một ERC-20 được thêm/bỏ khỏi whitelist.
    event TokenAllowlistUpdated(address indexed token, bool allowed);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error ZeroAmount();
    error InvalidSeller();
    error InvalidArbiter();
    error InvalidDeliveryPeriod(uint48 period);
    error TokenNotAllowed(address token);
    error InvalidMsgValue(uint256 expected, uint256 actual);
    error AmountMismatch(uint256 expected, uint256 received);
    error EscrowNotFound(uint256 id);
    error InvalidStatus(uint256 id, Status current);
    error Unauthorized();
    error DeadlinePassed();
    error DeadlineNotReached();
    error InvalidBps(uint256 bps);
    error FeeTooHigh(uint16 bps);
    error NothingToWithdraw();
    error EthTransferFailed();
    error RenounceDisabled();

    /*//////////////////////////////////////////////////////////////
                             USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tạo escrow và khóa tiền của người gọi (Buyer) vào contract.
     * @param seller Ví người bán, khác Buyer và khác `address(0)`.
     * @param token `address(0)` cho ETH, hoặc ERC-20 trong whitelist.
     * @param amount Số tiền ký quỹ (> 0). Với ETH phải bằng `msg.value`.
     * @param deliveryPeriod Thời hạn giao hàng tính từ bây giờ, trong khoảng 1 giờ – 90 ngày.
     * @param arbiter Trọng tài hai bên thống nhất; `address(0)` để dùng `defaultArbiter`.
     * @return id Mã escrow mới (bắt đầu từ 1).
     */
    function createEscrow(address seller, address token, uint256 amount, uint48 deliveryPeriod, address arbiter)
        external
        payable
        returns (uint256 id);

    /**
     * @notice Seller báo đã giao hàng; mở thời gian khiếu nại cho Buyer, kéo dài tới
     *         `max(now + 3 ngày, deliveryDeadline)`.
     * @param id Mã escrow.
     */
    function markDelivered(uint256 id) external;

    /**
     * @notice Giải ngân cho Seller (trừ phí). Buyer gọi khi `Funded`/`Delivered`;
     *         Seller gọi khi `Delivered` và đã qua cả `disputeDeadline` lẫn `deliveryDeadline`
     *         (tức `block.timestamp > max(disputeDeadline, deliveryDeadline)`).
     * @param id Mã escrow.
     */
    function release(uint256 id) external;

    /**
     * @notice Hoàn toàn bộ tiền cho Buyer, không phí. Seller gọi khi `Funded`/`Delivered`/`Disputed`;
     *         Buyer gọi khi `Funded` và đã qua `deliveryDeadline`.
     * @param id Mã escrow.
     */
    function refund(uint256 id) external;

    /**
     * @notice Buyer hoặc Seller mở tranh chấp trong thời hạn cho phép:
     *         `Funded` và `now <= deliveryDeadline`, hoặc `Delivered` và
     *         `now <= max(disputeDeadline, deliveryDeadline)`.
     * @param id Mã escrow.
     */
    function raiseDispute(uint256 id) external;

    /**
     * @notice Arbiter của escrow phân xử, chia tiền giữa Buyer và Seller.
     * @param id Mã escrow.
     * @param buyerBps Phần cho Buyer (0 – 10.000 bps); phí chỉ tính trên phần của Seller.
     */
    function resolveDispute(uint256 id, uint16 buyerBps) external;

    /**
     * @notice Buyer lấy lại 100% tiền gốc khi Arbiter không phán quyết trong 14 ngày.
     * @param id Mã escrow.
     */
    function claimTimeoutRefund(uint256 id) external;

    /**
     * @notice Rút toàn bộ số dư của người gọi theo tài sản. Không bị chặn bởi `pause`.
     * @param token `address(0)` cho ETH, hoặc địa chỉ ERC-20.
     */
    function withdraw(address token) external;

    /**
     * @notice Đọc dữ liệu một escrow.
     * @param id Mã escrow.
     * @return Dữ liệu escrow (status `None` nếu không tồn tại).
     */
    function getEscrow(uint256 id) external view returns (Escrow memory);

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Đặt phí cho escrow mới.
     * @param newBps Phí mới, tối đa `MAX_FEE_BPS` (500).
     */
    function setFeeBps(uint16 newBps) external;

    /**
     * @notice Đặt ví nhận phí.
     * @param newRecipient Ví mới, khác `address(0)`.
     */
    function setFeeRecipient(address newRecipient) external;

    /**
     * @notice Đặt trọng tài mặc định cho escrow mới; không ảnh hưởng escrow đã tạo.
     * @param newArbiter Ví mới, khác `address(0)`.
     */
    function setDefaultArbiter(address newArbiter) external;

    /**
     * @notice Thêm/bỏ ERC-20 khỏi whitelist; chỉ ảnh hưởng escrow mới.
     * @param token Địa chỉ ERC-20, khác `address(0)`.
     * @param allowed `true` để cho phép.
     */
    function setTokenAllowed(address token, bool allowed) external;

    /// @notice Chặn tạo escrow mới. Mọi thao tác khác vẫn chạy.
    function pause() external;

    /// @notice Bỏ chặn tạo escrow mới.
    function unpause() external;
}
