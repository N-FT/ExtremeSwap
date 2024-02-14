//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import '@openzeppelin/contracts/access/Ownable.sol';
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import '@openzeppelin/contracts/utils/math/SafeMath.sol';
// import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./AdminRole.sol";

interface IVAULT {
    function sendUSDT(address, uint256 amount) external;
}

// 合约地址 0x89EFEddC20cFB57270561646eED54BE79903c456
contract NPOOL is AdminRole, Initializable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    address public relation;
    address public trade;

    bool public pause;
    bool public recordOpen;

    address public burnAddress;
    address public fundAddress;
    address public USDT;
    bool public valueOpen;
    uint256 public checkTime;
    uint256 public startTime;
    uint256 public dayID;
    uint256 public stepPrice;
    uint256 public lastPrice;
    uint256 public dailyLimit;

    mapping(uint256 => uint256) public price;
    mapping(uint256 => uint256) public sellAmount;
    mapping(uint256 => uint256) public buyAmount;
    mapping(address => uint256) public points;
    mapping(address => uint256) public pointsClaimed;
    mapping(address => uint256) public toClaimReward;
    mapping(address => uint256) public rewardRate;
    mapping(address => uint256) public periodFinish;
    mapping(address => uint256) public claimTime;
    mapping(address => uint256) public claimedReward;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public rewardPerTokenStored;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public totalReward;
    uint256 public rewardPeriod;
    mapping(address => uint256) public vesttime;

    // constructor(uint256 startTime_){
    //     price[0] = 10**18;
    //     price[1] = 10**18;
    // startTime = startTime_;
    // checkTime = startTime_;
    // }

    function initialize() public initializer {
        _addAdmin(msg.sender);
        _addAdmin(0x52F105844eAa2Fb82c5A6fa28A575061c3Bc0943);

        price[0] = 10 ** 18;
        price[1] = 10 ** 18;
        // startTime = startTime_;
        // checkTime = startTime_;

        pause = true;
        recordOpen = true;
        burnAddress = 0x000000000000000000000000000000000000dEaD;
        fundAddress = 0x1Baeeb4132477f360eC65D92EaedFE4a33894011;
        USDT = 0x55d398326f99059fF775485246999027B3197955;
        stepPrice = 10 ** 16;
        dayID = 1;
        lastPrice = 10 ** 18;
        dailyLimit = 3000 * 10 ** 18;
        rewardPeriod = 100 * 86400;
    }

    modifier checkStart() {
        require(block.timestamp > startTime, "NOT START");
        _;
    }

    function addReward(
        address addr,
        uint256 reward
    ) public onlyAdmin updateReward(addr) {
        totalReward[addr] += reward;
        if (block.timestamp > vesttime[addr]) {
            if (block.timestamp >= periodFinish[addr]) {
                rewardRate[addr] = reward.div(rewardPeriod);
            } else {
                uint256 remaining = periodFinish[addr].sub(block.timestamp);
                uint256 leftover = remaining.mul(rewardRate[addr]);
                rewardRate[addr] = reward.add(leftover).div(rewardPeriod);
            }
            lastUpdateTime[addr] = block.timestamp;
            periodFinish[addr] = block.timestamp.add(rewardPeriod);
            emit RewardAdded(addr, reward);
        } else {
            rewardRate[addr] = reward.div(rewardPeriod);
            lastUpdateTime[addr] = vesttime[addr];
            periodFinish[addr] = vesttime[addr].add(rewardPeriod);
            emit RewardAdded(addr, reward);
        }
    }

    event RewardAdded(address addr, uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);

    modifier updateReward(address account) {
        rewardPerTokenStored[account] = rewardPerToken(account);
        lastUpdateTime[account] = lastTimeRewardApplicable(account);
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored[account];
        }
        _;
    }

    function lastTimeRewardApplicable(
        address account
    ) public view returns (uint256) {
        return MathUpgradeable.min(block.timestamp, periodFinish[account]);
    }

    function rewardPerToken(address account) public view returns (uint256) {
        return
            rewardPerTokenStored[account].add(
                lastTimeRewardApplicable(account)
                    .sub(lastUpdateTime[account])
                    .mul(rewardRate[account])
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            rewardPerToken(account).sub(userRewardPerTokenPaid[account]).add(
                rewards[account]
            );
    }

    function claim() public updateReward(msg.sender) checkStart checkDayID {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            claimedReward[msg.sender] += reward;
            uint256 point = 0;
            if (valueOpen) {
                point = (reward * 10 ** 18) / price[dayID - 1];
            } else {
                point = reward;
            }
            points[msg.sender] += point;
            pointsClaimed[msg.sender] += point;
            emit RewardPaid(msg.sender, reward);
        }
    }

    modifier checkDayID() {
        if (block.timestamp > checkTime + 86400) {
            price[dayID] = lastPrice;
            dayID++;
            checkTime += 86400;
        }
        _;
    }

    function buyPoints(uint256 amount) external checkDayID {
        require(buyAmount[dayID] + amount <= dailyLimit + sellAmount[dayID]);
        lastPrice = viewBuyPrice(amount);
        uint256 usdtAmount = (lastPrice * amount) / 10 ** 18;
        IERC20Upgradeable(USDT).transferFrom(
            msg.sender,
            fundAddress,
            usdtAmount
        );
        points[msg.sender] += amount;
        buyAmount[dayID] += amount;
    }

    function sellPoints(uint256 amount) external checkDayID {
        require(sellAmount[dayID] + amount <= dailyLimit + buyAmount[dayID]);
        require(points[msg.sender] >= amount);
        lastPrice = viewSellPrice(amount);
        uint256 usdtAmount = (lastPrice * amount) / 10 ** 18;
        IVAULT(fundAddress).sendUSDT(msg.sender, usdtAmount);
        points[msg.sender] -= amount;
        sellAmount[dayID] += amount;
    }

    function viewBuyPrice(uint256 amount) public view returns(uint256){
        require(buyAmount[dayID] + amount<= dailyLimit + sellAmount[dayID]);
        if(buyAmount[dayID] + amount > dailyLimit *2/3 + sellAmount[dayID]){
            return price[dayID - 1] + stepPrice*2;
        }
        else if(buyAmount[dayID] + amount > dailyLimit *1/3 + sellAmount[dayID]){
            return price[dayID - 1] + stepPrice;
        }

        else if(buyAmount[dayID] + amount > sellAmount[dayID]){
            return price[dayID - 1];
        }else if(sellAmount[dayID] > dailyLimit *1/3){
            if(buyAmount[dayID] + amount < sellAmount[dayID] - dailyLimit *1/3){
            return price[dayID - 1] - stepPrice;
        }
        }else if(sellAmount[dayID] > dailyLimit *2/3){
            if(buyAmount[dayID] + amount < sellAmount[dayID] - dailyLimit *2/3){
            return price[dayID - 1] - stepPrice * 2;
        }
        }
        return price[dayID - 1];
    }





    function viewSellPrice(uint256 amount) public view returns(uint256){
        require(sellAmount[dayID] + amount<= dailyLimit + buyAmount[dayID]);
        if(sellAmount[dayID] + amount > dailyLimit *2/3 + buyAmount[dayID]){
            return price[dayID - 1] - stepPrice*2;
        }

        else if(sellAmount[dayID] + amount > dailyLimit *1/3 + buyAmount[dayID]){
            return price[dayID - 1] - stepPrice;
        }

        else if(sellAmount[dayID] + amount > buyAmount[dayID]){
            return price[dayID - 1];
        }

        else if(sellAmount[dayID] + amount < buyAmount[dayID] - dailyLimit *1/3 &&buyAmount[dayID] > dailyLimit *1/3){
            return price[dayID - 1] + stepPrice;
        }
        else if(sellAmount[dayID] + amount < buyAmount[dayID] - dailyLimit *2/3 &&buyAmount[dayID] > dailyLimit *2/3){
            return price[dayID - 1] + stepPrice * 2;
        }
        else return price[dayID - 1];
    }

     function costPoints(address addr,uint256 usdtAmount) external checkDayID onlyAdmin{
        uint256 amount = usdtAmount * 10**18/ price[dayID -1];
        if(points[addr] >= amount){
        points[addr] -= amount;
        }
        else{
        IERC20Upgradeable(USDT).transferFrom(msg.sender,fundAddress,usdtAmount);
        }
    }


    function Migrate(
        address token,
        address to,
        uint256 amount
    ) external onlyAdmin {
        IERC20Upgradeable(token).safeTransfer(to, amount);
    }

    function setFund(address addr) external onlyAdmin {
        fundAddress = addr;
    }

    function setDailyLimit(uint256 amount) external onlyAdmin {
        dailyLimit = amount;
    }

    function setStepPrice(uint256 amount) external onlyAdmin {
        stepPrice = amount;
    }

    function setValueOpen(bool value) external onlyAdmin {
        valueOpen = value;
    }

    function setStartTime(uint256 startTime_) external onlyAdmin {
        startTime = startTime_;
        checkTime = startTime_;
    }

    function transferPoints(address addr, uint256 pAmount) external checkDayID {
        require(points[msg.sender] >= pAmount, "NOT ENOUGH BALANCE");
        points[msg.sender] -= pAmount;
        points[addr] += (pAmount * 95) / 100;
    }
}
