// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC165} from "forge-std/interfaces/IERC165.sol";

contract MockCypherWorms {
    string public name = "CypherWorms";
    string public symbol = "CWORM";
    uint256 private _totalSupply;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => uint256) private _tokenLevels;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(uint256 totalSupply_) {
        _totalSupply = totalSupply_;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function setTotalSupply(uint256 totalSupply_) external {
        _totalSupply = totalSupply_;
    }

    function mint(address to, uint256 tokenId, uint256 level) external {
        require(to != address(0), "mint to zero");
        require(_owners[tokenId] == address(0), "already minted");
        _owners[tokenId] = to;
        _balances[to]++;
        _tokenLevels[tokenId] = level;
        emit Transfer(address(0), to, tokenId);
    }

    function setTokenLevel(uint256 tokenId, uint256 level) external {
        _tokenLevels[tokenId] = level;
    }

    function getTokenLevel(uint256 tokenId) external view returns (uint256) {
        return _tokenLevels[tokenId];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "nonexistent token");
        return o;
    }

    function balanceOf(address o) external view returns (uint256) {
        require(o != address(0), "zero address");
        return _balances[o];
    }

    function transferFrom(address from, address to, uint256 tokenId) external payable {
        require(_isApprovedOrOwner(msg.sender, tokenId), "not approved");
        require(_owners[tokenId] == from, "wrong owner");
        require(to != address(0), "transfer to zero");

        _tokenApprovals[tokenId] = address(0);
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;

        // Mimics real CypherWorms: transfer resets level to 0
        _tokenLevels[tokenId] = 0;

        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external payable {
        this.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external payable {
        this.transferFrom(from, to, tokenId);
    }

    function approve(address to, uint256 tokenId) external payable {
        address o = _owners[tokenId];
        require(msg.sender == o || _operatorApprovals[o][msg.sender], "not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(o, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_owners[tokenId] != address(0), "nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address o, address operator) external view returns (bool) {
        return _operatorApprovals[o][operator];
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd || interfaceId == 0x01ffc9a7;
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address o = _owners[tokenId];
        return (spender == o || _tokenApprovals[tokenId] == spender || _operatorApprovals[o][spender]);
    }
}
