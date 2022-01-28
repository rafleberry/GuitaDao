import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { CONTRACTS } from "../constants";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const sGuitaDeployment = await deployments.get(CONTRACTS.sGuita);
    const migratorDeployment = await deployments.get(CONTRACTS.migrator);

    await deploy(CONTRACTS.gGuita, {
        from: deployer,
        args: [migratorDeployment.address, sGuitaDeployment.address],
        log: true,
        skipIfAlreadyDeployed: false,
    });
};

func.tags = [CONTRACTS.gGuita, "migration", "tokens"];
func.dependencies = [CONTRACTS.migrator];

export default func;
