// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import './CrosschainTestBase.sol';

import { LZBridgeTesting }      from 'lib/xchain-helpers/src/testing/bridges/LZBridgeTesting.sol';
import { LZGovBridgeForwarder } from 'lib/xchain-helpers/src/forwarders/LZGovBridgeForwarder.sol';

import { LZGovBridgeCrosschainPayload } from './payloads/LZGovBridgeCrosschainPayload.sol';
import { Deploy }                       from '../deploy/Deploy.sol';

interface IChainLog {
    function getAddress(bytes32) external view returns (address);
}

interface IGovOappSender {
    function owner() external view returns (address);
    function setCanCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget, bool _canCall) external;
}

contract LZGovBridgeCrosschainTest is CrosschainTestBase {

    using DomainHelpers   for *;
    using LZBridgeTesting for *;

    uint32  constant ENDPOINT_ID_AVALANCHE = 30106;

    // Live GovernanceOAppReceiver deployed on Avalanche
    address constant GOV_OAPP_RECEIVER_AVALANCHE = 0x6fdd46947ca6903c8c159d1dF2012Bc7fC5cEeec;

    IChainLog constant chainlog = IChainLog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    address govOappSender;

    address govOappReceiver;

    function deployCrosschainPayload(IPayload targetPayload, address _bridgeReceiver)
        internal override returns (IPayload)
    {
        return IPayload(new LZGovBridgeCrosschainPayload(
            ENDPOINT_ID_AVALANCHE,
            govOappSender,
            _bridgeReceiver,
            targetPayload
        ));
    }

    function setupDomain() internal override {
        mainnet.selectFork();
        govOappSender = chainlog.getAddress("LZ_GOV_SENDER");

        remote = getChain('avalanche').createFork();
        bridge = LZBridgeTesting.createLZBridge(mainnet, remote);

        remote.selectFork();

        // Use the live GovernanceOAppReceiver as-is (its peer already points at govOappSender).
        govOappReceiver = GOV_OAPP_RECEIVER_AVALANCHE;

        // bridgeExecutor will be the next contract deployed on this fork (by CrosschainTestBase.setUp())
        address expectedExecutor = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bridgeReceiver = Deploy.deployLZGovBridgeReceiver({
            govOappReceiver : govOappReceiver,
            srcEid          : LZGovBridgeForwarder.ENDPOINT_ID_ETHEREUM,
            srcAuthority    : L1_SPARK_PROXY,
            executor        : expectedExecutor
        });

        // Configure GovernanceOAppSender on mainnet
        mainnet.selectFork();
        address govOwner = IGovOappSender(govOappSender).owner();
        vm.startPrank(govOwner);
        IGovOappSender(govOappSender).setCanCallTarget(
            L1_SPARK_PROXY,
            ENDPOINT_ID_AVALANCHE,
            bytes32(uint256(uint160(bridgeReceiver))),
            true
        );
        vm.stopPrank();

        vm.deal(L1_SPARK_PROXY, 0.01 ether);
    }

    function relayMessagesAcrossBridge() internal override {
        bridge.relayMessagesToDestination(true, govOappSender, govOappReceiver);
    }

}
