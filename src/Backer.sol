pragma solidity 0.5.12;

contract StoreInf {
	function cdpTypes(bytes32 currencyType, bytes32 collateralType) public view returns (uint256 liquidationPenalty, uint256 liquidationDiscount, uint256 riskRatio, uint256 totalCollateralAmt, uint256 totalNormalizedDebt);
	function cdps(uint256 cdpi) public view returns (address owner, bytes32 currencyType, bytes32 collateralType, uint256 collateralAmt, uint256 normalizedDebt);
	function getCollateralPriceInStae(bytes32 currencyType, bytes32 collateralType) public view returns (uint256);
	function currencyTypes(bytes32) public view returns (address);
	function currencyTypesInv(address) public view returns (bytes32);
	function transfer(address, uint256) external returns (bool);
	function liquidateCdp(uint256 cdpi, uint256 normalizedBadDebt, uint256 confiscate) external;
	function liquidationMarkets(bytes32 currencyType, bytes32 collateralType) public view returns (uint256 normalizedBadDebt, uint256 confiscatedCollateral);
	function updateLiquidationMarkets(bytes32 currencyType, bytes32 collateralType, int256 normalizedStaeAmt, int256 collateralAmt) external;
	function collateralTypesList(uint256) public view returns (bytes32);
	function collateralTypesCount() external view returns (uint256);
	function collateralTellers(bytes32 collateralType) public view returns (address);
}
contract StaeTokenInf {
	function burn(address account, bytes32 collateralType, uint256 value) external;
	function transferFund(address to, uint256 value) external returns (bool);
	function totalSupply() public view returns (uint256);
	function totalCirculation() public view returns (uint256);
	function normalizeSaving(uint256 currValue, bool roundToNextPeriod) public view returns (uint256);
	function toCurrentSaving(uint256 normalizedValue, bool roundToNextPeriod) public view returns (uint256);
	function toCurrentDebt(bytes32 collateralType, uint256 normalizedValue) public view returns (uint256);
}
contract ERC20Inf {
	function transfer(address to, uint256 value) public returns (bool);
	function balanceOf(address owner) public view returns (uint256);
	function mint(address account, uint256 value) public;
	function burn(address account, uint256 value) public;
}
contract GovInf {
	function isBacker(address account) external view returns (bool);
	function token() public view returns (address);
}
contract TellerInf {
	function transferOut(address payable recipient, uint256 value, bytes memory params) public;
}
library SafeMath {
	function toInt256(uint256 x) internal pure returns (int256 y) {
		y = int256(x);
		require(y >= 0, "int-overflow");
	}

	function add(uint256 a, uint256 b) internal pure returns (uint256) {
		uint256 c = a + b;
		require(c >= a, "SafeMath: addition overflow");

		return c;
	}

	function sub(uint256 a, uint256 b) internal pure returns (uint256) {
		require(b <= a, "SafeMath: subtraction overflow");
		uint256 c = a - b;

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
		return mul(a, b) / unit;
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
contract Backer {
	using SafeMath for uint256;

	uint256 constant WEI = 10 ** 18;

	// --- Auth ---
	mapping (address => uint) public contractACL;
	function rely(address usr) external auth { contractACL[usr] = 1; }
	function deny(address usr) external auth { contractACL[usr] = 0; }
	modifier auth { 
		require(contractACL[msg.sender] == 1, "Backer: Not authorized"); 
		_; 
	}

	event LiquidateCdp(uint256 indexed cdpi, uint256 collateralValue, uint256 currAmt, uint256 penalty, uint256 confiscate, uint256 normalizedDebt);
	event BuyCollateral(bytes32 currencyType, bytes32 collateralType, uint256 staeAmt, uint256 colleateralAmt, uint256 discount);
	event MintBkr(bytes32 currencyType, bytes32 collateralType, uint256 staeAmt, uint256 bkrAmt);
	event BurnBkr(bytes32 currencyType, uint256 bkrAmt, uint256 staeAmt);
	
	address public storeAddr;
	address public govAddr;
	
	address systemLiquidator;
	
	constructor(address storeAddr_, address govAddr_) public {
		contractACL[msg.sender] = 1;
		storeAddr = storeAddr_;
		govAddr = govAddr_;
		systemLiquidator = msg.sender;
	}

	//ERC667
	function onTokenTransfer(address payable from, uint256 value, bytes memory extraData) public auth {
		bytes32 currencyType = StoreInf(storeAddr).currencyTypesInv(msg.sender);
		require(currencyType != 0, "Backer: STAE not exists");

		uint256 payloadSize;
		bytes32 action;

		uint256 cdpi;
		bytes32 collateralType;
		bytes memory params;
		
		assembly {
			payloadSize := mload(extraData)
			action := mload(add(extraData, 0x20))
			let size
			switch action
			case "liquidateAndBuy"{
				cdpi := mload(add(extraData, 0x40))
				size := sub(payloadSize, 0x40)
			}
			case "buyCollaterals"{
				collateralType := mload(add(extraData, 0x40))
				size := sub(payloadSize, 0x40)
			}
			params := mload(0x40)
			mstore(0x40, add(add(params, 0x20), size)) 
			mstore(params, size)
			calldatacopy(add(params,0x20), sub(calldatasize, size), size)
		}

		if (action == "liquidateAndBuy"){
			(,currencyType,collateralType,,) = StoreInf(storeAddr).cdps(cdpi);
			address erc20Addr = StoreInf(storeAddr).currencyTypes(currencyType);
			require(msg.sender == erc20Addr, "Backer: Currency type not match");
			liquidateCdpFrom(from, cdpi);
			(uint256 amtUsed,) = buyCollaterals(from, currencyType, collateralType, value, params);
			if (value > amtUsed)
				ERC20Inf(erc20Addr).transfer(from, value.sub(amtUsed));
		}else if(action == "buyCollaterals") {
			address erc20Addr = StoreInf(storeAddr).currencyTypes(currencyType);
			require(msg.sender == erc20Addr, "Backer: Currency type not match");
			(uint256 amtUsed,) = buyCollaterals(from, currencyType, collateralType, value, params);
			if (value > amtUsed)
				ERC20Inf(erc20Addr).transfer(from, value.sub(amtUsed));
		}else{
			revert();
		}
	}

	function getLiquidateCdpParam(uint256 cdpi) external view returns (uint256 collateralValue, uint256 currAmt, uint256 penalty, uint256 confiscate){
		return getLiquidateCdpParamFrom(msg.sender, cdpi);
	}
	function getLiquidateCdpParamFrom(address liquidator, uint256 cdpi) private view returns (uint256 collateralValue, uint256 currAmt, uint256 penalty, uint256 confiscate){
		address cdpOwner;
		bytes32 currencyType;
		bytes32 collateralType;
		uint256 collateralAmt;
		(cdpOwner, currencyType, collateralType, collateralAmt, currAmt/*is normalizedDebt*/) = StoreInf(storeAddr).cdps(cdpi);

		require(GovInf(govAddr).isBacker((msg.sender == StoreInf(storeAddr).currencyTypes(currencyType)) ? liquidator : msg.sender), "Backer: Not a backer");

		address erc20Addr = StoreInf(storeAddr).currencyTypes(currencyType);
		currAmt = StaeTokenInf(erc20Addr).toCurrentDebt(collateralType, currAmt/*is normalizedDebt*/);

		uint256 price = StoreInf(storeAddr).getCollateralPriceInStae(currencyType, collateralType);
		collateralValue = collateralAmt.mul(price, WEI);

		uint256 riskRatio;
		(penalty,, riskRatio,,) = StoreInf(storeAddr).cdpTypes(currencyType, collateralType);
		require(currAmt.mul(riskRatio, WEI) > collateralValue, "Backer: CDP is safe");

		penalty = currAmt.mul(penalty, WEI);

		//use currAmt or debt for penalty
		if (collateralValue > currAmt){
			if (collateralValue < currAmt.add(penalty)){
				// collateralValue not enough to cover penalty 
				penalty = collateralValue.sub(currAmt);
			}
			confiscate = currAmt.add(penalty).div(price, WEI);
		}else{
			//undercollateral
			penalty = 0;
			confiscate = collateralAmt;
		}
		return (collateralValue, currAmt, penalty, confiscate);
	}
	function liquidateCdp(uint256 cdpi) external {
		liquidateCdpFrom(msg.sender, cdpi);
	}
	
	function liquidateCdpFrom(address liquidator, uint256 cdpi) private {
		(uint256 collateralValue, uint256 currAmt, uint256 penalty, uint256 confiscate) = getLiquidateCdpParamFrom(liquidator, cdpi);

		(, bytes32 currencyType, bytes32 collateralType,,uint256 normalizedDebt) = StoreInf(storeAddr).cdps(cdpi);	
		
		StoreInf(storeAddr).liquidateCdp(cdpi, normalizedDebt, confiscate);
		
		emit LiquidateCdp(cdpi, collateralValue, currAmt, penalty, confiscate, normalizedDebt);
	}
	function buyCollaterals(address payable buyer, bytes32 currencyType, bytes32 collateralType, uint256 staeAmt, bytes memory params) private returns (uint256 amtUsed, uint256 collateralAmt) {
		(, uint256 discount,,,) = StoreInf(storeAddr).cdpTypes(currencyType, collateralType);
		(uint256 badDebt/*is normalized*/, uint256 confiscatedCollateral) = StoreInf(storeAddr).liquidationMarkets(currencyType, collateralType);

		address staeAddr = StoreInf(storeAddr).currencyTypes(currencyType);
		badDebt = StaeTokenInf(staeAddr).toCurrentSaving(badDebt/*is normalized*/, false);

		require(confiscatedCollateral > 0, "Backer: No collateral avaliable");
		require(collateralType == "BKR" || GovInf(govAddr).isBacker(buyer), "Backer: Not a backer");

		uint256 price = StoreInf(storeAddr).getCollateralPriceInStae(currencyType, collateralType);
		require(price > 0, "Backer: Price not set");

		if (discount > 0)
			price = price.mul(WEI.sub(discount), WEI);

		// calculate the collateral amount from stae amount
		collateralAmt = staeAmt.div(price, WEI);
		
		// reduce the final buying amount if the available collateral amount is less then the calculate requested amount 
		if (collateralAmt > confiscatedCollateral){
			collateralAmt = confiscatedCollateral;
			staeAmt = collateralAmt.mul(price, WEI);
		}
		
		uint256 burntAmt = staeAmt > badDebt ? badDebt : staeAmt;

		// transfer all stae from buyer to store, then burn the bad debt
		ERC20Inf(staeAddr).transfer(storeAddr, staeAmt);
		StaeTokenInf(staeAddr).burn(storeAddr, collateralType, burntAmt);

		// transfer collateral to buyer
		address teller = StoreInf(storeAddr).collateralTellers(collateralType);
		TellerInf(teller).transferOut(buyer, collateralAmt, params);

		burntAmt/*is normalized*/ = StaeTokenInf(staeAddr).normalizeSaving(burntAmt, false);
		StoreInf(storeAddr).updateLiquidationMarkets(currencyType, collateralType, -burntAmt.toInt256()/*is normalized*/, -collateralAmt.toInt256());
		
		emit BuyCollateral(currencyType, collateralType, staeAmt, collateralAmt, discount);

		return (staeAmt, collateralAmt);
	}

	function getUnderCollateralAmt(bytes32 currencyType, bytes32 collateralType) public view returns (uint256 staeAmt){
		(, uint256 discount,,,) = StoreInf(storeAddr).cdpTypes(currencyType, collateralType);
		(uint256 badDebt/*is normalized*/, uint256 confiscatedCollateral) = StoreInf(storeAddr).liquidationMarkets(currencyType, collateralType);

		address staeAddr = StoreInf(storeAddr).currencyTypes(currencyType);
		badDebt = StaeTokenInf(staeAddr).toCurrentSaving(badDebt/*is normalized*/, false);

		uint256 price = StoreInf(storeAddr).getCollateralPriceInStae(currencyType, collateralType);

		if (discount > 0)
			price = price.mul(WEI.sub(discount), WEI);

		uint256 collateralValue = confiscatedCollateral.mul(price, WEI);

		return (badDebt > collateralValue) ? badDebt.sub(collateralValue) : 0;
	}

	//convert undercollateral amount to bkr
	// surrender stae and get back bkr when total stae/debt value is larger then collateral's value
	function buyBkrWhenUnderCollateralAllCollaterals(bytes32 currencyType, uint256 staeAmt) external returns (uint256 bkrAmt){
		bkrAmt = 0;
		uint256 staeRemain = staeAmt;
		uint256 collateralTypesCount = StoreInf(storeAddr).collateralTypesCount();
		for (uint256 i = 0 ; i < collateralTypesCount && staeRemain > 0; i++){
			bytes32 collateral = StoreInf(storeAddr).collateralTypesList(i);
			(uint256 staeUsed_, uint256 bkrAmt_) = buyBkrWhenUnderCollateral(currencyType, collateral, staeRemain, false);
			bkrAmt = bkrAmt.add(bkrAmt_);
			staeRemain = staeRemain.sub(staeUsed_);
		}

		require(staeAmt != staeRemain);
		return bkrAmt;
	}
	function buyBkrWhenUnderCollateralSingleCollateral(bytes32 currencyType, bytes32 collateralType, uint256 staeAmt) external returns (uint256 staeUsed, uint256 bkrAmt) {
		return buyBkrWhenUnderCollateral(currencyType, collateralType, staeAmt, true);
	}
	function buyBkrWhenUnderCollateral(bytes32 currencyType, bytes32 collateralType, uint256 staeAmt, bool doRequire) private returns (uint256 staeUsed, uint256 bkrAmt) {
		uint256 forSale = getUnderCollateralAmt(currencyType, collateralType);
		require((!doRequire) || forSale > 0, "Backer: No collateral avaliable");
		if (forSale > 0){

			// stae available is less then requested value
			if (staeAmt > forSale)
				staeAmt = forSale;

			// calculate bkr amount
			uint256 price = StoreInf(storeAddr).getCollateralPriceInStae(currencyType, "BKR");
			bkrAmt = staeAmt.div(price, WEI);
	
			// burn stae from buyer
			address staeAddr = StoreInf(storeAddr).currencyTypes(currencyType);
			StaeTokenInf(staeAddr).burn(msg.sender, collateralType, staeAmt);
			
			// mint bkr to buyer
			address erc20Addr = GovInf(govAddr).token();
			ERC20Inf(erc20Addr).mint(msg.sender, bkrAmt);

			// update liquidationMarkets
			int256 normalizedStaeAmtSign = StaeTokenInf(staeAddr).normalizeSaving(staeAmt, false).toInt256();
			StoreInf(storeAddr).updateLiquidationMarkets(currencyType, collateralType, -normalizedStaeAmtSign, 0);

			emit MintBkr(currencyType, collateralType, staeAmt, bkrAmt);
		}else{
			staeAmt = 0;
			bkrAmt = 0;
		}
		return (staeAmt, bkrAmt);
	}

	function getUndercollalteralBkrAmtToMint(bytes32 currencyType, bytes32 collateralType) external view returns (uint256 staeAmt, uint256 bkrAmt){
		uint256 undercollateral = getUnderCollateralAmt(currencyType, collateralType);
		uint256 price = StoreInf(storeAddr).getCollateralPriceInStae(currencyType, "BKR");
		bkrAmt = undercollateral.div(price, WEI);
		
		return (undercollateral, bkrAmt);
	}
	// surrender bkr and get back stae (from contingency fund) (sellBkr)
	function burnBkrGetContingencyFund(bytes32 currencyType, uint256 bkrAmt) external auth {
		uint256 price = StoreInf(storeAddr).getCollateralPriceInStae(currencyType, "BKR");
		uint256 staeAmt = bkrAmt.mul(price, WEI);

		address staeAddr = StoreInf(storeAddr).currencyTypes(currencyType);
		uint256 storeAmt = ERC20Inf(staeAddr).balanceOf(storeAddr);
		uint256 fundBalance = StaeTokenInf(staeAddr).totalSupply() - StaeTokenInf(staeAddr).totalCirculation();
		
		uint256 newBkrAmt;
		if (staeAmt > storeAmt){
			StoreInf(storeAddr).transfer(staeAddr, storeAmt);
			if (staeAmt > storeAmt.add(fundBalance)){
				StaeTokenInf(staeAddr).transferFund(address(this), fundBalance);
				staeAmt = storeAmt.add(fundBalance);
				newBkrAmt = staeAmt.div(price, WEI);
			}else{
				StaeTokenInf(staeAddr).transferFund(address(this), staeAmt.sub(storeAmt));
				newBkrAmt = staeAmt.div(price, WEI);
			}
		}else{
			StoreInf(storeAddr).transfer(staeAddr, staeAmt);
			newBkrAmt = staeAmt.div(price, WEI);
		}
		
		ERC20Inf(GovInf(govAddr).token()).burn(msg.sender, newBkrAmt);
		ERC20Inf(staeAddr).transfer(msg.sender, staeAmt);
		
		emit BurnBkr(currencyType, newBkrAmt, staeAmt);
	}
}
