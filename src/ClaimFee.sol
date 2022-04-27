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
    function draw(address dst_, uint256 amount_) external;
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
    address public gate; // gate address
    address public immutable vat; // vat address

    mapping(address => mapping(bytes32 => uint256)) public cBal; // user address => class => balance [wad]
    mapping(bytes32 => uint256) public totalSupply; // class => total supply [wad]

    mapping(bytes32 => bool) public initializedIlks; // ilk => initialization status
    mapping(bytes32 => mapping (uint256 => uint256)) public rate; // ilk => timestamp => rate value [ray] ex: 1.05
    mapping(bytes32 => uint256) public latestRateTimestamp; // ilk => latest rate timestamp
    
    mapping (bytes32 => mapping(uint256 => uint256)) public ratio; // ilk => maturity timestamp => balance cashout ratio [wad]
    uint256 public closeTimestamp; // deco close timestamp

    event File(bytes32 indexed what, address data);
    event NewRate(bytes32 indexed ilk, uint256 indexed time, uint256 rate);
    event MoveClaim(address indexed src, address indexed dst, bytes32 indexed class_, uint256 bal);
    event Closed(uint256 timestamp, uint256 vatLive);
    event NewRatio(bytes32 indexed ilk, uint256 indexed maturity, uint256 ratio_);

    constructor(address gate_) {
        wards[msg.sender] = 1; // set admin
        emit Rely(msg.sender);

        gate = gate_;
        vat = GateAbstract(gate).vat();

        // initialized to max uint and updated when this deco instance is closed
        closeTimestamp = type(uint256).max;
    }
    
    // --- Utils ---
    uint256 constant internal WAD = 10 ** 18;
    uint256 constant internal RAY = 10 ** 27;

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    /// Update Gate address
    /// @dev Restricted to authorized governance addresses
    /// @param what what value are we updating
    /// @param data what are we updating it to
    function file(bytes32 what, address data) external auth {
        if (what == "gate") {
            require(vat == GateAbstract(data).vat(), "vat-does-not-match");
            gate = data; // update approved total amount

            emit File(what, data);
        } else revert("cfm/file-not-recognized");
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
        (, uint256 ilkRate, , , ) = VatAbstract(vat).ilks(ilk);
        require(ilkRate != 0, "ilk/not-initialized"); // check ilk is valid

        initializedIlks[ilk] = true; // add it to list of initializedIlks
        this.snapshot(ilk); // take a snapshot
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
        totalSupply[class_] = totalSupply[class_] + bal;
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
        totalSupply[class_] = totalSupply[class_] - bal;
        emit MoveClaim(usr, address(0), class_, bal);
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

    // --- Rate Functions ---
    /// Snapshots ilk rate value at current timestamp
    /// @param ilk Collateral Type
    /// @return ilkRate Ilk rate value at current timestamp
    /// @dev Snapshot is not allowed after close
    function snapshot(bytes32 ilk) external untilClose() returns (uint256 ilkRate) {
        require(initializedIlks[ilk] == true, "ilk/not-initialized");

        (, ilkRate, , , ) = VatAbstract(vat).ilks(ilk); // retrieve ilk.rate [ray]

        rate[ilk][block.timestamp] = ilkRate; // update rate value at current timestamp
        latestRateTimestamp[ilk] = block.timestamp; // update latest rate timestamp available for this ilk

        emit NewRate(ilk, block.timestamp, ilkRate);
    }

    /// Governance can insert a rate value at a timestamp
    /// @param ilk Collateral Type
    /// @param tBefore Rate value timestamp before insert timestamp to compare with as a guardrail
    /// @param t New rate value timestamp to insert at
    /// @param rate_ Rate value to insert at t
    /// @dev Can be executed after close but timestamp cannot fall after close timestamp
    /// @dev since all processing for balances after close is handled by ratio
    /// @dev Insert is allowed after close since guardrail prevents adding rate values after ilk latest
    function insert(bytes32 ilk, uint256 tBefore, uint256 t, uint256 rate_) external auth {
        // t is between before and tLatest(latestRateTimestamp of ilk)
        uint256 tLatest = latestRateTimestamp[ilk];
        // also ensures t is before block.timestamp and not in the future
        require(tBefore < t && t < tLatest, "rate/timestamps-not-in-order");
        
        // rate values should be valid
        require(rate_ >= RAY, "rate/below-one"); // should be 1 ray or above
        require(rate[ilk][t] == 0, "rate/overwrite-disabled"); // overwriting rate value disabled
        require(rate[ilk][tBefore] != 0, "rate/tBefore-not-present"); // rate value has to be present at tBefore
        
        // for safety, inserted rate value has to fall somewhere between before and latest rate values
        require(rate[ilk][tBefore] <= rate_ && rate_ <= rate[ilk][tLatest], "rate/invalid");

        // insert rate value at timestamp t
        rate[ilk][t] = rate_;

        emit NewRate(ilk, t, rate_);
    }

    // --- Claim Functions ---
    /// Issues claim balance
    /// @param ilk Collateral Type
    /// @param usr User address
    /// @param issuance Issuance timestamp
    /// @param maturity Maturity timestamp set for claim balance
    /// @param bal Claim balance issued by governance
    /// @dev bal amount is in wad
    /// @dev Issue is not allowed after close
    /// @dev usr address will likely be controlled by governance
    /// @dev various methods can be used to distribute claim fee balance from usr to vault owners
    function issue(
        bytes32 ilk,
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 bal
    ) external auth untilClose() {
        // issuance has to be before or at latest
        // maturity cannot be before current block timestamp
        require(
            issuance <= latestRateTimestamp[ilk] && block.timestamp <= maturity,
            "timestamp/invalid"
        );
        // rate value should exist at issuance
        require(rate[ilk][issuance] != 0, "rate/invalid");

        // issue claim balance 
        mintClaim(ilk, usr, issuance, maturity, bal);
    }

    /// Withdraws claim balance held by governance before maturity
    /// @dev Governance is allowed to burn the balance it owns
    /// @dev Users cannot withdraw their claim balance, can only execute collect
    /// @param ilk Collateral Type
    /// @param maturity Maturity timestamp of claim balance
    /// @param bal Claim balance amount to burn
    /// @dev With can be used both before or after close
    function withdraw(
        bytes32 ilk,
        uint256 issuance,
        uint256 maturity,
        uint256 bal
    ) external auth {
        burnClaim(ilk, msg.sender, issuance, maturity, bal);
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
    /// @dev Gate is used as source to transfer dai to user
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

        uint256 issuanceRate = rate[ilk][issuance]; // rate value at issuance timestamp
        uint256 collectRate = rate[ilk][collect_]; // rate value at collect timestamp

        // issuance rate value should not be 0
        // sliced claim balances without issuance rate values 
        // can use activate to move issuance to timestamp with rate value
        require(issuanceRate != 0, "rate/invalid");
        require(collectRate != 0, "rate/invalid"); // collect rate value cannot be 0

        burnClaim(ilk, usr, issuance, maturity, bal); // burn current claim balance
        
        uint256 daiAmt = bal * (((collectRate * RAY)/issuanceRate) - RAY); // [wad * ray = rad]
        GateAbstract(gate).draw(usr, daiAmt); // transfer dai from gate to user

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
    /// @param rewind_ Rewind timestamp
    /// @param bal Claim balance amount
    /// @dev Rewind transfers dai from user to offset the extra yield loaded
    /// @dev into claim balance by shifting issuance timestamp
    /// @dev Rewind is not allowed after close to stop dai from being sent to vow
    /// @dev Vow is used as destination for dai transfer from user
    /// @dev User has to approve deco instance within vat for rewind to suceed
    function rewind(
        bytes32 ilk,
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 rewind_,
        uint256 bal
    ) external untilClose() {
        require(wish(usr, msg.sender), "not-allowed");
        // rewind timestamp needs to be before issuance(rewinding) and maturity after
        require(
            (rewind_ <= issuance) && (issuance <= maturity),
            "timestamp/invalid"
        );

        uint256 rewindRate = rate[ilk][rewind_]; // rate value at rewind timestamp
        uint256 issuanceRate = rate[ilk][issuance]; // rate value at issuance timestamp

        require(rewindRate != 0, "rate/invalid"); // rewind rate value cannot be 0
        require(issuanceRate != 0, "rate/invalid"); // issuance rate value cannot be 0
        require(issuanceRate > rewindRate, "rate/no-difference"); // rate difference should be present

        burnClaim(ilk, usr, issuance, maturity, bal); // burn claim balance

        uint256 daiAmt = bal * (((issuanceRate * RAY)/rewindRate) - RAY); // [wad * ray = rad]
        address vow_ = GateAbstract(gate).vow();
        VatAbstract(vat).move(usr, vow_, daiAmt); // transfer dai from user to vow

        // mint new claim balance with issuance set to earlier rewind timestamp
        mintClaim(ilk, usr, rewind_, maturity, bal);
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
    /// @dev in the future at a timestamp that has a rate value when slice fails to get one
    /// @dev Slice can be used both before or after close
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

    /// Activates a balance whose issuance timestamp does not have a rate value set
    /// @param ilk Collateral Type
    /// @param usr User address
    /// @param t1 Issuance timestamp without a rate value
    /// @param t2 Activation timestamp with a rate value set
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

        require(rate[ilk][t1] == 0, "rate/valid"); // rate value should be missing at issuance
        require(rate[ilk][t2] != 0, "rate/invalid"); // valid rate value required to activate

        burnClaim(ilk, usr, t1, t3, bal); // burn inactive claim balance
        mintClaim(ilk, usr, t2, t3, bal); // mint active claim balance
    }

    // --- Close ---
    /// Closes this deco instance
    /// @dev Close timestamp set to current block.timestamp
    /// @dev Respective last rate values recorded for each ilk are used 
    /// @dev as apppropriate for settlement before and after close
    /// @dev Setup close trigger conditions and control based on the requirements of the yield token integration
    function close() external {
        // close conditions need to be met,
        // * maker protocol is shutdown, or
        // * maker governance executes close
        require(wards[msg.sender] == 1 || VatAbstract(vat).live() == 0, "close/conditions-not-met");
        require(closeTimestamp == type(uint256).max, "closed"); // can be closed only once

        closeTimestamp = block.timestamp;

        // close timestamp, and vat.live status at close
        emit Closed(block.timestamp, VatAbstract(vat).live());
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
        require(ratio_ <= WAD, "ratio/not-valid"); // needs to be less than or equal to 1
        require(ratio[ilk][maturity] == 0, "ratio/present"); // cannot overwrite existing ratio

        ratio[ilk][maturity] = ratio_;

        emit NewRatio(ilk, maturity, ratio_);
    }

    /// Exchanges a claim balance with maturity after close timestamp for dai amount
    /// @param ilk Collateral type
    /// @param usr User address
    /// @param maturity Maturity timestamp
    /// @param bal Balance amount
    /// @dev Issuance of claim needs to be at the latest rate timestamp of the ilk, 
    /// @dev which means user has collected all yield earned until latest using collect
    /// @dev Any previously sliced claim balances need to be merged back to their original balance
    /// @dev before cashing out or their entire value(or a portion) could be permanently lost
    function cashClaim(
        bytes32 ilk,
        address usr,
        uint256 maturity,
        uint256 bal
    ) external afterClose() {
        require(wish(usr, msg.sender), "not-allowed");
        require(ratio[ilk][maturity] != 0, "ratio/not-set"); // cashout ratio needs to be set
        
        // value of claim fee notional amount
        uint256 daiAmt = (bal * (WAD - ratio[ilk][maturity])) * (10**9); // [rad]
        GateAbstract(gate).draw(usr, daiAmt); // transfer dai to usr address

        burnClaim(ilk, usr, latestRateTimestamp[ilk], maturity, bal);
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
