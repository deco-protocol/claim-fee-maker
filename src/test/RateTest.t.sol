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
    uint256 constant internal WAD = 10 ** 18;

    // constructor(){
    // }

    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = (x * y) / RAY;
    }

    function ilkSetup(bytes32 ilk) public {
        this.init(ilk);
    }

    // increase rate by a percentage
    function increaseRate(bytes32 ilk_, uint256 percentage, address vow) public returns (uint256) {
        Ilk storage ilk = ilks[ilk_];

        // percentage between 0 to 500  in wad
        require(percentage >= 0 && percentage <= (500 * WAD), "not-valid-percentage"); 
        int256 rate = int256((ilk.rate * percentage)/10**20);

        ilk.rate = add(ilk.rate, rate);
        int rad = mul(ilk.Art, rate);
        dai[vow] = add(dai[vow], rad);
        debt = add(debt, rad);

        return ilk.rate;
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

// when rate value snapshot is taken
contract RateSnapshotTest is DSTest, DSMath {
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

    function wad(uint256 amt_) public pure returns (uint256) {
        return mulu(amt_, WAD);
    }

    function percentage(uint256 amt_) public pure returns (uint256) {
        return amt_ ;
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
        gov.initializeIlk(ETH_A);
        
        // (, uint256 ui1, , , ) = vat.ilks(ETH_A);
        // emit log_named_uint("rate value @ now: ", ui1);
        vat.increaseRate(ETH_A, wad(5), address(vow));
    }

    // should allow any address to take a snapshot 
    function testAllowAnyone() public {
        usr.snapshot(ETH_A); // take a snapshot

        assertGt(cfm.rate(ETH_A, block.timestamp), 0); // should be non zero
    }
    
    // should fail if deco is closed
    function testFailDecoClose() public {
        gov.close(); // close deco
        usr.snapshot(ETH_A); // take a snapshot
        
        // expect failure
    }
    
    // should return the rate value set
    function testReturnValue() public {
        uint256 rateReturnValue = usr.snapshot(ETH_A); // take a snapshot and capture return value
        assertGt(rateReturnValue, 0); // should be non zero
    }
    
    // should updated lastest rate timestamp of ilk
    function testLatestRateTimestamp() public {
        uint256 currentLatestTimestamp = usr.snapshot(ETH_A); // take a snapshot
        
        // ensure the last rate timestamp is updated
        assertGt(currentLatestTimestamp, cfm.latestRateTimestamp(ETH_A));
    }
    
    // should set rate value at current timestamp
    function testSetRateValue() public {
        (, uint256 rate, , , ) = vat.ilks(ETH_A);
        
        uint256 currentLatestTimestamp = usr.snapshot(ETH_A); // take a snapshot
        assertEq(cfm.rate(ETH_A, block.timestamp), rate);
        assertGt(cfm.rate(ETH_A, block.timestamp), 0);
    }

    // // should emit an event
    // function testEvent() public {
    //     // 
    // }
}

// when rate value is inserted by gov
contract RateInsertTest is DSTest, DSMath {
    Vm public vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 t0;
    uint256 t1;
    uint256 t2;

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

    function wad(uint256 amt_) public pure returns (uint256) {
        return mulu(amt_, WAD);
    }

    function percentage(uint256 amt_) public pure returns (uint256) {
        return amt_ ;
    }

    function setUp() public {
        vm.warp(1641400537);

        t0 = block.timestamp;
        t1 = block.timestamp + 5 days;
        t2 = block.timestamp + 10 days;

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
        gov.initializeIlk(ETH_A);
        
        // (, uint256 ui1, , , ) = vat.ilks(ETH_A);
        // emit log_named_uint("rate value @ now: ", ui1);
        vat.increaseRate(ETH_A, wad(5), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.05

        // no snapshot at t1

        // increase time and rate
        vm.warp(t2);
        vat.increaseRate(ETH_A, wad(10), address(vow)); // increase by 10%
        cfm.snapshot(ETH_A); // take a snapshot at t2 @ 1.155

        // emit log_named_uint("rate @ t0", cfm.rate(ETH_A, t0));
        // emit log_named_uint("rate @ t1", cfm.rate(ETH_A, t1));
        // emit log_named_uint("rate @ t2", cfm.rate(ETH_A, t2));
        // emit log_named_uint("rate late", cfm.rate(ETH_A, cfm.latestRateTimestamp(ETH_A)));
        // emit log_named_uint("rate inse", wad(90)/100);
    }
    
    // should fail if gov is not caller
    function testFailNotGov() public {
        // insert rate value from unauthorized address
        cfm.insert(ETH_A, t0, t1, ray(110)/100);

        // prank address but commented
        // expect failure
    }
    
    // should fail if rate value is below one
    function testFailRateAboveOne() public {
        // change to expectRevert

        // insert rate value below one
        gov.insert(ETH_A, t0, t1, RAY-1);
    }
    
    // should fail if rate value is inserted at future timestamp
    function testFailFutureTimestamp() public {
        // change to expectRevert "rate/timestamps-not-in-order"

        // insert rate value in future
        gov.insert(ETH_A, t0, block.timestamp+1 days, ray(110)/100);
    }
    
    // should fail if rate value is inserted after latest rate timestamp
    function testFailAfterLatest() public {
        // change to expectRevert "rate/timestamps-not-in-order"

        vm.warp(t2+2 days); // t3 = no snapshot, after

        // insert rate value after latest rate timestamp
        gov.insert(ETH_A, t0, t2+1 days, ray(110)/100);
    }
    
    // should fail if rate value is already present at timestamp
    function testFailRateExistsTimestamp() public {
        // change to expectRevert "rate/overwrite-disabled"
        gov.insert(ETH_A, t0, t1, ray(110)/100);

        // insert rate value when it already exists
        gov.insert(ETH_A, t0, t1, ray(110)/100);
    }
    
    // should fail if lower than the guard rail value
    function testFailGuardrailLower() public {
        // change to expectRevert "rate/invalid"
        // insert rate value lower than guardrail

        gov.insert(ETH_A, t0, t1, ray(116)/100);
    }
    
    // should fail if guardrail timestamp is higher
    function testFailGuardrailTimestampInvalid() public {
        // change to expectRevert "rate/timestamps-not-in-order"

        // 1.00 - 1.11 - 1.15 (t0 - t1.1 - t2)
        // insert 1.11 at t1+1 seconds to ensure it has a valid rate value
        // t0 guardrail
        gov.insert(ETH_A, t0, t1+1, ray(111)/100);
        
        // 1.00 - 1.10 - 1.11 - 1.15 (t0 - t1 - t1.1 - t2)
        // t1+1 guardrail is invalid since it is higher than t1
        gov.insert(ETH_A, t1+1, t1, ray(110)/100);
    }
    
    // should fail if rate value is not present at guardrail timestamp
    function testFailGuardrailRateInvalid() public {
        // change to expectRevert "rate/tBefore-not-present"

        // insert valid rate value, empty rate value at guardrail
        gov.insert(ETH_A, t0+1 seconds, t1, ray(111)/100);
    }
    
    // should update rate value
    function testRateUpdated() public {
        // insert rate value
        gov.insert(ETH_A, t0, t1, ray(111)/100);
        
        assertEq(cfm.rate(ETH_A, t1), ray(111)/100);
    }
    
    // should emit event
    // function testNewRateEvent() public {
    // }
}

