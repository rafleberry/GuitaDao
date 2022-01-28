import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { waitFor } from "../txHelper";
import { CONTRACTS, INITIAL_REWARD_RATE, INITIAL_INDEX, BOUNTY_AMOUNT } from "../constants";
import {
    GuitaAuthority__factory,
    Distributor__factory,
    GuitaERC20Token__factory,
    GuitaStaking__factory,
    SGuita__factory,
    GGUITA__factory,
    GuitaTreasury__factory,
} from "../../types";

// TODO: Shouldn't run setup methods if the contracts weren't redeployed.
const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployments, getNamedAccounts, ethers } = hre;
    const { deployer } = await getNamedAccounts();
    const signer = await ethers.provider.getSigner(deployer);

    const authorityDeployment = await deployments.get(CONTRACTS.authority);
    const guitaDeployment = await deployments.get(CONTRACTS.guita);
    const sGuitaDeployment = await deployments.get(CONTRACTS.sGuita);
    const gGuitaDeployment = await deployments.get(CONTRACTS.gGuita);
    const distributorDeployment = await deployments.get(CONTRACTS.distributor);
    const treasuryDeployment = await deployments.get(CONTRACTS.treasury);
    const stakingDeployment = await deployments.get(CONTRACTS.staking);

    const authorityContract = await GuitaAuthority__factory.connect(
        authorityDeployment.address,
        signer
    );
    const guita = GuitaERC20Token__factory.connect(guitaDeployment.address, signer);
    const sGuita = SGuita__factory.connect(sGuitaDeployment.address, signer);
    const gGuita = GGUITA__factory.connect(gGuitaDeployment.address, signer);
    const distributor = Distributor__factory.connect(distributorDeployment.address, signer);
    const staking = GuitaStaking__factory.connect(stakingDeployment.address, signer);
    const treasury = GuitaTreasury__factory.connect(treasuryDeployment.address, signer);

    // Step 1: Set treasury as vault on authority
    await waitFor(authorityContract.pushVault(treasury.address, true));
    console.log("Setup -- authorityContract.pushVault: set vault on authority");

    // Step 2: Set distributor as minter on treasury
    await waitFor(treasury.enable(8, distributor.address, ethers.constants.AddressZero)); // Allows distributor to mint guita.
    console.log("Setup -- treasury.enable(8):  distributor enabled to mint guita on treasury");

    // Step 3: Set distributor on staking
    await waitFor(staking.setDistributor(distributor.address));
    console.log("Setup -- staking.setDistributor:  distributor set on staking");

    // Step 4: Initialize sGUITA and set the index
    if ((await sGuita.gGUITA()) == ethers.constants.AddressZero) {
        await waitFor(sGuita.setIndex(INITIAL_INDEX)); // TODO
        await waitFor(sGuita.setgGUITA(gGuita.address));
        await waitFor(sGuita.initialize(staking.address, treasuryDeployment.address));
    }
    console.log("Setup -- sguita initialized (index, gguita");

    // Step 5: Set up distributor with bounty and recipient
    await waitFor(distributor.setBounty(BOUNTY_AMOUNT));
    await waitFor(distributor.addRecipient(staking.address, INITIAL_REWARD_RATE));
    console.log("Setup -- distributor.setBounty && distributor.addRecipient");

    // Approve staking contact to spend deployer's GUTIA
    // TODO: Is this needed?
    // await guita.approve(staking.address, LARGE_APPROVAL);
};

func.tags = ["setup"];
func.dependencies = [CONTRACTS.guita, CONTRACTS.sGuita, CONTRACTS.gGuita];

export default func;
