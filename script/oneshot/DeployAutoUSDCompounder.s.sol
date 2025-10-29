// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console } from "forge-std/console.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { AutopoolCompounder } from "src/compounder/AutopoolCompounder.sol";
import { Constants } from "test/utils/Constants.t.sol";
import { ITokenizedStrategy } from "tokenized-strategy-3.0.4/src/interfaces/ITokenizedStrategy.sol";

contract DeployAutoUSDCompounder is DeployScript, Constants, StdAssertions {
    using DeployerFunctions for Deployer;

    string internal constant _PRODUCTION_KEY = "Production_AutopoolCompounder_autoUSD";
    string internal constant _STAGING_KEY = "Staging_AutopoolCompounder_autoUSD";
    string internal constant _ARTIFACT = "AutopoolCompounder.sol:AutopoolCompounder";

    AutopoolCompounder public compounder;

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

        _verifyDeployment();
    }

    function _verifyDeployment() internal view {
        require(address(compounder) != address(0), "Compounder not initialised");
        require(ITokenizedStrategy(address(compounder)).asset() == TOKEMAK_AUTOUSD, "Incorrect autopool asset");
        require(address(compounder.rewarder()) == TOKEMAK_AUTOUSD_REWARDER, "Incorrect rewarder");
        require(address(compounder.milkman()) == TOKEMAK_MILKMAN, "Incorrect Milkman");

        console.log(unicode"\n✅ Shared AutopoolCompounder configuration verified");
    }
}
