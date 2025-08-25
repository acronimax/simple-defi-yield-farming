// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

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
    DappToken public dappToken;
    LPToken public lpToken;
    uint256 public constant REWARD_PER_BLOCK = 1e18; // Reward per block (total for all users)
    uint256 public totalStakingBalance; // Total tokens staked
    address[] public stakers;
    mapping(address => uint256) public stakingBalance;
    mapping(address => uint256) public checkpoints;
    mapping(address => uint256) public pendingRewards;
    mapping(address => bool) public hasStaked;
    mapping(address => bool) public isStaking;

    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsDistributed(address indexed distributor);

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
    constructor(DappToken _dappToken, LPToken _lpToken) {
        dappToken = _dappToken;
        lpToken = _lpToken;
        owner = msg.sender;
    }

    /**
     * @notice Deposits LP tokens for staking.
     * @param _amount The amount of LP tokens to deposit.
     */
    function deposit(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");

        // Distribute any pending rewards before updating the staking balance
        if (isStaking[msg.sender]) {
            distributeRewards(msg.sender);
        }

        lpToken.transferFrom(msg.sender, address(this), _amount);
        stakingBalance[msg.sender] += _amount;
        totalStakingBalance += _amount;

        if (!hasStaked[msg.sender]) {
            stakers.push(msg.sender);
            hasStaked[msg.sender] = true;
        }

        isStaking[msg.sender] = true;
        checkpoints[msg.sender] = block.number; // Set checkpoint to the current block

        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice Withdraws all staked LP tokens.
     */
    function withdraw() external {
        require(isStaking[msg.sender], "You are not staking");
        uint256 balance = stakingBalance[msg.sender];
        require(balance > 0, "Staking balance must be greater than 0");

        // Calculate and update pending rewards before withdrawal
        distributeRewards(msg.sender);

        totalStakingBalance -= balance;
        stakingBalance[msg.sender] = 0;
        isStaking[msg.sender] = false;

        lpToken.transfer(msg.sender, balance);

        emit Withdraw(msg.sender, balance);
    }

    /**
     * @notice Claims pending rewards.
     */
    function claimRewards() external {
        // Distribute rewards one last time before claiming
        distributeRewards(msg.sender);

        uint256 pendingAmount = pendingRewards[msg.sender];
        require(pendingAmount > 0, "No rewards to claim");

        pendingRewards[msg.sender] = 0;
        dappToken.mint(msg.sender, pendingAmount);

        emit RewardsClaimed(msg.sender, pendingAmount);
    }

    /**
     * @notice Distributes rewards to all staking users. (Owner only)
     */
    function distributeRewardsAll() external onlyOwner {
        for (uint i = 0; i < stakers.length; i++) {
            address user = stakers[i];
            if (isStaking[user]) {
                distributeRewards(user);
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
        if (totalStakingBalance > 0 && block.number > checkpoints[beneficiary]) {
            uint256 blocksPassed = block.number - checkpoints[beneficiary];
            // Calculate reward using precise multiplication and division
            uint256 reward = (REWARD_PER_BLOCK * blocksPassed * stakingBalance[beneficiary]) / totalStakingBalance;
            pendingRewards[beneficiary] += reward;
        }
        // Update the checkpoint to the current block for the next calculation
        checkpoints[beneficiary] = block.number;
    }
}
