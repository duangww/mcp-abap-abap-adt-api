import fs from "fs";
import path from "path";
import { ADTClient, session_types } from "abap-adt-api";

const mcpPath = path.join(process.env.USERPROFILE, ".cursor", "mcp.json");
const env = JSON.parse(fs.readFileSync(mcpPath, "utf8")).mcpServers["mcp-abap-dev"].env;

const terminalId = "SCRIPT-TERM-YJW-MAKTX";
const ideId = "SCRIPT-IDE-YJW-MAKTX";
const clientId = "bp-yjw-maktx";
const user = String(env.SAP_USER).toUpperCase();
const bp = "/sap/bc/adt/programs/programs/yjw_demo01/source/main#start=39";
const outFile = path.join("scripts", "lv_maktx.out.txt");

const a = new ADTClient(
  env.SAP_URL,
  env.SAP_USER,
  env.SAP_PASSWORD,
  env.SAP_CLIENT,
  env.SAP_LANGUAGE
);
a.stateful = session_types.stateful;

function hexUtf16LeToString(hex) {
  if (!hex) return "";
  const clean = hex.replace(/\s+/g, "");
  const bytes = Buffer.from(clean, "hex");
  return bytes.toString("utf16le");
}

try {
  await a.login();
  try {
    await a.debuggerDeleteListener("user", terminalId, ideId, user);
  } catch {
    /* ignore */
  }

  await a.debuggerSetBreakpoints(
    "user",
    terminalId,
    ideId,
    clientId,
    [bp],
    user,
    "external"
  );
  console.log("BP_OK line=39");
  console.log("WAITING: GUI /hext user = bakkf  then run YJW_DEMO01");

  const hit = await a.debuggerListen("user", terminalId, ideId, user, true, true);
  console.log("HIT", hit.PRG_CURR, "line", hit.LINE_CURR);

  await a.debuggerAttach("user", hit.DEBUGGEE_ID, user);

  const vars = await a.debuggerVariables(["LV_MAKTX"]);
  const v = vars?.[0] || {};
  const fromHex = hexUtf16LeToString(v.HEX_VALUE);
  const value =
    fromHex && fromHex.length >= Number(v.LENGTH || 0)
      ? fromHex
      : v.VALUE || "";

  fs.writeFileSync(outFile, value, "utf8");
  console.log("LV_MAKTX_META", JSON.stringify({
    length: v.LENGTH,
    valueLen: (v.VALUE || "").length,
    hexLen: (v.HEX_VALUE || "").length,
    decodedLen: fromHex.length,
    incomplete: v.IS_VALUE_INCOMPLETE,
    outFile
  }));
  console.log("LV_MAKTX_VALUE");
  console.log(value);

  try {
    await a.debuggerStep("stepContinue");
  } catch (e) {
    console.log("CONTINUE_FAIL", e.message);
  }
  try {
    await a.debuggerDeleteListener("user", terminalId, ideId, user);
  } catch {
    /* ignore */
  }
  console.log("DONE");
} catch (e) {
  console.error("FATAL", e.message || e);
  process.exitCode = 1;
} finally {
  try {
    await a.logout();
  } catch {
    /* ignore */
  }
}
