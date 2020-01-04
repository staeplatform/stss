pragma solidity 0.5.12;

import "./VotingContract.sol";

contract VotingManagerProxy {
	// --- Auth ---
	mapping (address => uint256) public owners;
	function rely(address account) external auth { owners[account] = 1; }
	function deny(address account) external auth { owners[account] = 0; }
	modifier auth {
		require(owners[msg.sender] == 1); 
		_; 
	}
	address votingManager;
	address governance;

	event NewVote(address vote);
	event NewPoll(address vote);
	
	constructor(address votingManager_, address governance_) public{
		owners[msg.sender] = 1;
		votingManager = votingManager_;
		governance = governance_;
	}

	function newVote(bytes32 name_, 
	                 bytes32[] memory options_, 
	                 uint256 quorum_, 
	                 uint256 voteEndTime_,
	                 address executor_, 
	                 uint256 executeDelay_, 
	                 bytes32[] memory executeParam_
	                ) auth public {
		uint256 id = VotingManagerInf(votingManager).getNewVoteId();
		VotingContract vote = new VotingContract(votingManager, governance, id, name_, options_, quorum_, voteEndTime_, executor_, executeDelay_, executeParam_);
		if (executeParam_.length != 0)
			VotingManagerInf(votingManager).newVote(address(vote), executor_);
		else
			VotingManagerInf(votingManager).newVote(address(vote), address(0));
	}
	function updateWeight(address account) external {
		VotingManagerInf(votingManager).updateWeight(account);
	}
}
