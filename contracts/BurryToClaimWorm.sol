// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ICypherWorms} from "./ICypherWorms.sol";

//
//                            .:=+*#%%@@%%#*+=:.
//                       .=*%@░▒▓██████████▓▒░@%*=.
//                    :+#▓███████████████████████▓#+-
//                  =%▓████▓▒*=:..        ..:=+▒▓████▓%=
//                +▓████▒=.    .:=+**##**+=:.    .=▒████▓+
//              -#███▓+.   :+#▓████████████▓#*:.   .+▓███#-
//             *████+.  .+%████▓▒*+====+*▒▓████%+.   +████*
//            +███▓:  .+▓███▒=.            .=▒███▓+.  .▓███+
//           -████.  :%███▒:   .=+*####*+=.   :▒███%:  .████-
//           %███-  +███▓:  .+#████████████#+.  :▓███+  -███%
//          .███▓  :████. .+▓███▒*+====+*▒███▓+. .████:  ▓███.
//          :███▒  *███+ .#███▒:          :▒███#. +███*  ▒███:
//          .▓██▓  ▓███  #███+              +███#  ███▓  ▓██▓.
//           +███: -███▒ +███▓.           .▓███+ ▒███- :███+
//            ▓██▓  *███+ :▓███+        +███▓: +███*  ▓██▓
//            .████: :▓███+. =▒▓██▓##▓██▓▒= .+███▓: :████.
//             :████+  =%███▓+:. .:==:. .:+▓███%=  +████:
//              .▒███▓=  .=*▓████▓▓▓▓████▓*=.  =%███▒.
//                =%███▓*:   .:=+*####*+=:.  :*▓███%=
//                  =▒████▓*=:.        .:=*▓████▒=
//                    .=*▓██████▓▓▓▓▓▓██████▓*=.
//                        :=+*#%%@@@@%%#*+=:
//                                                CypherWorms don't burn, they just burry deeper into Ethereum
//

