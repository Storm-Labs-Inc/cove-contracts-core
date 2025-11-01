// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console } from "forge-std/console.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { AutopoolCompounder } from "src/compounder/AutopoolCompounder.sol";
import { DynamicSlippageChecker } from "src/deps/milkman/pricecheckers/DynamicSlippageChecker.sol";
import { UniV2ExpectedOutCalculator } from "src/deps/milkman/pricecheckers/UniV2ExpectedOutCalculator.sol";
import { Constants } from "test/utils/Constants.t.sol";
import { ITokenizedStrategy } from "tokenized-strategy-3.0.4/src/interfaces/ITokenizedStrategy.sol";

contract DeployAutoUSDCompounder is DeployScript, Constants, StdAssertions {
    using DeployerFunctions for Deployer;

    string internal constant _PRODUCTION_KEY = "Production_AutopoolCompounder_autoUSD";
    string internal constant _STAGING_KEY = "Staging_AutopoolCompounder_autoUSD";
    string internal constant _ARTIFACT = "AutopoolCompounder.sol:AutopoolCompounder";

    // Price checker stack naming
    string internal constant _PRICE_CHECKER_SUFFIX = "DynamicSlippageChecker_TOKE-USDC";
    string internal constant _EXPECTED_OUT_SUFFIX = "UniV2ExpectedOutCalculator_SushiSwap";
    string internal constant _PRICE_CHECKER_ARTIFACT = "DynamicSlippageChecker.sol:DynamicSlippageChecker";
    string internal constant _EXPECTED_OUT_ARTIFACT = "UniV2ExpectedOutCalculator.sol:UniV2ExpectedOutCalculator";
    string internal constant _SHARED_PREFIX = "Production_";
    string internal constant _LOCAL_PREFIX = "Staging_";
    // Mainnet Sushiswap router (for expected out calculator)
    address internal constant _SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    AutopoolCompounder public compounder;
    DynamicSlippageChecker public priceChecker;
    UniV2ExpectedOutCalculator public expectedOutCalculator;

    function deploy() public {
        deployer.setAutoBroadcast(true);

        console.log("\n==== Deploy Shared AutoUSD AutopoolCompounder ====");

        address existing = deployer.getAddress(_PRODUCTION_KEY);
        if (existing != address(0)) {
            compounder = AutopoolCompounder(existing);
            console.log("AutopoolCompounder already deployed at:", existing);
        } else {
            compounder = deployer.deploy_AutopoolCompounder(
                _PRODUCTION_KEY, TOKEMAK_AUTOUSD, TOKEMAK_AUTOUSD_REWARDER, TOKEMAK_MILKMAN
            );
            console.log("AutopoolCompounder deployed at:", address(compounder));
        }

        if (deployer.getAddress(_STAGING_KEY) == address(0)) {
            deployer.save(_STAGING_KEY, address(compounder), _ARTIFACT);
            console.log("Staging alias saved for AutopoolCompounder");
        } else {
            console.log("Staging alias already present for AutopoolCompounder");
        }

        // Ensure ExpectedOut calculator (shared, with staging alias)
        string memory sharedExpectedOutKey = string.concat(_SHARED_PREFIX, _EXPECTED_OUT_SUFFIX);
        string memory localExpectedOutKey = string.concat(_LOCAL_PREFIX, _EXPECTED_OUT_SUFFIX);
        address expectedOutAddr = deployer.getAddress(sharedExpectedOutKey);
        if (expectedOutAddr == address(0)) {
            expectedOutCalculator = deployer.deploy_UniV2ExpectedOutCalculator(
                sharedExpectedOutKey, "SushiSwap UniV2 ExpectedOut", _SUSHISWAP_ROUTER
            );
            expectedOutAddr = address(expectedOutCalculator);
            console.log("UniV2ExpectedOutCalculator deployed:", expectedOutAddr);
        } else {
            expectedOutCalculator = UniV2ExpectedOutCalculator(expectedOutAddr);
            console.log("UniV2ExpectedOutCalculator reused:", expectedOutAddr);
        }
        if (deployer.getAddress(localExpectedOutKey) == address(0)) {
            deployer.save(localExpectedOutKey, expectedOutAddr, _EXPECTED_OUT_ARTIFACT);
            console.log("Staging alias saved for UniV2ExpectedOutCalculator");
        }

        // Ensure DynamicSlippageChecker (shared, with staging alias)
        string memory sharedPriceCheckerKey = string.concat(_SHARED_PREFIX, _PRICE_CHECKER_SUFFIX);
        string memory localPriceCheckerKey = string.concat(_LOCAL_PREFIX, _PRICE_CHECKER_SUFFIX);
        address checkerAddr = deployer.getAddress(sharedPriceCheckerKey);
        if (checkerAddr == address(0)) {
            priceChecker = deployer.deploy_DynamicSlippageChecker(
                sharedPriceCheckerKey, "SushiSwap TOKE->USDC Dynamic Slippage", address(expectedOutCalculator)
            );
            checkerAddr = address(priceChecker);
            console.log("DynamicSlippageChecker deployed:", checkerAddr);
        } else {
            priceChecker = DynamicSlippageChecker(checkerAddr);
            console.log("DynamicSlippageChecker reused:", checkerAddr);
        }
        if (deployer.getAddress(localPriceCheckerKey) == address(0)) {
            deployer.save(localPriceCheckerKey, checkerAddr, _PRICE_CHECKER_ARTIFACT);
            console.log("Staging alias saved for DynamicSlippageChecker");
        }

        // Configure compounder to use TOKE price checker
        console.log("\n==== Configure Compounder Price Checkers ====");
        // Broadcast as the management account
        vm.broadcast(msg.sender);
        compounder.updatePriceChecker(TOKEMAK_TOKE, checkerAddr);
        console.log("Price checker set for TOKE:", checkerAddr);

        // Broadcast setting the slippage tolerance
        vm.broadcast(msg.sender);
        compounder.setMaxPriceDeviation(500); // 5%
        console.log("Slippage tolerance set to 5%");

        // Configure keeper and emergency admin
        console.log("\n==== Configure Keeper and Emergency Admin ====");
        vm.broadcast(msg.sender);
        ITokenizedStrategy(address(compounder)).setKeeper(PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT);
        console.log("Keeper set:", PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT);

        vm.broadcast(msg.sender);
        ITokenizedStrategy(address(compounder)).setEmergencyAdmin(COVE_OPS_MULTISIG);
        console.log("Emergency admin set:", COVE_OPS_MULTISIG);

        // Transfer management to the shared production community multisig
        vm.broadcast(msg.sender);
        ITokenizedStrategy(address(compounder)).setPendingManagement(COVE_COMMUNITY_MULTISIG);
        console.log("Pending management set to:", COVE_COMMUNITY_MULTISIG);
        // Attempt acceptance
        vm.prank(COVE_COMMUNITY_MULTISIG);
        ITokenizedStrategy(address(compounder)).acceptManagement();

        _verifyDeployment();
    }

    function _verifyDeployment() internal view {
        require(address(compounder) != address(0), "Compounder not initialised");
        require(ITokenizedStrategy(address(compounder)).asset() == TOKEMAK_AUTOUSD, "Incorrect autopool asset");
        require(address(compounder.rewarder()) == TOKEMAK_AUTOUSD_REWARDER, "Incorrect rewarder");
        require(address(compounder.milkman()) == TOKEMAK_MILKMAN, "Incorrect Milkman");
        require(compounder.priceCheckerByToken(TOKEMAK_TOKE) != address(0), "Price checker not set for TOKE");
        require(
            ITokenizedStrategy(address(compounder)).keeper() == PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT, "Keeper not set"
        );
        require(
            ITokenizedStrategy(address(compounder)).emergencyAdmin() == COVE_OPS_MULTISIG, "Emergency admin not set"
        );

        // Validate TOKE->USDC pricing via the price checker stack
        uint256 probeAmountIn = 10_000e18; // 10,000 TOKE (18 decimals)
        uint256 expectedOut = expectedOutCalculator.getExpectedOut(probeAmountIn, TOKEMAK_TOKE, ETH_USDC, bytes(""));
        console.log("10,000 TOKE -> USDC expectedOut: ", expectedOut / 1e6, " USDC");
        require(expectedOut > 0, "TOKE/USDC expectedOut is zero");
        bool priceOk = priceChecker.checkPrice(
            probeAmountIn,
            TOKEMAK_TOKE,
            ETH_USDC,
            0, // feeAmount
            expectedOut,
            abi.encode(uint256(500), bytes("")) // 5% allowed slippage, no extra data
        );
        require(priceOk, "Price checker rejected TOKE->USDC quote");

        console.log(unicode"\n✅ Shared AutopoolCompounder configuration verified");
    }
}
