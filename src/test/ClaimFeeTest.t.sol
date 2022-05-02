/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.0;

import "ds-test/test.sol";
import "dss.git/vat.sol";
import "./DSMath.sol";
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
    address public vat;
    constructor(address vat_) {
        vat = vat_;
    }
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

    function try_withdraw(bytes32 ilk, address usr, uint256 issuance, uint256 maturity, uint256 bal) public {
        cfm.withdraw(ilk, usr, issuance, maturity, bal);
    }    
}

// when claim balance is transferred
contract ClaimFeeBalanceTransferTest is DSTest, DSMath {
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
        vow = new MockVow(address(vat));
        
        gate = new Gate1(address(vow));
        vat.rely(address(gate));
        gate.file("approvedtotal", rad(10000)); // set draw limit 

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
    
    // should fail if insufficient balance
    function testFailInsufficientBalance() public {
        // expectRevert "cBal/insufficient-balance"

        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));
        holder.moveClaim(holder_addr, me, class_t0_t2, wad(751));
    }
    
    // should update balance at both addresses
    function testBalanceUpdate() public {
        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));
        holder.moveClaim(holder_addr, me, class_t0_t2, wad(250));

        assertEq(cfm.cBal(holder_addr, class_t0_t2), wad(500));
        assertEq(cfm.cBal(me, class_t0_t2), wad(250));
    }
    
    // should fail if user is not approved or owner
    function testFailApproval() public {
        // expectRevert "..."

        // cfm address is not approved by holder to move their balance
        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));
        cfm.moveClaim(holder_addr, me, class_t0_t2, wad(250));
    }
}

// when claim fee is issued
contract ClaimFeeIssuanceTest is DSTest, DSMath {
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
        vow = new MockVow(address(vat));
        
        gate = new Gate1(address(vow));
        vat.rely(address(gate));
        gate.file("approvedtotal", rad(10000)); // set draw limit 

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
    }
    
    // should fail if caller is not governance
    function testFailNotGovernance() public {
        // expectRevert "gate1/not-authorized"

        // issuer not authorized
        cfm.issue(ETH_A, holder_addr, t0, t2, wad(99));
    }
    
    // should fail after close
    function testFailAfterClose() public {
        // expectRevert "closed"
        gov.close();
        gov.issue(ETH_A, holder_addr, t0, t2, wad(99));
    }
    
    // should fail if maturity falls before issuance
    function testFailMaturityEarlier() public {
        // expectRevert "timestamp/invalid"
        
        gov.issue(ETH_A, holder_addr, t0, t0-1, wad(99));
    }
    
    // should fail if maturity falls before latest rate timestamp of ilk
    function testFailMaturityBeforeLatest() public {
        // expectRevert "timestamp/invalid"

        // forward time to t2 and take a snapshot
        vm.warp(t2);
        cfm.snapshot(ETH_A);
        
        // issue one second before latest rate timestamp
        gov.issue(ETH_A, holder_addr, t0, t2-1, wad(99));
    }
    
    // should fail if rate value is not present at issuance
    function testFailRateInvalid() public {
        // expectRevert "timestamp/invalid"
        
        // rate value not present at t1
        gov.issue(ETH_A, holder_addr, t1, t2, wad(99));
    }
    
    // should fail if ilk was not initialized
    function testFailIlkInvalid() public {
        // expectRevert "ilk/not-initialized" 

        gov.issue(bytes32(bytes("WBTC-A")), holder_addr, t0, t2, wad(99));
    }
    
    // should issue claim balances for notional amount
    function testIssuance() public {
        gov.issue(ETH_A, holder_addr, t0, t2, wad(99));
        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));

        assertEq(cfm.cBal(holder_addr, class_t0_t2), wad(99));
    }

    // should increase totalSupply
    function testTotalSupplyIncrease() public {
        gov.issue(ETH_A, holder_addr, t0, t2, wad(99));
        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));

        assertEq(cfm.totalSupply(class_t0_t2), wad(99));
    }

    // should fail if maturity falls after latest rate timestamp but before block.timestamp
    function testFailIssuanceBetweenLatestRateAndBlockTimestamp() public {
        // expectRevert "timestamp/invalid"

        // forward time to t2 and take a snapshot
        vm.warp(t2);
        cfm.snapshot(ETH_A);

        // forward time to t2+10 days
        vm.warp(t2 + 10 days);
        
        // issue with maturity in the past
        // one second after latest rate timestamp 
        // but before current block.timestamp
        gov.issue(ETH_A, holder_addr, t0, t2+1, wad(99));
    }
}

