// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.5;

import "../interfaces/IERC20.sol";
import "../interfaces/IsGUITA.sol";
import "../interfaces/IwsGUITA.sol";
import "../interfaces/IgGUITA.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IStaking.sol";
import "../interfaces/IOwnable.sol";
import "../interfaces/IUniswapV2Router.sol";
import "../interfaces/IStakingV1.sol";
import "../interfaces/ITreasuryV1.sol";

import "../types/GuitaAccessControlled.sol";

import "../libraries/SafeMath.sol";
import "../libraries/SafeERC20.sol";

contract GuitaTokenMigrator is GuitaAccessControlled {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IgGUITA;
    using SafeERC20 for IsGUITA;
    using SafeERC20 for IwsGUITA;

    /* ========== MIGRATION ========== */

    event TimelockStarted(uint256 block, uint256 end);
    event Migrated(address staking, address treasury);
    event Funded(uint256 amount);
    event Defunded(uint256 amount);

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable oldGUITA;
    IsGUITA public immutable oldsGUITA;
    IwsGUITA public immutable oldwsGUITA;
    ITreasuryV1 public immutable oldTreasury;
    IStakingV1 public immutable oldStaking;

    IUniswapV2Router public immutable sushiRouter;
    IUniswapV2Router public immutable uniRouter;

    IgGUITA public gGUITA;
    ITreasury public newTreasury;
    IStaking public newStaking;
    IERC20 public newGUITA;

    bool public guitaMigrated;
    bool public shutdown;

    uint256 public immutable timelockLength;
    uint256 public timelockEnd;

    uint256 public oldSupply;

    constructor(
        address _oldGUITA,
        address _oldsGUITA,
        address _oldTreasury,
        address _oldStaking,
        address _oldwsGUITA,
        address _sushi,
        address _uni,
        uint256 _timelock,
        address _authority
    ) GuitaAccessControlled(IGuitaAuthority(_authority)) {
        require(_oldGUITA != address(0), "Zero address: GUITA");
        oldGUITA = IERC20(_oldGUITA);
        require(_oldsGUITA != address(0), "Zero address: sGUITA");
        oldsGUITA = IsGUITA(_oldsGUITA);
        require(_oldTreasury != address(0), "Zero address: Treasury");
        oldTreasury = ITreasuryV1(_oldTreasury);
        require(_oldStaking != address(0), "Zero address: Staking");
        oldStaking = IStakingV1(_oldStaking);
        require(_oldwsGUITA != address(0), "Zero address: wsGUITA");
        oldwsGUITA = IwsGUITA(_oldwsGUITA);
        require(_sushi != address(0), "Zero address: Sushi");
        sushiRouter = IUniswapV2Router(_sushi);
        require(_uni != address(0), "Zero address: Uni");
        uniRouter = IUniswapV2Router(_uni);
        timelockLength = _timelock;
    }

    /* ========== MIGRATION ========== */

    enum TYPE {
        UNSTAKED,
        STAKED,
        WRAPPED
    }

    // migrate GUITAv1, sGUITAv1, or wsGUITA for GUITAv2, sGUITAv2, or gGUITA
    function migrate(
        uint256 _amount,
        TYPE _from,
        TYPE _to
    ) external {
        require(!shutdown, "Shut down");

        uint256 wAmount = oldwsGUITA.sGUITATowGUITA(_amount);

        if (_from == TYPE.UNSTAKED) {
            require(guitaMigrated, "Only staked until migration");
            oldGUITA.safeTransferFrom(msg.sender, address(this), _amount);
        } else if (_from == TYPE.STAKED) {
            oldsGUITA.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            oldwsGUITA.safeTransferFrom(msg.sender, address(this), _amount);
            wAmount = _amount;
        }

        if (guitaMigrated) {
            require(oldSupply >= oldGUITA.totalSupply(), "GUITAv1 minted");
            _send(wAmount, _to);
        } else {
            gGUITA.mint(msg.sender, wAmount);
        }
    }

    // migrate all Guita tokens held
    function migrateAll(TYPE _to) external {
        require(!shutdown, "Shut down");

        uint256 guitaBal = 0;
        uint256 sGUITABal = oldsGUITA.balanceOf(msg.sender);
        uint256 wsGUITABal = oldwsGUITA.balanceOf(msg.sender);

        if (oldGUITA.balanceOf(msg.sender) > 0 && guitaMigrated) {
            guitaBal = oldGUITA.balanceOf(msg.sender);
            oldGUITA.safeTransferFrom(msg.sender, address(this), guitaBal);
        }
        if (sGUITABal > 0) {
            oldsGUITA.safeTransferFrom(msg.sender, address(this), sGUITABal);
        }
        if (wsGUITABal > 0) {
            oldwsGUITA.safeTransferFrom(msg.sender, address(this), wsGUITABal);
        }

        uint256 wAmount = wsGUITABal.add(oldwsGUITA.sGUITATowGUITA(guitaBal.add(sGUITABal)));
        if (guitaMigrated) {
            require(oldSupply >= oldGUITA.totalSupply(), "GUITAv1 minted");
            _send(wAmount, _to);
        } else {
            gGUITA.mint(msg.sender, wAmount);
        }
    }

    // send preferred token
    function _send(uint256 wAmount, TYPE _to) internal {
        if (_to == TYPE.WRAPPED) {
            gGUITA.safeTransfer(msg.sender, wAmount);
        } else if (_to == TYPE.STAKED) {
            newStaking.unwrap(msg.sender, wAmount);
        } else if (_to == TYPE.UNSTAKED) {
            newStaking.unstake(msg.sender, wAmount, false, false);
        }
    }

    // bridge back to GUITA, sGUITA, or wsGUITA
    function bridgeBack(uint256 _amount, TYPE _to) external {
        if (!guitaMigrated) {
            gGUITA.burn(msg.sender, _amount);
        } else {
            gGUITA.safeTransferFrom(msg.sender, address(this), _amount);
        }

        uint256 amount = oldwsGUITA.wGUITATosGUITA(_amount);
        // error throws if contract does not have enough of type to send
        if (_to == TYPE.UNSTAKED) {
            oldGUITA.safeTransfer(msg.sender, amount);
        } else if (_to == TYPE.STAKED) {
            oldsGUITA.safeTransfer(msg.sender, amount);
        } else if (_to == TYPE.WRAPPED) {
            oldwsGUITA.safeTransfer(msg.sender, _amount);
        }
    }

    /* ========== OWNABLE ========== */

    // halt migrations (but not bridging back)
    function halt() external onlyPolicy {
        require(!guitaMigrated, "Migration has occurred");
        shutdown = !shutdown;
    }

    // withdraw backing of migrated GUITA
    function defund(address reserve) external onlyGovernor {
        require(guitaMigrated, "Migration has not begun");
        require(timelockEnd < block.number && timelockEnd != 0, "Timelock not complete");

        oldwsGUITA.unwrap(oldwsGUITA.balanceOf(address(this)));

        uint256 amountToUnstake = oldsGUITA.balanceOf(address(this));
        oldsGUITA.approve(address(oldStaking), amountToUnstake);
        oldStaking.unstake(amountToUnstake, false);

        uint256 balance = oldGUITA.balanceOf(address(this));

        if (balance > oldSupply) {
            oldSupply = 0;
        } else {
            oldSupply -= balance;
        }

        uint256 amountToWithdraw = balance.mul(1e9);
        oldGUITA.approve(address(oldTreasury), amountToWithdraw);
        oldTreasury.withdraw(amountToWithdraw, reserve);
        IERC20(reserve).safeTransfer(address(newTreasury), IERC20(reserve).balanceOf(address(this)));

        emit Defunded(balance);
    }

    // start timelock to send backing to new treasury
    function startTimelock() external onlyGovernor {
        require(timelockEnd == 0, "Timelock set");
        timelockEnd = block.number.add(timelockLength);

        emit TimelockStarted(block.number, timelockEnd);
    }

    // set gGUITA address
    function setgGUITA(address _gGUITA) external onlyGovernor {
        require(address(gGUITA) == address(0), "Already set");
        require(_gGUITA != address(0), "Zero address: gGUITA");

        gGUITA = IgGUITA(_gGUITA);
    }

    // call internal migrate token function
    function migrateToken(address token) external onlyGovernor {
        _migrateToken(token, false);
    }

    /**
     *   @notice Migrate LP and pair with new GUITA
     */
    function migrateLP(
        address pair,
        bool sushi,
        address token,
        uint256 _minA,
        uint256 _minB
    ) external onlyGovernor {
        uint256 oldLPAmount = IERC20(pair).balanceOf(address(oldTreasury));
        oldTreasury.manage(pair, oldLPAmount);

        IUniswapV2Router router = sushiRouter;
        if (!sushi) {
            router = uniRouter;
        }

        IERC20(pair).approve(address(router), oldLPAmount);
        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            token,
            address(oldGUITA),
            oldLPAmount,
            _minA,
            _minB,
            address(this),
            block.timestamp
        );

        newTreasury.mint(address(this), amountB);

        IERC20(token).approve(address(router), amountA);
        newGUITA.approve(address(router), amountB);

        router.addLiquidity(
            token,
            address(newGUITA),
            amountA,
            amountB,
            amountA,
            amountB,
            address(newTreasury),
            block.timestamp
        );
    }

    // Failsafe function to allow owner to withdraw funds sent directly to contract in case someone sends non-GUITA tokens to the contract
    function withdrawToken(
        address tokenAddress,
        uint256 amount,
        address recipient
    ) external onlyGovernor {
        require(tokenAddress != address(0), "Token address cannot be 0x0");
        require(tokenAddress != address(gGUITA), "Cannot withdraw: gGUITA");
        require(tokenAddress != address(oldGUITA), "Cannot withdraw: old-GUITA");
        require(tokenAddress != address(oldsGUITA), "Cannot withdraw: old-sGUITA");
        require(tokenAddress != address(oldwsGUITA), "Cannot withdraw: old-wsGUITA");
        require(amount > 0, "Withdraw value must be greater than 0");
        if (recipient == address(0)) {
            recipient = msg.sender; // if no address is specified the value will will be withdrawn to Owner
        }

        IERC20 tokenContract = IERC20(tokenAddress);
        uint256 contractBalance = tokenContract.balanceOf(address(this));
        if (amount > contractBalance) {
            amount = contractBalance; // set the withdrawal amount equal to balance within the account.
        }
        // transfer the token from address of this contract
        tokenContract.safeTransfer(recipient, amount);
    }

    // migrate contracts
    function migrateContracts(
        address _newTreasury,
        address _newStaking,
        address _newGUITA,
        address _newsGUITA,
        address _reserve
    ) external onlyGovernor {
        require(!guitaMigrated, "Already migrated");
        guitaMigrated = true;
        shutdown = false;

        require(_newTreasury != address(0), "Zero address: Treasury");
        newTreasury = ITreasury(_newTreasury);
        require(_newStaking != address(0), "Zero address: Staking");
        newStaking = IStaking(_newStaking);
        require(_newGUITA != address(0), "Zero address: GUITA");
        newGUITA = IERC20(_newGUITA);

        oldSupply = oldGUITA.totalSupply(); // log total supply at time of migration

        gGUITA.migrate(_newStaking, _newsGUITA); // change gGUITA minter

        _migrateToken(_reserve, true); // will deposit tokens into new treasury so reserves can be accounted for

        _fund(oldsGUITA.circulatingSupply()); // fund with current staked supply for token migration

        emit Migrated(_newStaking, _newTreasury);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    // fund contract with gGUITA
    function _fund(uint256 _amount) internal {
        newTreasury.mint(address(this), _amount);
        newGUITA.approve(address(newStaking), _amount);
        newStaking.stake(address(this), _amount, false, true); // stake and claim gGUITA

        emit Funded(_amount);
    }

    /**
     *   @notice Migrate token from old treasury to new treasury
     */
    function _migrateToken(address token, bool deposit) internal {
        uint256 balance = IERC20(token).balanceOf(address(oldTreasury));

        uint256 excessReserves = oldTreasury.excessReserves();
        uint256 tokenValue = oldTreasury.valueOf(token, balance);

        if (tokenValue > excessReserves) {
            tokenValue = excessReserves;
            balance = excessReserves * 10**9;
        }

        oldTreasury.manage(token, balance);

        if (deposit) {
            IERC20(token).safeApprove(address(newTreasury), balance);
            newTreasury.deposit(balance, token, tokenValue);
        } else {
            IERC20(token).safeTransfer(address(newTreasury), balance);
        }
    }
}
