// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./DappToken.sol";
import "./LPToken.sol";

/**
 * @title Proportional Token Farm
 * @notice A staking farm where rewards are distributed proportionally to the total amount staked.
 */
contract TokenFarm {
    //
    // State Variables
    //
    string public name = "Proportional Token Farm";
    address public owner;
    DAppToken public dappToken;
    LPToken public lpToken;
    uint256 public constant REWARD_PER_BLOCK = 1e18; // Reward per block (total for all users)
    uint256 public totalStakingBalance; // Total tokens staked
    address[] public stakers;

    // --- Variable Reward Rate ---
    uint256 public rewardPerBlock;
    uint256 public minRewardPerBlock;
    uint256 public maxRewardPerBlock;
    // ----------------------------

    mapping(address => uint256) public stakingBalance;
    mapping(address => uint256) public checkpoints;
    mapping(address => uint256) public pendingRewards;
    mapping(address => bool) public hasStaked;
    mapping(address => bool) public isStaking;

    /**
     * @notice Holds all data related to a single staker.
     */
    struct Staker {
        uint256 stakingBalance;
        uint256 checkpoint;
        uint256 pendingRewards;
        bool hasStaked;
        bool isStaking;
    }
    mapping(address => Staker) public stakersInfo;

    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsDistributed(address indexed distributor);
    event RewardRateChanged(uint256 oldRate, uint256 newRate);

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    /**
     * @dev Throws if called by an account that is not currently staking.
     */
    modifier isStaker() {
        require(isStaking[msg.sender], "You are not currently staking");
        _;
    }

    /**
     * @notice Sets up the contract with token addresses and the owner.
     * @param _dappToken The address of the DappToken contract.
     * @param _lpToken The address of the LPToken contract.
     */
    constructor(
        DAppToken _dappToken,
        LPToken _lpToken,
        uint256 _initialReward,
        uint256 _minReward,
        uint256 _maxReward
    ) {
        require(_minReward <= _initialReward && _initialReward <= _maxReward, "Initial reward is out of range");
        dappToken = _dappToken;
        lpToken = _lpToken;
        owner = msg.sender;
        rewardPerBlock = _initialReward;
        minRewardPerBlock = _minReward;
        maxRewardPerBlock = _maxReward;
    }

    /**
     * @notice Allows the owner to update the reward rate per block.
     * @param _newRate The new reward rate to be set.
     */
    function setRewardPerBlock(uint256 _newRate) external onlyOwner {
        require(
            _newRate >= minRewardPerBlock && _newRate <= maxRewardPerBlock,
            "New rate is outside the allowed range"
        );
        uint256 oldRate = rewardPerBlock;
        rewardPerBlock = _newRate;
        emit RewardRateChanged(oldRate, _newRate);
    }

    /**
     * @notice Deposits LP tokens for staking.
     * @param _amount The amount of LP tokens to deposit.
     */
    function deposit(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");
        Staker storage user = stakersInfo[msg.sender];

        // Distribute any pending rewards before updating the staking balance
        if (user.isStaking) {
            distributeRewards(msg.sender);
        }

        lpToken.transferFrom(msg.sender, address(this), _amount);
        user.stakingBalance += _amount;
        totalStakingBalance += _amount;

        if (!user.hasStaked) {
            stakers.push(msg.sender);
            user.hasStaked = true;
        }

        user.isStaking = true;
        user.checkpoint = block.number;
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice Withdraws all staked LP tokens.
     */
    function withdraw() external {
        Staker storage user = stakersInfo[msg.sender];
        uint256 balance = user.stakingBalance;

        require(balance > 0, "Staking balance must be greater than 0");
        distributeRewards(msg.sender);

        totalStakingBalance -= balance;
        user.stakingBalance = 0;
        user.isStaking = false;

        lpToken.transfer(msg.sender, balance);
        emit Withdraw(msg.sender, balance);
    }

    /**
     * @notice Claims pending rewards.
     */
    function claimRewards() external {
        // Distribute rewards one last time before claiming
        distributeRewards(msg.sender);

        Staker storage user = stakersInfo[msg.sender];
        uint256 pendingAmount = user.pendingRewards;
        require(pendingAmount > 0, "No rewards to claim");

        user.pendingRewards = 0;
        dappToken.mint(msg.sender, pendingAmount);
        emit RewardsClaimed(msg.sender, pendingAmount);
    }

    /**
     * @notice Distributes rewards to all staking users. (Owner only)
     */
    function distributeRewardsAll() external onlyOwner {
        for (uint i = 0; i < stakers.length; i++) {
            address userAddress = stakers[i];
            if (stakersInfo[userAddress].isStaking) {
                distributeRewards(userAddress);
            }
        }
        emit RewardsDistributed(msg.sender);
    }

    /**
     * @notice Calculates and distributes rewards proportionally to the total staking.
     * @dev This function calculates the rewards based on the user's share of the total staked amount
     * since their last checkpoint.
     */
    function distributeRewards(address beneficiary) private {
        Staker storage user = stakersInfo[beneficiary];
        if (totalStakingBalance > 0 && block.number > user.checkpoint) {
            // Calculate reward using precise multiplication and division
            uint256 blocksPassed = block.number - user.checkpoint;
            // The calculation now uses the state variable instead of the constant
            uint256 reward = (rewardPerBlock * blocksPassed * user.stakingBalance) / totalStakingBalance;
            user.pendingRewards += reward;
        }
        // Update the checkpoint to the current block for the next calculation
        user.checkpoint = block.number;
    }
}
