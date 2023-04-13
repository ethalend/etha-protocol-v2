import { config } from "dotenv";
import { cleanEnv, str } from "envalid";

config();

export default cleanEnv(process.env, {
  POLYGON_PRIVKEY: str(),
  POLYGON_NODE_URL: str(),
  POLYGON_ETHERSCAN_API: str(),
  MULTISIG_ADDRESS_POLYGON: str(),
  AVAX_PRIVKEY: str(),
  AVAX_NODE_URL: str(),
  AVAX_ETHERSCAN_API: str(),
  MULTISIG_ADDRESS_AVALANCE: str(),
});
