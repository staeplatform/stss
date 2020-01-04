pragma solidity 0.5.12;

library SafeMath {
	function sub(uint256 a, uint256 b) internal pure returns (uint256) {
		require(b <= a, "SafeMath: subtraction overflow");
		uint256 c = a - b;

		return c;
	}
	function add(uint256 a, uint256 b) internal pure returns (uint256) {
		uint256 c = a + b;
		require(c >= a, "SafeMath: addition overflow");

		return c;
	}
}
// ERC677
contract ERC677Receiver {
	function onTokenTransfer(address _sender, uint256 _value, bytes memory _data) public;
}

contract Token {
	using SafeMath for uint256;
	
	// --- Auth ---
	mapping (address => uint256) public owners;
	function rely(address account) external auth { owners[account] = 1; }
	function deny(address account) external auth { owners[account] = 0; }
	modifier auth {
		//**********  access control disabled for easy testing  *********
		require(owners[msg.sender] == 1, "Token: Not authorized"); 
		_; 
	}

	// --- ERC20 Data ---
	string  public symbol;
	string  public name;
	uint256 public cap;
	uint8 public constant decimals = 18;
	
	mapping (address => uint256) private _balances;
	mapping (address => uint256) private _locked;
	uint256 public totalLocked;
	mapping (address => mapping (address => uint256)) private _allowances;
	uint256 private _totalSupply;

	event Transfer(address indexed from, address indexed to, uint256 value);
	event Approval(address indexed owner, address indexed spender, uint256 value);
	event Lock(address indexed owner, uint256 value);
	event Unlock(address indexed owner, uint256 value);

	constructor(string memory symbol_, string memory name_, uint256 initialSupply_, uint256 cap_) public {
		owners[msg.sender] = 1;
		symbol = symbol_;
		name = name_;
		cap = cap_;
		_totalSupply = initialSupply_;
		_balances[msg.sender] = _totalSupply;
	}
	function mint(address account, uint256 value) external auth {
		require(account != address(0), "ERC20: mint to the zero address");

		_totalSupply = _totalSupply.add(value);
		require(cap == 0 || cap >= _totalSupply, "ERC20Capped: cap exceeded");
		_balances[account] = _balances[account].add(value); 
		emit Transfer(address(0), account, value);
	}
	function burn(address account, uint256 value) external auth {
		require(account != address(0), "ERC20: burn from the zero address");

		_totalSupply = _totalSupply.sub(value);
		_balances[account] = _balances[account].sub(value);
		emit Transfer(account, address(0), value);
	}
	function totalSupply() external view returns (uint256) {
		return _totalSupply;
	}
	function balanceOf(address owner) external view returns (uint256) {
		return _balances[owner];
	}
	function allowance(address owner, address spender) external view returns (uint256) {
		return _allowances[owner][spender];
	}
	function transfer(address to, uint256 value) external returns (bool) {
		_transfer(msg.sender, to, value);
		return true;
	}
	function approve(address spender, uint256 value) external returns (bool) {
		_approve(msg.sender, spender, value);
		return true;
	}

	// ERC677
	function transferAndCall(address spender, uint256 value, bytes memory extraData) public returns (bool success) {
		_transfer(msg.sender, spender, value);
		uint256 length;
		assembly { 
			length := extcodesize(spender)
		}
		if (length > 0){
			ERC677Receiver(spender).onTokenTransfer(msg.sender, value, extraData);
		}
		return true;
	}

	function transferFrom(address from, address to, uint256 value) external returns (bool) {
		_transfer(from, to, value);
		_approve(from, msg.sender, _allowances[from][msg.sender].sub(value));
		return true;
	}
	function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
		_approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
		return true;
	}
	function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
		_approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue));
		return true;
	}
	function _transfer(address from, address to, uint256 value) internal {
		require(from != address(0), "ERC20: transfer from the zero address");
		require(to != address(0), "ERC20: transfer to the zero address");

		_balances[from] = _balances[from].sub(value);
		_balances[to] = _balances[to].add(value);
		emit Transfer(from, to, value);
	}
	function _approve(address owner, address spender, uint256 value) internal {
		require(owner != address(0), "ERC20: approve from the zero address");
		require(spender != address(0), "ERC20: approve to the zero address");

		_allowances[owner][spender] = value;
		emit Approval(owner, spender, value);
	}

	// BKR specifics
	function lock(address usr, uint256 value) external auth {
		require(usr != address(0), "BKR: Invalid address");
		require(value < _balances[usr], "BKR: Insufficient fund");
		totalLocked = totalLocked.add(value);
		_balances[usr] = _balances[usr].sub(value);
		_locked[usr] = _locked[usr].add(value);
		emit Lock(usr, value);
	}
	function unlock(address usr, uint256 value) external auth {
		require(usr != address(0), "BKR: Invalid address");
		require(value < _locked[usr], "BKR: unlock value exceed locked fund");
		totalLocked = totalLocked.sub(value);
		_balances[usr] = _balances[usr].add(value);
		_locked[usr] = _locked[usr].sub(value);
		emit Unlock(usr, value);
	}
	function locked(address account) external view returns(uint256) {
		return _locked[account];
	}
}
