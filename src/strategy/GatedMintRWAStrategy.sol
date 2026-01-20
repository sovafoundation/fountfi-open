// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {GatedMintRWA} from "../token/GatedMintRWA.sol";
import {ReportedStrategy} from "./ReportedStrategy.sol";
/**
 * @title GatedMintReportedStrategy
 * @notice Extension of ReportedStrategy that deploys and configures GatedMintRWA tokens
 */

contract GatedMintReportedStrategy is ReportedStrategy {
    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy a new GatedMintRWA token
     * @param name_ Name of the token
     * @param symbol_ Symbol of the token
     * @param asset_ Address of the underlying asset
     * @param assetDecimals_ Decimals of the asset
     */
    function _deployToken(string calldata name_, string calldata symbol_, address asset_, uint8 assetDecimals_)
        internal
        virtual
        override
        returns (address)
    {
        GatedMintRWA newToken = new GatedMintRWA(name_, symbol_, asset_, assetDecimals_, address(this));

        return address(newToken);
    }
}
