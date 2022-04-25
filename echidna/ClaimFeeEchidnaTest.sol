// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.1;

import {ClaimFee} from "../src/ClaimFee.sol";
import {Gate1} from "./gate1.sol";

//import {Vat} from "./Vat.sol";

interface Hevm {
    function store(address, bytes32, bytes32) external;
    function load(address, bytes32) external returns (bytes32);
}

contract ClaimFeeEchidnaTest  {

    ClaimFee internal mClaimFee;
    Gate1 internal gate;
    Hevm hevm;
    address internal vow = address(0xfffffff);
    address internal vat = address(0x100);

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

    constructor()  {

     //vat = new Vat();
     gate = new Gate1(vat, vow);
     mClaimFee = new ClaimFee(address(gate));
     hevm = Hevm(address(CHEAT_CODE));

    }
    
    // -- Logical OR --  
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
        assert(z == x || z == y);
    }

    // Fuzz goal : 
    // 1. The balance on src address should always be lesser than his prior balance.
    // 2. The balance on dest address should always be greater than his prior balance.
    function moveClaim(address src, address dest, bytes32 class_, uint256 bal) public {
    
       uint256 srcPrevBalance = mClaimFee.getCBalance(src, class_);
       uint256 destPrevBalance = mClaimFee.getCBalance(dest, class_);

        mClaimFee.moveClaim(src, dest, class_, bal);

        assert(address(mClaimFee).balance == 0);
        assert(mClaimFee.getCBalance(address(0x1), class_) == 0);
        assert(mClaimFee.getCBalance(src, class_) == (srcPrevBalance + bal)); // THIS IS WRONG and should fail
        assert(mClaimFee.getCBalance(dest, class_) == destPrevBalance + bal);
        
    }


}