
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./deps/DSMath.sol";

/**
    A simple test utility that contains commonly used functions across other echinda Tests.
 */
contract TestUtil is DSMath {

    function rad(uint256 amt_) external pure returns (uint256) {
        return mulu(amt_, RAD);
    }

    function ray(uint256 amt_) public pure returns (uint256) {
        return mulu(amt_, RAY);
    }

    function wad(uint256 amt_) public pure returns (uint256) {
        return mulu(amt_, WAD);
    }

    // Used for assertion of equality of two strings
    function cmpStr(string memory a, string memory b) public pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function teardown() public {
        revert("undo state changes");
    }
}