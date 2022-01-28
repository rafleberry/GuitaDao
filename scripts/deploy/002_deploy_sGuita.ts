import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { CONTRACTS } from "../constants";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    await deploy(CONTRACTS.sGuita, {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: false,
    });
};

func.tags = [CONTRACTS.guita, "staking", "tokens"];
export default func;
