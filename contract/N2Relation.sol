//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import '@openzeppelin/contracts/access/Ownable.sol';
// import "@openzeppelin/contracts/utils/math/Math.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "./AdminRole.sol";


interface IVAULT{
    function sendUSDT(address,uint256 amount) external;
}

interface IPOOL {
    function addReward(address addr,uint256 amount) external;
}

// 合约地址：0xe38853E29b3CBEAc44Ffa16A487A5031665B8659
contract N2Relation is AdminRole, Initializable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    address public pool;
    address public USDT;
    address public _burnAddress;
    address public fundAddress;
    uint256 public dayID;
    uint256 public checkTime;
    mapping(address => address) public Inviter;
    mapping(address => uint256) public bindLv;
    mapping(address => bool) public invStats;
    mapping(address => uint256) public vip;
    mapping(address => uint256) public mLv;
    mapping(uint256 => uint256) public rackback;
    mapping(uint256 => uint256) public mPrice;
    mapping(address => uint256) public USDTRewardClaimed;
    mapping(address => uint256) public USDTReward;
    mapping(address => address[]) public invList;

    mapping(address =>mapping(uint256 => uint256)) public teamResult;
    
    mapping(address =>mapping(uint256 => bool)) public claimStats;
    mapping(address => uint256) public claimedTeamReward;
    mapping(address =>mapping(uint256 => uint256)) public promoteResult;

    EnumerableSetUpgradeable.AddressSet private userList;
    
    uint256 public rewardAdjust;



    function initialize() public initializer { 
        pool = 0x89EFEddC20cFB57270561646eED54BE79903c456;
        invStats[0x52F105844eAa2Fb82c5A6fa28A575061c3Bc0943] = true;
        bindLv[0x52F105844eAa2Fb82c5A6fa28A575061c3Bc0943] =1;
        rackback[1] = 6;
        rackback[2] = 8;
        rackback[3] = 10;
        rackback[4] = 15;
        mPrice[1] = 50 * 10**18;
        mPrice[2] = 200 * 10**18;
        mPrice[3] = 1000 * 10**18;
        mPrice[4] = 10000 * 10**18;

        _addAdmin(msg.sender);
        _addAdmin(0x52F105844eAa2Fb82c5A6fa28A575061c3Bc0943);

        USDT = 0x55d398326f99059fF775485246999027B3197955;
        _burnAddress = 0x000000000000000000000000000000000000dEaD;
        fundAddress = 0x1Baeeb4132477f360eC65D92EaedFE4a33894011;
    }

  modifier checkDayID() {
    if(block.timestamp > checkTime + 86400){
      dayID += 1;
      checkTime += 86400;
    }
    _;
  }


    function bind(address addr) 
    public checkDayID
    {
        require(!invStats[msg.sender],"BIND ERROR: ONCE BIND");
        require(invStats[addr],"BIND ERROR: INVITER NOT BIND");
        _bind(addr,msg.sender);
    }

    event BINDED(address inv,address newuser, uint256 bindTimestamp);

    function _bind(address addr,address newaddr) 
    internal 
    {
        if (!userList.contains(addr)) 
        {
            userList.add(addr);
        }
        Inviter[newaddr] = addr;
        invList[addr].push(newaddr);
        invStats[newaddr]= true;
        bindLv[newaddr] = bindLv[addr] +1 ;
        emit BINDED(addr,newaddr,block.timestamp);
    }


     function BatchBind(address[] memory addrs, address[] memory invs) external onlyAdmin{
        for(uint256 i = 0; i < addrs.length; i++ ){
        if (!userList.contains(addrs[i])) 
        {
            userList.add(addrs[i]);
        }
            _bind(invs[i],addrs[i]);
        }
    }

    function addUserList(address[] memory addrs) external onlyAdmin{
        for(uint256 i = 0; i < addrs.length; i++ ){
        if (!userList.contains(addrs[i])) 
        {
            userList.add(addrs[i]);
        }  
        }      
    }

    function getUserLength() external view returns (uint256) {
        return userList.length();
    }

     function getUserList() public view returns (address[] memory _addrsList)
    {
        uint256 length = userList.length();
        _addrsList = new address[](length);
        for(uint256 i=0;i<length;i++){
            _addrsList[i] = userList.at(i);
        }
    }





    function setBindLv(address addr_, uint256 lv_) external onlyAdmin{
        bindLv[addr_] = lv_;
    }

    function BatchSetBindLv(address[] memory addrs, uint256[] memory lvls) external onlyAdmin{
        for(uint256 i=0;i< addrs.length;i++){
        bindLv[addrs[i]] = lvls[i];
        }
    }

    function invListLength(address addr_) public view returns(uint256)
    {
        return invList[addr_].length;
    }

    function getInvList(address addr_)
        public view
        returns(address[] memory _addrsList)
    {
        _addrsList = new address[](invList[addr_].length);
        for(uint256 i=0;i<invList[addr_].length;i++){
            _addrsList[i] = invList[addr_][i];
        }
    }

    

    function purchaseM(uint256 lv) external checkDayID {
        require(lv < 4 && mLv[msg.sender] == 0,"Not Exist");
        IERC20Upgradeable(USDT).safeTransferFrom(msg.sender,fundAddress, mPrice[lv]);
        mLv[msg.sender] = lv;
        address inv = Inviter[msg.sender];
        uint256 mlv = mLv[inv];
        USDTReward[inv] += mPrice[lv]* rackback[mlv]/100;
        IPOOL(pool).addReward(msg.sender,mPrice[lv]);
    }




    function devSetM(address[] memory addrs,uint256[] memory lvs) external onlyAdmin{
        require(addrs.length == lvs.length,"DATA ERROR");
        for(uint256 i=0;i<addrs.length;i++){
            address addr = addrs[i];
            uint256 lv = lvs[i];
            mLv[addr] = lv;
           IPOOL(pool).addReward(addr,mPrice[lv]);
        }
    }


    function updateM() external checkDayID {
        require(mLv[msg.sender] < 4 && mLv[msg.sender] > 0,"UNABLE TO UPDATE");
        uint256 lv =  mLv[msg.sender];
        uint256 price = mPrice[lv+1] - mPrice[lv];
        IERC20Upgradeable(USDT).safeTransferFrom(msg.sender,fundAddress, price);
        mLv[msg.sender] = lv + 1;
        address inv = Inviter[msg.sender];
        uint256 mlv = mLv[inv];
        USDTReward[inv] += price* rackback[mlv]/100; 
        IPOOL(pool).addReward(msg.sender,price);   
    } 

    function claimUSDT() external checkDayID{
        require(USDTReward[msg.sender]>0,"No Reward to Claim");
        IVAULT(fundAddress).sendUSDT(msg.sender,USDTReward[msg.sender]);
        USDTRewardClaimed[msg.sender] += USDTReward[msg.sender];
        USDTReward[msg.sender] = 0;
    }

    function Migrate(address token, address to, uint256 amount) external onlyAdmin {
        IERC20Upgradeable(token).safeTransfer(to, amount);
    }

    function setStates(address addr) external onlyAdmin{
        invStats[addr]= true;
    }

    function setFund(address addr) external onlyAdmin{
        fundAddress= addr;
    }

    function setPool(address addr) external onlyAdmin{
        pool= addr;
    }


    function setCheckTime(uint256 value) external onlyAdmin{
        checkTime= value;
    }


    function setDayID(uint256 value) external onlyAdmin{
        dayID= value;
    }

    
    
    function batchUpdateTeamResult(address[] memory addrs, uint256[] memory amounts) external onlyAdmin checkDayID{
        require(addrs.length == amounts.length,"DATA ERROR");
        for(uint256 i = 0;i< addrs.length;i++){
            address addr = addrs[i];
            address inv = Inviter[addr];
            for(uint256 j =0; j< bindLv[addr];j++){
            teamResult[inv][dayID] += amounts[i];
            inv = Inviter[inv];
            }
        }
    }

    function batchUpdatePromoteResult(address[] memory addrs, uint256[] memory amounts) external onlyAdmin checkDayID{
        require(addrs.length == amounts.length,"DATA ERROR");
        for(uint256 i = 0;i< addrs.length;i++){
            address addr = addrs[i];
            address inv = Inviter[addr];
            promoteResult[inv][dayID] += amounts[i];
            }
        }

    function getVIP(address addr, uint256 dID) public view returns(uint256){
        uint256 result = teamResult[addr][dID] / 10**18;
        if(result >= 2000000 && mLv[addr]>3) {
            return 6;
        }
        else if (result >= 750000 && mLv[addr]>3){
            return 5;
        }
        else if (result >= 250000 && mLv[addr]>2){
            return 4;
        }
        else if (result >= 100000 && mLv[addr]>1){
            return 3;
        }
        else if (result >= 50000 && mLv[addr]>0){
            return 2;
        }
        else if (result >= 20000){
            return 1;
        }
        else return 0;
    }

    function viewTeamReward(address addr, uint256 dID) public view returns(uint256){
        uint256 myVIP = getVIP(addr, dID);
        uint256 reward = myVIP > 0?teamResult[addr][dID]*(myVIP+3)/1000 * rewardAdjust/100:0;
        if(reward>0){
        for (uint256 i = 0;i<invList[addr].length;i++){
            address iAddr = invList[addr][i];
            uint256 iVIP = getVIP(iAddr, dID);
            if(iVIP>0){
                reward -= teamResult[iAddr][dID]*(iVIP+3)/1000 * rewardAdjust/100;
            }
        }  
        }
        return claimStats[addr][dayID]?0:reward;
    }


    function viewVIPStats(address addr, uint256 dID) public view returns(bool){
        uint256 myVIP = getVIP(addr, dID);
        if(myVIP>0){
        for (uint256 i = 0;i<invList[addr].length;i++){
            address iAddr = invList[addr][i];
            uint256 iVIP = getVIP(iAddr, dID);
            if(iVIP >=  myVIP){
                return false;
            }
        }  
        }
        return true;
    }

    function claimTeamReward() external checkDayID{
        uint256 reward = viewTeamReward(msg.sender,dayID);
        uint256 myVIP = getVIP(msg.sender,dayID);
        if(reward>0 && myVIP > 0){
            address inv = Inviter[msg.sender];
            uint256 invVIP = getVIP(inv,dayID);
            if(invVIP == myVIP && viewVIPStats(msg.sender,dayID)){
            IVAULT(fundAddress).sendUSDT(inv,reward/10);  
            emit CLAIMSLREWARD(inv,reward/10,dayID);
            }
        }
        if(promoteResult[msg.sender][dayID] >0){
            reward += promoteResult[msg.sender][dayID];
            promoteResult[msg.sender][dayID] = 0;
        }
        if(reward>0){
            IVAULT(fundAddress).sendUSDT(msg.sender,reward);
            claimStats[msg.sender][dayID] = true;
            claimedTeamReward[msg.sender] += reward;
            emit CLAIMTREWARD(msg.sender,reward,dayID);
        }
    }



    event CLAIMTREWARD(address addr, uint256 amount, uint256 dayID);
    event CLAIMSLREWARD(address addr, uint256 amount, uint256 dayID);


    function batchFixTeamResult(address[] memory addrs, uint256[] memory amounts,uint256 _day) external onlyAdmin checkDayID{
        require(addrs.length == amounts.length,"DATA ERROR");
        for(uint256 i = 0;i< addrs.length;i++){
            address addr = addrs[i];
            address inv = Inviter[addr];
            for(uint256 j =0; j< bindLv[addr];j++){
            teamResult[inv][_day] -= amounts[i];
            inv = Inviter[inv];
            }
        }
    }

    function batchFixPromoteResult(address[] memory addrs, uint256[] memory amounts,uint256 _day) external onlyAdmin checkDayID{
        require(addrs.length == amounts.length,"DATA ERROR");
        for(uint256 i = 0;i< addrs.length;i++){
            address addr = addrs[i];
            address inv = Inviter[addr];
            promoteResult[inv][_day] -= amounts[i];
            }
        }

    function setUSDTReward(address addr,uint256 amount) external onlyAdmin checkDayID{
        USDTReward[addr] = amount;
    }

    function setRewardAdjust(uint256 amount) external onlyAdmin{
        require(amount<=100,"Wrong Number");
        rewardAdjust = amount;
    }

    function devSetLv(address[] memory addrs,uint256[] memory lvs) external onlyAdmin{
        require(addrs.length == lvs.length,"DATA ERROR");
        for(uint256 i=0;i<addrs.length;i++){
            address addr = addrs[i];
            uint256 lv = lvs[i];
            mLv[addr] = lv;
        }
    }


     function checkUserList(address addr) external onlyAdmin{
        if (!userList.contains(addr))
        {
            userList.add(addr);
        }     
    }


     




    }

