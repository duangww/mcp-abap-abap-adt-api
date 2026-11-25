import { test } from "node:test";
import assert from "node:assert/strict";
import {
  applyHeadingUpdates,
  applySelectionUpdates,
  applySymbolUpdates,
  parseHeadingSource,
  parseSelectionSource,
  parseSymbolSource,
} from "../src/lib/programTexts.js";

const symbols = "@MaxLength:14\r\nT01=选择条件\r\n\r\n@MaxLength:40\r\nT02=功能选择";
const selections = "P_DET   =完工工单成本明细\r\n\r\nS_BUKRS =公司代码";

test("program text sources parse symbols, selections and headings", () => {
  assert.deepEqual(parseSymbolSource(symbols), [
    { name: "T01", text: "选择条件", maxLength: 14 },
    { name: "T02", text: "功能选择", maxLength: 40 },
  ]);
  assert.deepEqual(parseSelectionSource(selections), [
    { name: "P_DET", text: "完工工单成本明细" },
    { name: "S_BUKRS", text: "公司代码" },
  ]);
  assert.deepEqual(parseHeadingSource("listHeader=\r\n\r\ncolumnHeader_1=\r\n"), [
    { name: "listHeader", text: "" },
    { name: "columnHeader_1", text: "" },
  ]);
});

test("unchanged program texts are not rewritten", () => {
  assert.equal(
    applySymbolUpdates(symbols, [{ name: "t01", text: "选择条件" }]),
    symbols,
  );
  assert.equal(
    applySelectionUpdates(selections, [{ name: "s_bukrs", text: "公司代码" }]),
    selections,
  );
});

test("symbol updates keep the larger max length and append new names", () => {
  const updated = applySymbolUpdates(symbols, [
    { name: "T01", text: "新的选择条件" },
  ]);
  assert.match(updated, /@MaxLength:14\r\nT01=新的选择条件/);
  assert.match(updated, /@MaxLength:40\r\nT02=功能选择/);
  const longer = "X".repeat(41);
  const raised = applySymbolUpdates(symbols, [{ name: "T02", text: longer }]);
  assert.match(
    raised,
    new RegExp(`@MaxLength:${longer.length}\\r\\nT02=${longer}`),
  );
  const withSymbol = applySymbolUpdates(symbols, [
    { name: "T03", text: "金额$1" },
  ]);
  assert.match(withSymbol, /@MaxLength:4\r\nT03=金额\$1$/);
  const withSelection = applySelectionUpdates(selections, [
    { name: "S_AUFNR", text: "SAP工单号" },
  ]);
  assert.match(withSelection, /S_AUFNR =SAP工单号$/);
  const withHeading = applyHeadingUpdates(
    "listHeader=\r\ncolumnHeader_1=\r\n",
    [{ name: "columnHeader_1", text: "公司代码" }],
  );
  assert.equal(withHeading, "listHeader=\r\ncolumnHeader_1=公司代码\r\n");
});
