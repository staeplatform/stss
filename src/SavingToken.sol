pragma solidity 0.5.13;

library SafeMath48 {
	function add(uint48 a, uint48 b) internal pure returns (uint48) {
		uint48 c = a + b;
		require(c >= a, "SafeMath: addition overflow");

		return c;
	}
}

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
	function mod(uint256 a, uint256 b) internal pure returns (uint256) {
		require(b > 0, "SafeMath: modulo by zero");
		return a % b;
	}
	function pow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
		assembly {
			switch x 
				case 0 {
					switch n 
						case 0 {z := b} 
						default {z := 0}
				}
				default {
					switch mod(n, 2) 
						case 0 { z := b } 
						default { z := x }
					let half := div(b, 2)  // for rounding.
					for { n := div(n, 2) } n { n := div(n,2) } {
						let xx := mul(x, x)
						if iszero(eq(div(xx, x), x)) { revert(0,0) }
						let xxRound := add(xx, half)
						if lt(xxRound, xx) { revert(0,0) }
						x := div(xxRound, b)
						if mod(n,2) {
							let zx := mul(z, x)
							if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
							let zxRound := add(zx, half)
							if lt(zxRound, zx) { revert(0,0) }
							z := div(zxRound, b)
						}
					}
				}
		}
	}
}

// ERC677
contract ERC677Receiver {
	function onTokenTransfer(address _sender, uint256 _value, bytes memory _data) public;
}

