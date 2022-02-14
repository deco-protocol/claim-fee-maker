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

    function rely(address _usr) public {
        cfm.rely(_usr);
    }

    function deny(address _usr) public {
        cfm.deny(_usr);
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

// when governance address is updated
contract ClaimFeeGovTest is DSTest, DSMath {
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
        gov.issue(ETH_A, holder_addr, t0, t2, wad(750)); // issue cf 750
    }
    
    // should fail if caller is not current gov
    function testFailNotGov() public {
        // expectRevert "gate1/not-authorized"

        cfm.rely(holder_addr);
    }

    // should update gov to new address
    function testGov() public {
        assertEq(cfm.wards(holder_addr), 0);
        
        gov.rely(holder_addr);
        assertEq(cfm.wards(holder_addr), 1);
    }
}
