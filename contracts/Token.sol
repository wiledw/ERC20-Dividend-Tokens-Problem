pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
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

  // Dividend accounting state variables
  uint256 constant ACCURACY = 1e18;
  uint256 public dividendPerToken;  // Scaled by ACCURACY
  mapping(address => int256) public dividendDebt;
  
  // ERC20 allowance
  mapping(address => mapping(address => uint256)) private _allowance;
  
  // Holder tracking
  address[] private holders;
  mapping(address => uint256) private holderIndex;  // 1-based, 0 = not in list

  // Helper function to add holder to list
  function _addHolder(address holder) private {
    if (holderIndex[holder] == 0 && balanceOf[holder] > 0) {
      holders.push(holder);
      holderIndex[holder] = holders.length;
    }
  }

  // Helper function to remove holder from list
  function _removeHolder(address holder) private {
    uint256 index = holderIndex[holder];
    if (index > 0 && balanceOf[holder] == 0) {
      // Swap with last element and pop
      uint256 lastIndex = holders.length;
      if (index != lastIndex) {
        address lastHolder = holders[lastIndex - 1];
        holders[index - 1] = lastHolder;
        holderIndex[lastHolder] = index;
      }
      holders.pop();
      holderIndex[holder] = 0;
    }
  }

  // IERC20

  function allowance(address owner, address spender) external view override returns (uint256) {
    return _allowance[owner][spender];
  }

  function transfer(address to, uint256 value) external override returns (bool) {
    require(to != address(0), "Transfer to zero address");
    require(balanceOf[msg.sender] >= value, "Insufficient balance");
    
    address sender = msg.sender;
    bool wasZeroSender = balanceOf[sender] == 0;
    bool wasZeroReceiver = balanceOf[to] == 0;
    
    // Update balances
    balanceOf[sender] = balanceOf[sender].sub(value);
    balanceOf[to] = balanceOf[to].add(value);
    
    // Update dividend debt: debt moves with tokens
    int256 debtAdjustment = int256(value.mul(dividendPerToken).div(ACCURACY));
    dividendDebt[sender] = dividendDebt[sender] - debtAdjustment;
    dividendDebt[to] = dividendDebt[to] + debtAdjustment;
    
    // Update holder list (only if balance actually changed from/to zero)
    if (value > 0) {
      if (wasZeroSender && balanceOf[sender] == 0) {
        // Was zero, still zero - no change
      } else if (!wasZeroSender && balanceOf[sender] == 0) {
        _removeHolder(sender);
      }
      
      if (wasZeroReceiver && balanceOf[to] > 0) {
        _addHolder(to);
      }
    }
    
    return true;
  }

  function approve(address spender, uint256 value) external override returns (bool) {
    _allowance[msg.sender][spender] = value;
    return true;
  }

  function transferFrom(address from, address to, uint256 value) external override returns (bool) {
    require(to != address(0), "Transfer to zero address");
    require(balanceOf[from] >= value, "Insufficient balance");
    require(_allowance[from][msg.sender] >= value, "Insufficient allowance");
    
    bool wasZeroSender = balanceOf[from] == 0;
    bool wasZeroReceiver = balanceOf[to] == 0;
    
    // Update balances
    balanceOf[from] = balanceOf[from].sub(value);
    balanceOf[to] = balanceOf[to].add(value);
    _allowance[from][msg.sender] = _allowance[from][msg.sender].sub(value);
    
    // Update dividend debt: debt moves with tokens
    int256 debtAdjustment = int256(value.mul(dividendPerToken).div(ACCURACY));
    dividendDebt[from] = dividendDebt[from] - debtAdjustment;
    dividendDebt[to] = dividendDebt[to] + debtAdjustment;
    
    // Update holder list (only if balance actually changed from/to zero)
    if (value > 0) {
      if (wasZeroSender && balanceOf[from] == 0) {
        // Was zero, still zero - no change
      } else if (!wasZeroSender && balanceOf[from] == 0) {
        _removeHolder(from);
      }
      
      if (wasZeroReceiver && balanceOf[to] > 0) {
        _addHolder(to);
      }
    }
    
    return true;
  }

  // IMintableToken

  function mint() external payable override {
    require(msg.value > 0, "Must send ETH");
    
    bool wasZero = balanceOf[msg.sender] == 0;
    
    // Update balance and total supply
    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
    totalSupply = totalSupply.add(msg.value);
    
    // Update dividend debt: new tokens get current dividendPerToken as debt
    // This ensures they don't receive historical dividends
    int256 newDebt = int256(msg.value.mul(dividendPerToken).div(ACCURACY));
    dividendDebt[msg.sender] = dividendDebt[msg.sender] + newDebt;
    
    // Add to holder list if was zero
    if (wasZero) {
      _addHolder(msg.sender);
    }
  }

  function burn(address payable dest) external override {
    require(balanceOf[msg.sender] > 0, "No balance to burn");
    require(dest != address(0), "Burn to zero address");
    
    uint256 amount = balanceOf[msg.sender];
    bool willBeZero = amount == balanceOf[msg.sender];
    
    // Update balance and total supply
    balanceOf[msg.sender] = balanceOf[msg.sender].sub(amount);
    totalSupply = totalSupply.sub(amount);
    
    // Update dividend debt: reduce debt by amount * dividendPerToken
    // This preserves any unclaimed dividends (negative debt)
    int256 debtReduction = int256(amount.mul(dividendPerToken).div(ACCURACY));
    dividendDebt[msg.sender] = dividendDebt[msg.sender] - debtReduction;
    
    // Remove from holder list if balance becomes zero
    if (willBeZero && balanceOf[msg.sender] == 0) {
      _removeHolder(msg.sender);
    }
    
    // Transfer ETH
    dest.transfer(amount);
  }

  // IDividends

  function getNumTokenHolders() external view override returns (uint256) {
    return holders.length;
  }

  function getTokenHolder(uint256 index) external view override returns (address) {
    require(index > 0 && index <= holders.length, "Index out of bounds");
    return holders[index - 1];
  }

  function recordDividend() external payable override {
    require(msg.value > 0, "Must send ETH");
    require(totalSupply > 0, "No tokens minted");
    
    // Add to dividendPerToken: (msg.value * ACCURACY) / totalSupply
    uint256 dividendIncrease = msg.value.mul(ACCURACY).div(totalSupply);
    dividendPerToken = dividendPerToken.add(dividendIncrease);
  }

  function getWithdrawableDividend(address payee) external view override returns (uint256) {
    // Formula: claimable = (balance * dividendPerToken) / ACCURACY - dividendDebt
    uint256 totalEarned = balanceOf[payee].mul(dividendPerToken).div(ACCURACY);
    int256 debt = dividendDebt[payee];
    
    // If debt is negative, it means they have unclaimed dividends from when they held tokens
    // In this case, totalEarned is 0 (no balance), so claimable = -debt
    if (debt < 0) {
      return uint256(-debt);
    }
    
    // Otherwise, calculate claimable = totalEarned - debt
    int256 claimable = int256(totalEarned) - debt;
    if (claimable > 0) {
      return uint256(claimable);
    }
    return 0;
  }

  function withdrawDividend(address payable dest) external override {
    require(dest != address(0), "Withdraw to zero address");
    
    uint256 claimable = this.getWithdrawableDividend(msg.sender);
    require(claimable > 0, "No dividend to withdraw");
    
    // Update dividend debt: increase by amount withdrawn
    // This sets claimable to 0 after withdrawal
    dividendDebt[msg.sender] = dividendDebt[msg.sender] + int256(claimable);
    
    // Transfer ETH
    dest.transfer(claimable);
  }
}