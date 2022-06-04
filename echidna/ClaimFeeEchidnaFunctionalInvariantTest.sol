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

contract ClaimFeeEchidnaFunctionalInvariantTest is DSMath {
    
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

    GovernanceUser public gov_user;
    MakerUser public usr;
    MakerUser public usr2;
    address public me;
    address public gov_addr;
    address public usr_addr;
    address public usr2_addr;

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

        testUtil = new TestUtil();
        me = address(this);
        vat = new TestVat();
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

        vat.mint(usr_addr, testUtil.rad(10000));

        // ILK : ETH_A
        vat.ilkSetup(ETH_A); // vat initializes ILK (ETH_A).
        gov_user.initializeIlk(ETH_A); // Gov initializes ILK (ETH_A) in Claimfee as gov is a ward
        
        // ILK : WBTC_A
        vat.ilkSetup(WBTC_A); // Vat initializes ILK (WBTC_A)
        gov_user.initializeIlk(WBTC_A); // gov initialize ILK (WBTC_A) in claimfee as gov is a ward

        vat.increaseRate(ETH_A, testUtil.wad(5), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.05
        cfm.issue(ETH_A, usr_addr, t0, t2, testUtil.wad(750)); // issue cf 750 to cHolder

        vat.increaseRate(WBTC_A, testUtil.wad(5), address(vow));
        cfm.snapshot(WBTC_A); // take a snapshot at t0 @ 1.05
        cfm.issue(WBTC_A, usr_addr, t0, t2, testUtil.wad(5000)); // issue cf 5000 to cHolder
        
    }

    // Fuzz Goal : User transfers claim fee to another user.  The balances are adjusted accordingly.
    function test_moveclaim(address src, address dest, bytes32 class_, uint256 bal) public  {
        
        uint256 srcBalance = cfm.cBal(src,class_);
        uint256 destBalance = cfm.cBal(dest, class_);

        try cfm.moveClaim(src, dest, class_, bal) {
            assert(cfm.cBal(src, class_) == (srcBalance - bal));
            assert(cfm.cBal(dest, class_) == (destBalance + bal));
        } catch Error (string memory errMessage) {
            assert(
                msg.sender != src && testUtil.cmpStr(errMessage, "not-allowed") ||
                cfm.cBal(src, class_) < bal 
            );
        }
    }

    function test_issue(address user, uint256 iss, uint256 mat, uint256 bal) public {

        bytes32 class_iss_mat = keccak256(abi.encodePacked(ETH_A, iss, mat));
        uint256 pBal = cfm.cBal(user, class_iss_mat);
        uint256 pTotalSupply = cfm.totalSupply(class_iss_mat);

        try cfm.issue(ETH_A, user, iss, mat, bal) {

            assert(cfm.cBal(user, class_iss_mat) == pBal + bal);
            assert(cfm.totalSupply(class_iss_mat) == pTotalSupply - bal);

        } catch Error(string memory error_message) {
            assert(
                cfm.latestRateTimestamp(ETH_A) <= iss  && testUtil.cmpStr(error_message, "timestamp/invalid") || 
                block.timestamp > mat && testUtil.cmpStr(error_message,"timestamp/invalid") ||
                cfm.rate(ETH_A, iss) == 0 && testUtil.cmpStr(error_message, "rate/invalid")
            );
        } catch {
            assert(false); // if echidna fails on any other reverts
        }
    }
}