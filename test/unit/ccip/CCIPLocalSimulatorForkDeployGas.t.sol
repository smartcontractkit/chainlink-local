// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";

/// @dev Deploys the simulator from inside an external call, so the CREATE can be given a hard gas budget.
contract CCIPLocalSimulatorForkDeployer {
    function deploy() external returns (address) {
        return address(new CCIPLocalSimulatorFork());
    }
}

/// @dev The documented setup is `vm.createSelectFork(...)` followed by `new CCIPLocalSimulatorFork()`, so the deployment
///      runs under the forked chain's block gas limit. Many chains cap blocks at 30M gas, so the simulator must deploy
///      well below that.
contract CCIPLocalSimulatorForkDeployGasTest is Test {
    /// @dev Leaves headroom below 30M-gas-limit chains.
    uint256 internal constant DEPLOY_GAS_BUDGET = 24_000_000;

    /// @dev Enforced with a hard gas cap on the CREATE: forge does not meter the gas of a large CREATE reliably through
    ///      `gasleft()` or `vm.lastCallGas`, but it does enforce a gas cap.
    function test_deploy_succeedsWithinBudget() public {
        CCIPLocalSimulatorForkDeployer deployer = new CCIPLocalSimulatorForkDeployer();
        address simulator = deployer.deploy{gas: DEPLOY_GAS_BUDGET}();
        assertTrue(simulator.code.length > 0);
    }

    /// @dev Reports the actual deployment cost (smallest gas cap that succeeds), for the release notes.
    function test_logDeployGas() public {
        CCIPLocalSimulatorForkDeployer deployer = new CCIPLocalSimulatorForkDeployer();
        uint256 low = 1_000_000;
        uint256 high = 60_000_000;
        while (high - low > 50_000) {
            uint256 mid = (low + high) / 2;
            try deployer.deploy{gas: mid}() {
                high = mid;
            } catch {
                low = mid;
            }
        }
        emit log_named_uint("CCIPLocalSimulatorFork deploy gas (upper bound, +-50k)", high);
    }

    /// @dev Same condition as deploying after `createSelectFork` on a chain with a 30M block gas limit.
    function test_deploy_succeedsWithin30MGas() public {
        CCIPLocalSimulatorForkDeployer deployer = new CCIPLocalSimulatorForkDeployer();
        address simulator = deployer.deploy{gas: 30_000_000}();
        assertTrue(simulator.code.length > 0);
    }

    /// @dev Network details must still be available after the size reduction.
    function test_networkDetails_availableAfterDeploy() public {
        CCIPLocalSimulatorFork simulator = new CCIPLocalSimulatorFork();
        assertEq(simulator.getNetworkDetails(11155111).chainSelector, 16015286601757825753);
        assertEq(simulator.getNetworkDetails(11155111).routerAddress, 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59);
        assertEq(simulator.getNetworkDetails(1).chainSelector, 5009297550715157269);
    }
}