contract SavingToken {
	using SafeMath for uint256;
	using SafeMath48 for uint48;

	uint8 public constant decimals = 18;
	uint256 constant GETHER = 10 ** 27;
	
	uint256 constant SECONDS_IN_ONE_MONTH = 2592000;

	// --- Auth ---
	event Auth(address indexed account, uint256 auth);
	mapping (address => uint256) public owners;
	function rely(address account) public auth { 
		owners[account] = 1; 
		emit Auth(account, 1);
	}
	function deny(address account) public auth { 
		require(account != msg.sender, "Auth: Cannot self deny");
		owners[account] = 0; 
		emit Auth(account, 0); 
	}
	modifier auth {
		//**********  access control disabled for easy testing  *********
		require(owners[msg.sender] == 1, "Non authorized access"); 
		_; 
	}

	// --- ERC20 Data ---
	string  public name;
	string  public symbol;
	uint256 public cap;

	// ERC865 Data
	mapping (address => uint256) public preSignNonces;

/*
	Pre-calculate the next accumulatedRate to save gas:

	|<-----interest period----->|<-----interest period----->|
	^ timestamp1                ^ timestamp2                ^ timestamp3
	^ accumulatedRate           ^ nextAccumulatedRate       ^ (calculate new rate)

    ^ if now pass timestamp1 :  ^ if now pass timestamp2 :  ^ if now pass timestamp3 :
	^ no update                 ^ no update                 ^ no update, calculate rate    getCurrSavingsRate (view)
	^ no update                 ^ may update (doUpdate?)    ^ update rate                  updateAccumulatedSavingsRate
*/

	uint256 public savingsRate;          // gether
	uint48 public interestPeriod;        // in second
	uint256 public accumulatedRate;      // gether
	uint256 public nextAccumulatedRate;  // gether
	uint256 public increaseInOnePeriod;  // gether
	uint48 public timestamp1;
	uint48 public timestamp2;
	uint48 public timestamp3;

	bool requireNormalize;

	mapping (address => uint256) public normalizedBalances;
	mapping (address => mapping (address => uint256)) public allowances;
	uint256 public normalizedCirculation;

	struct CollateralType {
		uint256 stabilityRate;             // gether
		uint256 normalizedDebt;            // wei
		uint256 accumulatedStabilityRate;  // gether
		uint48  lastStabilityRateUpdate;   // timestamp in second
	}
	mapping (bytes32 => CollateralType) public collateralTypes; 
	bytes32[] public collateralTypesList;

	event Transfer(address indexed from, address indexed to, uint256 value);
	event Approval(address indexed owner, address indexed spender, uint256 value);
	event StabilityRateChanged(bytes32 indexed collateralType, uint256 newRate);
	event SavingsRateChanged(uint256 newRate);
	event TransferPreSigned(address indexed from, address indexed to, address indexed delegate, uint256 amount, uint256 fee);

	constructor(string memory symbol_, string memory name_,  uint256 cap_) public {
		owners[msg.sender] = 1;
		emit Auth(msg.sender, 1);
		symbol = symbol_;
		name = name_;
		cap = cap_;
		savingsRate = GETHER;
		interestPeriod = 1;
		accumulatedRate = GETHER;
		nextAccumulatedRate = GETHER;
		increaseInOnePeriod = GETHER;
		timestamp1 = uint48(now.sub(now.mod(interestPeriod)));
		timestamp2 = timestamp1.add(interestPeriod);
		timestamp3 = timestamp2.add(interestPeriod);
	}

	function addCollateralType(bytes32 collateralType, uint256 newRate) external auth {
		require(collateralTypes[collateralType].stabilityRate == 0, "Add-Collateral: Collateral already exists");
		require(newRate >= savingsRate, "Add-Collateral: Rate smaller than savings rate");

		collateralTypes[collateralType].stabilityRate = newRate;
		collateralTypes[collateralType].normalizedDebt = 0;
		collateralTypes[collateralType].accumulatedStabilityRate = newRate;
		collateralTypes[collateralType].lastStabilityRateUpdate = uint48(now);
		collateralTypesList.push(collateralType);
		
		emit StabilityRateChanged(collateralType, newRate);
	}
	function allCollateralTypes() external view returns (bytes32[] memory){
		return collateralTypesList;
	}
	function collateralTypesCount() external view returns (uint256){
		return collateralTypesList.length;
	}

	function getCurrStabilityRate(bytes32 collateralType) public view returns (uint256) {
		CollateralType memory colType = collateralTypes[collateralType];
		require(colType.stabilityRate != 0, "CollateralType does not exist");

		if (now > colType.lastStabilityRateUpdate)
			return colType.stabilityRate.pow(now.sub(colType.lastStabilityRateUpdate), GETHER).mul(colType.accumulatedStabilityRate, GETHER);
		else
			return colType.accumulatedStabilityRate;
	}
	function updateAccumulatedStabilityRate(bytes32 collateralType) public returns (uint256 newRate) {
		require(collateralTypes[collateralType].stabilityRate != 0, "Set-Rate: CollateralType does not exist");

		if (now > collateralTypes[collateralType].lastStabilityRateUpdate){
			collateralTypes[collateralType].accumulatedStabilityRate = getCurrStabilityRate(collateralType);
			collateralTypes[collateralType].lastStabilityRateUpdate = uint48(now);
		}
		return collateralTypes[collateralType].accumulatedStabilityRate;
	}
	function setStabilityRate(bytes32 collateralType, uint256 newRate) external auth {
		require(collateralTypes[collateralType].stabilityRate != 0, "Set-Rate: CollateralType does not exist");
		require(newRate >= savingsRate, "Set-Rate: New rate smaller than savings rate");

		updateAccumulatedStabilityRate(collateralType);
		collateralTypes[collateralType].stabilityRate = newRate;

		emit StabilityRateChanged(collateralType, newRate);
	}
	function normalizeDebt(bytes32 collateralType, uint256 currValue) public view returns (uint256) {
		uint256 currRate = getCurrStabilityRate(collateralType);
		return currValue.div(currRate, GETHER);
	}
	function toCurrentDebt(bytes32 collateralType, uint256 normalizedValue) public view returns (uint256) {
		uint256 currRate = getCurrStabilityRate(collateralType);
		return normalizedValue.mul(currRate, GETHER);
	}

	function getCurrSavingsRate(bool roundToNextPeriod) public view returns (uint256) {
		if (now < timestamp2) {
			return roundToNextPeriod ? nextAccumulatedRate : accumulatedRate;
		} else if (now < timestamp3) {
			return roundToNextPeriod ? increaseInOnePeriod.mul(nextAccumulatedRate, GETHER) : nextAccumulatedRate;
		} else {
			uint256 lastInterestPeriod = now.sub(now.mod(interestPeriod));

			uint256 secondsPastTimestamp2 = lastInterestPeriod.sub(timestamp2);
			if (roundToNextPeriod)
				secondsPastTimestamp2 = secondsPastTimestamp2.add(interestPeriod);

			return savingsRate.pow(secondsPastTimestamp2, GETHER).mul(nextAccumulatedRate, GETHER);
		}
	}
	function updateAccumulatedSavingsRate(bool roundToNextPeriod, bool doUpdate) public returns (uint256 newRate) {
		if (now < timestamp2) {
			// no-op
			return roundToNextPeriod ? nextAccumulatedRate : accumulatedRate;
		} else if (now < timestamp3) {
			if (doUpdate){
				accumulatedRate = nextAccumulatedRate;
				nextAccumulatedRate = increaseInOnePeriod.mul(accumulatedRate, GETHER);
	
				timestamp1 = timestamp2;
				timestamp2 = timestamp3;
				timestamp3 = timestamp3.add(interestPeriod);

				return roundToNextPeriod ? nextAccumulatedRate : accumulatedRate;
			} else {
				return roundToNextPeriod ? increaseInOnePeriod.mul(nextAccumulatedRate, GETHER) : nextAccumulatedRate;
			}
		} else {
			uint256 lastInterestPeriod = now.sub(now.mod(interestPeriod));

			uint256 secondsPastTimestamp2 = lastInterestPeriod.sub(timestamp2);
			accumulatedRate = savingsRate.pow(secondsPastTimestamp2, GETHER).mul(nextAccumulatedRate, GETHER);
			nextAccumulatedRate = increaseInOnePeriod.mul(accumulatedRate, GETHER);

			timestamp1 = uint48(lastInterestPeriod);
			timestamp2 = timestamp1.add(interestPeriod);
			timestamp3 = timestamp2.add(interestPeriod);
			
			return roundToNextPeriod ? nextAccumulatedRate : accumulatedRate;
		}
	}
	function setSavingsRate(uint256 newRate, uint48 interestPeriod_) external auth {
		require(newRate >= GETHER, "Set-Rate: New rate smaller than one");
		require(interestPeriod_ >= 1, "Set-Rate: interestPeriod is zero");
		require(interestPeriod_ <= SECONDS_IN_ONE_MONTH, "Set-Rate: interestPeriod is larger than one month");

		updateAccumulatedSavingsRate(false, true);
		for (uint256 i = 0 ; i < collateralTypesList.length ; i++ ){
			bytes32 collateralType = collateralTypesList[i];
			uint256 stabilityRate = collateralTypes[collateralType].stabilityRate;
			require(stabilityRate >= newRate, "Set-Rate: New rate greater than stability rate");
		}
		savingsRate = newRate;
		interestPeriod = interestPeriod_;
		timestamp3 = timestamp2.add(interestPeriod);
		increaseInOnePeriod = savingsRate.pow(interestPeriod, GETHER);

		if (savingsRate > GETHER || accumulatedRate > GETHER){
			requireNormalize = true;
		}
		emit SavingsRateChanged(newRate);
	}
	function normalizeSaving(uint256 currValue, bool roundToNextPeriod) public returns (uint256) {
		uint256 currRate = updateAccumulatedSavingsRate(roundToNextPeriod, false);
		return currValue.div(currRate, GETHER);
	}
	function toCurrentSaving(uint256 normalizedValue, bool roundToNextPeriod) public view returns (uint256) {
		uint256 currRate = getCurrSavingsRate(roundToNextPeriod);
		return normalizedValue.mul(currRate, GETHER);
	}

	function mint(address account, bytes32 collateralType, uint256 value) external auth returns (uint256 normalizedDebt, uint256 normalizedSaving) {
		require(account != address(0), "ERC20: mint to the zero address");
		require(collateralTypes[collateralType].stabilityRate >= savingsRate, "Set-Rate: stability rate smaller than savings rate");

		updateAccumulatedStabilityRate(collateralType);
		
		normalizedDebt = normalizeDebt(collateralType, value);
		normalizedDebt = normalizedDebt.mul(getCurrStabilityRate(collateralType)) < value.mul(GETHER) ? normalizedDebt.add(1) : normalizedDebt;
		collateralTypes[collateralType].normalizedDebt = collateralTypes[collateralType].normalizedDebt.add(normalizedDebt);

		uint256 valueToUse;
		if (requireNormalize){
			valueToUse = normalizeSaving(value, true);
			valueToUse = valueToUse.mul(getCurrSavingsRate(true)) < value.mul(GETHER) ? valueToUse.add(1) : valueToUse;
		} else {
			valueToUse = value;
		}
		normalizedCirculation = normalizedCirculation.add(valueToUse);
		normalizedBalances[account] = normalizedBalances[account].add(valueToUse); 

		require(cap == 0 || cap >= totalSupply(), "ERC20Capped: cap exceeded");
		emit Transfer(address(0), account, value);
	}
	function burn(address account, bytes32 collateralType, uint256 value) external auth returns (uint256 normalizedDebt, uint256 normalizedSaving) {
		require(account != address(0), "ERC20: burn from the zero address");

		updateAccumulatedStabilityRate(collateralType);

		normalizedDebt = normalizeDebt(collateralType, value);
		collateralTypes[collateralType].normalizedDebt = collateralTypes[collateralType].normalizedDebt.sub(normalizedDebt);

		uint256 valueToUse = requireNormalize ? normalizeSaving(value, false) : value;
		normalizedCirculation = normalizedCirculation.sub(valueToUse);
		normalizedBalances[account] = normalizedBalances[account].sub(valueToUse);

		emit Transfer(account, address(0), value);
	}

	function supplyByCollateral(bytes32 collateralType) public view returns (uint256) {
		return toCurrentDebt(collateralType, collateralTypes[collateralType].normalizedDebt);
	}
	function totalSupply() public view returns (uint256) {
		uint256 totalSupply_ = 0;

		for (uint256 i = 0 ; i < collateralTypesList.length ; i++ ){
			bytes32 collateralType = collateralTypesList[i];
			uint256 supply = supplyByCollateral(collateralType);
			totalSupply_ = totalSupply_.add(supply);
		}
		return totalSupply_;
	}
	function totalCirculation() public view returns (uint256) {
		return (requireNormalize) ? toCurrentSaving(normalizedCirculation, false) : normalizedCirculation;
	}
	function balanceOf(address owner) public view returns (uint256) {
		return (requireNormalize) ? toCurrentSaving(normalizedBalances[owner], false) : normalizedBalances[owner];
	}

	function allowance(address owner, address spender) external view returns (uint256) {
		return allowances[owner][spender];
	}
	function transfer(address to, uint256 value) external returns (bool) {
		_transfer(msg.sender, to, value);
		return true;
	}
	function transferAll(address to) external returns (bool) {
		require(to != address(0), "ERC20: transfer to the zero address");

		uint256 normalizedValue = normalizedBalances[msg.sender];
		normalizedBalances[msg.sender] = 0;
			normalizedBalances[to] = normalizedBalances[to].add(normalizedValue);

		emit Transfer(msg.sender, to, (requireNormalize) ? toCurrentSaving(normalizedValue, false) : normalizedValue);
		return true;
	}
	function transferFrom(address from, address to, uint256 value) external returns (bool) {
		_transfer(from, to, value);
		_approve(from, msg.sender, allowances[from][msg.sender].sub(value));
		return true;
	}
	function approve(address spender, uint256 value) external returns (bool) {
		_approve(msg.sender, spender, value);
		return true;
	}

	function _transfer(address from, address to, uint256 value) internal {
		require(from != address(0), "ERC20: transfer from the zero address");
		require(to != address(0), "ERC20: transfer to the zero address");

		uint256 valueToUse = requireNormalize ? normalizeSaving(value, false) : value;
		normalizedBalances[from] = normalizedBalances[from].sub(valueToUse);
		normalizedBalances[to] = normalizedBalances[to].add(valueToUse);

		emit Transfer(from, to, value);
	}
	function _approve(address owner, address spender, uint256 value) internal {
		require(owner != address(0), "ERC20: approve from the zero address");
		require(spender != address(0), "ERC20: approve to the zero address");

		allowances[owner][spender] = value;

		emit Approval(owner, spender, value);
	}
	
	function transferFund(address to, uint256 value) external auth returns (bool) {
		require(to != address(0), "ERC20: transfer to the zero address");

		uint256 valueToUse = requireNormalize ? normalizeSaving(value, true) : value;
		normalizedBalances[to] = normalizedBalances[to].add(valueToUse);
		normalizedCirculation = normalizedCirculation.add(valueToUse);
	   
		require(totalCirculation() <= totalSupply(), "Total circulation greater than total supply");

		emit Transfer(address(this), to, value);
		return true;
	}
	function transferDebtBetweenCollaterals(bytes32 fromCollateral, bytes32 toCollateral, uint256 value) external auth {
		uint256 normalizedValue = normalizeDebt(fromCollateral, value);
		collateralTypes[fromCollateral].normalizedDebt = collateralTypes[fromCollateral].normalizedDebt.sub(normalizedValue);
		normalizedValue = normalizeDebt(toCollateral, value);
		collateralTypes[toCollateral].normalizedDebt = collateralTypes[toCollateral].normalizedDebt.add(normalizedValue);
	}

	// ERC865 transferPreSigned only
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        // Check the signature length
        require(signature.length == 65, "Invalid Signature");

        // Divide the signature in r, s and v variables
        bytes32 r;
        bytes32 s;
        uint8 v;

        // ecrecover takes the signature parameters, and the only way to get them
        // currently is to use assembly.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (281): 0 < s < secp256k1n ÷ 2 + 1, and for v in (282): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        require(uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, "Invalid Signature");

		// Version of signature should be 27 or 28, but 0 and 1 are also possible versions
		if (v < 27) {
			v += 27;
		}
		require(v == 27 || v == 28, "Invalid Signature");

        // If the signature is valid (and not malleable), return the signer address
        return ecrecover(hash, v, r, s);
    }
	function getTransferPreSignedHash(address _token, address _to, uint256 _value, uint256 _fee, uint256 _nonce) private pure returns (bytes32) {
		 /* "0d98dcb1": getTransferPreSignedHash(address,address,uint256,uint256,uint256) */
		return keccak256(abi.encodePacked(bytes4(0x0d98dcb1), _token, _to, _value, _fee, _nonce));
	}
    function transferPreSigned(bytes memory _signature, address _to, uint256 _value, uint256 _fee, uint256 _nonce) public auth returns (bool) {
		require(_to != address(0), "ERC20: transfer to the zero address");

		bytes32 hashedParams = getTransferPreSignedHash(address(this), _to, _value, _fee, _nonce);
		
		address from = recover(hashedParams, _signature);
		require(from != address(0), "ERC20: transfer from the zero address");
		
		require(_nonce == preSignNonces[from], "Incorrect Nonce.");
		preSignNonces[from] = preSignNonces[from].add(1);

		_transfer(from, _to, _value);
		_transfer(from, msg.sender, _fee);

		emit TransferPreSigned(from, _to, msg.sender, _value, _fee);
		return true;
    }

	// ERC677
	function transferAndCall(address spender, uint256 value, bytes memory extraData) public returns (bool success) {
		_transfer(msg.sender, spender, value);
		uint256 length;
		assembly { 
			length := extcodesize(spender)
		}
		if (length > 0){
			ERC677Receiver(spender).onTokenTransfer(msg.sender, value, extraData);
		}
		return true;
	}
}