/// @title BurryToClaimWorm - Burry CypherWorms NFTs to Claim $WORM Tokens
/// @author CypherWorms Team
/// @notice Holders burry (lock) their CypherWorms NFTs into this contract to claim
///         $WORM token rewards. Higher-level worms receive proportionally larger claims.
/// @dev Claims are calculated dynamically: (remainingPool * (level + 1)) / (remainingNFTs * 9).
///      NFTs are transferred to this contract and locked forever, they are not burned.
///      The level is read before transfer since CypherWorms resets level on transfer.
contract BurryToClaimWorm is Ownable, ReentrancyGuard {

    // ERRORS

    /// @dev Thrown when a zero address is passed where a valid address is required
    error ZeroAddress();
    /// @dev Thrown when attempting to withdraw remaining tokens before all NFTs are burried
    error NFTsStillRemaining();
    /// @dev Thrown when attempting to burry an NFT that has already been burried
    error AlreadyBurried(uint256 tokenId);
    /// @dev Thrown when all NFTs have been burried and no more can be accepted
    error AllNFTsBurried();
    /// @dev Thrown when the caller does not own the NFT they are trying to burry
    error CallerNotTokenOwner(uint256 tokenId);
    /// @dev Thrown when an empty array is passed to batchBurry
    error NoTokenIds();
    /// @dev Thrown when an ERC20 transfer or transferFrom returns false
    error TransferFailed();
    /// @dev Thrown when burrying is attempted before the admin has opened it
    error BurryNotOpen();
    /// @dev Thrown when a non-owner and non-funder tries to fund the pool
    error NotFunder();
    /// @dev Thrown when a token is not owned by a known burn address
    error NotBurnAddress(uint256 tokenId);
    /// @dev Thrown when zero amount is passed to fundPool
    error ZeroAmount();

    // EVENTS

    /// @notice Emitted when the owner funds the reward pool
    /// @param amount The amount of $WORM tokens added
    /// @param totalPool The new total pool size after funding
    event PoolFunded(uint256 amount, uint256 totalPool);

    /// @notice Emitted when the funder address is updated
    /// @param funder The new funder address (address(0) to remove)
    event FunderUpdated(address indexed funder);

    /// @notice Emitted when the owner opens or closes burrying
    /// @param isBurryOpen Whether burrying is now open
    event BurryOpened(bool isBurryOpen);

    /// @notice Emitted when a CypherWorm NFT is burried and rewards are claimed
    /// @param burryer The address that burried the NFT
    /// @param tokenId The token ID of the burried NFT
    /// @param level The worm's level at time of burrying (0-8)
    /// @param claimAmount The amount of $WORM tokens claimed
    event Burried(
        address indexed burryer,
        uint256 indexed tokenId,
        uint256 level,
        uint256 claimAmount
    );

    /// @notice Emitted when a burn address is registered
    /// @param burnAddress The address that was registered
    event BurnAddressUpdated(address indexed burnAddress);

    /// @notice Emitted when a token is marked as dead (owned by a burn address)
    /// @param tokenId The token ID that was marked dead
    /// @param burnAddress The burn address that owns the token
    event MarkedDead(uint256 indexed tokenId, address indexed burnAddress);

    /// @notice Emitted when the owner withdraws remaining dust after all NFTs are burried
    /// @param to The address that received the remaining tokens
    /// @param amount The amount of tokens withdrawn
    event RemainingWithdrawn(address indexed to, uint256 amount);

    // IMMUTABLES

    /// @notice The CypherWorms NFT contract
    ICypherWorms public immutable cypherWorms;

    /// @notice The $WORM ERC20 reward token
    IERC20 public immutable wormToken;

    // STATE

    /// @notice Total $WORM tokens deposited into the reward pool
    uint256 public totalPool;

    /// @notice Total $WORM tokens claimed by burryers so far
    uint256 public totalClaimed;

    /// @notice Number of NFTs burried so far
    uint256 public totalBurried;

    /// @notice Tracks which token IDs have been burried
    mapping(uint256 => bool) public burried;

    /// @notice Whether burrying is currently open (set by owner)
    bool public isBurryOpen;

    /// @notice Optional address allowed to fund the pool (set by owner, address(0) = disabled)
    address public funder;

    /// @notice Known burn addresses where NFTs are permanently unreachable
    mapping(address => bool) public burnAddresses;

    /// @notice Initializes the contract with the CypherWorms NFT and $WORM token addresses
    /// @param _cypherWorms Address of the CypherWorms NFT contract
    /// @param _rewardToken Address of the $WORM ERC20 token contract
    constructor(
        address _cypherWorms,
        address _rewardToken
    ) Ownable(msg.sender) {
        if (_cypherWorms == address(0)) revert ZeroAddress();
        if (_rewardToken == address(0)) revert ZeroAddress();

        cypherWorms = ICypherWorms(_cypherWorms);
        wormToken = IERC20(_rewardToken);
    }

    // ADMIN FUNCTIONS

    /// @notice Deposit $WORM tokens into the reward pool (owner or funder)
    /// @dev Requires prior ERC20 approval. Can be called multiple times to top up.
    /// @param amount The amount of $WORM tokens to deposit
    function fundPool(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (msg.sender != owner() && msg.sender != funder) revert NotFunder();
        totalPool += amount;
        bool success = wormToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) revert TransferFailed();
        emit PoolFunded(amount, totalPool);
    }

    /// @notice Set the funder address allowed to fund the pool (owner only)
    /// @param _funder The address to allow funding, or address(0) to disable
    function setFunder(address _funder) external onlyOwner {
        funder = _funder;
        emit FunderUpdated(_funder);
    }

    /// @notice Open or close burrying for NFT holders (owner only)
    /// @param _isBurryOpen True to open burrying, false to close it
    function setBurryOpen(bool _isBurryOpen) external onlyOwner {
        isBurryOpen = _isBurryOpen;
        emit BurryOpened(_isBurryOpen);
    }

    /// @notice Register a known burn address (owner only, irreversible)
    /// @param _burnAddress The address to register as a burn address
    function addBurnAddress(address _burnAddress) external onlyOwner {
        burnAddresses[_burnAddress] = true;
        emit BurnAddressUpdated(_burnAddress);
    }

    /// @notice Mark token IDs as dead because they are owned by a known burn address
    /// @dev Anyone can call this. Each token must be owned by a registered burn address
    ///      and not already burried. Increments totalBurried with no payout.
    ///      Because dead tokens reduce remainingNFTs without reducing remainingPool,
    ///      marking tokens dead increases the per-NFT claim for all subsequent burryers.
    /// @param tokenIds Array of token IDs to mark as dead
    function markDead(uint256[] calldata tokenIds) external {
        if (tokenIds.length == 0) revert NoTokenIds();

        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            if (burried[tokenId]) revert AlreadyBurried(tokenId);

            address tokenOwner = cypherWorms.ownerOf(tokenId);
            if (!burnAddresses[tokenOwner]) revert NotBurnAddress(tokenId);

            burried[tokenId] = true;
            totalBurried++;

            emit MarkedDead(tokenId, tokenOwner);
        }
    }

    /// @notice Withdraw remaining dust after all NFTs have been burried (owner only)
    /// @dev Only callable when totalBurried >= cypherWorms.totalSupply()
    /// @param to The address to send remaining tokens to
    function withdrawRemaining(address to) external onlyOwner {
        if (totalBurried < cypherWorms.totalSupply()) revert NFTsStillRemaining();
        if (to == address(0)) revert ZeroAddress();

        uint256 amount = wormToken.balanceOf(address(this));
        bool success = wormToken.transfer(to, amount);
        if (!success) revert TransferFailed();
        emit RemainingWithdrawn(to, amount);
    }

    // CORE FUNCTIONS

    /// @notice Burry a single CypherWorm NFT to claim $WORM tokens
    /// @dev Caller must own the NFT and have approved this contract for transfer
    /// @param tokenId The token ID of the CypherWorm to burry
    function burry(uint256 tokenId) external nonReentrant {
        uint256 claimAmount = _burry(tokenId);
        bool success = wormToken.transfer(msg.sender, claimAmount);
        if (!success) revert TransferFailed();
    }

    /// @notice Burry multiple CypherWorm NFTs in a single transaction
    /// @dev Caller must own all NFTs and have approved this contract for each transfer
    /// @param tokenIds Array of token IDs to burry
    function batchBurry(uint256[] calldata tokenIds) external nonReentrant {
        if (tokenIds.length == 0) revert NoTokenIds();

        uint256 totalClaim;
        for (uint256 i; i < tokenIds.length; ++i) {
            totalClaim += _burry(tokenIds[i]);
        }

        bool success = wormToken.transfer(msg.sender, totalClaim);
        if (!success) revert TransferFailed();
    }

    /// @notice Internal burry logic shared by burry() and batchBurry()
    /// @dev Follows checks-effects-interactions pattern. Reads level before transfer
    ///      since CypherWorms resets level to 0 on transfer.
    /// @param tokenId The token ID to burry
    /// @return claimAmount The amount of $WORM tokens earned for this NFT
    function _burry(uint256 tokenId) internal returns (uint256 claimAmount) {
        // Checks
        if (!isBurryOpen) revert BurryNotOpen();
        if (burried[tokenId]) revert AlreadyBurried(tokenId);
        uint256 supply = cypherWorms.totalSupply();
        if (totalBurried >= supply) revert AllNFTsBurried();
        if (cypherWorms.ownerOf(tokenId) != msg.sender)
            revert CallerNotTokenOwner(tokenId);

        // Read level BEFORE transfer (transfer resets level), cap at 8
        uint256 level = cypherWorms.getTokenLevel(tokenId);
        if (level > 8) level = 8;

        // Calculate claim
        uint256 remainingNFTs = supply - totalBurried;
        claimAmount =
            ((totalPool - totalClaimed) * (level + 1)) /
            (remainingNFTs * 9);

        // Effects
        burried[tokenId] = true;
        totalClaimed += claimAmount;
        totalBurried++;

        // Interaction - NFT locked forever in this contract
        cypherWorms.transferFrom(msg.sender, address(this), tokenId);

        emit Burried(msg.sender, tokenId, level, claimAmount);
    }

    // VIEW FUNCTIONS

    /// @notice Preview the claim amount for a given token ID at current pool state
    /// @param tokenId The token ID to check
    /// @return The amount of $WORM tokens that would be claimed
    function calculateClaim(uint256 tokenId) external view returns (uint256) {
        if (burried[tokenId]) return 0;
        uint256 remainingNFTs = cypherWorms.totalSupply() - totalBurried;
        if (remainingNFTs == 0) return 0;
        uint256 level = cypherWorms.getTokenLevel(tokenId);
        if (level > 8) level = 8;
        return ((totalPool - totalClaimed) * (level + 1)) / (remainingNFTs * 9);
    }

    /// @notice Returns the amount of $WORM tokens still available in the pool
    /// @return The unclaimed portion of the reward pool
    function remainingPool() external view returns (uint256) {
        return totalPool - totalClaimed;
    }

    /// @notice Returns the current total supply of CypherWorms NFTs
    /// @return The live totalSupply from the CypherWorms contract
    function nftSupply() external view returns (uint256) {
        return cypherWorms.totalSupply();
    }

    /// @notice Check whether a specific token ID has been burried
    /// @param tokenId The token ID to check
    /// @return True if the token has been burried
    function isBurried(uint256 tokenId) external view returns (bool) {
        return burried[tokenId];
    }
}
