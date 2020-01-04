pragma solidity 0.5.12;

contract VotingInf {
	function veto() public;
	function updateWeight(address) public;
}
contract ExecutorInf {
	function rely(address) public;
}

contract VotingManager {
	// --- Auth ---
	mapping (address => uint256) public owners;
	function rely(address account) external auth { owners[account] = 1; }
	function deny(address account) external auth { owners[account] = 0; }
	modifier auth { 
		require(owners[msg.sender] == 1); 
		_; 
	}
	
	mapping(address=>uint256) public votingIdx;
	address[] public votings;
	uint256 public voteCount;
	function getNewVoteId() public auth returns (uint256) {
		voteCount++;
		return voteCount;
	}
	
	event NewVote(address vote);
	event NewPoll(address vote);
	event Vote(address indexed account, address indexed vote, uint256 option);
	event Poll(address indexed account, address indexed vote, uint256 option);
	event Execute(address indexed vote);
	
	constructor() public{
		owners[msg.sender] = 1;
	}

	function voted(bool poll, address account, uint256 option) external {
		require(votings[votingIdx[msg.sender]] == msg.sender, "VotingManager: Voting contract not exists");
		if (poll)
			emit Poll(account, msg.sender, option);
		else
			emit Vote(account, msg.sender, option);
	}

	function veto(address voting) external auth {
		VotingInf(voting).veto();
	}

	function newVote(address vote, address executor) external auth {
		require(vote != address(0), "VotingManager: Invalid voting address");
		require(votings[votingIdx[msg.sender]] != msg.sender, "VotingManager: Voting contract already exists");

		votingIdx[vote] = votings.length;
		votings.push(vote);

		if (executor != address(0)){
			ExecutorInf(executor).rely(vote);
			emit NewVote(vote);
		}
		else{
			emit NewPoll(vote);
		}
	}
	function closeVote(address vote) external auth {
		uint256 idx = votingIdx[vote];
		require(idx > 0 || votings[0] == vote, "VotingManager: Voting contract not exists");
		if (idx < votings.length - 1) {
			votings[idx] = votings[votings.length - 1];
			votingIdx[votings[idx]] = idx;
		}
		votingIdx[vote] = 0;
		votings.length--;
	}
	function updateWeight(address account) external {
		for (uint256 i = 0; i < votings.length; i ++){
			VotingInf(votings[i]).updateWeight(account);
		}
	}
}
