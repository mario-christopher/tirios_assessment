// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
  /**
   * @dev Mintable ERC-20 token backed 1:1 by deposited ETH, with
   *      dividend distribution to holders based on proportional balances.
   *      Recorded dividends remain withdrawable even after tokens are
   *      transferred or burned.
   */
  // ------------------------------------------ //
  // ----- BEGIN: DO NOT EDIT THIS SECTION ---- //
  // ------------------------------------------ //
  using SafeMath for uint256;
  uint256 public totalSupply;
  uint256 public decimals = 18;
  string public name = "Test token";
  string public symbol = "TEST";
  mapping (address => uint256) public balanceOf;
  // ------------------------------------------ //
  // ----- END: DO NOT EDIT THIS SECTION ------ //  
  // ------------------------------------------ //

  // ERC20
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
  event DividendWithdrawn(address indexed payee, address indexed dest, uint256 amount);

  mapping(address => mapping(address => uint256)) private _allowances;

  // Dividends
  address[] private _tokenHolders;
  mapping(address => bool) private _isTokenHolder;
  mapping(address => uint256) private _tokenHolderIndex;
  mapping(address => uint256) private _withdrawableDividend;

  // IERC20

  function allowance(address owner_, address spender_) external view override returns (uint256) {
    return _allowances[owner_][spender_];
  }

  function transfer(address to_, uint256 value_) external override returns (bool) {
    require(to_ != address(0), "Invalid recipient");
    _transfer(msg.sender, to_, value_);
    return true;
  }

  function approve(address spender_, uint256 value_) external override returns (bool) {
    require(spender_ != address(0), "Invalid spender");
    _allowances[msg.sender][spender_] = value_;
    emit Approval(msg.sender, spender_, value_);
    return true;
  }

  function transferFrom(address from_, address to_, uint256 value_) external override returns (bool) {
    require(from_ != address(0), "Invalid sender");
    require(to_ != address(0), "Invalid recipient");
    require(_allowances[from_][msg.sender] >= value_, "Insufficient allowance");
    _allowances[from_][msg.sender] = _allowances[from_][msg.sender].sub(value_);
    _transfer(from_, to_, value_);
    return true;
  }

  // IMintableToken

  function mint() external payable override {
    require(msg.value > 0, "Mint value must be greater than 0");
    
    uint256 amount = msg.value;
    balanceOf[msg.sender] = balanceOf[msg.sender].add(amount);
    totalSupply = totalSupply.add(amount);
    
    // Add to token holder list if not already present
    if (!_isTokenHolder[msg.sender]) {
      _addTokenHolder(msg.sender);
    }
    emit Transfer(address(0), msg.sender, amount);
  }

  function burn(address payable dest_) external override {
    require(dest_ != address(0), "Invalid destination");
    require(balanceOf[msg.sender] > 0, "No tokens to burn");
    
    uint256 amount = balanceOf[msg.sender];
    balanceOf[msg.sender] = 0;
    totalSupply = totalSupply.sub(amount);
    
    // Remove from token holder list
    if (_isTokenHolder[msg.sender]) {
      _removeTokenHolder(msg.sender);
    }
    
    emit Transfer(msg.sender, address(0), amount);
    // Send ETH to destination
    (bool success, ) = dest_.call{value: amount}("");
    require(success, "ETH transfer failed");
  }

  // IDividends

  function getNumTokenHolders() external view override returns (uint256) {
    return _tokenHolders.length;
  }

  function getTokenHolder(uint256 index_) external view override returns (address) {
    if (index_ < 1 || index_ > _tokenHolders.length) {
      return address(0);
    }
    return _tokenHolders[index_ - 1]; // Convert 1-based to 0-based
  }

  function recordDividend() external payable override {
    require(msg.value > 0, "Dividend must be greater than 0");
    require(totalSupply > 0, "No tokens minted");
    // Distribute dividend to all current holders
    for (uint256 i = 0; i < _tokenHolders.length; i++) {
      address tokenHolder = _tokenHolders[i];
      uint256 dividend = msg.value.mul(balanceOf[tokenHolder]).div(totalSupply);
      _withdrawableDividend[tokenHolder] = _withdrawableDividend[tokenHolder].add(dividend);
    }
  }

  function getWithdrawableDividend(address payee_) external view override returns (uint256) {
    return _withdrawableDividend[payee_];
  }

  function withdrawDividend(address payable dest_) external override {
    require(dest_ != address(0), "Invalid destination");
    uint256 amount = _withdrawableDividend[msg.sender];
    require(amount > 0, "No dividend to withdraw");
    _withdrawableDividend[msg.sender] = 0;
    (bool success, ) = dest_.call{value: amount}("");
    require(success, "ETH transfer failed");
    emit DividendWithdrawn(msg.sender, dest_, amount);
  }

  // Helper functions

  function _transfer(address from_, address to_, uint256 value_) private {
    require(balanceOf[from_] >= value_, "Insufficient balance");
    
    balanceOf[from_] = balanceOf[from_].sub(value_);
    balanceOf[to_] = balanceOf[to_].add(value_);
    
    // Update token holder list
    if (balanceOf[from_] == 0 && _isTokenHolder[from_]) {
      _removeTokenHolder(from_);
    }
    if (value_ > 0 && balanceOf[to_] > 0 && !_isTokenHolder[to_]) {
      _addTokenHolder(to_);
    }
    emit Transfer(from_, to_, value_);
  }

  function _addTokenHolder(address tokenHolder_) private {
    _tokenHolders.push(tokenHolder_);
    _isTokenHolder[tokenHolder_] = true;
    _tokenHolderIndex[tokenHolder_] = _tokenHolders.length; // 1-based index to allow default 0
  }

  function _removeTokenHolder(address tokenHolder_) private {
    uint256 index_ = _tokenHolderIndex[tokenHolder_];
    if (index_ == 0) {
      return;
    }

    uint256 lastIndex = _tokenHolders.length;
    address lastTokenHolder = _tokenHolders[lastIndex - 1];

    if (index_ != lastIndex) {
      _tokenHolders[index_ - 1] = lastTokenHolder;
      _tokenHolderIndex[lastTokenHolder] = index_;
    }

    _tokenHolders.pop();
    delete _tokenHolderIndex[tokenHolder_];
    _isTokenHolder[tokenHolder_] = false;
  }
}