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
    uint256 t4;

    ClaimFee public cfm; // contract to be tested

    TestVat public vat;
    MockVow public vow;
    Gate1 public gate;
    CHolder public holder;
    TestUtil public testUtil;

    GovernanceUser public gov_user;
    MakerUser public usr;
    MakerUser public usr2;

    address public me;
    address public gov_addr;
    address public usr_addr;
    address public usr2_addr;
    address public holder_addr;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

    bytes32 public ETH_A = bytes32("ETH-A");
    bytes32 public WBTC_A = bytes32("WBTC-A");
    bytes32 public ethA_t0_t2_class = keccak256(abi.encodePacked(ETH_A, t0, t2));

    constructor()  {
        vm.warp(1641400537);

        t0 = block.timestamp; // Current block timestamp
        t1 = block.timestamp + 5 days; // Current block TS + 5 days
        t2 = block.timestamp + 10 days; // Current block TS + 10 days
        t3 = block.timestamp + 15 days; // Current block TS + 15 days
        t4 = block.timestamp + 20 days; // Current block TS + 20 days

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
        gov_user = new GovernanceUser(cfm);
        gov_addr = address(gov_user);  
        cfm.rely(gov_addr); // Add gov user as a ward.
        gate.kiss(address(cfm)); // Add a CFM as integration to gate

        // Public User
        usr = new MakerUser(cfm);
        usr_addr = address(usr);

        usr2 = new MakerUser(cfm);
        usr2_addr = address(usr2);

        vat.mint(usr_addr, testUtil.rad(10000)); // maker user holds 10000 RAD vault

        vat.ilkSetup(ETH_A); // vat initializes ILK (ETH_A).
        gov_user.initializeIlk(ETH_A); // Gov initializes ILK (ETH_A) in Claimfee as gov is a ward
        vat.ilkSetup(WBTC_A); // Vat initializes ILK (WBTC_A)
        gov_user.initializeIlk(WBTC_A); // gov initialize ILK (WBTC_A) in claimfee as gov is a ward

        vat.increaseRate(ETH_A, testUtil.wad(5), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.05
        cfm.issue(ETH_A, usr_addr, t0, t2, testUtil.wad(750)); // issue cf 750 to usr

        vat.increaseRate(WBTC_A, testUtil.wad(5), address(vow));
        cfm.snapshot(WBTC_A); // take a snapshot at t0 @ 1.10
        cfm.issue(WBTC_A, usr_addr, t0, t2,testUtil. wad(5000)); // issue cf 5000 to usr
        
    }

    // Conditional Invariant : Ilk  cannot be initialized until its init in VAT
    function test_cannot_initialize_ilk_vatmiss() public {
        bytes32 ETH_Z = bytes32("ETH-Z"); // not initialized in vat

        try gov_user.initializeIlk(ETH_Z) {
            assert(cfm.initializedIlks(ETH_Z) == false);
        } catch Error (string memory errmsg) {
            assert(testUtil.cmpStr(errmsg, "ilk/not-initialized"));
        } catch {
            assert(false);  // echidna will fail if any other revert cases are caught
        }

    }

    // Conditional Invariant : Ilk cannot be reinitialized
    function test_already_initialized_ilk() public {
        try gov_user.initializeIlk(ETH_A) {
        } catch Error (string memory errmsg) {
            assert(testUtil.cmpStr(errmsg, "ilk/initialized"));
        } catch {
            assert(false);  // echidna will fail
        }
    }

    // Conditional Invariant : Cannot move claim balance if not authorized
    function test_move_unauthorized(uint256 bal) public {
        try usr2.moveClaim(usr_addr, usr2_addr, ethA_t0_t2_class, bal) {
        } catch Error (string memory errmsg) {
            assert(testUtil.cmpStr(errmsg, "not-allowed"));
        } catch {
            assert(false);  // echidna will fail 
        }
    }

    // Conditional Invariant : Cannot move claim balance upon insufficient balance
    function test_move_insufficient_balance(uint256 bal) public {

        cfm.issue(ETH_A, usr2_addr, t0, t2, testUtil.wad(100)); // issue cf 100 to usr2
        usr2.hope(address(this));

        try usr2.moveClaim(usr2_addr, usr_addr, ethA_t0_t2_class, bal) {
        } catch Error (string memory errmsg) {
            assert(testUtil.cmpStr(errmsg, "cBal/insufficient-balance"));
        } catch {
            assert(false);  // echidna will fail 
        }
    }

    // Conditional Invariant : Snapshot is not allowed only if initialized
    function test_snapshot_not_initialized() public {
        bytes32 ETH_Z = bytes32("ETH-Z"); // not initialized in vat

        try usr.snapshot(ETH_Z) {
        } catch Error (string memory errmsg) {
            assert(testUtil.cmpStr(errmsg, "ilk/not-initialized"));
        } catch {
            assert(false); // on any other echidna reverts
        }
    }

    // Conditional Invariant : The insert rate timestamp cannot be in future
    function test_insert_rate_not_in_order(uint256 newRate) public {

        // here t2 greater than the block timestamp (cannot be in future)
        try gov_user.insert(ETH_A, t0, t2, newRate) {
        } catch Error (string memory errmsg) {
            assert(testUtil.cmpStr(errmsg, "rate/timestamps-not-in-order"));
        } catch {
            assert(false); // on any other echidna reverts
        }
    }

    // Conditional Invariant : Overwriting rate timestamp is not allowed on a ILK
    function test_insert_rate_overwrite_notallowed() public {

        vm.warp(t1);
        vat.increaseRate(ETH_A, testUtil.wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.1

        vm.warp(t3);
        vat.increaseRate(ETH_A, testUtil.wad(15), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.15

        // here t1 is in between t0 and t2
        try gov_user.insert(ETH_A, t0, t1, ray(115)/100) {
        } catch Error (string memory errmsg) {
            assert(testUtil.cmpStr(errmsg, "rate/overwrite-disabled"));
        } catch {
            assert(false); // on any other echidna reverts
        }

        teardown();
    }

    // Conditional Invariant : Before rate is not present
    function test_insert_pastrate_not_present() public {

        vm.warp(t3);
        vat.increaseRate(ETH_A, testUtil.wad(15), address(vow));
        cfm.snapshot(ETH_A);

        vm.warp(t4);

        // here the rate is not recorded at t1
        try gov_user.insert(ETH_A, t1, t2, ray(115)/100) {
        } catch Error (string memory errmsg) {
            assert(testUtil.cmpStr(errmsg, "rate/tBefore-not-present"));
        } catch {
            assert(false); // on any other echidna reverts
        }
        teardown();
    }

    // Conditional Invariant Goal : Claimfee cannot be issued if the rate at issuance ts is not recorded  
    function test_cannot_issueClaim_unlessRateRecorded_ThrowsError(uint256 bal) public {

        vm.warp(t3);
        vat.increaseRate(ETH_A, testUtil.wad(15), address(vow));

        try gov_user.issue(ETH_A, usr_addr, t2,t3, bal) {
            // no-op
        } catch Error (string memory errorMessage) {
            assert(testUtil.cmpStr(errorMessage, "timestamp/invalid") || 
            testUtil.cmpStr(errorMessage, "rate/invalid"));
        }  catch {
            assert(false);
        }
    }

    // Conditional : The DAI cannot be collected by unauthroized 
    function test_collect_unauthorized(uint256 bal) public {

        try cfm.collect(ETH_A, usr_addr, t0, t2, t1, testUtil.wad(bal)) {
        } catch Error (string memory errorMessage) {
            // Echidna - possible errors on call sequence invariants
            assert(testUtil.cmpStr(errorMessage, "not-allowed")); 
        }  catch {
            assert(false);
        } 
    }

    // Conditional : The collect timestamp cannot be after maturity
    function test_collect_post_maturity(uint256 bal) public {

        usr.hope(address(this));
        try cfm.collect(ETH_A, usr_addr, t0, t2, t3, testUtil.wad(bal)) {
        } catch Error (string memory errorMessage) {
            assert(testUtil.cmpStr(errorMessage, "timestamp/invalid")); 
        }  catch {
            assert(false);
        } 
        teardown();
    }

    // Conditional : The rate value should be recorded at collect ts 
    function test_collect_invalid_collection(uint256 bal) public {

        usr.hope(address(this));
        try cfm.collect(ETH_A, usr_addr, t0, t2, t1, testUtil.wad(bal)) {
        } catch Error (string memory errorMessage) {
            assert(testUtil.cmpStr(errorMessage, "rate/invalid")); 
        }  catch {
            assert(false);
        }
        teardown();
    }


    // Conditional : Unauthorized user cannot invoke rewind
    function test_rewind_unauthorized(uint256 bal) public {
        uint256 t00 = t0 - 5 days; // past  5 days
        try cfm.rewind(ETH_A, usr_addr, t0, t2, t00, bal) {
        } catch Error (string memory errorMsg){
            assert(testUtil.cmpStr(errorMsg, "not-allowed"));
        } catch {
            assert(false);
        }
    }

    // Conditional : The rewind ts cannot be between issuance and maturity
    function test_rewind_invalid_rewindts(uint256 bal) public {

        usr.hope(address(this));

        // the rewind ts (t2) cannot be in between issuance and maturity
        try cfm.rewind(ETH_A, usr_addr, t0, t3, t2, bal) {
        } catch Error (string memory errorMsg){
            assert(testUtil.cmpStr(errorMsg, "timestamp/invalid"));
        } catch {
            assert(false);
        }
        teardown();
    }

    // Conditional : The rewind fails if rate is not recorded at rewind ts.
    function test_rewind_invalid_rate(uint256 bal) public {

        usr.hope(address(this));
        
        gov_user.issue(ETH_A, usr_addr, t2,t3, bal);

        // The rate is not recorded at t1
        try cfm.rewind(ETH_A, usr_addr, t2, t3, t1, bal) {
        } catch Error (string memory errorMsg){
            assert(testUtil.cmpStr(errorMsg, "rate/invalid"));
        } catch {
            assert(false);
        }
        teardown();
    }

    // Conditional : slice cannot be performed after maturity
     function test_slice_aftermaturity(uint256 bal) public {
        usr.hope(address(this));
        try cfm.slice(ETH_A, usr_addr, t0, t2+1, t2, bal) {
        } catch Error (string memory errMsg) {
            assert(testUtil.cmpStr(errMsg, "timestamp/invalid"));
        } catch {
            assert(false);
        }
        teardown();
     }

     // Conditional : slice cannot be performed after maturity
     function test_slice_unauthorized(uint256 bal) public {
        try cfm.slice(ETH_A, usr_addr, t0, t2+1, t2, bal) {
        } catch Error (string memory errMsg) {
            assert(testUtil.cmpStr(errMsg, "not-allowed"));
        } catch {
            assert(false); // fail on echidna reverts
        }
     }

      // Conditional : slice cannot be invoked before issuance 
      function test_slice_beforeissuance(uint256 bal) public {
        usr.hope(address(this));
        try cfm.slice(ETH_A, usr_addr, t0, t0-1, t2, bal) {
        } catch Error (string memory errMsg) {
            assert(testUtil.cmpStr(errMsg, "timestamp/invalid") );
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
        teardown();
     }

     // Conditional : Merge cannot be performed after maturity
     function test_merge_aftermaturity(uint256 bal) public {

         gov_user.issue(ETH_A, usr_addr, t0, t1, bal);
         gov_user.issue(ETH_A, usr_addr, t1, t2, bal);
         usr.hope(address(this));

        try cfm.merge(ETH_A, usr_addr, t0, t1, t2+1, bal) {
        } catch Error (string memory errMsg) {
            assert(testUtil.cmpStr(errMsg, "timestamp/invalid")); 
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
        teardown();
     }

     // Conditional : Merge unauthorized
     function test_merge_unauthorized(uint256 bal) public {

         gov_user.issue(ETH_A, usr_addr, t0, t1, bal);
         gov_user.issue(ETH_A, usr_addr, t1, t2, bal);

        try cfm.merge(ETH_A, usr_addr, t0, t1, t2+1, bal) {
        } catch Error (string memory errMsg) {
            assert(testUtil.cmpStr(errMsg, "not-allowed")); 
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
     }

     // Conditional : activate can be invoke only by authorized delegates
     function test_activate_unauthorized(uint256 bal) public {

        try cfm.activate(ETH_A, usr_addr, t0, t1, t2, bal) {
        } catch Error (string memory errMsg) {
            assert(testUtil.cmpStr(errMsg, "not-allowed")); 
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
     }

     // Conditional : issuance time stamp should be absent
     function test_activate_invalid_issuancerate(uint256 bal) public {

        usr.hope(address(this));
        try cfm.activate(ETH_A, usr_addr, t0, t1, t2, bal) {
        } catch Error (string memory errMsg) {
            assert(testUtil.cmpStr(errMsg, "rate/valid")); 
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
        teardown();
     }

     // Conditional : activation time stamp should be present
     function test_activate_invalid_activationrate(uint256 bal) public {

        usr.hope(address(this));
        
        gov_user.issue(ETH_A, usr_addr, t1, t3, bal);
        vat.increaseRate(ETH_A, testUtil.wad(15), address(vow));
        cfm.snapshot(ETH_A);

        vm.warp(t2);

        try cfm.activate(ETH_A, usr_addr, t1, t2, t3, bal) {
        } catch Error (string memory errMsg) {
            assert(testUtil.cmpStr(errMsg, "rate/invalid")); 
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
        teardown();
     }

     // Conditional : activate invalid timestamp order
     function test_activate_invalid_timestamp(uint256 bal) public {

        usr.hope(address(this));

        try cfm.activate(ETH_A, usr_addr, t2, t3, t1, bal) {
        } catch Error (string memory errMsg) {
            assert(testUtil.cmpStr(errMsg, "timestamp/invalid")); 
        } catch {
            assert(false);
        }
        teardown();
     }

     function test_close_conditions() public {
        try usr.try_close() {
        } catch Error (string memory errMsg) {
            assert(testUtil.cmpStr(errMsg, "close/conditions-not-met")); 
        } catch {
            assert(false);
        }
        teardown();
     }

/*
    // Conditional : The rewind fails if rate is same at both issuance and rewind.
    function test_rewind_same_rate(uint256 bal) public {

        usr.hope(address(this));

        vm.warp(t2);
        vat.increaseRate(ETH_A, testUtil.wad(5), address(vow)); // same rate
        cfm.snapshot(ETH_A);

        vm.warp(t3);

        gov.issue(ETH_A, usr_addr, t2, t3, bal);

        try cfm.rewind(ETH_A, usr_addr, t2, t3, t0, bal) {
        } catch Error (string memory errorMsg){
            assert(testUtil.cmpStr(errorMsg, "rate/np-differnce"));
        } catch {
            assert(false);
        }
        teardown();
    }
*/

    function ray(uint256 amt_) public pure returns (uint256) {
        return mulu(amt_, RAY);
    }


    function teardown() pure internal {
        revert("undo state changes");
    }
}