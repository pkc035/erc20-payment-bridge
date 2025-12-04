// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

contract PaymentBridge {
    address public owner;                 
    address public payoutWallet;          

    IERC20 public immutable ccToken;      
    IERC20 public immutable cbkToken;    

    uint256 public constant CC_TO_CBK_RATE = 1000;

    event PaymentCompleted(
        address indexed from,
        uint256 ccAmount,
        uint256 cbkAmount,
        uint256 indexed userId,
        uint256 indexed productId
    );

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PayoutWalletUpdated(address indexed oldWallet, address indexed newWallet);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _ccTokenAddress, address _cbkTokenAddress) {
        owner = msg.sender;
        ccToken = IERC20(_ccTokenAddress);
        cbkToken = IERC20(_cbkTokenAddress);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setPayoutWallet(address _newWallet) external onlyOwner {
        require(_newWallet != address(0), "Invalid wallet");
        emit PayoutWalletUpdated(payoutWallet, _newWallet);
        payoutWallet = _newWallet;
    }

    function depositCbkToVault(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");

        uint256 allowed = cbkToken.allowance(msg.sender, address(this));
        require(allowed >= amount, "Not enough allowance set for contract");

        bool received = cbkToken.transferFrom(msg.sender, address(this), amount);
        require(received, "Transfer to contract failed");
    }

    function withdrawToken(address tokenAddress, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        require(tokenAddress != address(0), "Invalid token");

        IERC20 t = IERC20(tokenAddress);

        uint256 balance = t.balanceOf(address(this));
        require(balance >= amount, "Insufficient token balance");

        bool success = t.transfer(owner, amount);
        require(success, "Withdraw failed");
    }

    function depositCcAndSendCbk(
        uint256 ccAmount,
        uint256 userId,
        uint256 productId
    ) external {
        require(ccAmount > 0, "Amount must be > 0");
        require(payoutWallet != address(0), "Payout wallet not set");

        uint256 allowed = ccToken.allowance(msg.sender, address(this));
        require(allowed >= ccAmount, "Not enough CC allowance set for contract");

        bool received = ccToken.transferFrom(msg.sender, address(this), ccAmount);
        require(received, "CC transfer to contract failed");

        uint256 cbkAmount = ccAmount / CC_TO_CBK_RATE;
        require(cbkAmount > 0, "Amount too small for rate");

        uint256 cbkBalance = cbkToken.balanceOf(address(this));
        require(cbkBalance >= cbkAmount, "Insufficient CBK vault balance");

        bool sent = cbkToken.transfer(payoutWallet, cbkAmount);
        require(sent, "CBK transfer to payout wallet failed");

        emit PaymentCompleted(msg.sender, ccAmount, cbkAmount, userId, productId);
    }
}
