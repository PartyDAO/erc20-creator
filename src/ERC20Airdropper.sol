// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "./GovernableERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract ERC20Airdropper {
    struct Recipient {
        address addr;
        uint256 amount;
    }

    event ERC20Created(
        address indexed token,
        string name,
        string symbol,
        uint256 totalSupply
    );
    event Airdropped(address indexed token, Recipient[] recipients);

    function createToken(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        Recipient[] memory recipients
    ) external returns (ERC20) {
        GovernableERC20 token = new GovernableERC20(
            name,
            symbol,
            totalSupply,
            address(this)
        );

        emit ERC20Created(address(token), name, symbol, totalSupply);

        if (recipients.length > 0) {
            for (uint256 i = 0; i < recipients.length; i++) {
                token.transfer(recipients[i].addr, recipients[i].amount);
            }
            emit Airdropped(address(token), recipients);
        }

        uint256 remaining = token.balanceOf(address(this));
        if (remaining > 0) {
            token.transfer(msg.sender, remaining);
        }

        return token;
    }
}
