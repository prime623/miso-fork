import { ethers } from "hardhat";
import { Signer } from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import { AbiCoder } from "ethers/lib/utils";

describe("Lpad", function () {
  let accounts: Signer[];
  let owner: SignerWithAddress;

  beforeEach(async function () {
    [owner, ...accounts] = await ethers.getSigners();
  });

  it("deploy", async function () {
  
    // contract deployment and saving the addresses
    const AccessControl = await ethers.getContractFactory("VaporAccessControls");
    const accessControl = await AccessControl.deploy();
    const initAC = accessControl.initAccessControls(owner.address);

    const Factory = await ethers.getContractFactory("VaporTokenFactory");
    const factory = await Factory.deploy();
    await factory.deployed();
    const factoryAddr = factory.address;
    const Erc721 = await ethers.getContractFactory("MintableToken");
    const erc721 = await Erc721.deploy();
    await erc721.deployed();
    const erc721Addr = erc721.address;
    console.log(erc721Addr);

    const mintData = await erc721.getInitData("PrimeNFT", "PRM", owner.address, 10000);
    const initData = await erc721.init(mintData);


    const init = await factory.initVaporTokenFactory(accessControl.address);
    
    const newTemplate = factory.addTokenTemplate(erc721Addr);
    const templateId = await factory.getTemplateId(erc721Addr);
    console.log(templateId.toString());
    const tokenTemplate = await factory.getTokenTemplate(templateId);
    console.log(tokenTemplate);
    const setTemplate = await factory.setCurrentTemplateId(1, templateId);
    
    
    const deployToken = await factory.createToken(1, owner.address, mintData);

    const useClone = await ethers.getContractAt("MintableToken", "0x75537828f2ce51be7289709686a69cbfdbb714f1", owner );

    const mint = await useClone.mint(owner.address, 100000);
    const bal = await useClone.balanceOf(owner.address);
    console.log(bal);
    const burn = await useClone.burn(500);
    const bal1 = await useClone.balanceOf(owner.address);
    console.log(bal1);
    
});
});