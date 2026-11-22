// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title VaultReferencePattern
 * @notice Mẫu chuẩn kết hợp Ownable2Step, ReentrancyGuard, Pausable, SafeERC20 và Custom Errors.
 */
contract VaultReferencePattern is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Custom Errors tiết kiệm gas
    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);

    // State Variables sắp xếp tối ưu slot
    IERC20 public immutable stakingToken;
    mapping(address => uint256) public balances;

    // Events có indexed để Indexer lọc nhanh
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(address _token, address _initialOwner) Ownable(_initialOwner) {
        stakingToken = IERC20(_token);
    }

    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        // Effects trước Interactions
        balances[msg.sender] += amount;

        // Interactions
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 userBal = balances[msg.sender];
        if (userBal < amount) revert InsufficientBalance(amount, userBal);

        // Checks -> Effects -> Interactions (CEI)
        balances[msg.sender] = userBal - amount;
        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
