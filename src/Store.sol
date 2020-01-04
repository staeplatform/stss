pragma solidity 0.5.12;

contract TokenInf {
	function transfer(address to, uint256 value) public returns (bool);
}
contract StaeTokenInf {
	function toCurrentDebt(bytes32 collateralType, uint256 normalizedValue) public view returns (uint256);
	function toCurrentSaving(uint256 normalizedValue, bool roundToNextPeriod) public view returns (uint256);
}
library SafeMath {
	function toInt256(uint256 x) internal pure returns (int256 y) {
		y = int256(x);
		require(y >= 0, "int-overflow");
	}

	function toUint256(int256 x) internal pure returns (uint256 y) {
		y = uint256(x);
		require(x >= 0, "int-overflow");
	}

	function add(uint256 a, uint256 b) internal pure returns (uint256) {
		uint256 c = a + b;
		require(c >= a, "SafeMath: addition overflow");

		return c;
	}

	function add(uint256 a, int256 b) internal pure returns (uint256) {
		uint256 c = a + uint256(b);
		require((b >= 0 && c >= a) || (b < 0 && c < a));

		return c;
	}

	function sub(uint256 a, uint256 b) internal pure returns (uint256) {
		require(b <= a, "SafeMath: subtraction overflow");
		uint256 c = a - b;

		return c;
	}

	function sub(uint256 a, int256 b) internal pure returns (uint256) {
		uint256 c = toUint256(toInt256(a) - b);
		require((b >= 0 && c <= a) || (b < 0 && c > a));

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
	
	function mul(uint256 a, uint256 b, uint256 unit) internal pure returns (uint256) {
		return div(mul(a, b), unit);
	}

	function div(uint256 a, uint256 b) internal pure returns (uint256) {
		require(b > 0, "SafeMath: division by zero");
		uint256 c = a / b;
		// assert(a == b * c + a % b); // There is no case in which this doesn't hold

		return c;
	}
	
	function div(uint256 a, uint256 b, uint256 unit) internal pure returns (uint256) {
		return div(mul(a, unit), b);
	}
}
contract Store {
   using SafeMath for uint256;

	// --- Logs ---
	modifier log {
		_;
		assembly {
			let mark := msize
			mstore(0x40, add(mark, add(calldatasize, 0x40)))
			mstore	  (	mark	   ,			0x20)
			mstore	  (add(mark, 0x20),	calldatasize)
			calldatacopy(add(mark, 0x40), 0, calldatasize)

			log1(mark, add(calldatasize, 0x40), shr(224, calldataload(0))) // (256-(8*4))
		}
	}

	uint256 constant WEI = 10 ** 18;

	/********************************* /
	/****** TODO: to be removed ******* /
	uint256 _now_;
	function now_() public view returns (uint256) {
		return _now_ == 0 ? now : _now_;
	}
	function setTime(uint256 _now) public auth {
		_now_ = _now;
	}
	/************************************/
	
	// --- Auth ---
	mapping (address => uint) public contractACL;
	function rely(address usr) external auth { contractACL[usr] = 1; }
	function deny(address usr) external auth { contractACL[usr] = 0; }
	modifier auth { 
		require(contractACL[msg.sender] == 1, "Store: Not authorized"); 
		_; 
	}

	event NewCdp(address indexed owner, bytes32 indexed currencyType, bytes32 indexed collateralType, uint256 cdp);
	event CdpAdjustment(uint256 indexed cdpi, int256 colAdj, int256 normalizedDebtAdj, int256 debtAdj);
	event CloseCdp(uint256 indexed cdpi);
	event UpdatePriceFeed(bytes32 currency, bytes32 token, uint256 value);
	event SetLive(uint256 live);

	uint256 public live;

	mapping (bytes32 => address) public currencyTypes;
	mapping (address => bytes32) public currencyTypesInv;
	bytes32[] public currencyTypesList;
	mapping (bytes32 => address) public collateralTellers; // collateralTellers[collateralType]
	mapping (address => bytes32) public collateralTellersInv;
	bytes32[] public collateralTypesList;
	// priceFeed[fiat][token], omit "STAE" for "STAE-(CCY)", e.g., priceFeed["USD"]["USD"], priceFeed["USD"]["ETH"];
	mapping (bytes32 => mapping (bytes32 => uint256)) public priceFeed; 


	// parameters by stae/collateral
	struct CdpType {
		// paramters updated by Foundation / votings / backers
		uint256 liquidationPenalty;        // wei, penalty added to debt when liqudate
		uint256 liquidationDiscount;       // wei, discount of collateral when liqudate
		uint256 riskRatio;                 // wei, when collateral value (in stae) / cdp debt over this ratio, this cdp can be liquidated
		// parameters updated by system
		uint256 totalCollateralAmt;        // wei
		uint256 totalNormalizedDebt;       // wei
	}
	mapping (bytes32 => mapping (bytes32 => CdpType)) public cdpTypes; // cdpTypes[currencyType][collateralType]

	struct CDP {
		address owner;                // owner of the CDP
		bytes32 currencyType;         // currency Type, e.g., CNY, USD
		bytes32 collateralType;       // collateral Type, e.g., ETH, BTC
		uint256 collateralAmt;        // wei, amt of collateral
		uint256 normalizedDebt;       // wei, normalized debt
	}
	mapping (uint256 => CDP) public cdps; // cdps[cdpi]
	uint256 public cdpCounter;

	struct LiquidationMarket {
		uint256 normalizedBadDebt;
		uint256 confiscatedCollateral;
	}
	mapping (bytes32 => mapping (bytes32 => LiquidationMarket)) public liquidationMarkets; // liquidationMarkets[currencyType][collateralType]


	// TODO: since bitcoain addresses are in base58 format, use string instead of bytes32 to avaoid conversion
	mapping (uint256 => bytes32) public depositAddresses;
	mapping (bytes32 => uint256) public depositAddressesInv;

	mapping (bytes32 => bytes32[]) public houseWallets;
	mapping (bytes32 => mapping (bytes32 => uint256)) houseWalletsInv;
	



	// --- Init ---
	constructor() public {
		contractACL[msg.sender] = 1;
		live = 1;
	}
	function () external payable {
	}
	
	function setLive(uint256 live_) external log auth {
		live = live_;
		emit SetLive(live);
	}
	function updateCdpTypeParam(bytes32 currencyType, bytes32 collateralType, bytes32 field, uint256 value) external log auth {
		require(cdpTypes[currencyType][collateralType].riskRatio != 0, "Store: CDP type not exists");
		if (field == "liquidationPenalty"){
			cdpTypes[currencyType][collateralType].liquidationPenalty = value;
		}else if (field == "liquidationDiscount"){
			require(value <= WEI, "Store: Invalid liquidation discount");
			cdpTypes[currencyType][collateralType].liquidationDiscount = value;
		}else if (field == "riskRatio"){
			require(value >= WEI, "Store: Invalid risk ratio");
			cdpTypes[currencyType][collateralType].riskRatio = value;
		}else{
			require(false, "Store: Invalid CDP field");
		}
	}
	function addCurrencyType(bytes32 currencyType, address contractAddr) external log auth {
		// check if stae already exists
		require(currencyTypes[currencyType] == address(0), "Store: Currency already exists");
		
		// check if parameters are valid
		require(currencyType != 0, "Store: No currency type");
		require(contractAddr != address(0), "Store: No currency address");

		currencyTypes[currencyType] = contractAddr;
		currencyTypesInv[contractAddr] = currencyType;

		currencyTypesList.push(currencyType);
	}
	function allCurrencyTypes() external view returns (bytes32[] memory){
		return currencyTypesList;
	}
	function currencyTypesCount() external view returns (uint256){
		return currencyTypesList.length;
	}
	function addCollateralType(bytes32 collateralType, address tellerAddr) external log auth {
		// check if collateral type already exists
		require(collateralTellers[collateralType] == address(0), "Store: Collateral already exists");

		// check if parameters are valid
		require(collateralType != 0, "Store: No collateral type");
		require(tellerAddr != address(0), "Store: No collateral address");

		collateralTellers[collateralType] = tellerAddr;
		collateralTellersInv[tellerAddr] = collateralType;
		collateralTypesList.push(collateralType);
	}
	function setCollateralTeller(bytes32 collateralType, address tellerAddr) external log auth {
		// check if collateral type exists
		require(collateralTellers[collateralType] != address(0), "Store: Collateral already exists");

		// check if parameters are valid
		require(collateralType != 0, "Store: No collateral type");
		require(tellerAddr != address(0), "Store: No collateral address");

		collateralTellers[collateralType] = tellerAddr;
		collateralTellersInv[tellerAddr] = collateralType;
	}
	function allCollateralTypes() external view returns (bytes32[] memory){
		return collateralTypesList;
	}
	function collateralTypesCount() external view returns (uint256){
		return collateralTypesList.length;
	}
	function updatePriceFeed(bytes32 fiat, bytes32 token, uint256 value) external log auth {
		priceFeed[fiat][token] = value;
		emit UpdatePriceFeed(fiat, token, value);
	}
	function addCdpType(bytes32 currencyType, bytes32 collateralType, uint256 liquidationPenalty, uint256 liquidationDiscount, uint256 riskRatio) external log auth {
		// check if collateral already exists
		require(cdpTypes[currencyType][collateralType].riskRatio == 0, "Store: CDP type already exists");

		// check if parameters are valid
		require(currencyType != 0, "Store: Invalid currency type");
		require(collateralType != 0, "Store: Invalid collateral type");
		require(currencyTypes[currencyType] != address(0), "Store: Currency type not exists");
		require(collateralTellers[collateralType] != address(0), "Store: Collateral type not exists");
		require(liquidationDiscount <= WEI, "Store: Invalid liquidation discount");
		require(riskRatio >= WEI, "Store: Invalid risk ratio");

		cdpTypes[currencyType][collateralType].liquidationPenalty = liquidationPenalty;
		cdpTypes[currencyType][collateralType].liquidationDiscount = liquidationDiscount;
		cdpTypes[currencyType][collateralType].riskRatio = riskRatio;

		cdpTypes[currencyType][collateralType].totalCollateralAmt = 0;
		cdpTypes[currencyType][collateralType].totalNormalizedDebt = 0;
	}

	function registerDepositAddress(uint256 cdpi, bytes32 depositAddress) external auth {
		depositAddresses[cdpi] = depositAddress;
		depositAddressesInv[depositAddress] = cdpi;
	}
	function addHouseWallet(bytes32 collateralType, bytes32 wallet) external auth {
		houseWalletsInv[collateralType][wallet] = houseWallets[collateralType].length;
		houseWallets[collateralType].push(wallet);
	}
	function removeHouseWallet(bytes32 collateralType, bytes32 wallet) external auth {
		uint256 idx = houseWalletsInv[collateralType][wallet];
		if (idx < houseWallets[collateralType].length - 1){
			houseWallets[collateralType][idx] = houseWallets[collateralType][houseWallets[collateralType].length - 1];
			houseWalletsInv[collateralType][houseWallets[collateralType][idx]] = idx;
		}
		houseWallets[collateralType].length--;
		delete houseWalletsInv[collateralType][wallet];
	}
	function houseWalletsCount(bytes32 collateralType) external returns (uint256){
		return houseWallets[collateralType].length;
	}

	// stae to collateral price, NOT currency
	function getCollateralPriceInStae(bytes32 currencyType, bytes32 collateralType) public view returns (uint256) {
		uint256 collateralPrice = priceFeed[currencyType][collateralType];
		uint256 staePrice = priceFeed[currencyType][currencyType];
		require(collateralPrice != 0);
		require(staePrice != 0);
		return collateralPrice.div(staePrice, WEI);
	}
	function isCdpSafe(uint256 cdpi) public view returns (bool safe) {
		CDP memory cdp = cdps[cdpi];
		CdpType memory cdpType = cdpTypes[cdp.currencyType][cdp.collateralType];

		uint256 price = getCollateralPriceInStae(cdp.currencyType, cdp.collateralType);
		uint256 currAmt = StaeTokenInf(currencyTypes[cdp.currencyType]).toCurrentDebt(cdp.collateralType, cdp.normalizedDebt);

		safe = (currAmt.mul(cdpType.riskRatio) <= cdp.collateralAmt.mul(price)); // both side should div by WEI (i.e., .mul(xxx, WEI) ) cancelled out
	}

	function open(bytes32 currencyType, bytes32 collateralType, address owner) external auth returns (uint256) {
		require(live == 1, "Store: System down");

		cdpCounter++;
		uint256 cdpi = cdpCounter;
		require(cdpi > 0, "Store: cdpi overflow");
		require(cdpTypes[currencyType][collateralType].riskRatio >= WEI, "Store: Invalid risk ratio");
		cdps[cdpi].owner = owner;
		cdps[cdpi].currencyType = currencyType;
		cdps[cdpi].collateralType = collateralType;

		emit NewCdp(owner, currencyType, collateralType, cdpi);
		return cdpi;
	}
	function cdpAdjustment(address from, uint256 cdpi, int256 colAdj, int256 normalizedDebtAdj, int256 debtAdj) external auth {
		CDP storage cdp = cdps[cdpi];
		CdpType storage cdpType = cdpTypes[cdp.currencyType][cdp.collateralType];
		require(from == cdp.owner, "Store: CDP owner not match");

		cdp.collateralAmt = cdp.collateralAmt.add(colAdj);
		cdp.normalizedDebt = cdp.normalizedDebt.add(normalizedDebtAdj);

		cdpType.totalCollateralAmt = cdpType.totalCollateralAmt.add(colAdj);
		cdpType.totalNormalizedDebt = cdpType.totalNormalizedDebt.add(normalizedDebtAdj);

		bool repayDebt = normalizedDebtAdj <= 0;
		bool addCol = colAdj >= 0;
		bool nice = repayDebt && addCol;
		// FIXME: calculate the currency sum from different cdpTypes
		// bool systemSafe = mul(cdpType.totalNormalizedDebt, rate) / GETHER <= cdpType.limit // && mul(totalNormalizedDebt[cdp.currencyType], rate) / GETHER  <= systemMaxLimit[cdp.currencyType];
		bool cdpSafe = isCdpSafe(cdpi);
		require(cdpSafe || nice, "Store: CDP not save");
		
		emit CdpAdjustment(cdpi, colAdj, normalizedDebtAdj, debtAdj);
	}

	function liquidateCdp(uint256 cdpi, uint256 normalizedBadDebt, uint256 confiscate) external auth {
		CDP storage cdp = cdps[cdpi];

		require(!isCdpSafe(cdpi), "CDP is safe");

		CdpType storage cdpType = cdpTypes[cdp.currencyType][cdp.collateralType];

		liquidationMarkets[cdp.currencyType][cdp.collateralType].normalizedBadDebt = liquidationMarkets[cdp.currencyType][cdp.collateralType].normalizedBadDebt.add(normalizedBadDebt);
		liquidationMarkets[cdp.currencyType][cdp.collateralType].confiscatedCollateral = liquidationMarkets[cdp.currencyType][cdp.collateralType].confiscatedCollateral.add(confiscate);

		cdpType.totalCollateralAmt = cdpType.totalCollateralAmt.sub(confiscate);
		cdpType.totalNormalizedDebt = cdpType.totalNormalizedDebt.sub(cdp.normalizedDebt);

		cdp.collateralAmt = cdp.collateralAmt.sub(confiscate);
		cdp.normalizedDebt = 0;
	}
	function updateLiquidationMarkets(bytes32 currencyType, bytes32 collateralType, int256 normalizedStaeAmt, int256 collateralAmt) external auth {
		liquidationMarkets[currencyType][collateralType].normalizedBadDebt = liquidationMarkets[currencyType][collateralType].normalizedBadDebt.add(normalizedStaeAmt);
		liquidationMarkets[currencyType][collateralType].confiscatedCollateral = liquidationMarkets[currencyType][collateralType].confiscatedCollateral.add(collateralAmt);
	}

	function close(address from, uint256 cdpi) external auth {
		CDP storage cdp = cdps[cdpi];
		CdpType storage cdpType = cdpTypes[cdp.currencyType][cdp.collateralType];
		require(from == cdp.owner, "Store: CDP owner not match");

		cdpType.totalCollateralAmt = cdpType.totalCollateralAmt.sub(cdp.collateralAmt);
		cdpType.totalNormalizedDebt = cdpType.totalNormalizedDebt.sub(cdp.normalizedDebt);

		cdp.collateralAmt = 0;
		cdp.normalizedDebt = 0;

		emit CloseCdp(cdpi);
	}

	// transfer token / stae out of store (no need to approve() / transferFrom() )
	function transfer(address tokenAddres, uint256 amt) external auth returns (bool) {
		TokenInf(tokenAddres).transfer(msg.sender, amt);
		return true;
	}
	function transferETH(uint256 amt) external auth returns (bool) {
		msg.sender.transfer(amt);
		return true;
	}
}

