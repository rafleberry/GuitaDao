import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import {
    CONTRACTS,
    EPOCH_LENGTH_IN_BLOCKS,
    FIRST_EPOCH_TIME,
    FIRST_EPOCH_NUMBER,
} from "../constants";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const authorityDeployment = await deployments.get(CONTRACTS.authority);
    const guitaDeployment = await deployments.get(CONTRACTS.guita);
    const sGuitaDeployment = await deployments.get(CONTRACTS.sGuita);
    const gGuitaDeployment = await deployments.get(CONTRACTS.gGuita);

    await deploy(CONTRACTS.staking, {
        from: deployer,
        args: [
            guitaDeployment.address,
            sGuitaDeployment.address,
            gGuitaDeployment.address,
            EPOCH_LENGTH_IN_BLOCKS,
            FIRST_EPOCH_NUMBER,
            FIRST_EPOCH_TIME,
            authorityDeployment.address,
        ],
        log: true,
        skipIfAlreadyDeployed: false,
    });
};

func.tags = [CONTRACTS.staking, "staking"];
func.dependencies = [CONTRACTS.guita, CONTRACTS.sGuita, CONTRACTS.gGuita];

export default func;
