
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import {ClaimFee} from "../src/ClaimFee.sol";

// A regular maker public user (non ward). 
contract MakerUser {
    ClaimFee public cfm;

    constructor(ClaimFee cfm_) {
        cfm = cfm_;
    }
    
    function snapshot(bytes32 ilk) public returns (uint256 rate) {
        rate = cfm.snapshot(ilk);
    }

    function initializeIlk(bytes32 ilk) public {
        cfm.initializeIlk(ilk);
    }

    function hope(address usr) public {
        cfm.hope(usr);
    }

    function nope(address usr) public {
        cfm.nope(usr);
    }

    function moveClaim(address src, address dst, bytes32 class_, uint256 bal) public {
        cfm.moveClaim(src, dst, class_, bal);
    }

    function rewind(bytes32 ilk, address usr, uint256 issuance, uint256 maturity, uint256 rewind_, uint256 bal) public {
        cfm.rewind(ilk, usr, issuance, maturity, rewind_, bal);
    }

    // Impermissible operation
    function try_issue(bytes32 ilk, address usr, uint256 issuance, uint256 maturity, uint256 bal) public {
        cfm.issue(ilk, usr, issuance, maturity, bal);
    }

    // Impermissible operation
     function try_withdraw(bytes32 ilk,address usr, uint256 issuance, uint256 maturity, uint256 bal) public {
        cfm.withdraw(ilk, usr, issuance, maturity, bal);
    }   

    // Impermissible operation
    function try_insert(bytes32 ilk, uint256 tBefore, uint256 t, uint256 rate_) public {
        cfm.insert(ilk, tBefore, t, rate_);
    }

    // Impermissible operation
     function try_calculate(bytes32 ilk, uint256 maturity, uint256 ratio_) public {
        cfm.calculate(ilk, maturity, ratio_);
    }

    // Impermissible operation
     function try_close() public {
        cfm.close();
    }
}