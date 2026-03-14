// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract ConditionalToken is ERC1155, EIP712, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using SignatureChecker for address;

    enum MarketState { Active, YesWins, NoWins, Invalid }

    struct Order {
        address maker;
        uint256 marketId;
        uint256 amount;
        uint256 price;
        bool isYes;
        uint256 nonce;
    }

    struct Market {
        string question;
        address oracle;
        bool resolved;
        MarketState result;
        uint256 createdAt;
        uint256 resolvedAt;
    }

    IERC20 public immutable COLLATERAL_TOKEN;
    uint256 public marketCounter;
    mapping(uint256 => Market) public markets;
    mapping(address => mapping(uint256 => bool)) public usedNonces;
    mapping(address => bool) public authorizedRelayers;

    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(address maker,uint256 marketId,uint256 amount,uint256 price,bool isYes,uint256 nonce)"
    );

    constructor(address _collateralToken) 
        ERC1155("Polymarket Position") 
        EIP712("Polymarket Clone", "1")
        Ownable(msg.sender) 
    {
        require(_collateralToken != address(0), "Invalid collateral token");
        COLLATERAL_TOKEN = IERC20(_collateralToken);
    }

    function addRelayer(address relayer) external onlyOwner {
        authorizedRelayers[relayer] = true;
    }

    function createCondition(string calldata _question, address _oracle) external returns (uint256 marketId) {
        require(_oracle != address(0), "Invalid oracle address");
        require(bytes(_question).length > 0, "Question cannot be empty");
        
        marketId = marketCounter++;
        markets[marketId] = Market({
            question: _question,
            oracle: _oracle,
            resolved: false,
            result: MarketState.Active,
            createdAt: block.timestamp,
            resolvedAt: 0
        });
        
        emit MarketCreated(marketId, _question, _oracle, block.timestamp);
    }

    function fillOrder(
        Order calldata makerOrder,
        Order calldata takerOrder,
        bytes calldata makerSig,
        bytes calldata takerSig
    ) external nonReentrant returns (bool success) {
        require(makerOrder.amount > 0, "Invalid maker amount");
        require(takerOrder.amount > 0, "Invalid taker amount");
        require(makerOrder.marketId == takerOrder.marketId, "Market mismatch");
        require(makerOrder.isYes != takerOrder.isYes, "Side must be opposite");
        require(makerOrder.maker != takerOrder.maker, "Self-trading not allowed");
        require(makerOrder.marketId < marketCounter, "Market does not exist");
        require(!markets[makerOrder.marketId].resolved, "Market resolved");
        require(!usedNonces[makerOrder.maker][makerOrder.nonce], "Maker nonce used");
        require(!usedNonces[takerOrder.maker][takerOrder.nonce], "Taker nonce used");
        require(_verifySignature(makerOrder.maker, _hashOrder(makerOrder), makerSig), "Invalid maker signature");
        require(_verifySignature(takerOrder.maker, _hashOrder(takerOrder), takerSig), "Invalid taker signature");
        require(makerOrder.price + takerOrder.price == 10000, "Price must sum to 1 USDC");

        usedNonces[makerOrder.maker][makerOrder.nonce] = true;
        usedNonces[takerOrder.maker][takerOrder.nonce] = true;

        uint256 fillAmount = makerOrder.amount < takerOrder.amount ? makerOrder.amount : takerOrder.amount;
        uint256 tokenId = makerOrder.isYes ? _getYesTokenId(makerOrder.marketId) : _getNoTokenId(makerOrder.marketId);
        address buyer = makerOrder.isYes ? makerOrder.maker : takerOrder.maker;
        address seller = makerOrder.isYes ? takerOrder.maker : makerOrder.maker;
        uint256 usdcAmount = (makerOrder.price * fillAmount) / 10000;

        COLLATERAL_TOKEN.safeTransferFrom(buyer, seller, usdcAmount);
        _safeTransferFrom(seller, buyer, tokenId, fillAmount, "");

        emit OrderFilled(makerOrder.marketId, makerOrder.maker, takerOrder.maker, fillAmount, makerOrder.price, takerOrder.price, makerOrder.isYes, msg.sender);
        return true;
    }

    function splitPosition(uint256 marketId, uint256 amount) external nonReentrant {
        require(marketId < marketCounter, "Market does not exist");
        require(!markets[marketId].resolved, "Market already resolved");
        require(amount > 0, "Amount must be greater than 0");
        
        COLLATERAL_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        
        uint256 yesTokenId = _getYesTokenId(marketId);
        uint256 noTokenId = _getNoTokenId(marketId);
        
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        
        tokenIds[0] = yesTokenId;
        tokenIds[1] = noTokenId;
        amounts[0] = amount;
        amounts[1] = amount;
        
        _mintBatch(msg.sender, tokenIds, amounts, "");
        emit PositionSplit(marketId, msg.sender, amount, amount, amount);
    }

    function redeemPositions(uint256 marketId, uint256 amount) external nonReentrant {
        require(marketId < marketCounter, "Market does not exist");
        require(markets[marketId].resolved, "Market not resolved yet");
        
        MarketState result = markets[marketId].result;
        uint256 tokenId;
        uint256 redeemAmount;
        
        if (result == MarketState.YesWins) {
            tokenId = _getYesTokenId(marketId);
            redeemAmount = amount;
        } else if (result == MarketState.NoWins) {
            tokenId = _getNoTokenId(marketId);
            redeemAmount = amount;
        } else if (result == MarketState.Invalid) {
            require(amount % 2 == 0, "Amount must be even for Invalid market");
            if (balanceOf(msg.sender, _getYesTokenId(marketId)) >= amount) {
                tokenId = _getYesTokenId(marketId);
                redeemAmount = amount / 2;
            } else if (balanceOf(msg.sender, _getNoTokenId(marketId)) >= amount) {
                tokenId = _getNoTokenId(marketId);
                redeemAmount = amount / 2;
            } else {
                revert("Insufficient tokens to redeem");
            }
        } else {
            revert("Market state error");
        }
        
        require(balanceOf(msg.sender, tokenId) >= amount, "Insufficient tokens");
        _burn(msg.sender, tokenId, amount);
        COLLATERAL_TOKEN.safeTransfer(msg.sender, redeemAmount);
        emit PositionRedeemed(marketId, msg.sender, amount, redeemAmount);
    }

    function resolveMarket(uint256 marketId, MarketState _result) external {
        require(marketId < marketCounter, "Market does not exist");
        require(msg.sender == markets[marketId].oracle, "Only oracle can resolve");
        require(!markets[marketId].resolved, "Market already resolved");
        require(_result != MarketState.Active, "Invalid result state");
        
        markets[marketId].resolved = true;
        markets[marketId].result = _result;
        markets[marketId].resolvedAt = block.timestamp;
        
        emit MarketResolved(marketId, _result, block.timestamp);
    }

    function _getYesTokenId(uint256 marketId) internal pure returns (uint256) {
        return marketId * 2 + 1;
    }
    
    function _getNoTokenId(uint256 marketId) internal pure returns (uint256) {
        return marketId * 2 + 2;
    }

    function _hashOrder(Order memory order) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            ORDER_TYPEHASH,
            order.maker,
            order.marketId,
            order.amount,
            order.price,
            order.isYes,
            order.nonce
        )));
    }

    function _verifySignature(address signer, bytes32 hash, bytes memory signature) internal view returns (bool) {
        return signer.isValidSignatureNow(hash, signature);
    }

    // Events
    event MarketCreated(uint256 indexed marketId, string question, address oracle, uint256 createdAt);
    event PositionSplit(uint256 indexed marketId, address indexed user, uint256 amountCollateral, uint256 yesTokens, uint256 noTokens);
    event PositionMerged(uint256 indexed marketId, address indexed user, uint256 yesTokensBurned, uint256 noTokensBurned, uint256 amountRedeemed);
    event MarketResolved(uint256 indexed marketId, MarketState result, uint256 resolvedAt);
    event PositionRedeemed(uint256 indexed marketId, address indexed user, uint256 tokensBurned, uint256 amountRedeemed);
    event OrderFilled(uint256 indexed marketId, address indexed maker, address indexed taker, uint256 amount, uint256 makerPrice, uint256 takerPrice, bool isYes, address relayer);
}
