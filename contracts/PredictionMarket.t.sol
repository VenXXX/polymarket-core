// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./PredictionMarket.sol";

/**
 * @title MockUSDC
 * @dev Mock USDC token for testing (6 decimals)
 */
contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title PredictionMarketTest
 * @dev Comprehensive test suite for all 6 security fixes
 */
contract PredictionMarketTest is Test {
    // ============================================================================
    // State Variables
    // ============================================================================

    PredictionMarket public market;
    MockUSDC public usdc;

    address public owner = makeAddr("owner");
    address public relayer = makeAddr("relayer");
    address public maker = makeAddr("maker");
    address public taker = makeAddr("taker");
    address public unauthorized = makeAddr("unauthorized");

    uint256 public constant PRICE_BASIS = 10000;
    uint256 public constant USDC_DECIMALS = 6;

    // ============================================================================
    // Setup
    // ============================================================================

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy prediction market
        market = new PredictionMarket(address(usdc));

        // Mint USDC to test accounts (1000 USDC each)
        uint256 initialBalance = 1000 * 10 ** USDC_DECIMALS;
        usdc.mint(owner, initialBalance);
        usdc.mint(relayer, initialBalance);
        usdc.mint(maker, initialBalance);
        usdc.mint(taker, initialBalance);
        usdc.mint(unauthorized, initialBalance);

        // Approve market to spend USDC
        vm.prank(owner);
        usdc.approve(address(market), type(uint256).max);

        vm.prank(relayer);
        usdc.approve(address(market), type(uint256).max);

        vm.prank(maker);
        usdc.approve(address(market), type(uint256).max);

        vm.prank(taker);
        usdc.approve(address(market), type(uint256).max);

        vm.prank(unauthorized);
        usdc.approve(address(market), type(uint256).max);

        // Authorize relayer
        vm.prank(owner);
        market.setRelayerAuthorization(relayer, true);
    }

    // ============================================================================
    // FIX #1: Partial Fill Support Tests
    // ============================================================================

    function test_FIX1_PartialFill_Success() public {
        // Create order for 100 shares
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 5000, 100, block.timestamp + 1 days, 1);
        vm.stopPrank();

        // First fill: 30 shares
        vm.prank(relayer);
        PredictionMarket.Order memory order = market.orders(orderHash);
        market.fillOrder(orderHash, 30, order);

        // Verify filled amount
        uint256 filledAfter1 = market.orderFilledAmount(orderHash);
        assertEq(filledAfter1, 30, "Should have filled 30");

        // Second fill: 50 shares
        vm.prank(relayer);
        market.fillOrder(orderHash, 50, order);

        uint256 filledAfter2 = market.orderFilledAmount(orderHash);
        assertEq(filledAfter2, 80, "Should have filled 80 total");

        // Third fill: 20 shares (completes order)
        vm.prank(relayer);
        market.fillOrder(orderHash, 20, order);

        uint256 filledAfter3 = market.orderFilledAmount(orderHash);
        assertEq(filledAfter3, 100, "Should have filled 100 total");

        // Verify order is fully filled
        assertTrue(market.isOrderFullyFilled(orderHash), "Order should be fully filled");
    }

    function test_FIX1_PartialFill_ExceedsRemaining_Reverts() public {
        // Create order for 100 shares
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 5000, 100, block.timestamp + 1 days, 1);
        vm.stopPrank();

        // Try to fill 150 shares (exceeds order amount)
        vm.prank(relayer);
        PredictionMarket.Order memory order = market.orders(orderHash);
        
        vm.expectRevert("Exceeds remaining amount");
        market.fillOrder(orderHash, 150, order);
    }

    function test_FIX1_GetRemainingFillable() public {
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 5000, 100, block.timestamp + 1 days, 1);
        vm.stopPrank();

        // Initially 100 remaining
        assertEq(market.getRemainingFillable(orderHash), 100, "Should have 100 remaining");

        // Fill 30
        vm.prank(relayer);
        PredictionMarket.Order memory order = market.orders(orderHash);
        market.fillOrder(orderHash, 30, order);

        // Now 70 remaining
        assertEq(market.getRemainingFillable(orderHash), 70, "Should have 70 remaining");
    }

    // ============================================================================
    // FIX #2: Auto-Mint Mode Tests
    // ============================================================================

    function test_FIX2_AutoMint_MintsShares() public {
        // Maker creates YES order
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 5000, 100, block.timestamp + 1 days, 1);
        vm.stopPrank();

        // Get order data
        PredictionMarket.Order memory order = market.orders(orderHash);

        // Check balances before
        assertEq(market.balanceOf(maker, 0), 0, "Maker should have 0 YES before");
        assertEq(market.balanceOf(taker, 1), 0, "Taker should have 0 NO before");

        // Fill order
        vm.prank(relayer);
        vm.prank(taker);
        market.fillOrder(orderHash, 100, order);

        // Check balances after - shares should be MINTED
        assertEq(market.balanceOf(maker, 0), 100, "Maker should have 100 YES after mint");
        assertEq(market.balanceOf(taker, 1), 100, "Taker should have 100 NO after mint");

        // Check total minted
        assertEq(market.totalMinted(0), 100, "Total YES minted should be 100");
        assertEq(market.totalMinted(1), 100, "Total NO minted should be 100");
    }

    function test_FIX2_AutoMint_TransfersUSDC() public {
        // Maker creates YES order at 5000 basis points (50%)
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 5000, 100, block.timestamp + 1 days, 1);
        vm.stopPrank();

        // Taker USDC balance before
        uint256 takerBalanceBefore = usdc.balanceOf(taker);

        // Fill order
        vm.prank(relayer);
        vm.prank(taker);
        PredictionMarket.Order memory order = market.orders(orderHash);
        market.fillOrder(orderHash, 100, order);

        // USDC should be transferred: 5000 * 100 / 10000 = 50 USDC
        uint256 expectedUSDC = 50 * 10 ** USDC_DECIMALS;
        assertEq(usdc.balanceOf(taker), takerBalanceBefore - expectedUSDC, "Taker USDC should decrease");
        assertEq(usdc.balanceOf(address(market)), expectedUSDC, "Market should receive USDC");
    }

    // ============================================================================
    // FIX #3: Relayer Authorization Tests
    // ============================================================================

    function test_FIX3_UnauthorizedRelayer_Reverts() public {
        // Maker creates order
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 5000, 100, block.timestamp + 1 days, 1);
        vm.stopPrank();

        // Unauthorized user tries to fill
        vm.prank(unauthorized);
        PredictionMarket.Order memory order = market.orders(orderHash);
        
        vm.expectRevert("Not relayer");
        market.fillOrder(orderHash, 100, order);
    }

    function test_FIX3_AuthorizedRelayer_Success() public {
        // Maker creates order
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 5000, 100, block.timestamp + 1 days, 1);
        vm.stopPrank();

        // Authorized relayer fills
        vm.prank(relayer);
        vm.prank(taker);
        PredictionMarket.Order memory order = market.orders(orderHash);
        
        // Should not revert
        market.fillOrder(orderHash, 100, order);
    }

    function test_FIX3_SetRelayerAuthorization() public {
        // Authorize new relayer
        vm.prank(owner);
        market.setRelayerAuthorization(unauthorized, true);

        // Now unauthorized can fill
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 5000, 100, block.timestamp + 1 days, 1);
        vm.stopPrank();

        vm.prank(unauthorized);
        PredictionMarket.Order memory order = market.orders(orderHash);
        market.fillOrder(orderHash, 100, order); // Should succeed
    }

    // ============================================================================
    // FIX #4: Invalid Market Withdrawal (No Even Check) Tests
    // ============================================================================

    function test_FIX4_InvalidMarket_OddAmount_Success() public {
        // Setup: User has 101 YES shares (odd amount)
        _setupShares(maker, 101, 0); // 101 YES shares

        // Resolve market as INVALID
        vm.prank(owner);
        market.resolveMarket(PredictionMarket.Outcome.INVALID);

        // User should be able to withdraw 101 shares (odd amount!)
        uint256 balanceBefore = usdc.balanceOf(maker);
        
        vm.prank(maker);
        market.withdraw(101, 0); // 0 = YES outcome

        // Should receive floor(101 / 2) = 50 USDC
        uint256 expectedRefund = 50 * 10 ** USDC_DECIMALS;
        assertEq(usdc.balanceOf(maker), balanceBefore + expectedRefund, "Should receive 50 USDC");
    }

    function test_FIX4_InvalidMarket_EvenAmount_Success() public {
        // Setup: User has 100 YES shares (even amount)
        _setupShares(maker, 100, 0);

        // Resolve market as INVALID
        vm.prank(owner);
        market.resolveMarket(PredictionMarket.Outcome.INVALID);

        // Withdraw 100 shares
        uint256 balanceBefore = usdc.balanceOf(maker);
        
        vm.prank(maker);
        market.withdraw(100, 0);

        // Should receive 100 / 2 = 50 USDC
        uint256 expectedRefund = 50 * 10 ** USDC_DECIMALS;
        assertEq(usdc.balanceOf(maker), balanceBefore + expectedRefund, "Should receive 50 USDC");
    }

    function test_FIX4_InvalidMarket_SingleShare_Success() public {
        // Setup: User has 1 YES share (minimum odd)
        _setupShares(maker, 1, 0);

        // Resolve market as INVALID
        vm.prank(owner);
        market.resolveMarket(PredictionMarket.Outcome.INVALID);

        // Withdraw 1 share - should work! (previously would fail)
        uint256 balanceBefore = usdc.balanceOf(maker);
        
        vm.prank(maker);
        market.withdraw(1, 0);

        // Should receive floor(1 / 2) = 0 USDC (acceptable precision loss)
        assertEq(usdc.balanceOf(maker), balanceBefore, "Should receive 0 USDC (floor rounding)");
    }

    // ============================================================================
    // FIX #5: Dust Attack Prevention Tests
    // ============================================================================

    function test_FIX5_DustAttack_ZeroUSDC_Reverts() public {
        // Maker creates order with very low price
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 100, 100, block.timestamp + 1 days, 1);
        // Price 100 basis points = 1%
        // fillAmount = 1 → usdcAmount = 100 * 1 / 10000 = 0
        vm.stopPrank();

        // Try to fill with amount that results in 0 USDC
        vm.prank(relayer);
        vm.prank(taker);
        PredictionMarket.Order memory order = market.orders(orderHash);
        
        vm.expectRevert("Amount too small");
        market.fillOrder(orderHash, 1, order);
    }

    function test_FIX5_MinimumValidFill_Success() public {
        // Maker creates order with reasonable price
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 5000, 100, block.timestamp + 1 days, 1);
        vm.stopPrank();

        // Fill with amount that results in >0 USDC
        // 5000 * 1 / 10000 = 0.5 → floors to 0, so need at least 2
        // 5000 * 2 / 10000 = 1 → valid
        vm.prank(relayer);
        vm.prank(taker);
        PredictionMarket.Order memory order = market.orders(orderHash);
        market.fillOrder(orderHash, 2, order); // Should succeed
    }

    function test_FIX5_LowPrice_RequiresLargerFill() public {
        // Very low price: 10 basis points (0.1%)
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 10, 1000, block.timestamp + 1 days, 1);
        vm.stopPrank();

        // Need fillAmount >= 1000 to get usdcAmount >= 1
        // 10 * 999 / 10000 = 0 → reverts
        vm.prank(relayer);
        vm.prank(taker);
        PredictionMarket.Order memory order = market.orders(orderHash);
        
        vm.expectRevert("Amount too small");
        market.fillOrder(orderHash, 999, order);

        // 10 * 1000 / 10000 = 1 → succeeds
        market.fillOrder(orderHash, 1000, order);
    }

    // ============================================================================
    // FIX #6: mergePositions Tests
    // ============================================================================

    function test_FIX6_MergePositions_Success() public {
        // Setup: User has 10 YES + 10 NO
        _setupShares(maker, 10, 0); // 10 YES
        _setupShares(maker, 10, 1); // 10 NO

        // Deposit USDC to market for refund
        vm.prank(owner);
        usdc.transfer(address(market), 100 * 10 ** USDC_DECIMALS);

        // Check balances before
        uint256 usdcBefore = usdc.balanceOf(maker);
        assertEq(market.balanceOf(maker, 0), 10, "Should have 10 YES");
        assertEq(market.balanceOf(maker, 1), 10, "Should have 10 NO");

        // Merge positions
        vm.prank(maker);
        market.mergePositions(10);

        // Check balances after
        assertEq(market.balanceOf(maker, 0), 0, "YES should be burned");
        assertEq(market.balanceOf(maker, 1), 0, "NO should be burned");
        assertEq(usdc.balanceOf(maker), usdcBefore + 10 * 10 ** USDC_DECIMALS, "Should receive 10 USDC");
    }

    function test_FIX6_MergePositions_InsufficientYES_Reverts() public {
        // Setup: User has 5 YES + 10 NO
        _setupShares(maker, 5, 0);
        _setupShares(maker, 10, 1);

        // Try to merge 10 pairs
        vm.prank(maker);
        vm.expectRevert("Insufficient YES shares");
        market.mergePositions(10);
    }

    function test_FIX6_MergePositions_InsufficientNO_Reverts() public {
        // Setup: User has 10 YES + 5 NO
        _setupShares(maker, 10, 0);
        _setupShares(maker, 5, 1);

        // Try to merge 10 pairs
        vm.prank(maker);
        vm.expectRevert("Insufficient NO shares");
        market.mergePositions(10);
    }

    function test_FIX6_MergePositions_ZeroAmount_Reverts() public {
        vm.prank(maker);
        vm.expectRevert("Amount must be positive");
        market.mergePositions(0);
    }

    function test_FIX6_MergePositions_PartialMerge() public {
        // Setup: User has 20 YES + 20 NO
        _setupShares(maker, 20, 0);
        _setupShares(maker, 20, 1);

        // Deposit USDC
        vm.prank(owner);
        usdc.transfer(address(market), 100 * 10 ** USDC_DECIMALS);

        // Merge only 10 pairs
        vm.prank(maker);
        market.mergePositions(10);

        // Should have 10 YES + 10 NO remaining
        assertEq(market.balanceOf(maker, 0), 10, "Should have 10 YES remaining");
        assertEq(market.balanceOf(maker, 1), 10, "Should have 10 NO remaining");
        assertEq(usdc.balanceOf(maker), 10 * 10 ** USDC_DECIMALS, "Should receive 10 USDC");
    }

    // ============================================================================
    // Integration Tests
    // ============================================================================

    function test_Integration_FullLifecycle() public {
        // 1. Maker creates YES order
        vm.startPrank(maker);
        bytes32 orderHash = market.createOrder(0, 6000, 50, block.timestamp + 1 days, 1);
        vm.stopPrank();

        // 2. Taker fills order (partial)
        vm.prank(relayer);
        vm.prank(taker);
        PredictionMarket.Order memory order = market.orders(orderHash);
        market.fillOrder(orderHash, 30, order);

        // 3. Another taker fills remaining
        address taker2 = makeAddr("taker2");
        usdc.mint(taker2, 1000 * 10 ** USDC_DECIMALS);
        vm.prank(taker2);
        usdc.approve(address(market), type(uint256).max);
        
        vm.prank(relayer);
        vm.prank(taker2);
        market.fillOrder(orderHash, 20, order);

        // 4. Market resolves YES
        vm.prank(owner);
        market.resolveMarket(PredictionMarket.Outcome.YES);

        // 5. YES holders withdraw
        uint256 makerYES = market.balanceOf(maker, 0);
        vm.prank(maker);
        market.withdraw(makerYES, 0);

        // Maker should get full payout for YES shares
        assertEq(usdc.balanceOf(maker), makerYES * 10 ** USDC_DECIMALS, "Maker should get full payout");
    }

    // ============================================================================
    // Helper Functions
    // ============================================================================

    function _setupShares(address user, uint256 amount, uint256 outcome) internal {
        // Mint shares directly using market's internal _mint (via prank on market)
        // For testing, we use the public mint by filling an order
        // Alternative: use vm.mockCall or deploy with shares pre-minted
        
        // Simple approach: create and self-fill an order
        vm.startPrank(user);
        bytes32 orderHash = market.createOrder(outcome, 100, amount, block.timestamp + 1 days, 1);
        vm.stopPrank();

        vm.prank(relayer);
        vm.prank(user);
        PredictionMarket.Order memory order = market.orders(orderHash);
        market.fillOrder(orderHash, amount, order);
    }
}
