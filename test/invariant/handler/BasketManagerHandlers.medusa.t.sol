pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BasketToken } from "src/BasketToken.sol";
import { BasketManagerHandlers } from "test/invariant/handler/BasketManagerHandlers.deployement.t.sol";

import { console } from "forge-std/console.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { Status } from "src/types/BasketManagerStorage.sol";

import { BasketManager } from "src/BasketManager.sol";
import { RebalanceStatus } from "src/types/BasketManagerStorage.sol";

import { BasketManagerValidationLib } from "test/utils/BasketManagerValidationLib.sol";

contract ScenarioSimpleMedusa is BasketManagerHandlers {
    using BasketManagerValidationLib for BasketManager;

    function setUp() public override {
        for (uint256 i = 0; i < users.length; i++) {
            targetContract(address(users[i]));
        }
        targetContract(address(tokenSwap));
        targetContract(address(rebalancer));
        targetContract(address(oracleHandler));
        targetContract(address(feeCollectorHandler));
        targetContract(address(basketManagerAdminHandler));
        return;
    }

    constructor() {
        super.setUp();
    }

    ///////////////////////
    // INVARIANTS
    ///////////////////////

    /**
     * @notice Verifies asset conservation: sum of basket balances equals actual token balance when not in rebalance
     * @custom:preconditions Price was not updated without rebalancing and system is not in active rebalance
     * @custom:action Sums up all basket balances for each asset and compares with actual BasketManager balance
     * @custom:postcondition Total basket balances must equal actual token balance in BasketManager
     */
    function invariant_assetConservation() public {
        // Skip if the price was update without rebalancing
        if (globalState.price_was_updated()) {
            return;
        }

        // Skip if currently in the middle of a rebalance process
        if (basketManager.rebalanceStatus().status != Status.NOT_STARTED) {
            return;
        }

        // Check each asset
        address[] memory assets = AssetRegistry(address(basketManager.assetRegistry())).getAllAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 totalBasketBalances = 0;

            // Sum up the balances across all baskets
            address[] memory baskets = basketManager.basketTokens();
            uint256 balanceOf;
            for (uint256 j = 0; j < baskets.length; j++) {
                balanceOf = basketManager.basketBalanceOf(baskets[j], asset);

                console.log("### Balance of basket", baskets[j], balanceOf);
                totalBasketBalances += balanceOf;
            }

            // Since collectedSwapFees is not directly accessible (it's private), we can't check it directly
            // in this invariant test. We rely on the internal accounting to be correct.

            console.log("### Diff ", totalBasketBalances, IERC20(asset).balanceOf(address(basketManager)));
            // Verify conservation: sum of basket balances = actual balance when not in rebalance
            assertEq(
                totalBasketBalances,
                IERC20(asset).balanceOf(address(basketManager)),
                "Asset conservation violated for asset"
            );
        }
    }

    /**
     * @notice Verifies oracle configurations remain valid and return non-zero values
     * @custom:preconditions none
     * @custom:action none
     * @custom:postcondition Oracle paths must be properly configured and return valid non-zero values
     */
    /*
    function invariant_oraclePathsAreValid() public {
        // Verify oracle configurations remain valid
        basketManager.testLib_validateConfiguredOracles();
    }*/

    /**
     * @notice Verifies basket registration consistency: count, indices, and mapping integrity
     * @custom:preconditions System has registered basket tokens
     * @custom:action Checks that basket token count matches array length and each basket has correct index
     * @custom:postcondition numOfBasketTokens equals basketTokens.length and each basket index is correct
     */
    function invariant_basketRegistrationConsistency() public {
        // Check that numOfBasketTokens matches basketTokens.length
        assertEq(basketManager.numOfBasketTokens(), basketManager.basketTokens().length, "Basket token count mismatch");

        // Check that each basket's index is correct
        address[] memory baskets = basketManager.basketTokens();
        for (uint256 i = 0; i < baskets.length; i++) {
            assertEq(basketManager.basketTokenToIndex(baskets[i]), i, "Basket token index mismatch");
        }
    }

    /**
     * @notice Verifies basket registration consistency for known baskets and their basketIds
     * @custom:preconditions System has registered basket tokens with valid bitFlags and strategies
     * @custom:action Checks basketId to address mapping integrity and validates no orphaned basketIds exist
     * @custom:postcondition All basketIds map to valid baskets and all baskets have valid indices
     */
    function invariant_knownBasketRegistrationConsistency() public {
        address[] memory baskets = basketManager.basketTokens();

        // Check each basket
        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];

            // Get basket's bitFlag and strategy
            uint256 bitFlag = BasketToken(basket).bitFlag();
            address strategy = BasketToken(basket).strategy();

            // Calculate expected basketId
            bytes32 basketId = keccak256(abi.encodePacked(bitFlag, strategy));

            // Verify basketIdToAddress mapping is correct
            assertEq(basketManager.basketIdToAddress(basketId), basket, "BasketId to address mapping mismatch");

            // Verify basket has valid index by checking if basketTokenToIndex() doesn't revert
            // If the basket is not properly registered, this will revert with BasketTokenNotFound
            uint256 index = basketManager.basketTokenToIndex(basket);
            assertTrue(index < type(uint256).max, "Basket has invalid index"); // Always true if above doesn't revert
        }

        // Additional check: Verify all known basketIds point to baskets with valid indices
        // This is a more comprehensive check that ensures no "orphaned" basketIds exist
        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];
            uint256 bitFlag = BasketToken(basket).bitFlag();
            address strategy = BasketToken(basket).strategy();
            bytes32 basketId = keccak256(abi.encodePacked(bitFlag, strategy));

            address registeredBasket = basketManager.basketIdToAddress(basketId);
            if (registeredBasket != address(0)) {
                // This will revert with BasketTokenNotFound if the basket is not properly registered
                uint256 index = basketManager.basketTokenToIndex(registeredBasket);
                assertTrue(index < type(uint256).max, "Known basket has invalid index"); // Always true if above doesn't
                    // revert
            }
        }
    }

    /**
     * @notice Verifies BasketManager configurations are within intended hardcoded bounds
     * @custom:preconditions BasketManager is deployed with configuration parameters
     * @custom:action Checks all configuration parameters against their maximum/minimum bounds
     * @custom:postcondition All configuration parameters must be within their defined bounds
     */
    function invariant_configurationBounds() public {
        // Check swap fee is within bounds
        assertTrue(basketManager.swapFee() <= MAX_SWAP_FEE, "Swap fee exceeds maximum");

        // Check step delay is within bounds
        uint40 stepDelay = basketManager.stepDelay();
        assertTrue(stepDelay >= MIN_STEP_DELAY, "Step delay below minimum");
        assertTrue(stepDelay <= MAX_STEP_DELAY, "Step delay above maximum");

        // Check retry limit is within bounds
        assertTrue(basketManager.retryLimit() <= MAX_RETRIES, "Retry limit exceeds maximum");

        // Check slippage limit is within bounds
        assertTrue(basketManager.slippageLimit() <= MAX_SLIPPAGE_LIMIT, "Slippage limit exceeds maximum");

        // Check weight deviation limit is within bounds
        assertTrue(
            basketManager.weightDeviationLimit() <= MAX_WEIGHT_DEVIATION_LIMIT, "Weight deviation limit exceeds maximum"
        );

        // Check management fee for each basket is within bounds
        address[] memory baskets = basketManager.basketTokens();
        for (uint256 i = 0; i < baskets.length; i++) {
            assertTrue(basketManager.managementFee(baskets[i]) <= MAX_MANAGEMENT_FEE, "Management fee exceeds maximum");
        }
    }

    /**
     * @notice Verifies variable links are correct between BasketToken and BasketManager
     * @custom:preconditions Basket tokens are deployed and linked to BasketManager
     * @custom:action Checks that each basket token has correct assetRegistry and basketManager references
     * @custom:postcondition All basket tokens must have correct assetRegistry and basketManager addresses
     */
    function invariant_variableLink() public {
        address[] memory baskets = basketManager.basketTokens();

        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];
            // Check Asset Registry link
            assertEq(
                BasketToken(basket).assetRegistry(),
                address(basketManager.assetRegistry()),
                "Basket asset registry mismatch"
            );
            // Check Basket Manager link
            assertEq(BasketToken(basket).basketManager(), address(basketManager), "Basket manager address mismatch");
        }
    }

    /**
     * @notice Verifies rebalance status validity: retry count, basket mask, trade hashes, and timestamps
     * @custom:preconditions BasketManager has a rebalance status state
     * @custom:action Validates rebalance status consistency and state transitions based on current status
     * @custom:postcondition Rebalance status must be consistent with its current state and respect all constraints
     */
    function invariant_rebalanceStatusValidity() public {
        RebalanceStatus memory status = basketManager.rebalanceStatus();

        /*
        assertEq(
            keccak256(abi.encode(status)),
            keccak256(abi.encode(handler.rebalanceStatus())),
            "Rebalance status should be consistent"
        );*/

        // Check retry count does not exceed limit
        assertTrue(status.retryCount <= basketManager.retryLimit(), "Retry count exceeds limit");

        // Status-specific validations
        if (status.status == Status.NOT_STARTED) {
            // When not started, all state should be reset
            assertEq(status.proposalTimestamp, 0, "Proposal timestamp should be zero outside of rebalance");
            assertEq(status.retryCount, 0, "Retry count should be zero outside of rebalance");
            assertEq(status.basketMask, 0, "Basket mask should be zero outside of rebalance");
            assertEq(status.basketHash, bytes32(0), "Basket hash should be zero outside of rebalance");
            assertEq(
                basketManager.externalTradesHash(), bytes32(0), "External trades hash should be zero when not started"
            );
            if (status.epoch == 0 && status.retryCount == 0) {
                assertEq(status.timestamp, 0, "Timestamp should be zero when not started");
            }
            if (status.timestamp > 0) {
                assertTrue(
                    status.epoch > 0 || status.retryCount > 0,
                    "Epoch or retry count should be non-zero when timestamp is non-zero"
                );
            }
        } else {
            // Active rebalance validations
            assertTrue(status.basketMask != 0, "Basket mask is not zero during active rebalance");
            assertTrue(status.basketHash != bytes32(0), "Basket hash is not zero during active rebalance");
            assertTrue(status.proposalTimestamp != 0, "Proposal timestamp should be non-zero during rebalance");
            assertTrue(
                status.timestamp >= status.proposalTimestamp, "Timestamp should not be before proposal timestamp"
            );

            // Status-specific external trades hash checks
            if (status.status == Status.TOKEN_SWAP_PROPOSED || status.status == Status.TOKEN_SWAP_EXECUTED) {
                // Technically, the external trades could be empty if only internal trades are proposed
                // However the resulting hash should still be non-zero as hash of zero bytes is non-zero
                assertTrue(
                    basketManager.externalTradesHash() != bytes32(0),
                    "External trades hash should be non-zero after trade proposal"
                );
            }
        }
    }

    /**
     * @notice Verifies asset index consistency and base asset index validity for each basket
     * @custom:preconditions Baskets are deployed with configured assets
     * @custom:action Checks that asset indices are consistent and base asset index is valid
     * @custom:postcondition All asset indices must be correct and base asset index must match BasketToken.asset()
     */
    function invariant_assetIndexConsistency() public {
        address[] memory baskets = basketManager.basketTokens();

        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];
            address[] memory assets = basketManager.basketAssets(basket);

            for (uint256 j = 0; j < assets.length; j++) {
                address asset = assets[j];

                // Check that getAssetIndexInBasket returns the correct index
                assertEq(basketManager.getAssetIndexInBasket(basket, asset), j, "Asset index mismatch");
            }

            // Check base asset index is valid and matches
            uint256 baseAssetIndex = basketManager.basketTokenToBaseAssetIndex(basket);
            assertLt(baseAssetIndex, assets.length, "Base asset index out of bounds");

            // Verify base asset in BasketToken matches the asset at baseAssetIndex
            assertEq(BasketToken(basket).asset(), assets[baseAssetIndex], "Base asset mismatch");
        }
    }

    /**
     * @notice Verifies that completeRebalance reverts when step delay has not been met
     * @custom:preconditions A rebalance has been initiated with a timestamp
     * @custom:action Attempts to complete rebalance before step delay has passed
     * @custom:postcondition completeRebalance must revert when step delay has not been met
     */
    function invariant_completeRebalance_revertsWhen_StepDelayIsNotMet() public {
        // Get the last action timestamp

        uint256 lastActionTimestamp = basketManager.rebalanceStatus().timestamp;
        if (lastActionTimestamp > 0) {
            // Only if the step delay has not passed
            if (lastActionTimestamp + basketManager.stepDelay() > block.timestamp) {
                try basketManager.completeRebalance(
                    tokenSwap.externalTrades(),
                    tokenSwap.rebalancingBaskets(),
                    tokenSwap.targetWeights(),
                    tokenSwap.basketAssets()
                ) {
                    assertTrue(false, "Expected reversion");
                } catch {
                    // Expected reversion
                }
            }
        }
    }

    /**
     * @notice Verifies ERC20 total supply consistency: totalSupply equals sum of all holder balances
     * @custom:preconditions Price was not updated without rebalancing and baskets have holders
     * @custom:action Sums up all holder balances for each basket token
     * @custom:postcondition totalSupply must equal sum of all holder balances for each basket
     */
    function invariant_erc20_total_supply() public {
        // Skip if the price was update without rebalancing
        if (globalState.price_was_updated()) {
            return;
        }

        address[] memory baskets = basketManager.basketTokens();

        for (uint256 i = 0; i < baskets.length; i++) {
            // Start with the tokens in the basket itself
            // These are the tokens held during deposit
            uint256 sum = BasketToken(baskets[i]).balanceOf(address(baskets[i]));

            // fees
            sum += BasketToken(baskets[i]).balanceOf(basketManager.feeCollector());

            for (uint256 j = 0; j < users.length; j++) {
                sum += BasketToken(baskets[i]).balanceOf(address(users[j]));
                console.log("sum", sum);
            }

            console.log("total supply ", BasketToken(baskets[i]).totalSupply());

            assert(BasketToken(baskets[i]).totalSupply() == sum);
        }
    }

    /**
     * @notice Verifies that max functions (maxDeposit, maxMint, maxRedeem, maxWithdraw) don't revert
     * @custom:preconditions none
     * @custom:action none
     * @custom:postcondition All max functions must execute without reverting for any user and basket combination
     */
    function max_no_revert(address user) public {
        address[] memory baskets = basketManager.basketTokens();

        for (uint256 i = 0; i < baskets.length; i++) {
            try BasketToken(baskets[i]).maxDeposit(user) { }
            catch {
                assert(false);
            }
            try BasketToken(baskets[i]).maxMint(user) { }
            catch {
                assert(false);
            }
            try BasketToken(baskets[i]).maxRedeem(user) { }
            catch {
                assert(false);
            }
            try BasketToken(baskets[i]).maxWithdraw(user) { }
            catch {
                assert(false);
            }
        }
    }

    // DISABLED as the property can fail
    /**
     * @notice Verifies that totalAssets() approximates sum of oracle quotes within 1% tolerance
     * @custom:preconditions Price was not updated without rebalancing and system is not in active rebalance
     * @custom:action Calculates sum of oracle quotes for all assets in each basket
     * @custom:postcondition totalAssets must approximate sum of oracle quotes within 1% tolerance
     */
    /*    function invariant_ERC4626_totalAssets() public{

        // Skip if the price was update without rebalancing
        if (globalState.price_was_updated()){
            return ;
        }

        if (basketManager.rebalanceStatus().status != Status.NOT_STARTED) {
            return;
        }

        address[] memory baskets = basketManager.basketTokens();


        for(uint i = 0; i<baskets.length; i++){

            // Start with the tokens in the basket itself
            // These are the tokens held during deposit
            address[] memory assets = BasketToken(baskets[i]).getAssets();

            uint totalAsset = BasketToken(baskets[i]).totalAssets();
            uint sum;

            for(uint j=0; j<assets.length; j++){
    // sum += priceOracle.getQuote(IERC20(assets[j]).balanceOf(baskets[i]), assets[j], BasketToken(baskets[i]).asset());
    sum += priceOracle.getQuote(basketManager.basketBalanceOf(baskets[i], assets[j]), assets[j],
    BasketToken(baskets[i]).asset());
                console.log("added sum", sum);
            }

            console.log("sum final", sum);
            console.log("total asset", totalAsset);

            // Approximate by 1%
            if((sum < totalAsset) && (totalAsset > 0)){
                console.log("diff ", sum  * 100 / totalAsset);
                assert(100 - sum  * 100 / totalAsset <= 1);
            }
            if((sum > totalAsset) && (sum > 0)){
                console.log("diff ", totalAsset  * 100 / sum);
                assert(100 - totalAsset  * 100 / sum  <= 1);
            }
            //assert(totalAsset == sum);
        }

    }*/

    /**
     * @notice Verifies the deposit request asset consistency
     * @custom:preconditions None
     * @custom:action Sum all the assets deposited on a request by all the controllers
     * @custom:postcondition The sum must be equal to totalDepositAssets
     */
    function invariant_deposit_request() public {
        address[] memory baskets = basketManager.basketTokens();

        for (uint256 i = 0; i < baskets.length; i++) {
            uint256 maxDepositRequest = BasketToken(baskets[i]).nextDepositRequestId();

            for (uint256 depositId = 0; depositId <= maxDepositRequest; depositId++) {
                BasketToken.DepositRequestView memory requestView = BasketToken(baskets[i]).getDepositRequest(depositId);

                uint256 totalDepositAsset = requestView.totalDepositAssets;
                if (totalDepositAsset == 0) {
                    continue;
                }

                // Current we can't track easily pending request that are filled
                // Because we can't access _depositRequests directly
                // So we can't see depositRequest.depositAssets[controller]
                if (!(requestView.fulfilledShares == 0 && !requestView.fallbackTriggered)) {
                    continue;
                }

                address[] memory controllers = globalState.get_controller_from_request_id(baskets[i], depositId);

                uint256 sumAsset;
                for (uint256 controllerId = 0; controllerId < controllers.length; controllerId++) {
                    sumAsset += BasketToken(baskets[i]).pendingDepositRequest(depositId, controllers[controllerId]);
                }

                assert(sumAsset == totalDepositAsset);
            }
        }
    }
}
