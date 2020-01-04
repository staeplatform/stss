pragma solidity 0.5.12;
contract ERC20Inf {
	function transfer(address to, uint256 value) public returns (bool);
	function transferFrom(address from, address to, uint256 value) public returns (bool);
	function mint(address account, uint256 value) public;
	function burn(address account, uint256 value) public;
}
contract StoreInf {
	function transfer(address, uint256) public returns (bool);
	function transferETH(uint256) public returns (bool);
	function depositAddresses(uint256) public returns (bytes32);
}
contract ActionsInf {
	function processDeposit(address from, uint256 value, bytes memory extraData) public;
}


/*
Ether:
1. user -> ETHTeller.transferAndCall.value(...).(...) -> Actions.processDeposit()

Bitcoin:
desposit:
1. user deposits BTC to multi-sig wallet
3. BTC notifications watcher -> BtcTeller.mintAndCall() -> Token(BTC).mint()

withdrawl:
1. user sends withdrawl request, 
2. ETH events watcher -> BtcTeller.withdrawalConfirm() -> Token(BTC).burn()

ERC827:
1. user -> Token.transferAndCall() -> ERCTeller.onTokenTransfer() -> Actions.processDeposit()
OR:
1. user -> Token.approveAndCall() -> ERCTeller.receiveApproval() -> { Token.transferFrom() , Actions.processDeposit() }

ERC20:
1. user -> Token.approve()
2. user -> ERCTeller.receiveApproval() ->  { Token.transferFrom() , Actions.processDeposit() }
*/

contract ETHTeller {
	// --- Auth ---
	mapping (address => uint) public contractACL;
	function rely(address usr) external auth { contractACL[usr] = 1; }
	function deny(address usr) external auth { contractACL[usr] = 0; }
	modifier auth { require(contractACL[msg.sender] == 1, "Teller: Not authorized"); _; }

	address payable storeAddr;
	address actionsAddr;

	constructor(address payable storeAddr_, address actionsAddr_) public {
		contractACL[msg.sender] = 1;
		storeAddr = storeAddr_;
		actionsAddr = actionsAddr_;
	}

	function () external payable {
	}

	function transferAndCall(address spender, uint256 value, bytes memory extraData) public payable {
		require(value == msg.value, "Token not matched");
		storeAddr.transfer(msg.value);
		ActionsInf(actionsAddr).processDeposit(msg.sender, value, extraData);
		spender; // silence warnings
	}

	function transferOut(address payable recipient, uint256 value, bytes memory params) public auth {
		StoreInf(storeAddr).transferETH(value);
		recipient.transfer(value);
		params; // silence warnings
	}
}

contract ERCTeller {
	// --- Auth ---
	mapping (address => uint) public contractACL;
	function rely(address usr) external auth { contractACL[usr] = 1; }
	function deny(address usr) external auth { contractACL[usr] = 0; }
	modifier auth { require(contractACL[msg.sender] == 1, "Teller: Not authorized"); _; }

	address public storeAddr;
	address public actionsAddr;
	address public tokenAddr;

	constructor(address storeAddr_, address actionsAddr_, address tokenAddr_) public {
		contractACL[msg.sender] = 1;
		storeAddr = storeAddr_;
		actionsAddr = actionsAddr_;
		tokenAddr = tokenAddr_;
	}

	// ERC223 Interface
	function tokenFallback(address from, uint256 value, bytes memory extraData) public {
		require(tokenAddr == msg.sender, "Teller: Token not matched");
		ERC20Inf(tokenAddr).transfer(storeAddr, value);
		ActionsInf(actionsAddr).processDeposit(from, value, extraData);
	}
	// ERC677 Interface
	function onTokenTransfer(address from, uint256 value, bytes memory extraData) public {
		require(msg.sender == tokenAddr, "Teller: Token not matched");
		ERC20Inf(tokenAddr).transfer(storeAddr, value);
		ActionsInf(actionsAddr).processDeposit(from, value, extraData);
	}
	// ERC???
	function receiveApproval(address from, uint256 value, address tokenAddr_, bytes memory extraData) public {
		require(msg.sender == from || msg.sender == tokenAddr, "Token not matched");
		require(tokenAddr == tokenAddr_, "Teller: Token not matched");
		ERC20Inf(tokenAddr).transferFrom(from, address(this), value);
		ERC20Inf(tokenAddr).transfer(storeAddr, value);
		ActionsInf(actionsAddr).processDeposit(from, value, extraData);
	}

	function transferOut(address recipient, uint256 value, bytes memory params) public auth {
		StoreInf(storeAddr).transfer(tokenAddr, value);
		ERC20Inf(tokenAddr).transfer(recipient, value);
		params; // silence warnings
	}
}
contract BTCTeller {
	// --- Auth ---
	mapping (address => uint) public contractACL;
	function rely(address usr) external auth { contractACL[usr] = 1; }
	function deny(address usr) external auth { contractACL[usr] = 0; }
	modifier auth { require(contractACL[msg.sender] == 1, "Teller: Not authorized"); _; }

	mapping (address => uint) public owners;
	function addOwner(address usr) owner external {
		owners[usr] = 1;
	}
	function removeOwner(address usr) owner external {
		require(msg.sender != usr, "Cannot remove own account");
		owners[usr] = 0;
	}
	modifier owner { require(owners[msg.sender] == 1, "Teller: Not authorized"); _; }

	address public storeAddr;
	address public actionsAddr;
	address public tokenAddr;

	event WithdrawalRequest(uint256 indexed cdpi, uint256 amt, bytes32 targetAddr);
	event TransferRequest(bytes32 targetAddr, uint256 amt);

	constructor(address storeAddr_, address actionsAddr_, address tokenAddr_) public {
		contractACL[msg.sender] = 1;
		owners[msg.sender] = 1;
		storeAddr = storeAddr_;
		actionsAddr = actionsAddr_;
		tokenAddr = tokenAddr_;
	}

	// called by watcher when there is BTC deposit to the registered BTC wallet address, mimic to transferAndCall()
	function mintAndCall(address from, uint256 value, bytes memory extraData) public owner {
		ERC20Inf(tokenAddr).mint(storeAddr, value);
		uint256 cdpi;
		bytes32 bitcoinWallet;
		assembly{
			let offset := mload(extraData)
			cdpi := mload(add(extraData, 0x40))
			bitcoinWallet := mload(add(extraData, offset))
		}
  		require(StoreInf(storeAddr).depositAddresses(cdpi) == bitcoinWallet, "Teller: Bitcoin address not matched");
		
		ActionsInf(actionsAddr).processDeposit(from, value, extraData);
	}

	function transferOut(address recipient, uint256 value, bytes memory params) public auth {
		bytes32 targetAddr;
		uint256 cdpi;
		assembly{
			// if not(eq(payloadSize, 0x40)) { revert(0, 0) }
			targetAddr := mload(add(params, 0x20))
			cdpi := mload(add(params, 0x40))
		}

		if (cdpi != 0)
			emit WithdrawalRequest(cdpi, value, targetAddr);
		else
			emit TransferRequest(targetAddr, value);

		recipient; // silence warnings
	}
}

