import { session_types } from "abap-adt-api";
import { stringify } from "../lib/results.js";
import { ErrorCode, McpError, safeError } from "../lib/errors.js";
import { BaseHandler } from "./BaseHandler.js";
import type { ToolDefinition } from "../types/tools.js";
import {
  TEXT_APPLY,
  TEXT_PARTS,
  type TextKind,
  type TextUpdate,
  parseHeadingSource,
  parseSelectionSource,
  parseSymbolSource,
  programName,
  textRoot,
  toCrlf,
} from "../lib/programTexts.js";

const KINDS: TextKind[] = ["symbols", "selections", "headings"];

export class ProgramTextHandlers extends BaseHandler {
  getTools(): ToolDefinition[] {
    return [
      {
        name: "readProgramTexts",
        description:
          "Read a program's selection texts, text symbols and list headings. Uses the text-element content types. Do not use getObjectSource for these URLs; that call returns an HTML preview.",
        inputSchema: {
          type: "object",
          properties: {
            program: {
              type: "string",
              description: "Program name, for example ZCOR013",
            },
          },
          required: ["program"],
        },
      },
      {
        name: "writeProgramTexts",
        description:
          "Merge selection texts, text symbols or list headings by name, then activate when something changed. Only the names passed in are updated. transport is the transport request number, never the task number. Do not use this for data-element labels.",
        inputSchema: {
          type: "object",
          properties: {
            program: {
              type: "string",
              description: "Program name, for example ZCOR013",
            },
            symbols: {
              type: "array",
              description: "Text symbols. Name T01 matches TEXT-t01.",
              optional: true,
            },
            selections: {
              type: "array",
              description:
                "Selection texts. Name matches the screen field, for example S_BUKRS.",
              optional: true,
            },
            headings: {
              type: "array",
              description:
                "List headings, for example listHeader or columnHeader_1.",
              optional: true,
            },
            transport: {
              type: "string",
              description:
                "Transport request number, not the task number. Omit only when the object does not need a request.",
              optional: true,
            },
            activate: {
              type: "boolean",
              description:
                "Activate the text element after a real change. Default true.",
              optional: true,
            },
          },
          required: ["program"],
        },
      },
    ];
  }

  async handle(toolName: string, args: any): Promise<any> {
    switch (toolName) {
      case "readProgramTexts":
        return this.finish(await this.readTexts(args.program));
      case "writeProgramTexts":
        return this.finish(await this.writeTexts(args));
      default:
        throw new McpError(
          ErrorCode.MethodNotFound,
          `Unknown program text tool: ${toolName}`,
        );
    }
  }

  private finish(result: unknown) {
    return {
      content: [{ type: "text", text: stringify(result) }],
    };
  }

  private async readPart(root: string, kind: TextKind) {
    const part = TEXT_PARTS[kind];
    const response = await this.adtclient.httpClient.request(
      `${root}/${part.path}`,
      { headers: { Accept: part.accept } },
    );
    const etag = response.headers.etag;
    return {
      body: response.body,
      etag: typeof etag === "string" ? etag : "",
    };
  }

  private async readTexts(programArg: unknown) {
    const program = programName(programArg);
    const root = textRoot(program);
    const meta = await this.adtclient.httpClient.request(root, {
      headers: { Accept: "application/vnd.sap.adt.textelements.v1+xml" },
    });
    const version = /adtcore:version="([^"]*)"/.exec(meta.body)?.[1] || "";
    const symbols = await this.readPart(root, "symbols");
    const selections = await this.readPart(root, "selections");
    const headings = await this.readPart(root, "headings");
    return {
      status: "success",
      program,
      version,
      symbols: parseSymbolSource(symbols.body),
      selections: parseSelectionSource(selections.body),
      headings: parseHeadingSource(headings.body),
    };
  }

  private async writeTexts(args: any) {
    const program = programName(args.program);
    const requested = KINDS.filter(
      (kind) => Array.isArray(args[kind]) && args[kind].length > 0,
    );
    if (!requested.length)
      throw new McpError(
        ErrorCode.InvalidParams,
        "Pass at least one symbols, selections or headings entry",
      );
    const transport = String(args.transport ?? "").trim();
    const root = textRoot(program);
    this.adtclient.stateful = session_types.stateful;
    let handle = "";
    let unlockError = "";
    const written: TextKind[] = [];
    const unchanged: TextKind[] = [];
    try {
      const lock = await this.adtclient.lock(root);
      handle = lock.LOCK_HANDLE;
      if (String(lock.MODIFICATION_SUPPORT).toLowerCase() === "false")
        throw new McpError(
          ErrorCode.InvalidParams,
          "Text elements cannot be modified. Check the transport request and whether the object is read-only.",
        );
      for (const kind of requested) {
        const current = await this.readPart(root, kind);
        const next = TEXT_APPLY[kind](current.body, args[kind] as TextUpdate[]);
        if (next === toCrlf(current.body)) {
          unchanged.push(kind);
          continue;
        }
        const part = TEXT_PARTS[kind];
        await this.adtclient.httpClient.request(`${root}/${part.path}`, {
          method: "PUT",
          qs: {
            lockHandle: handle,
            ...(transport ? { corrNr: transport } : {}),
          },
          headers: {
            Accept: part.accept,
            "Content-Type": `${part.accept}; charset=utf-8`,
            ...(current.etag ? { "If-Match": current.etag } : {}),
          },
          body: next,
        });
        written.push(kind);
      }
    } catch (error) {
      if (handle) unlockError = await this.unlock(root, handle);
      const message = safeError(error);
      throw new McpError(
        error instanceof McpError ? error.code : ErrorCode.InternalError,
        unlockError ? `${message}; unlock failed: ${unlockError}` : message,
      );
    }
    if (handle) unlockError = await this.unlock(root, handle);

    let activated = false;
    let activation: unknown = null;
    if (args.activate !== false && written.length) {
      try {
        activation = await this.adtclient.activate(program, root);
        activated = Boolean(
          activation &&
            typeof activation === "object" &&
            (activation as { success?: boolean }).success,
        );
      } catch (error) {
        activation = { success: false, error: safeError(error) };
      }
    }
    const texts = await this.readTexts(program);
    return {
      ...texts,
      transport: transport || null,
      written,
      unchanged,
      activated,
      activation,
      unlockError: unlockError || null,
    };
  }

  private async unlock(root: string, handle: string) {
    try {
      await this.adtclient.unLock(root, handle);
      return "";
    } catch (error) {
      return safeError(error);
    }
  }
}
