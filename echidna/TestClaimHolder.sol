// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import {ClaimFee} from "../src/ClaimFee.sol";
import {Gate1} from "./deps/gate1.sol";
import "./TestVat.sol";

contract CHolder {
    ClaimFee public cfm;

    constructor(ClaimFee cfm_) {
        cfm = cfm_;
    }

    function hope(address usr) public {
        cfm.hope(usr);
    }

    function nope(address usr) public {
        cfm.nope(usr);
    }

    function vatHope(address usr) public {
        TestVat(cfm.vat()).hope(usr);
    }

    function moveClaim(address src, address dst, bytes32 class_, uint256 bal) public {
        cfm.moveClaim(src, dst, class_, bal);
    }

    function collect(bytes32 ilk, address usr, uint256 issuance, uint256 maturity, uint256 collect_, uint256 bal) public {
        cfm.collect(ilk, usr, issuance, maturity, collect_, bal);
    }

    function rewind(bytes32 ilk, address usr, uint256 issuance, uint256 maturity, uint256 rewind_, uint256 bal) public {
        cfm.rewind(ilk, usr, issuance, maturity, rewind_, bal);
    }

    function slice(bytes32 ilk, address usr, uint256 t1, uint256 t2, uint256 t3, uint256 bal) public {
        cfm.slice(ilk, usr, t1, t2, t3, bal);
    }

    function merge(bytes32 ilk, address usr, uint256 t1, uint256 t2, uint256 t3, uint256 bal) public {
        cfm.merge(ilk, usr, t1, t2, t3, bal);
    }

    function activate(bytes32 ilk, address usr, uint256 t1, uint256 t2, uint256 t3, uint256 bal) public {
        cfm.activate(ilk, usr, t1, t2, t3, bal);
    }

    function cashClaim(bytes32 ilk, address usr, uint256 maturity, uint256 bal) public {
        cfm.cashClaim(ilk, usr, maturity, bal);
    }

    function try_withdraw(bytes32 ilk,address usr, uint256 issuance, uint256 maturity, uint256 bal) public {
        cfm.withdraw(ilk, usr, issuance, maturity, bal);
    }    
}

