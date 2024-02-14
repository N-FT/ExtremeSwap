//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import '@openzeppelin/contracts/access/Ownable.sol';
// import "@openzeppelin/contracts/utils/math/Math.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/utils/Address.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./AdminRole.sol";

interface IVAULT {
    function sendUSDT(address, uint256 amount) external;
}

interface IPOOL {
    function costPoints(address addr, uint256 amount) external;
}

interface INFT {
    function mint(address to, uint256 typeId, uint256 number) external;

    function totalSupplyOfType(uint256 typeId) external view returns (uint256);

    function getTokenId(
        uint256 typeId,
        uint256 index
    ) external pure returns (uint256);

    function getType(uint256 tokenId) external pure returns (uint256);

    function transferFrom(address from, address to, uint256 tokenId) external;

    function ownerOf(uint256 tokenId) external view returns (address);
}

// 合约地址：0x904AF34F01D3bA83923557A453615EFa1CBD06Ca
contract N2SWAP is AdminRole, Initializable {
    // using SafeMath for uint256;
    // using SafeERC20 for IERC20;
    // using Address for address;

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    bool public autoOpen;
    uint256 public aPrice;
    address public fundAddress;
    address public USDT;
    address public _burnAddress;
    mapping(uint256 => address[]) public nftOwnerList;
    mapping(address => uint256) public balance;
    mapping(uint256 => uint256) public intTime;
    mapping(uint256 => uint256) public typeId;
    mapping(address => mapping(uint256 => bool)) public reserveStats;
    mapping(address => mapping(uint256 => uint256)) public reserveAmount;
    mapping(uint256 => mapping(uint256 => uint256)) public nftPrice;

    uint256 public dayID;

    mapping(uint256 => uint256) public dailyReserveAmount;
    mapping(address => uint256) public income;
    NFTInfo[] public NFTInfoList;
    struct NFTInfo {
        address tokenContract;
        uint256 tokenID;
        uint256 initDayID;
        uint256 initPrice;
        address initAddress;
        uint256 initCycle;
        bool claimedStats;
    }

    mapping(address => bool) whiteContract;

    mapping(uint256 => mapping(uint256 => uint256)) public nftBuyPrice;
    mapping(uint256 => mapping(uint256 => uint256)) public nftSellPrice;

    address public pool;

    mapping(address => mapping(uint256 => uint256)) public resaleFee;
    mapping(address => mapping(uint256 => uint256)) public resaleAmount;

    uint256 public percent;


    function initialize() public initializer {
        _addAdmin(msg.sender);
        _addAdmin(0x52F105844eAa2Fb82c5A6fa28A575061c3Bc0943);
        fundAddress = 0xd1dda8203a04c72b9c9a4f1c9eacF40a2887046F;
        USDT = 0x55d398326f99059fF775485246999027B3197955;
        _burnAddress = 0x000000000000000000000000000000000000dEaD;
        aPrice = 150 * 10 ** 18;
    }

    function setPoolAddr() external onlyAdmin {
        pool = 0x89EFEddC20cFB57270561646eED54BE79903c456;
    }

    event RESERVED(address addr, uint256 amount, uint256 _dayID);

    function reserve(uint256 amount,bool feeType) external {
        require(!reserveStats[msg.sender][dayID],"RESERVED ALREADY");
        uint256 avPrice = getAPrice();
        uint256 value = avPrice * amount;
        if(value < balance[msg.sender]){
            IVAULT(fundAddress).sendUSDT(msg.sender,balance[msg.sender] - value);
            balance[msg.sender] = value;
            reserveAmount[msg.sender][dayID] = amount;
            reserveStats[msg.sender][dayID] = true;
            emit RESERVED(msg.sender,amount,dayID);
        }
        else{
            IERC20Upgradeable(USDT).transferFrom(msg.sender,fundAddress,value - balance[msg.sender]);
            balance[msg.sender] = value;
            reserveAmount[msg.sender][dayID] = amount;
            reserveStats[msg.sender][dayID] = true;
            emit RESERVED(msg.sender,amount,dayID);
        }

        (,uint256 usdtAmount) = getSaleTimesAndFee(msg.sender,dayID);
        if(usdtAmount >0){
        if(feeType){
        IPOOL(pool).costPoints(msg.sender, usdtAmount*percent/100);
        }
        else {
        IERC20Upgradeable(USDT).transferFrom(msg.sender,fundAddress,usdtAmount);   
        }
        }

    }

     function setPercent(uint256 amount) external onlyAdmin {
        require(amount <= 100,"Wrong Amount");
        percent = amount;
    }



    function setNFTOwnerList(
        address[] memory addrs,
        uint256 dID
    ) external onlyAdmin {
        for (uint256 i = 0; i < addrs.length; i++) {
            nftOwnerList[dID].push(addrs[i]);
        }
    }

    function nftOwnerListLength(uint256 _dayID) public view returns (uint256) {
        return nftOwnerList[_dayID].length;
    }

    function getNftOwnerList(
        uint256 _dayID
    ) public view returns (address[] memory _addrsList) {
        _addrsList = new address[](nftOwnerList[_dayID].length);
        for (uint256 i = 0; i < nftOwnerList[_dayID].length; i++) {
            _addrsList[i] = nftOwnerList[_dayID][i];
        }
    }

    function checkBalance(
        uint256 dayId,
        uint256[] memory prices
    ) external onlyAdmin {
        uint256 length = nftOwnerList[dayId].length;
        require(length == prices.length, "DATA ERROR");
        for (uint256 i = 0; i < length; i++) {
            address seller = nftOwnerList[dayId - 1][i];
            address buyer = nftOwnerList[dayId][i];
            uint256 price = prices[i];
            balance[seller] += price;
            emit TRADE(buyer, seller, i, price, dayId);
        }
    }

    event TRADE(
        address buyer,
        address seller,
        uint256 number,
        uint256 price,
        uint256 dayId
    );
    event BOUGHT(address buyer, uint256 dayId, uint256 price);
    event SOLD(address seller, uint256 dayId, uint256 price);

    function updateBalance(
        address[] memory addrs,
        uint256[] memory amounts
    ) external onlyAdmin {
        require(addrs.length == amounts.length, "DATA ERROR");
        for (uint256 i = 0; i < addrs.length; i++) {
            address addr = addrs[i];
            uint256 balanceBefore = balance[addr];
            uint256 balanceAfter = amounts[i];
            balance[addr] = balanceAfter;
            if (balanceBefore > balanceAfter) {
                emit BOUGHT(addr, dayID, balanceBefore - balanceAfter);
            } else {
                emit SOLD(addr, dayID, balanceAfter - balanceBefore);
            }
        }
    }

    function addBalance(
        address[] memory addrs,
        uint256[] memory amounts
    ) external onlyAdmin {
        require(addrs.length == amounts.length, "DATA ERROR");
        for (uint256 i = 0; i < addrs.length; i++) {
            address addr = addrs[i];
            balance[addr] += amounts[i];
            emit SOLD(addr, dayID, amounts[i]);
        }
    }

    function reduceBalance(
        address[] memory addrs,
        uint256[] memory amounts
    ) external onlyAdmin {
        require(addrs.length == amounts.length, "DATA ERROR");
        for (uint256 i = 0; i < addrs.length; i++) {
            address addr = addrs[i];
            balance[addr] -= amounts[i];
            emit BOUGHT(addr, dayID, amounts[i]);
        }
    }

    function updateIncome(
        address[] memory addrs,
        uint256[] memory amounts
    ) external onlyAdmin {
        require(addrs.length == amounts.length, "DATA ERROR");
        for (uint256 i = 0; i < addrs.length; i++) {
            address addr = addrs[i];
            income[addr] += amounts[i];
        }
    }

    function getAPrice() public view returns (uint256) {
        // if(autoOpen){
        // uint256 totalAmount = 0;
        // uint256 totalValue = 0;
        // for(uint256 i = 0; i< NFTList.length;i++){
        //     if(status[i]){
        //        totalAmount += 1;
        //        totalValue += 1;
        //     }
        // }
        // return totalValue/totalAmount;
        // }
        return aPrice;
    }

    function setAPrice(uint256 value) external onlyAdmin {
        aPrice = value;
    }

    function setFund(address addr) external onlyAdmin {
        fundAddress = addr;
    }

    function setDayID(uint256 value) external onlyAdmin {
        dayID = value;
    }

    function setDailyReserveAmount(
        uint256 amount,
        uint256 currentdayID
    ) external onlyAdmin {
        dailyReserveAmount[currentdayID] = amount;
    }

    function setWhiteContract(address addr, bool value) external onlyAdmin {
        whiteContract[addr] = value;
    }

    function devStakeNFT(
        address _tokenContract,
        uint256 _tokenID,
        uint256 _intPrice,
        address _intAddress
    ) external onlyAdmin {
        _stakeNFT(
            _tokenContract,
            _tokenID,
            dayID,
            _intPrice,
            _intAddress,
            0,
            false
        );
    }

    function batchStakeNFT(
        address _tokenContract,
        uint256[] memory tokenIDs,
        uint256 _dayID,
        uint256[] memory initPrices,
        address[] memory initAddrs,
        uint256[] memory initCycles
    ) external onlyAdmin {
        for (uint256 i = 0; i < tokenIDs.length; i++) {
            _stakeNFT(
                _tokenContract,
                tokenIDs[i],
                _dayID,
                initPrices[i],
                initAddrs[i],
                initCycles[i],
                false
            );
            nftOwnerList[_dayID].push(initAddrs[i]);
        }
    }

    function _stakeNFT(
        address _tokenContract,
        uint256 _tokenID,
        uint256 _initDayID,
        uint256 _initPrice,
        address _initAddress,
        uint256 _initCycle,
        bool _claimedStats
    ) internal {
        require(
            whiteContract[_tokenContract],
            "stakeToken is the zero address"
        );
        NFTInfo memory _nft = NFTInfo({
            tokenContract: _tokenContract,
            tokenID: _tokenID,
            initDayID: _initDayID,
            initPrice: _initPrice,
            initAddress: _initAddress,
            initCycle: _initCycle,
            claimedStats: _claimedStats
        });
        NFTInfoList.push(_nft);
        nftOwnerList[_initDayID].push(_initAddress);
    }

    function getNFTInfoList() external view returns (NFTInfo[] memory) {
        return NFTInfoList;
    }

    function clearNFTOwnerList(uint256 num, uint256 dID) external onlyAdmin {
        for (uint256 i = 0; i < num; i++) {
            nftOwnerList[dID].pop();
        }
    }

 

    // function getSaleTimesAndFee(address _addr,uint256 _dayID) public view returns(uint256 times, uint256 fee){
    //     for(uint256 i = 0; i< nftOwnerList[_dayID].length; i++){
    //         if(_addr == nftOwnerList[_dayID][i]){
    //             times++;
    //             uint256 intDay = NFTInfoList[i].initDayID;
    //             fee += (nftSellPrice[100*10**18][_dayID-intDay+1]-nftSellPrice[100*10**18][_dayID-intDay])*3/10;
    //         }
    //     }
    // }

    

    function batchUpdateResale(
        address[] memory addrs,
        uint256[] memory amounts
    ) external onlyAdmin {
        require(addrs.length == amounts.length, "DATA ERROR");
        for (uint256 i = 0; i < addrs.length; i++) {
            address addr = addrs[i];
            resaleFee[addr][dayID] += amounts[i] * 3;
            resaleAmount[addr][dayID] += 1;
        }
    }

    function getSaleTimesAndFee(
        address _addr,
        uint256 _dayID
    ) public view returns (uint256 times, uint256 fee) {
        times = resaleAmount[_addr][_dayID];
        fee = resaleFee[_addr][_dayID];
    }

    function viewResaleBuyPrice(
        address _addr,
        uint256 _dayID
    ) public view returns (uint256 value) {
        for (uint256 i = 0; i < nftOwnerList[_dayID].length; i++) {
            if (_addr == nftOwnerList[_dayID][i]) {
                uint256 intDay = NFTInfoList[i].initDayID;
                uint256 intCycle = NFTInfoList[i].initCycle;
                value += nftBuyPrice[100 * 10 ** 18][
                    _dayID + intCycle - intDay
                ];
            }
        }
    }

    function viewResaleSalePrice(
        address _addr,
        uint256 _dayID
    ) public view returns (uint256 value) {
        for (uint256 i = 0; i < nftOwnerList[_dayID].length; i++) {
            if (_addr == nftOwnerList[_dayID][i]) {
                uint256 intDay = NFTInfoList[i].initDayID;
                uint256 intCycle = NFTInfoList[i].initCycle;
                value += nftSellPrice[100 * 10 ** 18][
                    _dayID + intCycle - intDay + 1
                ];
            }
        }
    }

    function split(uint256 nftNum) external {
        require(!reserveStats[msg.sender][dayID], "Reserved");
        require(nftOwnerList[dayID][nftNum] == msg.sender, "Not the Owner");
        uint256 intDay = NFTInfoList[nftNum].initDayID;
        uint256 intCycle = NFTInfoList[nftNum].initCycle;
        uint256 tokenID = NFTInfoList[nftNum].tokenID;
        address gnft = NFTInfoList[nftNum].tokenContract;
        uint256 cycle = intCycle + dayID - intDay;
        require(cycle >= 30 && cycle <= 40, "Nirvana Mode Unavailable");
        uint256 nftType = INFT(gnft).getType(tokenID);
        require(INFT(gnft).ownerOf(tokenID) == address(this), "NFT NOT EXIST");
        INFT(gnft).transferFrom(address(this), _burnAddress, tokenID);
        do {
            INFT(gnft).mint(address(this), nftType, 1);
            uint256 number = INFT(gnft).totalSupplyOfType(nftType);
            uint256 newTokenId = INFT(gnft).getTokenId(nftType, number - 1);
            _stakeNFT(
                gnft,
                newTokenId,
                dayID,
                100 * 10 ** 18,
                msg.sender,
                0,
                false
            );
            cycle -= 10;
        } while (cycle >= 20);
        INFT(gnft).mint(address(this), nftType, 1);
        uint256 lastNumber = INFT(gnft).totalSupplyOfType(nftType);
        uint256 lastTokenId = INFT(gnft).getTokenId(nftType, lastNumber - 1);
        _stakeNFT(
            gnft,
            lastTokenId,
            dayID,
            nftBuyPrice[100 * 10 ** 18][(cycle - 10) * 2],
            msg.sender,
            (cycle - 10) * 2,
            false
        );
        resaleFee[msg.sender][dayID] += 15 * 10 ** 17;
        resaleAmount[msg.sender][dayID] += 2;
        nftOwnerList[dayID][nftNum] = address(0);
    }

 

    function TakeNFT(uint256 nftNum) external {
        uint256 tokenID = NFTInfoList[nftNum].tokenID;
        address gnft = NFTInfoList[nftNum].tokenContract;
        uint256 intDay = NFTInfoList[nftNum].initDayID;
        uint256 intCycle = NFTInfoList[nftNum].initCycle;
        uint256 cycle = intCycle + dayID - intDay;
        require(nftOwnerList[dayID][nftNum] == address(0), "Not the Owner");
        require(INFT(gnft).ownerOf(tokenID) == address(this), "NFT NOT EXIST");
        INFT(gnft).transferFrom(address(this), msg.sender, tokenID);
        resaleFee[msg.sender][dayID] -= (cycle / 20 + 1) * 15 * 10 ** 17;
        resaleAmount[msg.sender][dayID] -= 1;
        nftOwnerList[dayID][nftNum] = address(0);
    }
}
