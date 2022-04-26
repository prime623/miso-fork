import { ethers } from "hardhat";
import { Signer } from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";

describe("Lpad", function () {
  let accounts: Signer[];
  let owner: SignerWithAddress;

  beforeEach(async function () {
    [owner, ...accounts] = await ethers.getSigners();
  });

  it("deploy", async function () {
  
    // contract deployment and saving the addresses
    const AccessControl = await ethers.getContractFactory("MISOAccessControls");
    const accessControl = await AccessControl.deploy();
    const initAC = accessControl.initAccessControls(owner.address);

    const Factory = await ethers.getContractFactory("MISOTokenFactory");
    const factory = await Factory.deploy();
    await factory.deployed();
    const factoryAddr = factory.address;
    const Erc721 = await ethers.getContractFactory("ERC721");
    const erc721 = await Erc721.deploy("this", "TH");
    await erc721.deployed();
    const erc721Addr = erc721.address;
    console.log(erc721Addr);


    const init = await factory.initMISOTokenFactory(accessControl.address);
    
    const newTemplate = factory.addTokenTemplate(erc721Addr);
    const templateId = await factory.getTemplateId(erc721Addr);
    console.log(templateId.toString());
    const tokenTemplate = await factory.getTokenTemplate(0);
    console.log(tokenTemplate);
    
    const deployToken = await factory.createToken(templateId, owner.address, "0x");
    
});
});