pragma solidity 0.5.12;

contract StoreInf{
	function updateCdpTypeParam(bytes32 currencyType, bytes32 collateralType, bytes32 field, uint256 value) external;
	function currencyTypes(bytes32) public view returns (address);
}
contract StaeTokenInf{
	function setStabilityRate(bytes32 collateralType, uint256 newRate) external;
	function setSavingsRate(uint256 newRate, uint48 interestPeriod_) external;
}

contract VotingExecutor {
	// --- Auth ---
	mapping (address => uint256) public owners;
	function rely(address account) external auth { owners[account] = 1; }
	function deny(address account) external auth { owners[account] = 0; }
	modifier auth { 
		require(owners[msg.sender] == 1); 
		_; 
	}
	
	address public actions;
	address public store;
	
	constructor(address votingManager, address store_, address actions_) public {
		owners[msg.sender] = 1;
		owners[votingManager] = 1;
		store = store_;
		actions = actions_;
	}
	function execute(bytes32 currencyType, bytes32 collateralType, bytes32 paramName, uint256 paramValue) auth external {
		if (paramName == 'stabilityRate'){
			address staeAddr = StoreInf(store).currencyTypes(currencyType);
			StaeTokenInf(staeAddr).setStabilityRate(collateralType, paramValue);
		} else {
			StoreInf(store).updateCdpTypeParam(currencyType, collateralType, paramName, paramValue);
		}
	}
}