// when claim balance is withdrawn
contract ClaimFeeWithdrawTest is DSTest, DSMath {
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
        vow = new MockVow(address(vat));
        
        gate = new Gate1(address(vow));
        vat.rely(address(gate));
        gate.file("approvedtotal", rad(10000)); // set draw limit 

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

        gov.issue(ETH_A, holder_addr, t0, t2, wad(250));
    }
    
    // should fail if address is not governance
    function testFailNotGovernance() public {
        // expectRevert "gate1/not-authorized"

        // use unauthorized address to call
        cfm.withdraw(ETH_A, holder_addr, t0, t2, wad(99));
    }

    // should burn claim balance held by gov
    function testBurnGovBalance() public {
        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));

        // transfer from holder to governance
        holder.moveClaim(holder_addr, gov_addr, class_t0_t2, wad(250));
        assertEq(cfm.cBal(holder_addr, class_t0_t2), wad(0));

        gov.withdraw(ETH_A, gov_addr, t0, t2, wad(250)); // withdraw entire issuance
        
        assertEq(cfm.cBal(gov_addr, class_t0_t2), wad(0));
    }

    // should burn claim balance held by user
    function testBurnUserBalance() public {
        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));

        gov.withdraw(ETH_A, holder_addr, t0, t2, wad(250)); // withdraw entire issuance
        
        assertEq(cfm.cBal(holder_addr, class_t0_t2), wad(0));
    }

    // should fail if claim balance is being withdrawn by holder
    function testFailHolderWithdrawBalance() public {
        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));
        assertEq(cfm.cBal(holder_addr, class_t0_t2), wad(250));

        holder.try_withdraw(ETH_A, holder_addr, t0, t2, wad(250)); // withdraw entire issuance
    }

    // should decrease totalSupply
    function testTotalSupplyDecrease() public {
        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));

        gov.withdraw(ETH_A, holder_addr, t0, t2, wad(250)); // withdraw entire issuance
        
        assertEq(cfm.totalSupply(class_t0_t2), wad(0));
    }
}

