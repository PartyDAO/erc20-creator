// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Vm} from "forge-std/Vm.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract TestUtils {
    uint256 private immutable _nonce;

    constructor() {
        _nonce = uint256(
            keccak256(
                abi.encode(
                    tx.origin,
                    tx.origin.balance,
                    block.number,
                    block.timestamp,
                    block.coinbase
                )
            )
        );
    }

    function _randomBytes32(uint256 addNonce) internal view returns (bytes32) {
        bytes memory seed = abi.encode(
            _nonce,
            block.timestamp,
            gasleft(),
            addNonce
        );
        return keccak256(seed);
    }

    function _randomUint256() internal view returns (uint256) {
        return uint256(_randomBytes32(0));
    }

    function _randomAddress() internal view returns (address payable) {
        return payable(address(uint160(_randomUint256())));
    }

    function _isContract(address c) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(c)
        }
        return size > 0;
    }

    // AccessControl errors
    function _constructAccessControlErrorString(
        address account,
        bytes32 role
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "AccessControl: account ",
                    Strings.toHexString(account),
                    " is missing role ",
                    Strings.toHexString(uint256(role), 32)
                )
            );
    }

    /**
     * @dev Generates pseudo-random bytes.
     * @param length The length of the byte array to generate.
     * @return randomBytes The generated pseudo-random bytes.
     */
    function _getRandomBytes(
        uint256 length
    ) public view returns (bytes memory randomBytes) {
        uint256 seed = _randomUint256();
        randomBytes = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            // Update the seed for the next byte
            seed = uint256(keccak256(abi.encodePacked(seed)));
            // Extract a byte from the seed
            randomBytes[i] = bytes1(uint8(seed));
        }
    }
}
