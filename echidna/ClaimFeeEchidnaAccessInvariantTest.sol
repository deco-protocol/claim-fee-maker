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
    The following Echidna tests focuses on mostly access control related asserts. Echidna will run a 
    sequence of random input and various call sequences (configured depth) to violates the 
    access control invariants defined.

    Target Access modifiers : auth, untilClose, afterClose
 */
contract ClaimFeeEchidnaAccessInvariantTest is DSMath {
    
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
    TestUtil public test_util;

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
    bytes32 public ETH_Z = bytes32("ETH-Z");

    constructor()  {
        vm.warp(1641400537);

        t0 = block.timestamp; // Current block timestamp
        t1 = block.timestamp + 5 days; // Current block TS + 5 days
        t2 = block.timestamp + 10 days; // Current block TS + 10 days
        t3 = block.timestamp + 15 days; // Current block TS + 15 days

        me = address(this);
        vat = new TestVat();
        test_util = new TestUtil();
        vat.rely(address(vat));
        vow = new MockVow(address(vat));
        gate = new Gate1(address(vow));
        vat.rely(address(gate));
        gate.file("approvedtotal", test_util.rad(10000)); // set draw limit 

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
        vat.mint(holder_addr, test_util.rad(10000)); // cfm holder holds 10000 RAD vault

        vat.ilkSetup(ETH_A); // vat initializes ILK (ETH_A).
        gov.initializeIlk(ETH_A); // Gov initializes ILK (ETH_A) in Claimfee as gov is a ward
        vat.ilkSetup(WBTC_A); // Vat initializes ILK (WBTC_A)
        gov.initializeIlk(WBTC_A); // gov initialize ILK (WBTC_A) in claimfee as gov is a ward

        vat.increaseRate(ETH_A, test_util.wad(5), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.05
        cfm.issue(ETH_A, holder_addr, t0, t2, test_util.wad(750)); // issue cf 750 to cHolder

        vat.increaseRate(WBTC_A, test_util.wad(5), address(vow));
        cfm.snapshot(WBTC_A); // take a snapshot at t0 @ 1.10
        cfm.issue(WBTC_A, holder_addr, t0, t2,test_util. wad(5000)); // issue cf 5000 to cHolder

        // vm.warp(t1); // Forward time to t1
        
        // vat.increaseRate(ETH_A, testUtil.wad(10), address(vow));
        // cfm.snapshot(ETH_A); // take a snapshot at t1 @ 1.05

        // vat.increaseRate(WBTC_A, testUtil.wad(10), address(vow));
        // cfm.snapshot(WBTC_A); // take a snapshot at t1 @ 1.10
        
    }

    // Access Invariant - ilk cannot be initialized by a regular user
    function test_ilk_init() public {

        try  usr.initializeIlk(ETH_Z) {
            assert(cfm.initializedIlks(ETH_Z) == false);
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "gate1/not-authorized"));
        } catch {
            assert(false);  // echidna will fail if any other revert cases are caught
        }
    }

    // Access Invariant - claimfee balance can be issued only by a ward (not a regular user)
    function test_issue_wardonly(uint256 bal) public {
        try usr.try_issue(ETH_A,usr_addr, t0, t2, bal) {
            assert(cfm.initializedIlks(ETH_Z) == false);
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "gate1/not-authorized"));
        } catch {
            assert(false);  // echidna will fail if any other revert cases are caught
        }
    }

    // Access Invariant - Claimfee balance cannot be issued after close
    function test_issue_afterclose(uint256 bal) public {
        // set VAT and claimfee to close 
        gov.close();
        try gov.issue(ETH_A, usr_addr, t0 , t3, bal) {
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "closed" ));
        } catch {
            assert(false); // echidna will fail if any other revert cases are caught
        }
        teardown();
    }

    // Access Invariant - A ward is the only authorized to withdraw claimfee
    function test_withdraw_wardonly(uint256 bal) public {
        try usr.try_withdraw(ETH_A, usr_addr, t0 , t3, bal) {
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "gate1/not-authorized" ));
        } catch {
            assert(false); // echidna fails on other reverts
        }
    }

    // Access Invariant - Ward can withdraw after close
    function test_withdraw_afterclose(uint256 bal) public {
        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));

        gov.issue(ETH_A, usr_addr, t0, t2, bal); // issue to user
        gov.close(); // now, close the contract

        gov.withdraw(ETH_A, usr_addr, t0 , t2, bal);
        
        assert(cfm.cBal(usr_addr, class_t0_t2) == 0);

        teardown();
    }

    // Access Invariant - A ward is the only authorized to insert rates
    function test_insert_wardonly(uint256 newTS) public {
         try usr.try_insert(ETH_A, t0, newTS, test_util.wad(15))  {
         } catch Error(string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "gate1/not-authorized" ));
        } catch {
            assert(false); // echidna fails on other reverts
        }
        teardown();
    }

    // Access Invariant - A ward is the only authorized to insert rates
    function test_calculate_wardonly(uint256 ratio) public {
         try usr.try_calculate(ETH_A,t3, ratio)  {
         }catch Error(string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "gate1/not-authorized" ));
        } catch {
            assert(false); // echidna fails on other reverts
        }
        teardown();
    }

    // Access Invariant - A ward can set ratio after close
    function test_calculate_afterclose(uint256 ratio) public {

        gov.close();

        gov.calculate(ETH_A,t3, ratio);
        assert(cfm.ratio(ETH_A, t3) == ratio);
        teardown();
    }

    // Access Invariant - A ward cannot set ratio before close
    function test_calculate_beforeclose() public {
        try gov.calculate(ETH_A,t3, test_util.wad(5))  {
         } catch Error(string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "not-closed" ));
        } catch {
            assert(false); // echidna fails on other reverts
        }
        teardown();
    }

    // Access Invariant - slice 
    function test_rewind_afterclose(uint256 bal) public {

        gov.issue(ETH_A, usr_addr, t0, t2, bal);
        gov.close();

        try  cfm.rewind(ETH_A, usr_addr, t0, t2, t0-1, bal)  {
         } catch Error(string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "closed" ));
        } catch {
            assert(false); // echidna fails on other reverts
        }
        teardown();
    }

    // Access Invariant - delegate to another user
    function test_hope(address delegate) public {
        usr.hope(delegate);
        assert(cfm.can(usr_addr,delegate) == 1);       
        teardown();
    }

    // Access Invariant - deny a delegated
    function test_nope(address delegate) public {

        // delegate to
        usr.hope(delegate);

        usr.nope(delegate);
        assert(cfm.can(usr_addr,delegate) == 0);       
        teardown();
    }


    function teardown() pure internal {
        revert("undo state changes");
    }

}