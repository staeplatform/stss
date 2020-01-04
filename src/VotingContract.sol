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
	function mul(uint256 a, uint256 b) internal pure returns (uint256) {
		if (a == 0) {
			return 0;
		}
		uint256 c = a * b;
		require(c / a == b, "SafeMath: multiplication overflow");

		return c;
	}
	// function mul(uint256 a, uint256 b, uint256 unit) internal pure returns (uint256) {
	// 	return div(mul(a, b), unit);
	// }
	function div(uint256 a, uint256 b) internal pure returns (uint256) {
		// Solidity only automatically asserts when dividing by 0
		require(b > 0, "SafeMath: division by zero");
		uint256 c = a / b;
		// assert(a == b * c + a % b); // There is no case in which this doesn't hold

		return c;
	}
	function div(uint256 a, uint256 b, uint256 unit) internal pure returns (uint256) {
		return div(mul(a, unit), b);
	}
}
contract GovernanceInf {
	uint256 public totalStake;
	function stakeOf(address) public view returns(uint256);
}
contract ExecutorInf { 
	function execute(bytes32 currencyType, bytes32 collateralType, bytes32 paramName, uint256 paramValue) public;
	function deny(address account) public;
}
contract VotingManagerInf {
	function getNewVoteId() public returns (uint256);
	function voted(bool poll, address account, uint256 option) public;
	function newVote(address, address) public;
	function updateWeight(address) public;
}

contract VotingContract {
	using SafeMath for uint256;

	uint256 constant WEI = 10 ** 18;
	
	address public votingManager; 
	address public governance;
	address public executor;
	uint256 public id;
	bytes32 public name;
	bytes32[] public _options;
	uint256 public quorum;
	
	uint256 public voteStartTime;
	uint256 public voteEndTime;
	uint256 public executeDelay;
	bool public executed;
	bool public vetoed;
	
	mapping(address=>uint256) public accountVoteOption;
	mapping(address=>uint256) public accountVoteWeight;
	uint256[] public _optionsWeight;
	uint256 public totalVoteWeight;
	uint256 public totalWeight;
	bytes32[] public _executeParam;

	// --- Auth ---
	mapping (address => uint256) public owners;
	function rely(address account) external auth { owners[account] = 1; }
	function deny(address account) external auth { owners[account] = 0; }
	modifier auth { 
		//TODO: enable auth checking
		require(owners[msg.sender] == 1, "VotingContract: Not authorized"); 
		_; 
	}

	event Execute();
	
	constructor(address votingManager_, 
	            address governance_, 
	            uint256 id_, 
	            bytes32 name_, 
	            bytes32[] memory options_, 
	            uint256 quorum_, 
	            uint256 voteEndTime_,
	            address executor_, 
	            uint256 executeDelay_, 
	            bytes32[] memory executeParam_
	           ) public {
		require(executeParam_.length == 0 || executeParam_.length == 4);
		require(now <= voteEndTime_, 'already ended');
		if (executeParam_.length != 0){
			require(options_.length == 2 && options_[0] == 'Y' && options_[1] == 'N');
			require(quorum_ > 0 && quorum_ < uint256(100).mul(WEI));
		}
		owners[votingManager_] = 1;
		votingManager = votingManager_;
		executor = executor_;
		governance = governance_;
		totalWeight = GovernanceInf(governance).totalStake();
		id = id_;
		name = name_;
		_options = options_;
		quorum = quorum_;
		_optionsWeight.length = options_.length;
		
		voteStartTime = now;
		voteEndTime = voteEndTime_;
		executeDelay = executeDelay_;
		_executeParam = executeParam_;
	}
	function veto() external auth {
		require(!executed, 'already executed');
		vetoed = true;
	}
	function optionsCount() external view returns(uint256){
		return _options.length;
	}
	function options() external view returns (bytes32[] memory){
		return _options;
	}
	function optionsWeight() external view returns (uint256[] memory){
		return _optionsWeight;
	}
	function execute() external {
		require(now > voteEndTime + executeDelay);
		
		require(!vetoed, 'VotingContract: Vote already vetoed');
		require(!executed, 'VotingContract: Vote already executed');
		require(_executeParam.length != 0, 'VotingContract: Execute param not defined');

		uint256 ratio = totalVoteWeight.div(totalWeight, WEI); 
		require(ratio > quorum, 'quorum not met');
		
		require(_optionsWeight[0] > _optionsWeight[1]); // 0: Y, 1:N
		executed = true;
		ExecutorInf(executor).execute(_executeParam[0], _executeParam[1], _executeParam[2], uint256(_executeParam[3]));
		ExecutorInf(executor).deny(address(this));
		emit Execute();
	}
	function vote(uint256 option) external {
		require(now <= voteEndTime, 'VotingContract: Vote already ended');
		require(!vetoed, 'VotingContract: Vote already vetoed');
		require(!executed, 'VotingContract: Vote already executed');
		require(option < _options.length, 'VotingContract: Invalid option');

		VotingManagerInf(votingManager).voted(_executeParam.length == 0, msg.sender, option);

		uint256 currVoteWeight = accountVoteWeight[msg.sender];
		if (currVoteWeight > 0){
			uint256 currVoteIdx = accountVoteOption[msg.sender];	
			_optionsWeight[currVoteIdx] = _optionsWeight[currVoteIdx].sub(currVoteWeight);
			totalVoteWeight = totalVoteWeight.sub(currVoteWeight);
		}
		
		uint256 weight = GovernanceInf(governance).stakeOf(msg.sender);
		accountVoteOption[msg.sender] = option;
		accountVoteWeight[msg.sender] = weight;
		if (weight > 0){
			_optionsWeight[option] = _optionsWeight[option].add(weight);
			totalVoteWeight = totalVoteWeight.add(weight);
		}
		totalWeight = GovernanceInf(governance).totalStake();
	}
	function updateWeight(address account) external {
		if (now <= voteEndTime && !vetoed && !executed){
			uint256 weight = GovernanceInf(governance).stakeOf(account);
			uint256 currVoteWeight = accountVoteWeight[account];
			if (currVoteWeight > 0 && currVoteWeight != weight){
				uint256 currVoteIdx = accountVoteOption[account];
				accountVoteWeight[account] = weight;
				_optionsWeight[currVoteIdx] = _optionsWeight[currVoteIdx].sub(currVoteWeight).add(weight);
				totalVoteWeight = totalVoteWeight.sub(currVoteWeight).add(weight);
			}
			totalWeight = GovernanceInf(governance).totalStake();
		}
	}
	function executeValue() external view returns (uint256){
		return uint256(_executeParam[3]);
	}
	function executeParam() external view returns (bytes32[] memory){
		return _executeParam;
	}
}
