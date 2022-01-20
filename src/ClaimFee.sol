/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.0;

interface VatAbstract {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function live() external view returns (uint256);
    function move(address, address, uint256) external;
}

interface GateAbstract {
    function vat() external view returns (address);
    function vow() external view returns (address);
    function suck(address u, address v, uint256 rad) external;
}

contract ClaimFee {
    // --- Auth ---
    mapping (address => uint256) public wards; // Addresses with admin authority
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    function rely(address _usr) external auth { wards[_usr] = 1; emit Rely(_usr); }  // Add admin
    function deny(address _usr) external auth { wards[_usr] = 0; emit Deny(_usr); }  // Remove admin
    modifier auth {
        require(wards[msg.sender] == 1, "gate1/not-authorized");
        _;
    }

    // --- User Approvals ---
    mapping(address => mapping (address => uint256)) public can; // address => approved address => approval status
    event Approval(address indexed sender, address indexed usr, uint256 approval);
    function hope(address usr) external { can[msg.sender][usr] = 1; emit Approval(msg.sender, usr, 1);}
    function nope(address usr) external { can[msg.sender][usr] = 0; emit Approval(msg.sender, usr, 0);}
    function wish(address sender, address usr) internal view returns (bool) {
        return either(sender == usr, can[sender][usr] == 1);
    }

    // --- Deco ---
    address public immutable gate; // gate address
    address public immutable vat; // vat address
    address public immutable vow; // vow address

    mapping(address => mapping(bytes32 => uint256)) public cBal; // user address => class => balance [wad]
    mapping(bytes32 => uint256) public totalSupply; // class => total supply [wad]

    mapping(bytes32 => bool) public initializedIlks; // ilk => initialization status
    mapping(bytes32 => mapping (uint256 => uint256)) public frac; // ilk => timestamp => frac value [wad] ex: 0.85
    mapping(bytes32 => uint256) public latestFracTimestamp; // ilk => latest frac timestamp
    
    mapping (bytes32 => mapping(uint256 => uint256)) public ratio; // ilk => maturity timestamp => balance cashout ratio [wad]
    uint256 public closeTimestamp; // deco close timestamp

    event NewFrac(bytes32 indexed ilk, uint256 indexed time, uint256 frac);
    event MoveClaim(address indexed src, address indexed dst, bytes32 indexed class_, uint256 bal);

    constructor(address gate_) {
        wards[msg.sender] = 1; // set admin

        gate = gate_;
        vat = GateAbstract(gate).vat();
        vow = GateAbstract(gate).vow();

        // initialized to MAX_UINT and updated when this deco instance is closed
        closeTimestamp = MAX_UINT;
    }
    
    // --- Utils ---
    uint256 constant internal MAX_UINT = 2**256 - 1;
    uint256 constant internal WAD = 10 ** 18;

    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = (x * y) / WAD;
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    // --- Close Modifiers ---
    /// Restrict functions to work when deco instance is NOT closed
    modifier untilClose() {
        // current timestamp is before closetimestamp
        require(block.timestamp < closeTimestamp, "closed");
        _;
    }

    /// Restrict functions to work when deco instance is closed
    modifier afterClose() {
        // current timestamp is at or after closetimestamp
        require(block.timestamp >= closeTimestamp, "not-closed");
        _;
    }

    // -- Ilk Management --
    /// Initializes ilk within this deco instance to allow claim fee issuance
    /// @dev ilk initialization cannot be reversed
    /// @param ilk Collateral Type 
    function initializeIlk(bytes32 ilk) public auth {
        require(initializedIlks[ilk] == false, "ilk/initialized");
        require(this.snapshot(ilk) != 0, "ilk/not-initialized"); // check ilk is valid

        initializedIlks[ilk] = true; // add it to list of initializedIlks
    }

    // --- Internal functions ---
    /// Mints claim balance
    /// @param ilk Collateral Type
    /// @param usr User address
    /// @param issuance Issuance timestamp of claim balance
    /// @param maturity Maturity timestamp of claim balance
    /// @param bal Claim balance amount wad
    function mintClaim(
        bytes32 ilk,
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 bal
    ) internal {
        require(initializedIlks[ilk] == true, "ilk/not-initialized");

        // calculate claim class with ilk, issuance, and maturity timestamps
        bytes32 class_ = keccak256(abi.encodePacked(ilk, issuance, maturity));

        cBal[usr][class_] = cBal[usr][class_] + bal;
        emit MoveClaim(address(0), usr, class_, bal);
    }

    /// Burns claim balance
    /// @param ilk Collateral Type
    /// @param usr User address
    /// @param issuance Issuance timestamp of claim balance
    /// @param maturity Maturity timestamp of claim balance
    /// @param bal Claim balance amount wad
    function burnClaim(
        bytes32 ilk,
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 bal
    ) internal {
        // calculate claim class with ilk, issuance, and maturity timestamps
        bytes32 class_ = keccak256(abi.encodePacked(ilk, issuance, maturity));

        require(cBal[usr][class_] >= bal, "cBal/insufficient-balance");

        cBal[usr][class_] = cBal[usr][class_] - bal;
        emit MoveClaim(usr, address(0), class_, bal);
    }

    /// Lock transfers dai balance from user to maker
    /// Vow is used as destination
    /// @param usr User address
    /// @param frac_ Fraction value to apply
    /// @param bal_ Claim balance
    /// @dev user has to approve deco instance within vat
    function lock(
        address usr,
        uint256 frac_,
        uint256 bal_
    ) internal {
        uint256 daiAmt = ((wmul(bal_, frac_) * (10 ** 27)) + WAD); // [wad * ray = rad]
        // add one wad to cover calculation losses
        VatAbstract(vat).move(usr, vow, daiAmt); // transfer dai from user to vow
    }

    /// Unlock transfers dai balance from maker to user
    /// Gate is used as source
    /// @param usr User address
    /// @param frac_ Fraction value to apply
    /// @param bal_ Claim balance
    function unlock(
        address usr,
        uint256 frac_,
        uint256 bal_
    ) internal {
        uint256 daiAmt = (bal_ * frac_) * 10**9; // [rad = ((wad * wad) * 10**9)]
        GateAbstract(gate).suck(vow, usr, daiAmt); // transfer dai from gate to user
    }

    // --- Transfer Functions ---
    /// Transfers user's claim balance
    /// @param src Source address to transfer balance from
    /// @param dst Destination address to transfer balance to
    /// @param class_ Claim balance class
    /// @param bal Claim balance amount to transfer
    /// @dev Can transfer both activated and unactivated (future portion after slice) claim balances
    function moveClaim(
        address src,
        address dst,
        bytes32 class_,
        uint256 bal
    ) external {
        require(wish(src, msg.sender), "not-allowed");
        require(cBal[src][class_] >= bal, "cBal/insufficient-balance");

        cBal[src][class_] = cBal[src][class_] - bal;
        cBal[dst][class_] = cBal[dst][class_] + bal;

        emit MoveClaim(src, dst, class_, bal);
    }

    // --- Frac Functions ---
    /// Snapshots stability fee fraction value of ilk for current timestamp
    /// @param ilk Collateral Type
    /// @return newFracValue Ilk fraction value at current timestamp
    /// @dev Snapshot is not allowed after close
    function snapshot(bytes32 ilk) external untilClose() returns (uint256 newFracValue) {
        require(initializedIlks[ilk] == true, "ilk/not-initialized");

        (, uint256 newRate, , , ) = VatAbstract(vat).ilks(ilk); // retrieve ilk.rate [ray]

        newFracValue = (10 ** 45) / newRate; // [wad = rad / ray]
        frac[ilk][block.timestamp] = newFracValue; // update frac value at current timestamp
        latestFracTimestamp[ilk] = block.timestamp; // update latest frac timestamp available for this ilk

        emit NewFrac(ilk, block.timestamp, newFracValue);
    }

    /// Governance can insert a fraction value at a timestamp
    /// @param ilk Collateral Type
    /// @param tBefore Fraction value timestamp before insert timestamp to compare with
    /// @param t New fraction value timestamp
    /// @param frac_ Fraction value
    /// @dev Can be executed after close but timestamp cannot fall after close timestamp
    /// @dev since all processing for balances after close is handled by ratio
    /// @dev Insert is allowed after close since guardrail prevents adding frac values after ilk latest
    function insert(bytes32 ilk, uint256 tBefore, uint256 t, uint256 frac_) external auth {
        // governance calculates frac value from rate
        // ex: rate: 1.25, frac: 1/1.25 = 0.80
        
        // t is between before and tLatest(latestFracTimestamp of ilk)
        uint256 tLatest = latestFracTimestamp[ilk];
        // also ensures t is not in the future and before block.timestamp
        require(tBefore < t && t < tLatest, "frac/timestamps-not-in-order");
        
        // frac values should be valid
        require(frac_ <= WAD, "frac/above-one"); // should be 1 wad or below
        require(frac[ilk][t] == 0, "frac/overwrite-disabled"); // overwriting frac value disabled
        require(frac[ilk][tBefore] != 0, "frac/tBefore-not-present"); // frac value has to be present at tBefore
        
        // for safety, inserted frac value has to fall somewhere between before and latest frac values
        require(frac[ilk][tBefore] <= frac_ && frac_ <= frac[ilk][tLatest], "frac/invalid");

        // insert frac value at timestamp t
        frac[ilk][t] = frac_;

        emit NewFrac(ilk, t, frac_);
    }

    // --- Claim Functions ---
    /// Issues claim balance
    /// @param ilk Collateral Type
    /// @param usr User address
    /// @param issuance Issuance timestamp
    /// @param maturity Maturity timestamp set for claim balance
    /// @param bal Claim balance issued by governance
    /// @dev Issuance timestamp set to the block.timestamp value
    /// @dev bal amount is in wad
    /// @dev Convenience function available to both capture a snapshot at current timestamp and issue
    /// @dev Issue is not allowed after close
    function issue(
        bytes32 ilk,
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 bal
    ) external auth untilClose() {
        // issuance has to be before or at latest
        // maturity cannot be before latest
        require(
            issuance <= latestFracTimestamp[ilk] && latestFracTimestamp[ilk] <= maturity,
            "timestamp/invalid"
        );
        // frac value should exist at issuance
        require(frac[ilk][issuance] != 0, "frac/invalid");

        // issue claim balance 
        mintClaim(ilk, usr, issuance, maturity, bal);
    }

    /// Withdraws claim balance held by governance before maturity
    /// @dev Governance is allowed to burn the balance it owns
    /// @dev Users cannot withdraw their claim balance
    /// @param ilk Collateral Type
    /// @param usr User address
    /// @param maturity Maturity timestamp of claim balance
    /// @param bal Claim balance amount to burn
    /// @dev With can be used both before or after close
    function withdraw(
        bytes32 ilk,
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 bal
    ) external auth {
        burnClaim(ilk, usr, issuance, maturity, bal);
    }

    // --- Claim Functions ---
    /// Collects yield earned by a claim balance from issuance until collect timestamp
    /// @param ilk Collateral Type
    /// @param usr User address
    /// @param issuance Issuance timestamp
    /// @param maturity Maturity timestamp
    /// @param collect_ Collect timestamp
    /// @param bal Claim balance amount
    /// @dev Yield earned between issuance and maturity can be collected any number of times, not just once after maturity
    /// @dev Collect can be used both before or after close
    function collect(
        bytes32 ilk,
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 collect_,
        uint256 bal
    ) external {
        require(wish(usr, msg.sender), "not-allowed");
        // claims collection on notional amount can only be between issuance and maturity
        require(
            (issuance <= collect_) && (collect_ <= maturity),
            "timestamp/invalid"
        );

        uint256 issuanceFrac = frac[ilk][issuance]; // frac value at issuance timestamp
        uint256 collectFrac = frac[ilk][collect_]; // frac value at collect timestamp

        // issuance frac value cannot be 0
        // sliced claim balances in this situation can use activate to move issuance to timestamp with frac value
        require(issuanceFrac != 0, "frac/invalid");
        require(collectFrac != 0, "frac/invalid"); // collect frac value cannot be 0

        require(issuanceFrac > collectFrac, "frac/no-difference"); // frac difference should be present

        burnClaim(ilk, usr, issuance, maturity, bal); // burn current claim balance
        
        unlock(usr, (issuanceFrac - collectFrac), bal);

        // mint new claim balance for user to collect future yield earned between collect and maturity timestamps
        if (collect_ != maturity) {
            mintClaim(ilk, usr, collect_, maturity, bal);
        }
    }

    /// Rewinds issuance of claim balance back to a past timestamp
    /// @param ilk Collateral Type
    /// @param usr User address
    /// @param issuance Issuance timestamp
    /// @param maturity Maturity timestamp
    /// @param collect_ Collect timestamp
    /// @param bal Claim balance amount
    /// @dev Rewind also transfers dai from user to offset the extra yield loaded
    /// @dev into claim balance by shifting issuance timestamp
    /// @dev Rewind is not allowed after close to stop dai from being sent to vow
    function rewind(
        bytes32 ilk,
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 collect_,
        uint256 bal
    ) external untilClose() {
        require(wish(usr, msg.sender), "not-allowed");
        // collect timestamp needs to be before issuance(rewinding) and maturity after
        require(
            (collect_ <= issuance) && (issuance <= maturity),
            "timestamp/invalid"
        );

        uint256 collectFrac = frac[ilk][collect_]; // frac value at collect timestamp
        uint256 issuanceFrac = frac[ilk][issuance]; // frac value at issuance timestamp

        require(collectFrac != 0, "frac/invalid"); // collect frac value cannot be 0
        require(issuanceFrac != 0, "frac/invalid"); // issuance frac value cannot be 0
        require(collectFrac > issuanceFrac, "frac/no-difference"); // frac difference should be present

        burnClaim(ilk, usr, issuance, maturity, bal); // burn claim balance

        lock(usr, (collectFrac - issuanceFrac), bal);

        // mint new claim balance with issuance set to earlier collect timestamp
        mintClaim(ilk, usr, collect_, maturity, bal);
    }

    // ---  Future Claim Functions ---
    /// Slices one claim balance into two claim balances at a timestamp
    /// @param ilk Collateral Type
    /// @param usr User address
    /// @param t1 Issuance timestamp
    /// @param t2 Slice point timestamp
    /// @param t3 Maturity timestamp
    /// @param bal Claim balance amount
    /// @dev Slice issues two new claim balances, the second part needs to be activated
    /// @dev in the future at a timestamp that has a frac value when slice fails to get one
    /// @dev SLice can be used both before or after close
    function slice(
        bytes32 ilk,
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 bal
    ) external {
        require(wish(usr, msg.sender), "not-allowed");
        require(t1 < t2 && t2 < t3, "timestamp/invalid"); // timestamp t2 needs to be between t1 and t3

        burnClaim(ilk, usr, t1, t3, bal); // burn original claim balance
        mintClaim(ilk, usr, t1, t2, bal); // mint claim balance
        mintClaim(ilk, usr, t2, t3, bal); // mint claim balance to be activated later at t2
    }

    /// Merges two claim balances with contiguous time periods into one claim balance
    /// @param ilk Collateral Type
    /// @param usr User address
    /// @param t1 Issuance timestamp of first
    /// @param t2 Merge timestamp- maturity timestamp of first and issuance timestamp of second
    /// @param t3 Maturity timestamp of second
    /// @param bal Claim balance amount
    /// @dev Merge can be used both before or after close
    function merge(
        bytes32 ilk,
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 bal
    ) external {
        require(wish(usr, msg.sender), "not-allowed");
        require(t1 < t2 && t2 < t3, "timestamp/invalid"); // timestamp t2 needs to be between t1 and t3

        burnClaim(ilk, usr, t1, t2, bal); // burn first claim balance
        burnClaim(ilk, usr, t2, t3, bal); // burn second claim balance
        mintClaim(ilk, usr, t1, t3, bal); // mint whole
    }

    /// Activates a balance whose issuance timestamp does not have a fraction value set
    /// @param ilk Collateral Type
    /// @param usr User address
    /// @param t1 Issuance timestamp without a fraction value
    /// @param t2 Activation timestamp with a fraction value set
    /// @param t3 Maturity timestamp
    /// @param bal Claim balance amount
    /// @dev Yield earnt between issuance and activation becomes uncollectable and is permanently lost
    /// @dev Activate can be used both before or after close
    function activate(
        bytes32 ilk,
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 bal
    ) external {
        require(wish(usr, msg.sender), "not-allowed");
        require(t1 < t2 && t2 < t3, "timestamp/invalid"); // all timestamps are in order

        require(frac[ilk][t1] == 0, "frac/valid"); // frac value should be missing at issuance
        require(frac[ilk][t2] != 0, "frac/invalid"); // valid frac value required to activate

        burnClaim(ilk, usr, t1, t3, bal); // burn inactive claim balance
        mintClaim(ilk, usr, t2, t3, bal); // mint active claim balance
    }

    // --- Close ---
    /// Closes this deco instance
    /// @dev Close timestamp automatically set to the latest fraction value captured when close is executed
    /// @dev Setup close trigger conditions and control based on the requirements of the yield token integration
    function close() external {
        // close conditions need to be met,
        // * maker protocol is shutdown, or
        // * maker governance executes close
        require(wards[msg.sender] == 1 || VatAbstract(vat).live() == 0, "close/conditions-not-met");
        require(closeTimestamp == MAX_UINT, "closed"); // can be closed only once

        closeTimestamp = block.timestamp;
    }

    /// Stores a ratio value
    /// @param ilk Collateral type
    /// @param maturity Maturity timestamp to set ratio for
    /// @param ratio_ Ratio value
    /// @dev Ratio value sets the amount of notional value to be distributed to claim holders
    /// @dev Ex: Ratio of 0.985 means maker will give 0.015 of notional value
    /// @dev back to claim balance holders of this future maturity timestamp
    function calculate(bytes32 ilk, uint256 maturity, uint256 ratio_)
        public
        auth
        afterClose()
    {
        require(ratio_ <= WAD, "ratio/not-fraction"); // needs to be less than or equal to 1
        require(ratio[ilk][maturity] == 0, "ratio/present"); // cannot overwrite existing ratio

        ratio[ilk][maturity] = ratio_;
    }

    /// Exchanges a claim balance with maturity after close timestamp for dai amount
    /// @param ilk Collateral type
    /// @param usr User address
    /// @param maturity Maturity timestamp
    /// @param bal Balance amount
    /// @dev Issuance of claim needs to be at the latest frac timestamp of the ilk, 
    /// @dev which means user has collected all yield earned until latest using collect
    /// @dev Any previously sliced claim balances need to be merged back to their original balance
    /// @dev before cashing out or a portion of their value will be permanently lost
    function cashClaim(
        bytes32 ilk,
        address usr,
        uint256 maturity,
        uint256 bal
    ) external afterClose() {
        require(wish(usr, msg.sender), "not-allowed");
        require(ratio[ilk][maturity] != 0, "ratio/not-set"); // cashout ratio needs to be set
        
        uint256 daiAmt = wmul(bal, (WAD - ratio[ilk][maturity])); // yield token value of notional amount in claim
        GateAbstract(gate).suck(vow, usr, daiAmt); // transfer dai to usr address

        burnClaim(ilk, usr, latestFracTimestamp[ilk], maturity, bal);
    }

    // --- Convenience Functions ---
    /// Calculate and return the class value
    /// @param ilk Collateral Type
    /// @param issuance Issuance timestamp
    /// @param maturity Maturity timestamp
    /// @return class_ Calculated class value
    function getClass(string calldata ilk, uint256 issuance, uint256 maturity) public pure returns (bytes32 class_) {
        class_ = keccak256(abi.encodePacked(bytes32(bytes(ilk)), issuance, maturity));
    }
}
