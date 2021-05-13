pragma solidity 0.6.6;

import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ClaimMining2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardToClaim; // when deposit or withdraw, update pending reward  to rewartToClaim.
    }

    struct PoolInfo {
        IERC20 lpToken;            // Address of   LP token.
        uint256 allocPoint;         // How many allocation points assigned to this pool. mining token  distribute per block.
        uint256 lastRewardBlock;    // Last block number that mining token distribution occurs.
        uint256 accPerShare;        // Accumulated mining token per share, times 1e12. See below.
    }

    IERC20 public miningToken; // The mining token TOKEN

    uint256 public phase1StartBlockNumber;
    uint256 public phase1EndBlockNumber;
    uint256 public phase2EndBlockNumber;
    uint256 public phase1TokenPerBlock;
    uint256 public phase2TokenPerBlock;

    PoolInfo[] public poolInfo; // Info of each pool.
    mapping(uint256 => mapping(address => UserInfo)) private userInfo; // Info of each user that stakes LP tokens.
    uint256 public totalAllocPoint = 0;  // Total allocation points. Must be the sum of all allocation points in all pools.

    event Claim(address indexed user, uint256 pid, uint256 amount);
    event Deposit(address indexed user, uint256 pid, uint256 amount);
    event Withdraw(address indexed user, uint256 pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 pid, uint256 amount);


    constructor(address _mining_token, uint256 _mining_start_block) public {
        miningToken = IERC20(_mining_token);
        uint256 blockCountPerDay = 6600;
        phase1StartBlockNumber = _mining_start_block;
        phase1EndBlockNumber = phase1StartBlockNumber.add(blockCountPerDay.mul(28));
        phase2EndBlockNumber = phase1EndBlockNumber.add(blockCountPerDay.mul(365));

        phase1TokenPerBlock = 55 * 1e17;
        phase2TokenPerBlock = 13 * 1e17;
    }


    function getUserInfo(uint256 _pid, address _user) public view returns (
        uint256 _amount, uint256 _rewardDebt, uint256 _rewardToClaim) {
        require(_pid < poolInfo.length, "invalid _pid");
        UserInfo memory info = userInfo[_pid][_user];
        _amount = info.amount;
        _rewardDebt = info.rewardDebt;
        _rewardToClaim = info.rewardToClaim;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, address _lpToken,  bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > phase1StartBlockNumber ? block.number : phase1StartBlockNumber;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo(
            {
            lpToken : IERC20(_lpToken),
            allocPoint : _allocPoint,
            lastRewardBlock : lastRewardBlock,
            accPerShare : 0
            })
        );
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        require(_pid < poolInfo.length, "invalid _pid");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function getCurrentRewardsPerBlock() public view returns (uint256) {
        return getMultiplier(block.number - 1, block.number);
    }

    // Return reward  over the given _from to _to block. Suppose it doesn't span two adjacent mining block number
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        require(_to > _from, "_to should greater than  _from ");
        if (_from < phase1StartBlockNumber && phase1StartBlockNumber < _to && _to < phase1EndBlockNumber) {
            return _to.sub(phase1StartBlockNumber).mul(phase1TokenPerBlock);
        }
        if (phase1StartBlockNumber <= _from  && _to <= phase1EndBlockNumber) {
            return _to.sub(_from).mul(phase1TokenPerBlock);
        }

        if (phase1StartBlockNumber < _from  &&  _from < phase1EndBlockNumber && phase1EndBlockNumber <  _to && _to <= phase2EndBlockNumber) {
            return phase1EndBlockNumber.sub(_from).mul(phase1TokenPerBlock).add(_to.sub(phase1EndBlockNumber).mul(phase2TokenPerBlock));
        }

        if (phase1EndBlockNumber < _from  && _to <= phase2EndBlockNumber) {
            return _to.sub(_from).mul(phase2TokenPerBlock);
        }

        if (phase1EndBlockNumber < _from && _from < phase2EndBlockNumber && phase2EndBlockNumber < _to) {
            return phase2EndBlockNumber.sub(_from).mul(phase2TokenPerBlock);
        }
        
        return 0;
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        require(_pid < poolInfo.length, "invalid _pid");
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 reward = multiplier.mul(pool.allocPoint).div(totalAllocPoint);
        pool.accPerShare = pool.accPerShare.add(reward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    function getPendingAmount(uint256 _pid, address _user) public view returns (uint256) {
        require(_pid < poolInfo.length, "invalid _pid");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPerShare = pool.accPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward = multiplier.mul(pool.allocPoint).div(totalAllocPoint);
            accPerShare = accPerShare.add(reward.mul(1e12).div(lpSupply));
        }
        uint256 pending = user.amount.mul(accPerShare).div(1e12).sub(user.rewardDebt);
        uint256 totalPendingAmount = user.rewardToClaim.add(pending);
        return totalPendingAmount;
    }

    function getAllPendingAmount(address _user) external view returns (uint256) {
        uint256 length = poolInfo.length;
        uint256 allAmount = 0;
        for (uint256 pid = 0; pid < length; ++pid) {
            allAmount = allAmount.add(getPendingAmount(pid, _user));
        }
        return allAmount;
    }

    function claimAll() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            if (getPendingAmount(pid, msg.sender) > 0) {
                claim(pid);
            }
        }
    }

    function claim(uint256 _pid) public {
        require(_pid < poolInfo.length, "invalid _pid");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accPerShare).div(1e12).sub(user.rewardDebt);
            user.rewardToClaim = user.rewardToClaim.add(pending);
        }
        user.rewardDebt = user.amount.mul(pool.accPerShare).div(1e12);
        safeMiningTokenTransfer(msg.sender, user.rewardToClaim);
        emit Claim(msg.sender, _pid, user.rewardToClaim);
        user.rewardToClaim = 0;
    }

    // Deposit LP tokens to Mining for token allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant  {
        require(_pid < poolInfo.length, "invalid _pid");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accPerShare).div(1e12).sub(user.rewardDebt);
            user.rewardToClaim = user.rewardToClaim.add(pending);
        }
        if (_amount > 0) {// for gas saving
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            emit Deposit(msg.sender, _pid, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPerShare).div(1e12);
    }

    // Withdraw LP tokens from Mining.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        require(_pid < poolInfo.length, "invalid _pid");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: user.amount is not enough");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accPerShare).div(1e12).sub(user.rewardDebt);
        user.rewardToClaim = user.rewardToClaim.add(pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        require(_pid < poolInfo.length, "invalid _pid");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe token transfer function, just in case if rounding error causes pool to not have enough mining token.
    function safeMiningTokenTransfer(address _to, uint256 _amount) internal {
        uint256 bal = miningToken.balanceOf(address(this));
        require(bal >= _amount, "balance is not enough.");
        miningToken.safeTransfer(_to, _amount);
    }

}
