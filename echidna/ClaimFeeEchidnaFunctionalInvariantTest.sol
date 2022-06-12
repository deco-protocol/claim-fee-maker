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
                cfm.can(msg.sender, src) != 1 && testUtil.cmpStr(errMessage, "not-allowed") ||
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

    function test_initialize(bytes32 ilk) public {

        // Initialize the ilk in VAT
        vat.ilkSetup(ilk);
        vat.increaseRate(ilk, testUtil.wad(5), address(vow));

        try cfm.initializeIlk(ilk) {
            assert(cfm.initializedIlks(ilk) == true);
            assert(cfm.latestRateTimestamp(ilk) == block.timestamp);

        } catch Error(string memory error_message) {
            assert(
                cfm.initializedIlks(ilk) == false && testUtil.cmpStr(error_message, "ilk/initialized") ||
                cfm.wards(msg.sender) == 0 && testUtil.cmpStr(error_message, "gate1/not-authorized")
             );
        } catch {
            assert(false);
        }
    }

    function test_snapshot(bytes32 ilk) public {

        vat.ilkSetup(ilk);
        vat.increaseRate(ilk, testUtil.wad(10), address(vow));
        try cfm.snapshot(ilk) {

            assert(cfm.rate(ilk,block.timestamp) == testUtil.wad(10));
            assert(cfm.latestRateTimestamp(ilk) == block.timestamp);

        } catch Error(string memory error_message) {
            assert(
                cfm.initializedIlks(ilk) == false && testUtil.cmpStr(error_message, "ilk/not-initialized")
            );
        } catch {
            assert(false);
        }

    }

    function test_insert(bytes32 ilk, uint256 tBefore, uint256 tInsert, uint256 rate) public {
         vat.ilkSetup(ilk);
         vat.increaseRate(ilk, testUtil.wad(10), address(vow));
         cfm.initializeIlk(ilk);

        // cfm.rely(sender, usr); // this can be removed
         try cfm.insert(ilk, tBefore, tInsert, rate) {

                assert(cfm.rate(ilk, tInsert) == rate);

         } catch Error(string memory error_message) {
             assert(
                 (tBefore >= tInsert)  && testUtil.cmpStr(error_message, "rate/timestamps-not-in-order") ||
                 (tInsert >= cfm.latestRateTimestamp(ilk)) && testUtil.cmpStr(error_message, "rate/timestamps-not-in-order") ||
                 rate < RAY && testUtil.cmpStr(error_message, "rate/below-one") ||
                 cfm.rate(ilk, tInsert) != 0 && testUtil.cmpStr(error_message, "rate/overwrite-disabled") ||
                 cfm.rate(ilk, tBefore) == 0 && testUtil.cmpStr(error_message, "rate/tBefore-not-present") ||
                 cfm.rate(ilk, tBefore) > rate && testUtil.cmpStr(error_message, "rate/invalid") ||
                 cfm.rate(ilk, cfm.latestRateTimestamp(ilk)) < rate &&   testUtil.cmpStr(error_message, "rate/invalid")
             );
         }catch {
             assert(false);
         }
     }

    function test_collect(bytes32 ilk, address usr_address, uint256 issTS, uint256 matTS, uint256 collectTS, uint256 bal) public {

         vat.ilkSetup(ilk);
         vat.increaseRate(ilk, testUtil.wad(10), address(vow));
         cfm.initializeIlk(ilk);
         // issue ??

        uint256 issRate = cfm.rate(ilk, issTS);
        uint256 collectRate = cfm.rate(ilk, collectTS);

        bytes32 ilkClassIssMat = keccak256(abi.encodePacked(ilk, issTS, matTS)); // iss, mat
        bytes32 ilkClassColMat = keccak256(abi.encodePacked(ilk, collectTS, matTS)); // collect, mat
        uint256 issBalance = cfm.cBal(usr_address, ilkClassIssMat);
        uint256 collectBalance = cfm.cBal(usr_address, ilkClassColMat);

        try cfm.collect(ilk, usr_address, issTS, matTS, collectTS, bal) {

            assert(cfm.cBal(usr_address, ilkClassIssMat) == issBalance - bal);
            if (collectTS != matTS) {
                assert(cfm.cBal(usr_address, ilkClassColMat) == collectBalance + bal);
            }

        } catch Error(string memory error_message) {
            assert(
                msg.sender != usr_address && testUtil.cmpStr(error_message, "not-allowed") ||
                cfm.can(msg.sender, usr_address) != 1 && testUtil.cmpStr(error_message, "not-allowed") ||
                issRate == 0 && testUtil.cmpStr(error_message, "rate/invalid") ||
                collectRate == 0 && testUtil.cmpStr(error_message, "rate/invalid") ||
                issTS > collectTS && testUtil.cmpStr(error_message, "timestamp/invalid") ||
                collectTS > matTS && testUtil.cmpStr(error_message, "timestamp/invalid")
            );
        } catch {
            assert(false);
        }
    }

    function  test_slice(bytes32 ilk, address usr_address, uint256 ts1, uint256 ts2, uint256 ts3, uint256 bal) public {

        bytes32 ilkClass_t1_t3 = keccak256(abi.encodePacked(ilk, ts1, ts3)); // t1, t3
        bytes32 ilkClass_t1_t2 = keccak256(abi.encodePacked(ilk, ts1, ts2)); // t1, t2
        bytes32 ilkClass_t2_t3 = keccak256(abi.encodePacked(ilk, ts2, ts3)); // t2, t3

        uint256  prevBalance_t1_t3 =  cfm.cBal(usr_address, ilkClass_t1_t3);
        uint256  prevBalance_t1_t2 =  cfm.cBal(usr_address, ilkClass_t1_t2);
        uint256  prevBalance_t2_t3 =  cfm.cBal(usr_address, ilkClass_t2_t3);


        try cfm.slice(ilk, usr_address, t1, t2, t3, bal) {

            assert(cfm.cBal(usr_address, ilkClass_t1_t3) == prevBalance_t1_t3 - bal);
            assert(cfm.cBal(usr_address, ilkClass_t1_t2) == prevBalance_t1_t2 + bal);
            assert(cfm.cBal(usr_address, ilkClass_t2_t3) == prevBalance_t2_t3 + bal);

        } catch Error (string memory error_message) {
            assert(
                msg.sender != usr_address && testUtil.cmpStr(error_message, "not-allowed") ||
                cfm.can(msg.sender, usr_address) != 1 && testUtil.cmpStr(error_message, "not-allowed") ||
                t1 >= t2 && testUtil.cmpStr(error_message, "timestamp/invalid") ||
                t2 >= t3 && testUtil.cmpStr(error_message, "timestamp/invalid") ||
                cfm.cBal(usr_address, ilkClass_t1_t3) < bal && testUtil.cmpStr(error_message, "cBal/insufficient-balance")
            );
        } catch {
            assert(false);
        }
    }

    function test_merge(bytes32 ilk, address usr_address, uint256 ts1, uint256 ts2, uint256 ts3, uint256 bal) public {

        bytes32 ilkClass_t1_t3 = keccak256(abi.encodePacked(ilk, ts1, ts3)); // t1, t3
        bytes32 ilkClass_t1_t2 = keccak256(abi.encodePacked(ilk, ts1, ts2)); // t1, t2
        bytes32 ilkClass_t2_t3 = keccak256(abi.encodePacked(ilk, ts2, ts3)); // t2, t3

        uint256  prevBalance_t1_t3 =  cfm.cBal(usr_address, ilkClass_t1_t3);
        uint256  prevBalance_t1_t2 =  cfm.cBal(usr_address, ilkClass_t1_t2);
        uint256  prevBalance_t2_t3 =  cfm.cBal(usr_address, ilkClass_t2_t3);

        try cfm.merge(ilk, usr_address, ts1, ts2, ts3, bal) {

            assert(cfm.cBal(usr_address, ilkClass_t1_t3) == prevBalance_t1_t3 + bal);
            assert(cfm.cBal(usr_address, ilkClass_t1_t2) == prevBalance_t1_t2 - bal);
            assert(cfm.cBal(usr_address, ilkClass_t2_t3) == prevBalance_t2_t3 - bal);

        } catch Error (string memory error_message) {
            assert(
                msg.sender != usr_address && testUtil.cmpStr(error_message, "not-allowed") ||
                cfm.can(msg.sender, usr_address) != 1 && testUtil.cmpStr(error_message, "not-allowed") ||
                t1 >= t2 && testUtil.cmpStr(error_message, "timestamp/invalid") ||
                t2 >= t3 && testUtil.cmpStr(error_message, "timestamp/invalid") ||
                (t1 >= t2 || t2 >= t3) && testUtil.cmpStr(error_message, "timestamp/invalid") ||
                cfm.cBal(usr_address, ilkClass_t1_t2) < bal && testUtil.cmpStr(error_message, "cBal/insufficient-balance") ||
                cfm.cBal(usr_address, ilkClass_t2_t3) < bal && testUtil.cmpStr(error_message, "cBal/insufficient-balance")
            );
        }

    }

    function test_rewind(bytes32 ilk, address usr_address, uint256 issuanceTs, uint256 maturityTs, uint256 rewindTs, uint256 bal) public {

        uint256 rewindRate = cfm.rate(ilk, rewindTs);
        uint256 issuanceRate = cfm.rate(ilk, issuanceTs);

        bytes32 ilkClass_iss_mat = keccak256(abi.encodePacked(ilk, issuanceTs, maturityTs)); // iss, mat
        bytes32 ilkClass_rew_mat = keccak256(abi.encodePacked(ilk, rewindTs, maturityTs)); // rewind, mat

        uint256  prevBalance_iss_mat =  cfm.cBal(usr_address, ilkClass_iss_mat);
        uint256  prevBalance_rew_mat =  cfm.cBal(usr_address, ilkClass_rew_mat);


        try cfm.rewind(ilk, usr_address, issuanceTs, maturityTs, rewindTs, bal) {

            assert(cfm.cBal(usr_address, ilkClass_iss_mat) == prevBalance_iss_mat - bal);
            assert(cfm.cBal(usr_address, ilkClass_rew_mat) == prevBalance_rew_mat + bal);

        } catch Error(string memory error_message) {
            assert(
                msg.sender != usr_address && testUtil.cmpStr(error_message, "not-allowed") ||
                cfm.can(msg.sender, usr_address) != 1 && testUtil.cmpStr(error_message, "not-allowed") ||
                rewindTs > issuanceTs && testUtil.cmpStr(error_message, "timestamp/invalid") ||
                issuanceTs > maturityTs && testUtil.cmpStr(error_message, "timestamp/invalid") ||
                rewindRate == 0 && testUtil.cmpStr(error_message, "rate/invalid") ||
                issuanceRate == 0 && testUtil.cmpStr(error_message, "rate/invalid") ||
                issuanceRate <= rewindRate && testUtil.cmpStr(error_message, "rate/no-difference")
            );
        } catch {
            assert(false);
        }
    }

    function test_activate(bytes32 ilk, address user_address, uint256 ts1, uint256 ts2, uint256 ts3, uint256 bal) public {

        bytes32 ilkClass_t1_t2 = keccak256(abi.encodePacked(ilk, ts1, ts2)); // t1, t2
        bytes32 ilkClass_t2_t3 = keccak256(abi.encodePacked(ilk, ts2, ts3)); // t2, t3

        uint256  prevBalance_t1_t2 =  cfm.cBal(user_address, ilkClass_t1_t2);
        uint256  prevBalance_t2_t3 =  cfm.cBal(user_address, ilkClass_t2_t3);

        try cfm.activate(ilk, user_address, ts1, ts2, ts3, bal) {
            assert(cfm.cBal(user_address, ilkClass_t1_t2) == prevBalance_t1_t2 - bal);
            assert(cfm.cBal(user_address, ilkClass_t2_t3) == prevBalance_t2_t3 + bal);

        } catch Error (string memory error_message) {
            assert(
                ts1 >= ts2 && testUtil.cmpStr(error_message, "timestamp/invalid") ||
                ts2 >= ts3 && testUtil.cmpStr(error_message, "timestamp/invalid") ||
                msg.sender != user_address && testUtil.cmpStr(error_message, "not-allowed") ||
                cfm.can(msg.sender, user_address) != 1 && testUtil.cmpStr(error_message, "not-allowed") ||
                cfm.rate(ilk, ts1) !=0 && testUtil.cmpStr(error_message, "rate/invalid") ||
                cfm.rate(ilk, ts2) == 0 && testUtil.cmpStr(error_message, "timestamp/invalid")
            );
        } catch {
            assert(false);
        }
    }

    function test_withdraw(bytes32 ilk, address user_address, uint256 issuanceTs, uint256 maturityTs, uint256 bal) public {

        bytes32 ilkClass_iss_mat = keccak256(abi.encodePacked(ilk, issuanceTs, maturityTs)); // iss, mat
        uint256 prevBalance = cfm.cBal(user_address, ilkClass_iss_mat);

        try cfm.withdraw(ilk, user_address, issuanceTs, maturityTs, bal) {
            assert(cfm.cBal(user_address, ilkClass_iss_mat) == prevBalance - bal);
        }catch Error (string memory error_message) {
            assert(
                cfm.wards(msg.sender) == 0 && testUtil.cmpStr(error_message, "gate/not-authorized") ||
                cfm.cBal(user_address, ilkClass_iss_mat) < bal && testUtil.cmpStr(error_message, "cBal/insufficient-balance")
            );
        } catch {
            assert(false);
        }
    }

    function rely(address usr_address) public {
        try cfm.rely(usr_address) {
            assert(cfm.wards(usr_address) == 1);
        } catch Error(string memory error_message) {
            assert(false);
        }
    }

}