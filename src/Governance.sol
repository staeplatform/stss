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
contract TokenInf {
	function lock(address, uint) public;
	function unlock(address, uint) public;
	function locked(address) public view returns(uint256);
}

contract Governance {
	using SafeMath for uint256;
	
	// --- Auth ---
	mapping (address => uint256) public owners;
	function rely(address account) external auth { owners[account] = 1; }
	function deny(address account) external auth { owners[account] = 0; }
	modifier auth { 
		require(owners[msg.sender] == 1); 
		_; 
	}

	address public token;
	uint256 public minBackerBkr;
	
	uint256 public totalStake;

	event Stake(address indexed account, uint256 value);
	event Unstake(address indexed account, uint256 value);
	
	constructor(address token_, uint256 minBackerBkr_) public {
		owners[msg.sender] = 1;
		token = token_;
		minBackerBkr = minBackerBkr_;
	}
	function setMinBackerBkr(uint256 minBackerBkr_) external auth {
		minBackerBkr = minBackerBkr_;
	}
	function stake(address account, uint256 value) external auth {
		totalStake = totalStake.add(value);
		TokenInf(token).lock(account, value);
		emit Stake(account, value);
	}
	function unstake(address account, uint256 value) external auth {
		totalStake = totalStake.sub(value);
		TokenInf(token).unlock(account, value);
		emit Unstake(account, value);
	}
	function isBacker(address account) external view returns (bool) {
		return TokenInf(token).locked(account) >= minBackerBkr;
	}
	function stakeOf(address account) external view returns (uint256) {
		return TokenInf(token).locked(account);
	}
}

