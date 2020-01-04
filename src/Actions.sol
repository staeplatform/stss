pragma solidity 0.5.12;

contract StoreInf {
	function cdpTypes(bytes32 currencyType, bytes32 collateralType) public view returns (uint256 liquidationPenalty, uint256 liquidationDiscount, uint256 riskRatio, uint256 totalCollateralAmt, uint256 totalNormalizedDebt);
	function cdps(uint256 cdpi) public view returns (address owner, bytes32 currencyType, bytes32 collateralType, uint256 collateralAmt, uint256 normalizedDebt);
	function currencyTypes(bytes32) public view returns (address);
	function open(bytes32 currencyType, bytes32 collateralType, address usr) external returns (uint256 cdpi);
	function close(address from, uint256 cdpi) external;
	function cdpAdjustment(address from, uint256 cdpi, int256 colAdj, int256 normalizedDebtAdj, int256 debtAdj) external;
	function collateralTellers(bytes32 collateralType) public view returns (address);
	function collateralTellersInv(address) public view returns (bytes32 collateralType);
}
contract StaeTokenInf {
	function mint(address account, bytes32 collateralType, uint256 value) external returns (uint256 normalizedDebt, uint256 normalizedSaving);
	function burn(address account, bytes32 collateralType, uint256 value) external returns (uint256 normalizedDebt, uint256 normalizedSaving);
	function toCurrentDebt(bytes32 collateralType, uint256 normalizedValue) public view returns (uint256);
}
contract ERC20Inf {
	function balanceOf(address owner) public view returns (uint256);
}
contract TellerInf {
	function transferOut(address payable recipient, uint256 value, bytes memory params) public;
}
library SafeMath {
	function toInt256(uint256 x) internal pure returns (int256 y) {
		y = int256(x);
		require(y >= 0, "int-overflow");
	}
}
contract Actions {
	using SafeMath for uint256;

	uint256 constant GETHER = 10 ** 27;
	uint256 constant WEI = 10 ** 18;

	// --- Auth ---
	mapping (address => uint) public contractACL;
	function rely(address usr) external auth { contractACL[usr] = 1; }
	function deny(address usr) external auth { contractACL[usr] = 0; }
	modifier auth { require(contractACL[msg.sender] == 1, "Actions: Not authorized"); _; }


	address public storeAddr;

	constructor(address storeAddr_) public {
		contractACL[msg.sender] = 1;
		storeAddr = storeAddr_;
	}

	function open(bytes32 currencyType, bytes32 collateralType) external returns (uint256 cdpi)  {
		return openFrom(msg.sender, currencyType, collateralType);
	}
	function openFrom(address from, bytes32 currencyType, bytes32 collateralType) private returns (uint256 cdpi)  {
		cdpi = StoreInf(storeAddr).open(currencyType, collateralType, from);
		return cdpi;
	}

	function transferCollateralIn(address from, uint256 cdpi, uint256 amt) private {
		(address owner,, bytes32 collateralType,,) = StoreInf(storeAddr).cdps(cdpi);
		address teller = StoreInf(storeAddr).collateralTellers(collateralType);
		require(msg.sender == teller, "Actions: Teller not match");
		require(owner == from, "Actions: CDP owner not match");
		amt; // silence warnings
	}
	// params: for BTC, it will be the target bitcoin address transfering to
	function transferCollateralOut(uint256 cdpi, uint256 amt, bytes memory params) private {
		(address owner,, bytes32 collateralType,,) = StoreInf(storeAddr).cdps(cdpi);
		require(msg.sender == owner, "Actions: CDP owner not match");

		params = abi.encodePacked(params, cdpi);
		address teller = StoreInf(storeAddr).collateralTellers(collateralType);
		TellerInf(teller).transferOut(msg.sender, amt, params);
	}

	function transferStaeIn(address from, uint256 cdpi, uint256 amt) private returns (uint256 normalizedAmt) {
		(address owner, bytes32 currencyType, bytes32 collateralType,,) = StoreInf(storeAddr).cdps(cdpi);
		require(from == owner, "Actions: CDP owner not match");

		(normalizedAmt, ) = StaeTokenInf(StoreInf(storeAddr).currencyTypes(currencyType)).burn(from, collateralType, amt);
	}
	function transferStaeOut(address from, uint256 cdpi, uint256 amt) private returns (uint256 normalizedAmt){
		(address owner, bytes32 currencyType, bytes32 collateralType,,) = StoreInf(storeAddr).cdps(cdpi);
		require(from == owner, "Actions: CDP owner not match");

		(normalizedAmt, ) = StaeTokenInf(StoreInf(storeAddr).currencyTypes(currencyType)).mint(from, collateralType, amt);
	}
	
	// called from collateral tellers
	function processDeposit(address from, uint256 value, bytes memory extraData) public {
		bytes32 action;

		uint256 len = extraData.length;
		bytes32 currencyType;
		uint256 drawAmt;
		uint256 cdpi;

		assembly {
			action := mload(add(extraData, 0x20))
			switch action
			case "openDeposit" {
				currencyType := mload(add(extraData, 0x40))
			}
			case "openDepositDraw" {
				currencyType := mload(add(extraData, 0x40))
				drawAmt := mload(add(extraData, 0x60))
			}
			case "deposit" {
				cdpi := mload(add(extraData, 0x40))
			}
			case "depositDraw" {
				cdpi := mload(add(extraData, 0x40))
				drawAmt := mload(add(extraData, 0x60))
			}
		}

		if (action == "openDeposit"){
			cdpi = openDepositCollateralDrawStae(from, currencyType, value, 0);
		}else if (action == "openDepositDraw"){
			cdpi = openDepositCollateralDrawStae(from, currencyType, value, drawAmt);
		}else if (action == "deposit"){
			depositCollateralDrawStae(from, cdpi, value, 0);
		}else if (action == "depositDraw"){
			depositCollateralDrawStae(from, cdpi, value, drawAmt);
		}else{
			revert();
		}
	}

	function drawStae(uint256 cdpi, uint256 amt) external {
		depositCollateralDrawStae(msg.sender, cdpi, 0, amt);
	}

	// since user shouldn't call deposit collaterals directly (they should call through teller), make these functions private
	function depositCollateralDrawStae(address from, uint256 cdpi, uint256 depositAmt, uint256 drawAmt) private {
		if (depositAmt > 0)
			transferCollateralIn(from, cdpi, depositAmt);

		uint256 normalizedAmt = 0;
		if (drawAmt > 0)
			normalizedAmt = transferStaeOut(from, cdpi, drawAmt);

		StoreInf(storeAddr).cdpAdjustment(from, cdpi, depositAmt.toInt256(), normalizedAmt.toInt256(), drawAmt.toInt256());
	}
	function openDepositCollateralDrawStae(address from, bytes32 currencyType, uint256 depositAmt, uint256 drawAmt) private returns (uint256 cdpi) {
		bytes32 collateralType = StoreInf(storeAddr).collateralTellersInv(msg.sender);
		require(collateralType != 0, "Actions: Collateral not found");

		cdpi = openFrom(from, currencyType, collateralType);
		depositCollateralDrawStae(from, cdpi, depositAmt, drawAmt);
	}

	function depositStae(uint256 cdpi, uint256 amt) external {
		bytes memory NULL;
		depositStaeDrawCollateral(cdpi, amt, 0, NULL);
	}

	// params: for BTC, it will be the target bitcoin address transfering to
	function drawCollateral(uint256 cdpi, uint256 amt, bytes memory params) public {
		depositStaeDrawCollateral(cdpi, 0, amt, params);
	}
	function depositStaeDrawCollateral(uint256 cdpi, uint256 depositAmt, uint256 drawAmt, bytes memory params) public {
		uint256 normalizedAmt = 0;
		if (depositAmt > 0)
			normalizedAmt = transferStaeIn(msg.sender, cdpi, depositAmt);

		if (drawAmt > 0)
			transferCollateralOut(cdpi, drawAmt, params);

		StoreInf(storeAddr).cdpAdjustment(msg.sender, cdpi, -drawAmt.toInt256(), -normalizedAmt.toInt256(), -depositAmt.toInt256());
	}

	function getClosingAmt(uint256 cdpi) public view returns (uint256 collateralAmt, uint256 currAmt){
		address owner;
		bytes32 currencyType;
		bytes32 collateralType;
		uint256 normalizedDebt;
		(owner, currencyType, collateralType, collateralAmt, normalizedDebt) = StoreInf(storeAddr).cdps(cdpi);
		require(owner == msg.sender, "Actions: CDP owner not match");

		address staeAddr = StoreInf(storeAddr).currencyTypes(currencyType);
		uint256 balance = ERC20Inf(staeAddr).balanceOf(owner);
		currAmt = StaeTokenInf(staeAddr).toCurrentDebt(collateralType, normalizedDebt);
		require(balance >= currAmt, "Actions: Not enouth Stae to close");

		return (collateralAmt, currAmt);
	}
	// params: for BTC, it will be the target bitcoin address transfering to
	function close(uint256 cdpi, bytes memory params) public {
		(uint256 collateralAmt, uint256 currAmt) = getClosingAmt(cdpi);
		address owner;
		(owner,,,,) = StoreInf(storeAddr).cdps(cdpi);
		require(owner == msg.sender, "Actions: CDP owner not match");
		transferStaeIn(msg.sender, cdpi, currAmt);
		transferCollateralOut(cdpi, collateralAmt, params);
		StoreInf(storeAddr).close(msg.sender, cdpi);
	}
}