// when user collects with claim balance after maturity 
contract ClaimFeeCollectTest is DSTest, DSMath {
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
        vow = new MockVow(address(vat));
        
        gate = new Gate1(address(vow));
        vat.rely(address(gate));
        gate.file("approvedtotal", rad(10000)); // set draw limit 

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
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.00

        gov.issue(ETH_A, holder_addr, t0, t2, wad(250));

        // forward rate and time, take snapshot
        vm.warp(t1);
        vat.increaseRate(ETH_A, wad(5), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t1 @ 1.05
    }
    
    // should fail if sender is not approved
    function testFailNotApproved() public {
        // expectRevert "not-allowed"

        // use unauthorized address
        cfm.collect(ETH_A, holder_addr, t0, t2, t1, wad(250));
    }
    
    // should pass if sender is approved by user
    function testApproved() public {
        // approve cfm address
        holder.hope(address(this));

        cfm.collect(ETH_A, holder_addr, t0, t2, t1, wad(250));
    }
    
    // should fail when collect is before issuance
    function testFailBeforeIssuance() public {
        // // expectRevert "timestamp/invalid"

        // insert rate value at t1-1
        vm.warp(t1);
        vat.increaseRate(ETH_A, wad(1), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t1+1 @ 1.0605
        gov.issue(ETH_A, holder_addr, t1, t2, wad(250));

        gov.insert(ETH_A, t0, t1-1, ray(105)/100);

        vm.warp(t2);
        vat.increaseRate(ETH_A, wad(1), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t1+1 @ 1.0605

        holder.collect(ETH_A, holder_addr, t1, t2, t1-1, wad(250));
    }
    
    // should fail when collect is after maturity
    function testFailAfterMaturity() public {
        // expectRevert "timestamp/invalid"

        // forward and snapshot at t2(expiry)
        vm.warp(t2);
        vat.increaseRate(ETH_A, wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t2 @ 1.155

        // forward and snapshot at t3(beyond expiry)
        uint256 t3 = block.timestamp + 15 days;
        vm.warp(t3);
        vat.increaseRate(ETH_A, wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t3 @ 1.2705

        // try collect at t3 with valid snapshot
        holder.collect(ETH_A, holder_addr, t0, t2, t3, wad(250));
    }
    
    // should fail if collect rate value does not exist 
    function testFailCollectRateValueDoesNotExist() public {
        // expectRevert "rate/invalid"

        // no snapshot at t1+1
        holder.collect(ETH_A, holder_addr, t0, t2, t1+1, wad(250));
    }
    
    // should fail if issuance rate value is equal to collect
    // note: we removed this test since it creates a blocker
    // for a holder to collect and execute cashClaim without a
    // rate difference
    // function testFailNoDifference() public {
    //     // expectRevert "rate/no-difference"

    //     holder.collect(ETH_A, holder_addr, t0, t2, t0, wad(250));
    // }
    
    // should burn claim balance when successful
    function testBurnClaimBalance() public {
        holder.collect(ETH_A, holder_addr, t0, t2, t1, wad(250));

        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));
        assertEq(cfm.cBal(holder_addr, class_t0_t2), wad(0));
    }
    
    // should mint new claim balance if there is residual time period
    function testMintClaimBalance() public {
        holder.collect(ETH_A, holder_addr, t0, t2, t1, wad(250));

        bytes32 class_t1_t2 = keccak256(abi.encodePacked(ETH_A, t1, t2));
        assertEq(cfm.cBal(holder_addr, class_t1_t2), wad(250));
    }

    // should not mint new claim balance
    function testNoMintAfterFullCollection() public {
        // forward and snapshot at t2(expiry)
        vm.warp(t2);
        vat.increaseRate(ETH_A, wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t2 @ 1.155

        holder.collect(ETH_A, holder_addr, t0, t2, t2, wad(250));

        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));
        assertEq(cfm.cBal(holder_addr, class_t0_t2), wad(0));
    }
    
    // should transfer dai to user
    function testDaiTransfer() public {
        uint256 dai_start = vat.dai(holder_addr);
        assertEq(dai_start, rad(10000));
        
        // issue for t1-t2
        gov.issue(ETH_A, holder_addr, t1, t2, wad(100));

        // forward rate and time, take snapshot
        vm.warp(t2);
        vat.increaseRate(ETH_A, wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t2 @ 1.155

        // t1 - t2 collect calculations
        // yield between 1.050 - 1.155 on 100
        // (100/1.05) * (1.050 - 1.155)
        // 95.2380    *  0.105 = 10
        holder.collect(ETH_A, holder_addr, t1, t2, t2, wad(100));

        assertGe(vat.dai(holder_addr), dai_start + (rad(10) - RAD));
        // within single RAD rounding error

        bytes32 class_t1_t2 = keccak256(abi.encodePacked(ETH_A, t1, t2));
        assertEq(cfm.cBal(holder_addr, class_t1_t2), wad(0));
    }
}

// when user rewinds issuance timestamp on their claim balance
contract ClaimFeeRewindTest is DSTest, DSMath {
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
        vow = new MockVow(address(vat));
        
        gate = new Gate1(address(vow));
        vat.rely(address(gate));
        gate.file("approvedtotal", rad(10000)); // set draw limit 

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
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.00

        // forward rate and time, take snapshot
        vm.warp(t1);
        vat.increaseRate(ETH_A, wad(5), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t1 @ 1.05

        gov.issue(ETH_A, holder_addr, t1, t2, wad(250));
        
        // holder approves claimfee to debit their dai balance
        // permission needed for rewind
        holder.vatHope(address(cfm));
    }
    
    // should fail if sender is not approved
    function testFailNotApproved() public {
        // expectRevert "not-allowed"

        // use unauthorized address
        cfm.rewind(ETH_A, holder_addr, t1, t2, t0, wad(250));
    }

    // should fail after close
    function testFailClosed() public {
        // expectRevert "closed"

        // close instance
        gov.close();

        holder.rewind(ETH_A, holder_addr, t1, t2, t0, wad(250));
    }
    
    // should pass if sender is approved by user
    function testApproved() public {
        // approve cfm address
        holder.hope(address(this));

        cfm.rewind(ETH_A, holder_addr, t1, t2, t0, wad(250));
    }
    
    // should fail when rewind timestamp is after issuance
    function testFailAfterIssuance() public {
        // expectRevert "timestamp/invalid"

        // forward rate and time, take snapshot at t1+1
        vm.warp(t1+1);
        vat.increaseRate(ETH_A, wad(1), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t1+1 @ 1.0605

        holder.rewind(ETH_A, holder_addr, t1, t2, t1+1, wad(250));
    }
    
    // should fail when rewind is after maturity
    function testFailAfterMaturity() public {
        // expectRevert "timestamp/invalid"

        // forward and snapshot at t2(expiry)
        vm.warp(t2);
        vat.increaseRate(ETH_A, wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t2 @ 1.155

        // forward and snapshot at t3(beyond expiry)
        uint256 t3 = block.timestamp + 15 days;
        vm.warp(t3);
        vat.increaseRate(ETH_A, wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t3 @ 1.2705

        // try rewind at t3 with valid snapshot
        holder.rewind(ETH_A, holder_addr, t1, t2, t3, wad(250));
    }
    
    // should fail if rewind rate value does not exist 
    function testFailRewindRateValueDoesNotExist() public {
        // expectRevert "rate/invalid"

        // no snapshot at t1-1
        holder.rewind(ETH_A, holder_addr, t1, t2, t1-1, wad(250));
    }
    
    // should fail if issuance rate value is equal to rewind
    function testFailNoDifference() public {
        // expectRevert "rate/no-difference"

        holder.rewind(ETH_A, holder_addr, t1, t2, t1, wad(250));
    }
    
    // should adjust class of claim balance
    function testAdjustClassClaimBalance() public {
        holder.rewind(ETH_A, holder_addr, t1, t2, t0, wad(250));

        bytes32 class_t1_t2 = keccak256(abi.encodePacked(ETH_A, t1, t2));
        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));
        
        assertEq(cfm.cBal(holder_addr, class_t1_t2), wad(0));
        assertEq(cfm.cBal(holder_addr, class_t0_t2), wad(250));
    }
    
    // should transfer dai to maker
    function testDaiTransfer() public {
        uint256 dai_start = vat.dai(holder_addr);
        assertEq(dai_start, rad(10000));

        uint256 t3 = t2 + 15 days;

        // forward rate and time, take snapshot
        vm.warp(t2);
        vat.increaseRate(ETH_A, wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t2 @ 1.155

        // issue for t2-t3
        gov.issue(ETH_A, holder_addr, t2, t3, wad(100));

        // t2 - t1 rewind calculations
        // yield between 1.155 - 1.050 - on 100
        // 100/1.050 * 1.155 - 100 = 10
        holder.rewind(ETH_A, holder_addr, t2, t3, t1, wad(100));

        assertEq(vat.dai(holder_addr), dai_start - rad(10));

        bytes32 class_t2_t3 = keccak256(abi.encodePacked(ETH_A, t2, t3));
        assertEq(cfm.cBal(holder_addr, class_t2_t3), wad(0));

        bytes32 class_t1_t3 = keccak256(abi.encodePacked(ETH_A, t1, t3));
        assertEq(cfm.cBal(holder_addr, class_t1_t3), wad(100));
    }

    // should not have effect when rewind and collect are executed
    function testRewindCollect() public {
        uint256 dai_start = vat.dai(holder_addr);
        assertEq(dai_start, rad(10000));

        uint256 t3 = t2 + 15 days;

        // forward rate and time, take snapshot
        vm.warp(t2);
        vat.increaseRate(ETH_A, wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t2 @ 1.155

        // issue for t2-t3
        gov.issue(ETH_A, holder_addr, t2, t3, wad(100));

        holder.rewind(ETH_A, holder_addr, t2, t3, t1, wad(100));
        holder.collect(ETH_A, holder_addr, t1, t3, t2, wad(100));

        assertEq(vat.dai(holder_addr), dai_start);

        bytes32 class_t2_t3 = keccak256(abi.encodePacked(ETH_A, t2, t3));
        assertEq(cfm.cBal(holder_addr, class_t2_t3), wad(100));

        bytes32 class_t1_t3 = keccak256(abi.encodePacked(ETH_A, t1, t3));
        assertEq(cfm.cBal(holder_addr, class_t1_t3), wad(0));
    }
}

// when user slices their claim balance
contract ClaimFeeSliceTest is DSTest, DSMath {
    Vm public vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 t0;
    uint256 t1;
    uint256 t2;
    uint256 t3;

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
        t3 = block.timestamp + 15 days;

        me = address(this);
        vat = new TestVat();
        vat.rely(address(vat));
        vow = new MockVow(address(vat));
        
        gate = new Gate1(address(vow));
        vat.rely(address(gate));
        gate.file("approvedtotal", rad(10000)); // set draw limit 

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
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.00

        // forward rate and time, take snapshot
        vm.warp(t1);
        vat.increaseRate(ETH_A, wad(5), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t1 @ 1.05

        gov.issue(ETH_A, holder_addr, t1, t3, wad(250));
    }
    
    // should fail if sender is not approved 
    function testFailNotApproved() public {
        // expectRevert "not-allowed"

        // call from unauthorized address
        cfm.slice(ETH_A, holder_addr, t1, t2, t3, wad(250));
    }

    // should pass if sender is approved by user
    function testApproved() public {
        holder.slice(ETH_A, holder_addr, t1, t2, t3, wad(250));
    }

    // should fail when slice timestamp is before issuance
    function testFailBeforeIssuance() public {
        // expectRevert "timestamp/invalid"

        holder.slice(ETH_A, holder_addr, t1, t0, t3, wad(250));
    }

    // should fail if slice is after maturity
    function testFailAfterMaturity() public {
        // expectRevert "timestamp/invalid"
        gov.issue(ETH_A, holder_addr, t1, t2-1, wad(250));

        holder.slice(ETH_A, holder_addr, t1, t2, t2-1, wad(250));
    }

    // should adjust claim fee balances
    function testAdjustBalances() public {
        holder.slice(ETH_A, holder_addr, t1, t2, t3, wad(250));

        bytes32 class_t1_t3 = keccak256(abi.encodePacked(ETH_A, t1, t3));
        assertEq(cfm.cBal(holder_addr, class_t1_t3), wad(0));

        bytes32 class_t1_t2 = keccak256(abi.encodePacked(ETH_A, t1, t2));
        assertEq(cfm.cBal(holder_addr, class_t1_t2), wad(250));

        bytes32 class_t2_t3 = keccak256(abi.encodePacked(ETH_A, t2, t3));
        assertEq(cfm.cBal(holder_addr, class_t2_t3), wad(250));
    }
}

// when user activates their claim balance
contract ClaimFeeActivateTest is DSTest, DSMath {
    Vm public vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 t0;
    uint256 t1;
    uint256 t2;
    uint256 t3;

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
        t3 = block.timestamp + 15 days;

        me = address(this);
        vat = new TestVat();
        vat.rely(address(vat));
        vow = new MockVow(address(vat));
        
        gate = new Gate1(address(vow));
        vat.rely(address(gate));
        gate.file("approvedtotal", rad(10000)); // set draw limit 

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
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.00

        // forward rate and time, take snapshot
        vm.warp(t1);
        vat.increaseRate(ETH_A, wad(5), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t1 @ 1.05

        gov.issue(ETH_A, holder_addr, t1, t3, wad(250));
        holder.slice(ETH_A, holder_addr, t1, t2-1, t3, wad(250)); // sliced before t2

        // forward rate and time, take snapshot
        vm.warp(t2-2);
        // no change in rate from t1
        cfm.snapshot(ETH_A);
        
        // forward rate and time, take snapshot
        vm.warp(t2);
        vat.increaseRate(ETH_A, wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t2 @ 1.155
    }
    
    // should fail if sender is not approved 
    function testFailNotApproved() public {
        // expectRevert "not-allowed"

        // call from unauthorized address
        cfm.activate(ETH_A, holder_addr, t2-1, t2, t3, wad(250));
    }
    
    // should pass if sender is approved by user
    function testApproved() public {
        holder.activate(ETH_A, holder_addr, t2-1, t2, t3, wad(250));
    }
    
    // should fail when activate point is lower than issuance
    function testFailLowerThanIssuance() public {
        // expectRevert "timestamp/invalid"

        holder.activate(ETH_A, holder_addr, t2-1, t2-2, t3, wad(250));
    }
    
    // should fail when activate point is greater than maturity
    function testFailGreaterThanMaturity() public {
        // expectRevert "timestamp/invalid"

        // forward rate and time, take snapshot
        vm.warp(t3+1);
        // no change in rate from t2
        cfm.snapshot(ETH_A);

        holder.activate(ETH_A, holder_addr, t2-1, t3+1, t3, wad(250));
    }
    
    // should fail if issuance rate value is present
    function testFailIssuanceValid() public {
        // expectRevert "rate/valid"

        // set snapshot at t2-1
        vm.warp(t2-1);
        cfm.snapshot(ETH_A);
        vm.warp(t2); // back to t2

        holder.activate(ETH_A, holder_addr, t2-1, t2, t3, wad(250));
    }

    // should fail if activate rate value is not present
    function testFailActivateInvalid() public {
        // expectRevert "rate/invalid"

        // no snapshot at t2+1
        holder.activate(ETH_A, holder_addr, t2-1, t2+1, t3, wad(250));
    }

    // should fail if issuance and activate timestamps are equal
    function testFailIssuanceActivateEqual() public {
        // expectRevert "timestamp/invalid"

        // set snapshot at t2-1
        vm.warp(t2-1);
        cfm.snapshot(ETH_A);
        vm.warp(t2); // back to t2

        holder.activate(ETH_A, holder_addr, t2-1, t2-1, t3, wad(250));
    }

    // should adjust claim fee balance class
    function testAdjustClaimBalances() public {
        holder.activate(ETH_A, holder_addr, t2-1, t2, t3, wad(250));

        bytes32 class_t2min1_t3 = keccak256(abi.encodePacked(ETH_A, t2-1, t3));
        assertEq(cfm.cBal(holder_addr, class_t2min1_t3), wad(0));
        
        bytes32 class_t2_t3 = keccak256(abi.encodePacked(ETH_A, t2, t3));
        assertEq(cfm.cBal(holder_addr, class_t2_t3), wad(250));
    }
}

// wwhen user merges two claim balances
contract ClaimFeeMergeTest is DSTest, DSMath {
    Vm public vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 t0;
    uint256 t1;
    uint256 t2;
    uint256 t3;

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
        t3 = block.timestamp + 15 days;

        me = address(this);
        vat = new TestVat();
        vat.rely(address(vat));
        vow = new MockVow(address(vat));
        
        gate = new Gate1(address(vow));
        vat.rely(address(gate));
        gate.file("approvedtotal", rad(10000)); // set draw limit 

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
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.00

        // forward rate and time, take snapshot
        vm.warp(t1);
        vat.increaseRate(ETH_A, wad(5), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t1 @ 1.05

        gov.issue(ETH_A, holder_addr, t1, t3, wad(250));
        holder.slice(ETH_A, holder_addr, t1, t2, t3, wad(250)); // sliced at t2

        // forward rate and time, take snapshot
        vm.warp(t2);
        vat.increaseRate(ETH_A, wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t2 @ 1.155
    }
    
    // should fail if sender is not approved 
    function testNotApproved() public {
        // expectRevert "not-allowed"

        // call from unauthorized address
        holder.merge(ETH_A, holder_addr, t1, t2, t3, wad(250));
    }

    // should pass if sender is approved by user
    function testApproved() public {
        holder.merge(ETH_A, holder_addr, t1, t2, t3, wad(250));
    }

    // should fail when merge timestamp is lower than issuance
    function testFailLowerThanIssuance() public {
        // expectRevert "timestamp/invalid"

        holder.merge(ETH_A, holder_addr, t1, t1-1, t3, wad(250));
    }

    // should fail when merge timestamp is greater than maturity
    function testFailGreaterThanMaturity() public {
        // expectRevert "timestamp/invalid"

        holder.merge(ETH_A, holder_addr, t1, t2, t2-1, wad(250));
    }

    // should adjust claim fee balances
    function testAdjustBalances() public {
        holder.merge(ETH_A, holder_addr, t1, t2, t3, wad(250));

        bytes32 class_t1_t2 = keccak256(abi.encodePacked(ETH_A, t1, t2));
        assertEq(cfm.cBal(holder_addr, class_t1_t2), wad(0));

        bytes32 class_t2_t3 = keccak256(abi.encodePacked(ETH_A, t2, t3));
        assertEq(cfm.cBal(holder_addr, class_t2_t3), wad(0));
        
        bytes32 class_t1_t3 = keccak256(abi.encodePacked(ETH_A, t1, t3));
        assertEq(cfm.cBal(holder_addr, class_t1_t3), wad(250));
    }
}