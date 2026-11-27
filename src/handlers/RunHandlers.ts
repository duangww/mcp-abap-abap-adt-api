import { stringify } from "../lib/results.js";
import { BaseHandler } from "./BaseHandler.js";
import type { ToolDefinition } from "../types/tools.js";
import {
  abapName,
  namedJson,
  postClassRun,
} from "../lib/classRun.js";
import { ErrorCode, McpError } from "../lib/errors.js";

export class RunHandlers extends BaseHandler {
  getTools(): ToolDefinition[] {
    return [
      {
        name: "runReport",
        description:
          "Run a classic report through ZCL_RUN_REPORT and return JSON rows for checking the output. variant and selection values are those of this MCP connection; use QAS unless another system is requested. Example: report ZCOR013, variant NONE_COST. Optional params override the variant. max_rows defaults to 100 and cannot exceed 500.",
        inputSchema: {
          type: "object",
          properties: {
            report: {
              type: "string",
              description: "Report name, for example ZCOR013",
            },
            variant: {
              type: "string",
              description: "Selection variant, for example NONE_COST",
              optional: true,
            },
            params: {
              type: "array",
              description:
                "Selection values. selname is the screen field, low and high are the external values.",
              optional: true,
            },
            max_rows: {
              type: "number",
              description: "Maximum rows returned. Default 100, maximum 500.",
              optional: true,
            },
          },
          required: ["report"],
        },
      },
      {
        name: "runFunction",
        description:
          "Run a function module through ZCL_RUN_FUNCTION and return exporting, changing and tables as JSON. Prefer variant: an SE37 test-data-directory title or number saved in SAP GUI. Optional importing/changing/tables objects keyed by parameter name can supply or override values. Variants belong to this MCP connection; use QAS unless another system is requested. The call runs with the logged-on user and can change data.",
        inputSchema: {
          type: "object",
          properties: {
            functionName: {
              type: "string",
              description: "Function module name, for example ZRFC_ACCOUNTING_DOCUMENT",
            },
            variant: {
              type: "string",
              description:
                "SE37 test data directory entry: title or number saved under 测试数据目录",
              optional: true,
            },
            importing: {
              type: "object",
              description: "Importing parameters by name. Overrides matching values from variant.",
              optional: true,
            },
            changing: {
              type: "object",
              description: "Changing parameters by name. Overrides matching values from variant.",
              optional: true,
            },
            tables: {
              type: "object",
              description:
                "Tables parameters by name. Each value is an array of rows. Overrides matching values from variant.",
              optional: true,
            },
          },
          required: ["functionName"],
        },
      },
    ];
  }

  async handle(toolName: string, args: any): Promise<any> {
    switch (toolName) {
      case "runReport":
        return this.finish(await this.runReport(args));
      case "runFunction":
        return this.finish(await this.runFunction(args));
      default:
        throw new Error(`Unknown run tool: ${toolName}`);
    }
  }

  private finish(result: unknown) {
    return {
      content: [{ type: "text", text: stringify({ status: "success", result }) }],
    };
  }

  private async runReport(args: any) {
    const report = abapName(args.report, "report", 40);
    const payload: Record<string, unknown> = { report };
    if (args.variant) payload.variant = abapName(args.variant, "variant", 14);
    if (args.params !== undefined) payload.params = args.params;
    if (args.max_rows !== undefined) payload.max_rows = args.max_rows;
    return postClassRun(
      this.adtclient,
      "ZCL_RUN_REPORT",
      JSON.stringify(payload),
    );
  }

  private async runFunction(args: any) {
    const payload: Record<string, unknown> = {
      function: abapName(args.functionName, "functionName", 30),
      importing: namedJson(args.importing),
      changing: namedJson(args.changing),
      tables: namedJson(args.tables),
    };
    if (args.variant !== undefined && args.variant !== null && `${args.variant}`.trim()) {
      const variant = `${args.variant}`.trim();
      if (variant.length > 40) {
        throw new McpError(ErrorCode.InvalidParams, "variant is too long");
      }
      payload.variant = variant;
    }
    return postClassRun(
      this.adtclient,
      "ZCL_RUN_FUNCTION",
      JSON.stringify(payload),
    );
  }
}
