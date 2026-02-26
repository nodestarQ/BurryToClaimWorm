// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BurryToClaimWorm} from "./BurryToClaimWorm.sol";
import {MockCypherWorms} from "./mocks/MockCypherWorms.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract BurryToClaimWormTest is Test {
    BurryToClaimWorm wormBurn;
    MockCypherWorms nft;
    MockERC20 token;

    address admin = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint256 constant NFT_SUPPLY = 10;
    uint256 constant POOL_AMOUNT = 90 ether;

    function setUp() public {
        nft = new MockCypherWorms(NFT_SUPPLY);
        token = new MockERC20();
        wormBurn = new BurryToClaimWorm(address(nft), address(token));

        // Fund pool
        token.mint(admin, POOL_AMOUNT);
        token.approve(address(wormBurn), POOL_AMOUNT);
        wormBurn.fundPool(POOL_AMOUNT);
        wormBurn.setBurryOpen(true);
    }

    // --- Constructor Tests ---
    function test_ConstructorSetsImmutables() public view {
        assertEq(wormBurn.owner(), admin);
        assertEq(address(wormBurn.cypherWorms()), address(nft));
        assertEq(address(wormBurn.wormToken()), address(token));
        assertEq(wormBurn.nftSupply(), NFT_SUPPLY);
    }

    function test_ConstructorRevertsZeroCypherWorms() public {
        vm.expectRevert(BurryToClaimWorm.ZeroAddress.selector);
        new BurryToClaimWorm(address(0), address(token));
    }

    function test_ConstructorRevertsZeroRewardToken() public {
        vm.expectRevert(BurryToClaimWorm.ZeroAddress.selector);
        new BurryToClaimWorm(address(nft), address(0));
    }

    // --- Admin: fundPool ---
    function test_FundPool() public {
        token.mint(admin, 10 ether);
        token.approve(address(wormBurn), 10 ether);
        wormBurn.fundPool(10 ether);
        assertEq(wormBurn.totalPool(), POOL_AMOUNT + 10 ether);
        assertEq(token.balanceOf(address(wormBurn)), POOL_AMOUNT + 10 ether);
    }

    function test_FundPoolRevertsNonOwnerNonFunder() public {
        vm.prank(alice);
        vm.expectRevert(BurryToClaimWorm.NotFunder.selector);
        wormBurn.fundPool(1 ether);
    }

    function test_FundPoolAsFunder() public {
        wormBurn.setFunder(bob);
        token.mint(bob, 10 ether);
        vm.startPrank(bob);
        token.approve(address(wormBurn), 10 ether);
        wormBurn.fundPool(10 ether);
        vm.stopPrank();
        assertEq(wormBurn.totalPool(), POOL_AMOUNT + 10 ether);
    }

    // --- Admin: setFunder ---
    function test_SetFunder() public {
        wormBurn.setFunder(bob);
        assertEq(wormBurn.funder(), bob);
    }

    function test_SetFunderRevertsNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        wormBurn.setFunder(bob);
    }

    // --- Admin: setBurryOpen ---
    function test_SetBurryOpen() public {
        wormBurn.setBurryOpen(false);
        assertFalse(wormBurn.isBurryOpen());
        wormBurn.setBurryOpen(true);
        assertTrue(wormBurn.isBurryOpen());
    }

    function test_SetBurryOpenRevertsNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        wormBurn.setBurryOpen(true);
    }

    function test_BurryRevertsWhenNotOpen() public {
        wormBurn.setBurryOpen(false);
        nft.mint(alice, 1, 4);
        vm.startPrank(alice);
        nft.approve(address(wormBurn), 1);
        vm.expectRevert(BurryToClaimWorm.BurryNotOpen.selector);
        wormBurn.burry(1);
        vm.stopPrank();
    }

    function test_BatchBurryRevertsWhenNotOpen() public {
        wormBurn.setBurryOpen(false);
        nft.mint(alice, 0, 4);
        vm.startPrank(alice);
        nft.approve(address(wormBurn), 0);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.expectRevert(BurryToClaimWorm.BurryNotOpen.selector);
        wormBurn.batchBurry(ids);
        vm.stopPrank();
    }

    // --- Admin: withdrawRemaining ---
    function test_WithdrawRemainingAfterAllBurried() public {
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            nft.mint(alice, i, 4);
        }
        vm.startPrank(alice);
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            nft.approve(address(wormBurn), i);
            wormBurn.burry(i);
        }
        vm.stopPrank();

        uint256 dust = token.balanceOf(address(wormBurn));
        wormBurn.withdrawRemaining(admin);
        assertEq(token.balanceOf(admin), dust);
        assertEq(token.balanceOf(address(wormBurn)), 0);
    }

    function test_WithdrawRemainingRevertsNFTsStillRemaining() public {
        vm.expectRevert(BurryToClaimWorm.NFTsStillRemaining.selector);
        wormBurn.withdrawRemaining(admin);
    }

    function test_WithdrawRemainingRevertsZeroAddress() public {
        _burryAllNFTs();
        vm.expectRevert(BurryToClaimWorm.ZeroAddress.selector);
        wormBurn.withdrawRemaining(address(0));
    }

    function test_WithdrawRemainingRevertsNonOwner() public {
        _burryAllNFTs();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        wormBurn.withdrawRemaining(admin);
    }

    // --- Admin: addBurnAddress / markDead ---
    function test_AddBurnAddress() public {
        address dead = address(0xdead);
        wormBurn.addBurnAddress(dead);
        assertTrue(wormBurn.burnAddresses(dead));
    }

    function test_AddBurnAddressRevertsNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        wormBurn.addBurnAddress(address(0xdead));
    }

    function test_MarkDead() public {
        address dead = address(0xdead);
        nft.mint(dead, 0, 4);
        nft.mint(dead, 1, 2);
        wormBurn.addBurnAddress(dead);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;
        wormBurn.markDead(ids);

        assertEq(wormBurn.totalBurried(), 2);
        assertTrue(wormBurn.isBurried(0));
        assertTrue(wormBurn.isBurried(1));
        // No tokens claimed
        assertEq(wormBurn.totalClaimed(), 0);
    }

    function test_MarkDeadRevertsNotBurnAddress() public {
        nft.mint(alice, 0, 4);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.expectRevert(abi.encodeWithSelector(BurryToClaimWorm.NotBurnAddress.selector, 0));
        wormBurn.markDead(ids);
    }

    function test_MarkDeadRevertsAlreadyBurried() public {
        address dead = address(0xdead);
        nft.mint(dead, 0, 4);
        wormBurn.addBurnAddress(dead);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        wormBurn.markDead(ids);

        vm.expectRevert(abi.encodeWithSelector(BurryToClaimWorm.AlreadyBurried.selector, 0));
        wormBurn.markDead(ids);
    }

    function test_MarkDeadRevertsEmpty() public {
        uint256[] memory ids = new uint256[](0);
        vm.expectRevert(BurryToClaimWorm.NoTokenIds.selector);
        wormBurn.markDead(ids);
    }

    function test_WithdrawRemainingAfterMarkDead() public {
        address dead = address(0xdead);
        // 2 dead, 8 alive
        nft.mint(dead, 0, 4);
        nft.mint(dead, 1, 4);
        for (uint256 i = 2; i < NFT_SUPPLY; i++) {
            nft.mint(alice, i, 8);
        }

        wormBurn.addBurnAddress(dead);
        uint256[] memory deadIds = new uint256[](2);
        deadIds[0] = 0;
        deadIds[1] = 1;
        wormBurn.markDead(deadIds);

        // Burry the remaining 8
        vm.startPrank(alice);
        for (uint256 i = 2; i < NFT_SUPPLY; i++) {
            nft.approve(address(wormBurn), i);
            wormBurn.burry(i);
        }
        vm.stopPrank();

        assertEq(wormBurn.totalBurried(), NFT_SUPPLY);

        // Owner can now withdraw remaining dust
        uint256 dust = token.balanceOf(address(wormBurn));
        wormBurn.withdrawRemaining(admin);
        assertEq(token.balanceOf(address(wormBurn)), 0);
        assertEq(token.balanceOf(admin), dust);
    }

    // --- Single burry at each level ---
    function test_BurryLevel0() public {
        _mintAndBurry(alice, 1, 0);
        // claim = 90e18 * 1 / (10 * 9) = 1e18
        assertEq(token.balanceOf(alice), 1 ether);
    }

    function test_BurryLevel1() public {
        _mintAndBurry(alice, 1, 1);
        assertEq(token.balanceOf(alice), 2 ether);
    }

    function test_BurryLevel2() public {
        _mintAndBurry(alice, 1, 2);
        assertEq(token.balanceOf(alice), 3 ether);
    }

    function test_BurryLevel3() public {
        _mintAndBurry(alice, 1, 3);
        assertEq(token.balanceOf(alice), 4 ether);
    }

    function test_BurryLevel4() public {
        _mintAndBurry(alice, 1, 4);
        assertEq(token.balanceOf(alice), 5 ether);
    }

    function test_BurryLevel5() public {
        _mintAndBurry(alice, 1, 5);
        assertEq(token.balanceOf(alice), 6 ether);
    }

    function test_BurryLevel6() public {
        _mintAndBurry(alice, 1, 6);
        assertEq(token.balanceOf(alice), 7 ether);
    }

    function test_BurryLevel7() public {
        _mintAndBurry(alice, 1, 7);
        assertEq(token.balanceOf(alice), 8 ether);
    }

    function test_BurryLevel8() public {
        _mintAndBurry(alice, 1, 8);
        // claim = 90e18 * 9 / (10 * 9) = 9e18
        assertEq(token.balanceOf(alice), 9 ether);
    }

    // --- Dynamic redistribution ---
    function test_DynamicRedistribution_LowLevelFirst() public {
        nft.mint(alice, 1, 0);
        nft.mint(bob, 2, 8);

        vm.startPrank(alice);
        nft.approve(address(wormBurn), 1);
        wormBurn.burry(1);
        vm.stopPrank();

        // Alice: 90e18 * 1 / (10 * 9) = 1e18
        assertEq(token.balanceOf(alice), 1 ether);

        vm.startPrank(bob);
        nft.approve(address(wormBurn), 2);
        wormBurn.burry(2);
        vm.stopPrank();

        // Bob: (90e18 - 1e18) * 9 / (9 * 9) = 89e18 * 9 / 81 = 89e18 / 9
        uint256 expectedBob = uint256(89 ether) * 9 / 81;
        assertEq(token.balanceOf(bob), expectedBob);
    }

    // --- The spec example: 90 tokens, 10 NFTs ---
    function test_SpecExample_Level8_Level0_Then8MaxLevel() public {
        // Mint: token 0 = level 8, token 1 = level 0, tokens 2-9 = level 8
        nft.mint(alice, 0, 8);
        nft.mint(alice, 1, 0);
        for (uint256 i = 2; i < 10; i++) {
            nft.mint(alice, i, 8);
        }

        vm.startPrank(alice);
        for (uint256 i = 0; i < 10; i++) {
            nft.approve(address(wormBurn), i);
        }

        // Burry token 0 (level 8): claim = 90e18 * 9 / (10 * 9) = 9e18
        wormBurn.burry(0);
        assertEq(wormBurn.totalClaimed(), 9 ether);

        // Burry token 1 (level 0): claim = (90-9)e18 * 1 / (9 * 9) = 81e18 / 81 = 1e18
        wormBurn.burry(1);
        assertEq(wormBurn.totalClaimed(), 10 ether);

        // Burry tokens 2-9 (level 8 each): remaining 80e18 among 8 NFTs
        for (uint256 i = 2; i < 10; i++) {
            wormBurn.burry(i);
        }
        vm.stopPrank();

        // Total claimed should equal total pool (exact in this example)
        assertEq(wormBurn.totalClaimed(), POOL_AMOUNT);
        assertEq(token.balanceOf(alice), POOL_AMOUNT);
    }

    // --- Batch burry ---
    function test_BatchBurry() public {
        nft.mint(alice, 0, 0);
        nft.mint(alice, 1, 4);
        nft.mint(alice, 2, 8);

        vm.startPrank(alice);
        nft.approve(address(wormBurn), 0);
        nft.approve(address(wormBurn), 1);
        nft.approve(address(wormBurn), 2);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;
        wormBurn.batchBurry(ids);
        vm.stopPrank();

        assertEq(wormBurn.totalBurried(), 3);
        assertTrue(token.balanceOf(alice) > 0);
        assertEq(token.balanceOf(alice), wormBurn.totalClaimed());
    }

    function test_BatchBurryRevertsEmpty() public {
        uint256[] memory ids = new uint256[](0);
        vm.expectRevert(BurryToClaimWorm.NoTokenIds.selector);
        wormBurn.batchBurry(ids);
    }

    // --- Double burry revert ---
    function test_DoubleBurryReverts() public {
        nft.mint(alice, 1, 5);

        vm.startPrank(alice);
        nft.approve(address(wormBurn), 1);
        wormBurn.burry(1);

        vm.expectRevert(abi.encodeWithSelector(BurryToClaimWorm.AlreadyBurried.selector, 1));
        wormBurn.burry(1);
        vm.stopPrank();
    }

    // --- Not owner revert ---
    function test_BurryNotTokenOwnerReverts() public {
        nft.mint(alice, 1, 5);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BurryToClaimWorm.CallerNotTokenOwner.selector, 1));
        wormBurn.burry(1);
    }

    // --- All NFTs burried ---
    function test_AllNFTsBurried_TotalClaimedApproxPool() public {
        // All level 8
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            nft.mint(alice, i, 8);
        }

        vm.startPrank(alice);
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            nft.approve(address(wormBurn), i);
            wormBurn.burry(i);
        }
        vm.stopPrank();

        // All max level: each gets remainingPool / remainingNFTs = exactly pool/supply
        assertEq(wormBurn.totalClaimed(), POOL_AMOUNT);
        assertEq(wormBurn.totalBurried(), NFT_SUPPLY);
    }

    function test_AllNFTsBurried_ExtraBurryReverts() public {
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            nft.mint(alice, i, 4);
        }

        vm.startPrank(alice);
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            nft.approve(address(wormBurn), i);
            wormBurn.burry(i);
        }
        vm.stopPrank();

        // Mint one more beyond supply
        nft.mint(bob, 99, 4);
        vm.startPrank(bob);
        nft.approve(address(wormBurn), 99);
        vm.expectRevert(BurryToClaimWorm.AllNFTsBurried.selector);
        wormBurn.burry(99);
        vm.stopPrank();
    }

    // --- Pool exhaustion / dust ---
    function test_MixedLevels_DustMinimal() public {
        // Alternate level 0 and level 8
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            uint256 level = (i % 2 == 0) ? 0 : 8;
            nft.mint(alice, i, level);
        }

        vm.startPrank(alice);
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            nft.approve(address(wormBurn), i);
            wormBurn.burry(i);
        }
        vm.stopPrank();

        // Total claimed should be close to pool, with at most minimal integer dust
        uint256 dust = POOL_AMOUNT - wormBurn.totalClaimed();
        assertTrue(dust < 1e10, "dust too large");
    }

    // --- View functions ---
    function test_CalculateClaim() public {
        nft.mint(alice, 1, 8);
        uint256 expected = POOL_AMOUNT * 9 / (NFT_SUPPLY * 9);
        assertEq(wormBurn.calculateClaim(1), expected);
    }

    function test_RemainingPool() public view {
        assertEq(wormBurn.remainingPool(), POOL_AMOUNT);
    }

    function test_IsBurried() public {
        nft.mint(alice, 1, 4);
        assertFalse(wormBurn.isBurried(1));

        vm.startPrank(alice);
        nft.approve(address(wormBurn), 1);
        wormBurn.burry(1);
        vm.stopPrank();

        assertTrue(wormBurn.isBurried(1));
    }

    // --- Level cap ---
    function test_BurryLevelCappedAt8() public {
        // Mock a level > 8, should be capped to 8
        nft.mint(alice, 1, 20);
        vm.startPrank(alice);
        nft.approve(address(wormBurn), 1);
        wormBurn.burry(1);
        vm.stopPrank();

        // Should claim same as level 8: 90e18 * 9 / (10 * 9) = 9e18
        assertEq(token.balanceOf(alice), 9 ether);
    }

    // --- calculateClaim returns 0 for burried tokens ---
    function test_CalculateClaimReturnsZeroForBurried() public {
        nft.mint(alice, 1, 8);
        assertTrue(wormBurn.calculateClaim(1) > 0);

        vm.startPrank(alice);
        nft.approve(address(wormBurn), 1);
        wormBurn.burry(1);
        vm.stopPrank();

        assertEq(wormBurn.calculateClaim(1), 0);
    }

    // --- fundPool zero amount ---
    function test_FundPoolRevertsZeroAmount() public {
        vm.expectRevert(BurryToClaimWorm.ZeroAmount.selector);
        wormBurn.fundPool(0);
    }

    // --- Helpers ---
    function _mintAndBurry(address user, uint256 tokenId, uint256 level) internal {
        nft.mint(user, tokenId, level);
        vm.startPrank(user);
        nft.approve(address(wormBurn), tokenId);
        wormBurn.burry(tokenId);
        vm.stopPrank();
    }

    function _burryAllNFTs() internal {
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            nft.mint(alice, i, 8);
        }
        vm.startPrank(alice);
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            nft.approve(address(wormBurn), i);
            wormBurn.burry(i);
        }
        vm.stopPrank();
    }
}
