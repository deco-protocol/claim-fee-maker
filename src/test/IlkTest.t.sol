/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.0;

import "ds-test/test.sol";
import "dss.git/vat.sol";
import "../common/DSMath.sol";
import "./Vm.sol";
import {Gate1} from "dss-gate/gate1.sol";
import {ClaimFee} from "../ClaimFee.sol";

contract TestVat is Vat {
    uint256 constant internal RAY = 10 ** 27;

    // constructor(){
    // }

    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = (x * y) / RAY;
    }

    function ilkSetup(bytes32 ilk) public {
        this.init(ilk);
    }

    // increase rate by a percentage
    function increaseRate(bytes32 ilk_, uint256 percentage, address vow) public returns (uint256 newRate) {
        require(percentage >= RAY, "not-valid-percentage");
        newRate = rmul(ilks[ilk_].rate, percentage);
        this.fold(ilk_, vow, (int(newRate) - int(ilks[ilk_].rate)));
    }

    function mint(address usr, uint rad) public {
        dai[usr] += rad;
        debt += rad;
    }
}

contract MockVow {
    constructor() {}
}

// governance user
contract Gov {
    ClaimFee public cfm;

    constructor(ClaimFee cfm_) {
        cfm = cfm_;
    }

    function initializeIlk(bytes32 ilk) public {
        cfm.initializeIlk(ilk);
    }

    function insert(bytes32 ilk, uint256 tBefore, uint256 t, uint256 rate_) public {
        cfm.insert(ilk, tBefore, t, rate_);
    }

    function issue(bytes32 ilk, address usr, uint256 issuance, uint256 maturity, uint256 bal) public {
        cfm.issue(ilk, usr, issuance, maturity, bal);
    }

    function withdraw(bytes32 ilk, address usr, uint256 issuance, uint256 maturity, uint256 bal) public {
        cfm.withdraw(ilk, usr, issuance, maturity, bal);
    }

    function close() public {
        cfm.close();
    }

    function calculate(bytes32 ilk, uint256 maturity, uint256 ratio_) public {
        cfm.calculate(ilk, maturity, ratio_);
    }
}


// public user
contract Usr {
    ClaimFee public cfm;

    constructor(ClaimFee cfm_) {
        cfm = cfm_;
    }
    
    function snapshot(bytes32 ilk) public returns (uint256 rate) {
        rate = cfm.snapshot(ilk);
    }
}

// claim holder
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
}

// when ilk is initialized
contract IlkInitializedTest is DSTest, DSMath {
    Vm public vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    ClaimFee public cfm;

    TestVat public vat;
    MockVow public vow;
    Gate1 public gate;
    address public me;

    Gov public gov;
    Usr public usr;
    CHolder public holder;
    address public gov_addr;
    address public usr_addr;
    address public holder_addr;

    bytes32 public ETH_A = bytes32(bytes("ETH-A"));

    function rad(uint256 amt_) public pure returns (uint256) {
        return mulu(amt_, RAD);
    }

    function ray(uint256 amt_) public pure returns (uint256) {
        return mulu(amt_, RAY);
    }

    function setUp() public {
        vm.warp(1641400537);

        me = address(this);
        vat = new TestVat();
        vat.rely(address(vat));
        vow = new MockVow();
        
        gate = new Gate1(address(vat), address(vow));
        vat.rely(address(gate));
        gate.updateApprovedTotal(rad(10000)); // set draw limit 

        cfm = new ClaimFee(address(gate));
        gov = new Gov(cfm);
        gov_addr = address(gov);
        cfm.rely(gov_addr);
        gate.kiss(address(cfm));
        cfm.deny(me);
        
        usr = new Usr(cfm);
        usr_addr = address(usr);
        
        holder = new CHolder(cfm);
        holder_addr = address(holder);
        vat.mint(holder_addr, rad(10000));

        vat.ilkSetup(ETH_A);
    }

    // should set initialized to true
    function testSetInitialized() public {
        gov.initializeIlk(ETH_A);
        assertTrue(cfm.initializedIlks(ETH_A));
    }

    // should take a snapshot
    function testSnapshot() public {
        gov.initializeIlk(ETH_A);
        assertTrue(cfm.rate(ETH_A, block.timestamp) != 0);
    }

    // should fail if ilk was already initialized
    function testFailIlkAlreadyInitialized() public {
        gov.initializeIlk(ETH_A);

        // vm.expectRevert("ilk/initialized");
        gov.initializeIlk(ETH_A);
    }
}

