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

  mapping(address => mapping(address => uint256)) private allowances;

  // Dividends
  address[] private holders;
  mapping(address => bool) private isHolder;
  mapping(address => uint256) private holderIndex;
  mapping(address => uint256) private withdrawableDividends;

  // IERC20

  function allowance(address owner, address spender) external view override returns (uint256) {
    return allowances[owner][spender];
  }

  function transfer(address to, uint256 value) external override returns (bool) {
    require(to != address(0), "Invalid recipient");
    _transfer(msg.sender, to, value);
    return true;
  }

  function approve(address spender, uint256 value) external override returns (bool) {
    require(spender != address(0), "Invalid spender");
    allowances[msg.sender][spender] = value;
    emit Approval(msg.sender, spender, value);
    return true;
  }

  function transferFrom(address from, address to, uint256 value) external override returns (bool) {
    require(to != address(0), "Invalid recipient");
    require(allowances[from][msg.sender] >= value, "Insufficient allowance");
    allowances[from][msg.sender] = allowances[from][msg.sender].sub(value);
    _transfer(from, to, value);
    return true;
  }

  // IMintableToken

  function mint() external payable override {
    require(msg.value > 0, "Mint value must be greater than 0");
    
    uint256 amount = msg.value;
    balanceOf[msg.sender] = balanceOf[msg.sender].add(amount);
    totalSupply = totalSupply.add(amount);
    
    // Add to holder list if not already present
    if (!isHolder[msg.sender]) {
      addHolder(msg.sender);
    }
    emit Transfer(address(0), msg.sender, amount);
  }

  function burn(address payable dest) external override {
    require(dest != address(0), "Invalid destination");
    require(balanceOf[msg.sender] > 0, "No tokens to burn");
    
    uint256 amount = balanceOf[msg.sender];
    balanceOf[msg.sender] = 0;
    totalSupply = totalSupply.sub(amount);
    
    // Remove from holder list
    if (isHolder[msg.sender]) {
      removeHolder(msg.sender);
    }
    
    emit Transfer(msg.sender, address(0), amount);
    // Send ETH to destination
    (bool success, ) = dest.call{value: amount}("");
    require(success, "ETH transfer failed");
  }

  // IDividends

  function getNumTokenHolders() external view override returns (uint256) {
    return holders.length;
  }

  function getTokenHolder(uint256 index) external view override returns (address) {
    if (index < 1 || index > holders.length) {
      return address(0);
    }
    return holders[index - 1]; // Convert 1-based to 0-based
  }

  function recordDividend() external payable override {
    require(msg.value > 0, "Dividend must be greater than 0");
    
    // Distribute dividend to all current holders
    for (uint256 i = 0; i < holders.length; i++) {
      address holder = holders[i];
      uint256 dividend = msg.value.mul(balanceOf[holder]).div(totalSupply);
      withdrawableDividends[holder] = withdrawableDividends[holder].add(dividend);
    }
  }

  function getWithdrawableDividend(address payee) external view override returns (uint256) {
    return withdrawableDividends[payee];
  }

  function withdrawDividend(address payable dest) external override {
    require(dest != address(0), "Invalid destination");
    uint256 amount = withdrawableDividends[msg.sender];
    withdrawableDividends[msg.sender] = 0;
    (bool success, ) = dest.call{value: amount}("");
    require(success, "ETH transfer failed");
    emit DividendWithdrawn(msg.sender, dest, amount);
  }

  // Helper functions

  function _transfer(address from, address to, uint256 value) private {
    require(balanceOf[from] >= value, "Insufficient balance");
    
    balanceOf[from] = balanceOf[from].sub(value);
    balanceOf[to] = balanceOf[to].add(value);
    
    // Update holder list
    if (balanceOf[from] == 0 && isHolder[from]) {
      removeHolder(from);
    }
    if (value > 0 && balanceOf[to] > 0 && !isHolder[to]) {
      addHolder(to);
    }
    emit Transfer(from, to, value);
  }

  function addHolder(address holder) private {
    holders.push(holder);
    isHolder[holder] = true;
    holderIndex[holder] = holders.length; // 1-based index to allow default 0
  }

  function removeHolder(address holder) private {
    uint256 index = holderIndex[holder];
    if (index == 0) {
      return;
    }

    uint256 lastIndex = holders.length;
    address lastHolder = holders[lastIndex - 1];

    if (index != lastIndex) {
      holders[index - 1] = lastHolder;
      holderIndex[lastHolder] = index;
    }

    holders.pop();
    delete holderIndex[holder];
    isHolder[holder] = false;
  }
}