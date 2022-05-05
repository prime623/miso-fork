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
    // Time
    const seconds = 60;
    


    

    // Market and auction
    const AccessControl = await ethers.getContractFactory("VaporAccessControls");
    const accessControl = await AccessControl.deploy();
    const initAC = accessControl.initAccessControls(owner.address);
    const accessAddr = accessControl.address;

    const EnglishAuction = await ethers.getContractFactory("EnglishAuction");
    const englishAuction = await EnglishAuction.deploy();
    await englishAuction.deployed()
    const englishAddr = englishAuction.address;
    console.log(englishAddr);

    const PointList = await ethers.getContractFactory("PointList");
    const pointList = await PointList.deploy();
    await pointList.deployed()
    const pointListAddr = pointList.address;

    const VaporMarket = await ethers.getContractFactory("VaporMarket");
    const vaporMarket = await VaporMarket.deploy();
    const marketAddr = vaporMarket.address;

    // Factory and clone
    const Factory = await ethers.getContractFactory("VaporTokenFactory");
    const factory = await Factory.deploy();
    await factory.deployed();
    const factoryAddr = factory.address;
    
    const MintableToken = await ethers.getContractFactory("MintableToken");
    const mintableToken = await MintableToken.deploy();
    await mintableToken.deployed();
    const mintableTokenAddr = mintableToken.address;
    console.log(mintableTokenAddr);

    const mintData = await mintableToken.getInitData("PrimeNFT", "PRM", owner.address, 10000);
    const initData = await mintableToken.init(mintData);


    const init = await factory.initVaporTokenFactory(accessControl.address);
    
    const newTemplate = factory.addTokenTemplate(mintableTokenAddr);
    const templateId = await factory.getTemplateId(mintableTokenAddr);
    console.log(templateId.toString());
    const tokenTemplate = await factory.getTokenTemplate(templateId);
    console.log(tokenTemplate);
    const setTemplate = await factory.setCurrentTemplateId(1, templateId);
    
    
    const deployToken = await factory.createToken(1, owner.address, mintData);

    const useClone = await ethers.getContractAt("MintableToken", "0x61c36a8d610163660e21a8b7359e1cac0c9133e1", owner );

    const mint = await useClone.mint(owner.address, 1000000);
    const approve = await useClone.approve(englishAddr, 150000);
    const approve2 = await useClone.approve(marketAddr, 150000);
    const bal0 = await useClone.balanceOf(owner.address);
    console.log("owner balance: ", bal0.toString());

    const initMarket = await vaporMarket.initVaporMarket(accessAddr, [englishAddr]);
  

    const timestampBefore = Math.round(Date.now() / 1000) + 16;
    const timestampAfter = Math.round(Date.now() / 1000) + 2*seconds;
    const auctionInitData = await englishAuction.getAuctionInitData(owner.address, 
        "0x61c36a8d610163660e21a8b7359e1cac0c9133e1", 
        10000, 
        timestampBefore, 
        timestampAfter,
        "0x61c36a8d610163660e21a8b7359e1cac0c9133e1",
        1000,
        owner.address,
        pointListAddr,
        owner.address);

    const initData1 = await englishAuction.init(auctionInitData);
  /*  const initAuction = await englishAuction.initAuction(owner.address, 
      "0x61c36a8d610163660e21a8b7359e1cac0c9133e1", 
      10000, 
      timestampBefore, 
      timestampAfter,
      "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      1000,
      owner.address,
      pointListAddr,
      owner.address);*/
      
    const approve3 = useClone.approve("0x856e4424f806d16e8cbc702b3c0f2ede5468eae5", 200000);
    const createMarket = await vaporMarket.createMarket(1, "0x61c36a8d610163660e21a8b7359e1cac0c9133e1", 10000, owner.address, auctionInitData);
   
    const useMarketClone = await ethers.getContractAt("EnglishAuction", "0x856e4424f806d16e8cbc702b3c0f2ede5468eae5", owner);
    
    const commitTokens = await useMarketClone.bidTokens(10000, true);
    
    
});
});