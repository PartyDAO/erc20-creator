// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract GovernableERC20 is ERC20Permit, ERC20Votes, Ownable {
    event MetadataSet(string image, string description);

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

        emit MetadataSet(image_, description_);
    }

    /// @notice Updates the emitted metadata for the token.
    function setMetadata(string memory image, string memory description) external onlyOwner {
        emit MetadataSet(image, description);
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
