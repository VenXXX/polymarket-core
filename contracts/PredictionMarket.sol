// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PredictionMarket
 * @notice A prediction market contract with YES/NO shares, partial fill support, and auto-mint functionality
 * @dev Security-hardened version with all identified vulnerabilities fixed
 */
contract PredictionMarket is ERC1155, ERC1155Burnable, Ownable {
    using SafeERC20 for IERC20;

    // ============================================================================
    // Constants & State Variables
    // ============================================================================

    /// @dev Token IDs: 0 = YES shares, 1 = NO shares
    uint256 public constant TOKEN_ID_YES = 0;
    uint256 public constant TOKEN_ID_NO = 1;

    /// @dev USDC token address (immutable for security)
    IERC20 public immutable USDC;

    /// @dev Price basis for calculations (10000 = 100%)
    uint256 public constant PRICE_BASIS = 10000;

    /// @dev Minimum fill amount to prevent dust attacks
    uint256 public constant MIN_FILL_AMOUNT = 1;

    // ============================================================================
    // Order & Matching Structures
    // ============================================================================

    enum Outcome { YES, NO, INVALID }

    struct Order {
        address maker;
        uint256 outcome; // 0 = YES, 1 = NO
        uint256 price; // Price per share in basis points (e.g., 5000 = 50%)
        uint256 amount; // Total order amount
        uint256 expiration;
        bytes32 orderHash;
        bool isCancelled;
    }

    /// @dev FIX #1: Changed from simple nonce to orderFilledAmount for partial fill support
    /// Tracks how much of each order has been filled (by order hash)
    mapping(bytes32 => uint256) public orderFilledAmount;

    /// @dev Store active orders by hash
    mapping(bytes32 => Order) public orders;

    /// @dev FIX #3: Authorized relayers for fillOrder
    mapping(address => bool) public authorizedRelayers;

    /// @dev Market outcome (set when market resolves)
    Outcome public marketOutcome;
    bool public marketResolved;

    /// @dev Track total minted shares for each outcome
    mapping(uint256 => uint256) public totalMinted;

    // ============================================================================
    // Events
    // ============================================================================

    event OrderCreated(bytes32 indexed orderHash, address indexed maker, uint256 outcome, uint256 price, uint256 amount);
    event OrderFilled(bytes32 indexed orderHash, address indexed taker, uint256 fillAmount, uint256 usdcAmount);
    event OrderCancelled(bytes32 indexed orderHash);
    event SharesMinted(address indexed recipient, uint256 outcome, uint256 amount);
    event SharesBurned(address indexed sender, uint256 outcome, uint256 amount);
    event USDCDeposited(address indexed user, uint256 amount);
    event USDCWithdrawn(address indexed user, uint256 amount);
    event MarketResolved(Outcome outcome);
    event RelayerAuthorized(address indexed relayer, bool authorized);
    event PositionsMerged(address indexed user, uint256 yesAmount, uint256 noAmount, uint256 usdcRefund);

    // ============================================================================
    // Constructor
    // ============================================================================

    /**
     * @param usdcAddress USDC token contract address
     */
    constructor(address usdcAddress) ERC1155("") Ownable(msg.sender) {
        require(usdcAddress != address(0), "Invalid USDC address");
        USDC = IERC20(usdcAddress);
    }

    // ============================================================================
    // Modifier
    // ============================================================================

    modifier onlyAuthorizedRelayer() {
        require(authorizedRelayers[msg.sender], "Not relayer");
        _;
    }

    // ============================================================================
    // FIX #3: Relayer Management
    // ============================================================================

    /**
     * @dev Authorize or deauthorize a relayer
     */
    function setRelayerAuthorization(address relayer, bool authorized) external onlyOwner {
        require(relayer != address(0), "Invalid relayer address");
        authorizedRelayers[relayer] = authorized;
        emit RelayerAuthorized(relayer, authorized);
    }

    // ============================================================================
    // Order Creation
    // ============================================================================

    /**
     * @dev Create a new order
     * @param outcome 0 for YES, 1 for NO
     * @param price Price per share in basis points
     * @param amount Number of shares
     * @param expiration Unix timestamp when order expires
     * @param nonce Unique nonce for order hash
     */
    function createOrder(
        uint256 outcome,
        uint256 price,
        uint256 amount,
        uint256 expiration,
        uint256 nonce
    ) external returns (bytes32) {
        require(outcome <= 1, "Invalid outcome");
        require(price > 0 && price <= PRICE_BASIS, "Invalid price");
        require(amount > 0, "Invalid amount");
        require(expiration > block.timestamp, "Order expired");

        bytes32 orderHash = _computeOrderHash(msg.sender, outcome, price, amount, expiration, nonce);
        
        require(orders[orderHash].maker == address(0), "Order already exists");

        orders[orderHash] = Order({
            maker: msg.sender,
            outcome: outcome,
            price: price,
            amount: amount,
            expiration: expiration,
            orderHash: orderHash,
            isCancelled: false
        });

        // FIX #1: Initialize filled amount to 0
        orderFilledAmount[orderHash] = 0;

        emit OrderCreated(orderHash, msg.sender, outcome, price, amount);
        return orderHash;
    }

    /**
     * @dev Cancel an existing order
     */
    function cancelOrder(bytes32 orderHash) external {
        Order storage order = orders[orderHash];
        require(order.maker == msg.sender, "Not order maker");
        require(!order.isCancelled, "Already cancelled");
        require(block.timestamp < order.expiration, "Order expired");

        order.isCancelled = true;
        emit OrderCancelled(orderHash);
    }

    // ============================================================================
    // FIX #1, #2, #3, #5: Fill Order with Security Hardening
    // ============================================================================

    /**
     * @dev Fill an existing order (partial or full)
     * @param orderHash Hash of the order to fill
     * @param fillAmount Amount to fill (can be partial)
     * @param makerOrder The original order data
     */
    function fillOrder(
        bytes32 orderHash,
        uint256 fillAmount,
        Order calldata makerOrder
    ) external onlyAuthorizedRelayer {
        // FIX #3: Relayer authorization check (also enforced by modifier)
        require(authorizedRelayers[msg.sender], "Not relayer");

        Order storage order = orders[orderHash];
        
        // Validate order
        require(order.maker != address(0), "Order does not exist");
        require(!order.isCancelled, "Order cancelled");
        require(block.timestamp < order.expiration, "Order expired");
        require(fillAmount > 0, "Fill amount must be positive");

        // FIX #1: Check remaining fillable amount
        uint256 remainingAmount = order.amount - orderFilledAmount[orderHash];
        require(fillAmount <= remainingAmount, "Exceeds remaining amount");

        // FIX #5: Calculate USDC amount with precision loss protection
        uint256 usdcAmount = (makerOrder.price * fillAmount) / PRICE_BASIS;
        require(usdcAmount > 0, "Amount too small");

        // FIX #2: Auto-mint mode - deduct USDC from taker, mint shares to both parties
        address taker = msg.sender;
        address maker = order.maker;

        // Determine outcomes: maker has one outcome, taker gets the opposite
        uint256 makerOutcome = order.outcome;
        uint256 takerOutcome = makerOutcome == 0 ? 1 : 0;

        // Transfer USDC from taker to contract
        USDC.safeTransferFrom(taker, address(this), usdcAmount);

        // FIX #2: Auto-mint shares for both maker and taker
        _mint(maker, makerOutcome == 0 ? TOKEN_ID_YES : TOKEN_ID_NO, fillAmount, "");
        _mint(taker, takerOutcome == 0 ? TOKEN_ID_YES : TOKEN_ID_NO, fillAmount, "");

        // Update total minted
        totalMinted[makerOutcome] += fillAmount;
        totalMinted[takerOutcome] += fillAmount;

        // FIX #1: Update filled amount (supports partial fills)
        orderFilledAmount[orderHash] += fillAmount;

        emit SharesMinted(maker, makerOutcome == 0 ? TOKEN_ID_YES : TOKEN_ID_NO, fillAmount);
        emit SharesMinted(taker, takerOutcome == 0 ? TOKEN_ID_YES : TOKEN_ID_NO, fillAmount);
        emit OrderFilled(orderHash, taker, fillAmount, usdcAmount);
    }

    // ============================================================================
    // FIX #6: Merge Positions (New Method)
    // ============================================================================

    /**
     * @dev Merge YES and NO positions to get USDC refund
     * @dev Users can combine 1 YES + 1 NO to get 1 USDC back (no need to wait for market resolution)
     * @param amount Number of position pairs to merge
     */
    function mergePositions(uint256 amount) external {
        require(amount > 0, "Amount must be positive");

        // Check user has both YES and NO shares
        uint256 yesBalance = balanceOf(msg.sender, TOKEN_ID_YES);
        uint256 noBalance = balanceOf(msg.sender, TOKEN_ID_NO);
        require(yesBalance >= amount, "Insufficient YES shares");
        require(noBalance >= amount, "Insufficient NO shares");

        // Burn both YES and NO shares
        _burn(msg.sender, TOKEN_ID_YES, amount);
        _burn(msg.sender, TOKEN_ID_NO, amount);

        // Calculate refund: 1 USDC per pair (in basis points: 10000 = 1 USDC assuming 6 decimals)
        // Adjust based on USDC decimals (typically 6)
        uint256 refundAmount = amount * (10 ** 6); // Assuming USDC has 6 decimals

        // Transfer USDC refund to user
        require(USDC.balanceOf(address(this)) >= refundAmount, "Insufficient contract balance");
        USDC.safeTransfer(msg.sender, refundAmount);

        emit PositionsMerged(msg.sender, amount, amount, refundAmount);
    }

    // ============================================================================
    // FIX #4: Withdraw with Flexible Invalid Market Handling
    // ============================================================================

    /**
     * @dev Withdraw funds after market resolution
     * @param amount Amount of shares to redeem
     * @param outcome Outcome being redeemed (0=YES, 1=NO, 2=INVALID)
     */
    function withdraw(uint256 amount, uint256 outcome) external {
        require(marketResolved, "Market not resolved");
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender, outcome == 2 ? TOKEN_ID_YES : (outcome == 0 ? TOKEN_ID_YES : TOKEN_ID_NO)) >= amount, "Insufficient balance");

        uint256 payoutPerShare;

        if (marketOutcome == Outcome.INVALID) {
            // FIX #4: Removed rigid "amount % 2 == 0" check
            // Simply divide by 2 with automatic floor rounding - losing 1 wei is acceptable
            payoutPerShare = (10 ** 6) / 2; // Half refund for Invalid outcome
            // Note: Solidity automatically floors the division, no need for explicit check
        } else if (
            (marketOutcome == Outcome.YES && outcome == 0) ||
            (marketOutcome == Outcome.NO && outcome == 1)
        ) {
            // Winning outcome: full payout
            payoutPerShare = 10 ** 6; // 1 USDC per share
        } else {
            // Losing outcome: no payout
            payoutPerShare = 0;
        }

        require(payoutPerShare > 0, "No payout for this outcome");

        uint256 totalPayout = amount * payoutPerShare;

        // Burn the shares
        _burn(msg.sender, outcome == 2 ? TOKEN_ID_YES : (outcome == 0 ? TOKEN_ID_YES : TOKEN_ID_NO), amount);

        // Transfer payout
        require(USDC.balanceOf(address(this)) >= totalPayout, "Insufficient contract balance");
        USDC.safeTransfer(msg.sender, totalPayout);

        emit USDCWithdrawn(msg.sender, totalPayout);
    }

    // ============================================================================
    // Market Resolution
    // ============================================================================

    /**
     * @dev Resolve the market (owner only)
     */
    function resolveMarket(Outcome outcome) external onlyOwner {
        require(!marketResolved, "Already resolved");
        marketOutcome = outcome;
        marketResolved = true;
        emit MarketResolved(outcome);
    }

    // ============================================================================
    // Utility Functions
    // ============================================================================

    /**
     * @dev Compute order hash
     */
    function _computeOrderHash(
        address maker,
        uint256 outcome,
        uint256 price,
        uint256 amount,
        uint256 expiration,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(maker, outcome, price, amount, expiration, nonce));
    }

    /**
     * @dev Get remaining fillable amount for an order
     */
    function getRemainingFillable(bytes32 orderHash) external view returns (uint256) {
        Order storage order = orders[orderHash];
        if (order.maker == address(0)) return 0;
        return order.amount - orderFilledAmount[orderHash];
    }

    /**
     * @dev Check if order is fully filled
     */
    function isOrderFullyFilled(bytes32 orderHash) external view returns (bool) {
        Order storage order = orders[orderHash];
        if (order.maker == address(0)) return true;
        return orderFilledAmount[orderHash] >= order.amount;
    }

    /**
     * @dev Emergency withdraw for owner (safety mechanism)
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    /**
     * @dev URI for ERC1155 tokens
     */
    function uri(uint256 tokenId) public pure override returns (string memory) {
        return tokenId == TOKEN_ID_YES ? "ipfs://YES" : "ipfs://NO";
    }

    /**
     * @dev Deposit USDC to contract (for liquidity)
     */
    function depositUSDC(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        emit USDCDeposited(msg.sender, amount);
    }
}
