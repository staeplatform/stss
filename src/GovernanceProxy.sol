pragma solidity 0.5.12;

contract GovernanceInf {
	function stake(address, uint256) external;
	function unstake(address, uint256) external;
	function stakeOf(address) public view returns(uint256);
}
contract VotingManagerInf {
	function updateWeight(address) public;
}

contract GovernanceProxy {
	// --- Auth ---
	mapping (address => uint256) public owners;
	function rely(address account) external auth { owners[account] = 1; }
	function deny(address account) external auth { owners[account] = 0; }
	modifier auth { 
		require(owners[msg.sender] == 1); 
		_; 
	}
	address public governance;
	address public votingManager;

	constructor(address governance_, address votingManager_) public {
		owners[msg.sender] = 1;
		governance = governance_;
		votingManager = votingManager_;
	}
	function stake(uint256 value) external {
		GovernanceInf(governance).stake(msg.sender, value);
		VotingManagerInf(votingManager).updateWeight(msg.sender);
	}
	function unstake(uint256 value) external {
		GovernanceInf(governance).unstake(msg.sender, value);
		VotingManagerInf(votingManager).updateWeight(msg.sender);
	}
	function stakeOf(address account) external view returns(uint256) {
		return GovernanceInf(governance).stakeOf(account);
	}
}
