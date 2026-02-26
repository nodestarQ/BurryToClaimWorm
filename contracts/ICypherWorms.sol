// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC721} from "forge-std/interfaces/IERC721.sol";

interface ICypherWorms is IERC721 {
    function getTokenLevel(uint256 tokenId) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}
