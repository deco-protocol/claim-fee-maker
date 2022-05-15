// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import {ClaimFee} from "../src/ClaimFee.sol";
import {Gate1} from "./deps/gate1.sol";
import "./deps/vat.sol"; 
import "./deps/DSMath.sol";
import "./deps/Vm.sol";

// Echidna test helper contracts
import "./MockVow.sol";
import "./TestVat.sol";
import "./TestGovUser.sol";
import "./TestMakerUser.sol";
import "./TestClaimHolder.sol";
import "./TestUtil.sol";

/**
    The following Echidna tests focuses on mostly "require" conditional asserts. Echidna will run a 
    sequence of random input and various call sequences (configured depth) to violates the 
    conditional invariants defined.
 */
contract ClaimFeeEchidnaConditionalInvariantTest is DSMath {
    
    Vm public vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 t0;
    uint256 t1;
    uint256 t2;
    uint256 t3;

    ClaimFee public cfm; // contract to be tested

    TestVat public vat;
    MockVow public vow;
    Gate1 public gate;
    CHolder public holder;
    TestUtil public testUtil;

    Gov public gov;
    MakerUser public usr;
    address public me;
    address public gov_addr;
    address public usr_addr;
    address public holder_addr;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

    bytes32 public ETH_A = bytes32("ETH-A");
    bytes32 public WBTC_A = bytes32("WBTC-A");

    constructor()  {
        vm.warp(1641400537);

        t0 = block.timestamp; // Current block timestamp
        t1 = block.timestamp + 5 days; // Current block TS + 5 days
        t2 = block.timestamp + 10 days; // Current block TS + 10 days
        t3 = block.timestamp + 15 days; // Current block TS + 15 days

        me = address(this);
        vat = new TestVat();
        testUtil = new TestUtil();
        vat.rely(address(vat));
        vow = new MockVow(address(vat));
        gate = new Gate1(address(vow));
        vat.rely(address(gate));
        gate.file("approvedtotal", testUtil.rad(10000)); // set draw limit 

        // claimfee
        cfm = new ClaimFee(address(gate));
        gov = new Gov(cfm);
        gov_addr = address(gov);  
        cfm.rely(gov_addr); // Add gov user as a ward.
        gate.kiss(address(cfm)); // Add a CFM as integration to gate

        // Public User
        usr = new MakerUser(cfm);
        usr_addr = address(usr);

        holder = new CHolder(cfm);
        holder_addr = address(holder);
        vat.mint(holder_addr, testUtil.rad(10000)); // cfm holder holds 10000 RAD vault

        vat.ilkSetup(ETH_A); // vat initializes ILK (ETH_A).
        gov.initializeIlk(ETH_A); // Gov initializes ILK (ETH_A) in Claimfee as gov is a ward
        vat.ilkSetup(WBTC_A); // Vat initializes ILK (WBTC_A)
        gov.initializeIlk(WBTC_A); // gov initialize ILK (WBTC_A) in claimfee as gov is a ward

        vat.increaseRate(ETH_A, testUtil.wad(5), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.05
        cfm.issue(ETH_A, holder_addr, t0, t2, testUtil.wad(750)); // issue cf 750 to cHolder

        vat.increaseRate(WBTC_A, testUtil.wad(5), address(vow));
        cfm.snapshot(WBTC_A); // take a snapshot at t0 @ 1.10
        cfm.issue(WBTC_A, holder_addr, t0, t2,testUtil. wad(5000)); // issue cf 5000 to cHolder
        
    }

    // Coditional Invariant : Ilk  cannot be initialized until its init in VAT
    function test_cannot_initialize_vatmiss() public {
        bytes32 ETH_Z = bytes32("ETH-Z"); // not initialized in vat

        try gov.initializeIlk(ETH_Z) {
            assert(cfm.initializedIlks(ETH_Z) == false);
        } catch Error (string memory errmsg) {
            assert(testUtil.cmpStr(errmsg, "ilk/not-initialized"));
        } catch {
            assert(false);  // echidna will fail if any other revert cases are caught
        }
    }



}



