pragma solidity >=0.5.0;

contract BtcTellerI {
	function mintAndCall(address from, uint256 value, bytes memory extraData) public;
}

contract Multisig {

	uint signaturesRequired;
	mapping(address => uint) public authorizedSigners;
	mapping(uint256 => uint) public nonces;
	BtcTellerI public target;

	constructor(address[] memory authorizedSigners_, uint signaturesRequired_, address target_) public {
	    for (uint i = 0; i < authorizedSigners_.length; i++) {
	        authorizedSigners[authorizedSigners_[i]] = 1;
	    }
	    signaturesRequired = signaturesRequired_;
	    target = BtcTellerI(target_);
	}
	function mintAndCall(address from, uint256 value, bytes memory extraData, uint256 nonce, bytes memory signatures) public {
		bytes32 hashStage1 = keccak256(abi.encodePacked(address(this), from, value, extraData, nonce));

		verifySignatures(nonce, signatures, hashStage1);

		target.mintAndCall(from, value, extraData);
	}

	function verifySignatures(uint256 nonce, bytes memory signatures, bytes32 hashStage1) private {
		require(nonces[nonce] == 0);
		bytes memory prefix = "\x19Ethereum Signed Message:\n32";
		bytes32 hash = keccak256(abi.encodePacked(prefix, hashStage1));

		address[] memory signed = new address[](signaturesRequired);

		for (uint i = 0; i < signaturesRequired; i++) {
			address signer = recoverSigner(hash, signatures, 0x41 * i);
			require(authorizedSigners[signer] > 0);
			for (uint j = 0; j < i; j++) {
				require(signed[j] != signer);
			}
			signed[i] = signer;
		}

		nonces[nonce] = 1;
	}

	function recoverSigner(bytes32 hash, bytes memory sig, uint offset) private pure returns (address) {
		bytes32 r;
		bytes32 s;
		uint8 v;

		// Divide the signature in r, s and v variables
		assembly {
			// first 32 bytes, after the length prefix
			r := mload(add(sig, offset))
			// second 32 bytes
			s := mload(add(sig, add(offset, 0x20)))
			// final byte (first byte of the next 32 bytes)
			v := byte(0, mload(add(sig, add(offset, 0x40))))
		}

		// Version of signature should be 27 or 28, but 0 and 1 are also possible versions
		if (v < 27) {
			v += 27;
		}

		// If the version is correct return the signer address
		if (v != 27 && v != 28) {
			return (address(0));
		} else {
			return ecrecover(hash, v, r, s);
		}
	}
}

