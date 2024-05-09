// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract GovernableERC20 is ERC20Permit, ERC20Votes, Ownable {
    event ImageUpdated(string newImage);
    event DescriptionUpdated(string newDescription);
    event ERC20Created(
        string name,
        string symbol,
        string image,
        string description,
        uint256 totalSupply,
        address receiver,
        address owner
    );

    constructor(
        string memory name_,
        string memory symbol_,
        string memory image_,
        string memory description_,
        uint256 totalSupply_,
        address receiver_,
        address owner_
    ) ERC20(name_, symbol_) ERC20Permit(name_) Ownable(owner_) {
        _mint(receiver_, totalSupply_);

        emit ERC20Created(name_, symbol_, image_, description_, totalSupply_, receiver_, owner_);
    }

    /// @notice Emits updated image of the token. Only callable by the owner.
    function updateImage(string memory image) public onlyOwner {
        emit ImageUpdated(image);
    }

    /// @notice Emits updated description of the token. Only callable by the owner.
    function updateDescription(string memory description) public onlyOwner {
        emit DescriptionUpdated(description);
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
