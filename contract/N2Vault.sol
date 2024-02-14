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


// 合约地址：0xd1dda8203a04c72b9c9a4f1c9eacF40a2887046F
contract N2Vault is AdminRole, Initializable {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    address public USDT ;
    address public _burnAddress;


    function initialize() public initializer { 
        _addAdmin(msg.sender);
        _addAdmin(0x52F105844eAa2Fb82c5A6fa28A575061c3Bc0943);
        USDT = 0x55d398326f99059fF775485246999027B3197955;
        _burnAddress = 0x000000000000000000000000000000000000dEaD;
    }

    function sendUSDT(address addr, uint256 amount) external onlyAdmin{
        IERC20Upgradeable(USDT).safeTransfer(addr, amount);
    }

    function Migrate(address token, address to, uint256 amount) external onlyAdmin {
        IERC20Upgradeable(token).safeTransfer(to, amount);
    }


    }

