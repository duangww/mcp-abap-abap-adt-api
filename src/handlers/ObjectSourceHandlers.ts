import { stringify } from "../lib/results.js";
import { McpError, ErrorCode, safeError } from "../lib/errors.js";
import { BaseHandler } from "./BaseHandler.js";
import type { ToolDefinition } from "../types/tools.js";
import { session_types } from "abap-adt-api";
import {
  INLINE_SOURCE_CHARS,
  readLocalSource,
  resolveSourceTarget,
  sourceStats,
  writeLocalSource,
} from "../lib/sourceFiles.js";

const OMITTED_MESSAGE =
  "Source exceeds 12000 characters and was not returned. Call downloadSourceFile with an absolute filePath, then search that local file. Do not request the whole source again.";

export class ObjectSourceHandlers extends BaseHandler {
  getTools(): ToolDefinition[] {
    return [
      {
        name: "getObjectSource",
        description:
          "Retrieves a short ABAP source excerpt. Results longer than 12000 characters are omitted. For a class, program, CDS or any large source, call downloadSourceFile and search the local file instead of this tool.",
        inputSchema: {
          type: "object",
          properties: {
            objectSourceUrl: { type: "string" },
            options: { type: "string" },
            startLine: {
              type: "number",
              description:
                "1-based line number to start from (default 1). Use with maxLines for a short excerpt.",
              optional: true,
            },
            maxLines: {
              type: "number",
              description:
                "Maximum number of lines to return from startLine. Keep this small. Omit only for a short object.",
              optional: true,
            },
          },
          required: ["objectSourceUrl"],
        },
      },
      {
        name: "setObjectSource",
        description:
          "Sets a short ABAP source passed in the source argument. For a class, program or any source that belongs in a file, call uploadSourceFile instead.",
        inputSchema: {
          type: "object",
          properties: {
            objectSourceUrl: { type: "string" },
            source: { type: "string" },
            lockHandle: { type: "string" },
            transport: { type: "string" },
          },
          required: ["objectSourceUrl", "source", "lockHandle"],
        },
      },
      {
        name: "downloadSourceFile",
        description:
          "Download an ABAP object's source to a local absolute file. Returns the path, byte size and line count only, never the source text. After this call, search and read that file with local tools. Use this for classes, programs, includes, interfaces, CDS, BDEF, SRVD and tables.",
        inputSchema: {
          type: "object",
          properties: {
            filePath: {
              type: "string",
              description:
                "Absolute local path to write. An existing file is overwritten.",
            },
            objectUrl: {
              type: "string",
              description: "ADT object URL without /source/main",
              optional: true,
            },
            objectName: {
              type: "string",
              description:
                "ABAP object name. Required with objectKind when objectUrl is omitted.",
              optional: true,
            },
            objectKind: {
              type: "string",
              description:
                "class, program, include, interface, ddls, bdef, srvd or table. Required with objectName when objectUrl is omitted.",
              optional: true,
            },
            sourceUrl: {
              type: "string",
              description:
                "Source URL. Defaults to the object URL plus /source/main.",
              optional: true,
            },
          },
          required: ["filePath"],
        },
      },
      {
        name: "uploadSourceFile",
        description:
          "Read ABAP source from a local absolute file and write it to SAP. Do not put source text in the arguments. Locks, writes and unlocks in this session, then runs a syntax check. Activates only when activate is true and there are no syntax errors. transport is the transport request number, never the task number.",
        inputSchema: {
          type: "object",
          properties: {
            filePath: {
              type: "string",
              description: "Absolute path of the local source file.",
            },
            objectUrl: {
              type: "string",
              description:
                "ADT object URL without /source/main, for example /sap/bc/adt/oo/classes/zcl_example",
              optional: true,
            },
            objectName: {
              type: "string",
              description:
                "ABAP object name. Required with objectKind when objectUrl is omitted.",
              optional: true,
            },
            objectKind: {
              type: "string",
              description:
                "class, program, include, interface, ddls, bdef, srvd or table. Required with objectName when objectUrl is omitted.",
              optional: true,
            },
            sourceUrl: {
              type: "string",
              description:
                "Source URL. Defaults to the object URL plus /source/main.",
              optional: true,
            },
            transport: {
              type: "string",
              description:
                "Transport request number, not the task number. Omit only for objects that do not need a request.",
              optional: true,
            },
            activate: {
              type: "boolean",
              description:
                "Activate after a syntax check with zero errors. Default false.",
              optional: true,
            },
          },
          required: ["filePath"],
        },
      },
    ];
  }

  async handle(toolName: string, args: any): Promise<any> {
    switch (toolName) {
      case "getObjectSource":
        return this.handleGetObjectSource(args);
      case "setObjectSource":
        return this.handleSetObjectSource(args);
      case "downloadSourceFile":
        return this.handleDownloadSourceFile(args);
      case "uploadSourceFile":
        return this.handleUploadSourceFile(args);
      default:
        throw new McpError(
          ErrorCode.MethodNotFound,
          `Unknown object source tool: ${toolName}`,
        );
    }
  }

  async handleGetObjectSource(args: any): Promise<any> {
    const startTime = performance.now();
    try {
      const fullSource = await this.adtclient.getObjectSource(
        args.objectSourceUrl,
        args.options,
      );
      // Remember the source so a later syntaxCheckCode on the same URL can reuse
      // it without the caller re-sending it (issue #2).
      this.sourceCache.set(args.objectSourceUrl, fullSource);
      this.trackRequest(startTime, true);

      const lines = fullSource.split("\n");
      const totalLines = lines.length;

      // Optional pagination for large sources (issue #4). When neither
      // parameter is provided, behaviour is unchanged: the whole source is returned.
      const hasPaging =
        args.startLine !== undefined || args.maxLines !== undefined;
      const startLine = Math.max(1, Number(args.startLine) || 1);
      const startIndex = startLine - 1;
      const endIndex =
        args.maxLines !== undefined
          ? startIndex + Math.max(0, Number(args.maxLines))
          : totalLines;
      const source = hasPaging
        ? lines.slice(startIndex, endIndex).join("\n")
        : fullSource;
      const returnedLines = hasPaging
        ? Math.min(endIndex, totalLines) - startIndex
        : totalLines;
      const body: Record<string, unknown> = {
        status: "success",
        totalLines,
        startLine: hasPaging ? startLine : 1,
        returnedLines: Math.max(0, returnedLines),
        hasMore: hasPaging ? endIndex < totalLines : false,
        ...sourceStats(fullSource),
      };
      if (source.length > INLINE_SOURCE_CHARS) {
        body.omitted = true;
        body.message = OMITTED_MESSAGE;
      } else {
        body.source = source;
      }

      return {
        content: [
          {
            type: "text",
            text: stringify(body),
          },
        ],
      };
    } catch (error: any) {
      this.trackRequest(startTime, false);
      throw error;
    }
  }

  async handleSetObjectSource(args: any): Promise<any> {
    const startTime = performance.now();
    try {
      // dropSession/logout reset the client to stateless; writing source requires a stateful session
      this.adtclient.stateful = session_types.stateful;
      await this.adtclient.setObjectSource(
        args.objectSourceUrl,
        args.source,
        args.lockHandle,
        args.transport,
      );
      // Cache the just-written source so a follow-up syntaxCheckCode can reuse it
      // without the caller re-sending it (issue #2).
      this.sourceCache.set(args.objectSourceUrl, args.source);
      this.trackRequest(startTime, true);
      return {
        content: [
          {
            type: "text",
            text: stringify({
              status: "success",
              updated: true,
            }),
          },
        ],
      };
    } catch (error: any) {
      this.trackRequest(startTime, false);
      throw error;
    }
  }

  async handleDownloadSourceFile(args: any): Promise<any> {
    const startTime = performance.now();
    try {
      const target = resolveSourceTarget(args);
      const source = await this.adtclient.getObjectSource(target.sourceUrl);
      this.sourceCache.set(target.sourceUrl, source);
      const file = await writeLocalSource(args.filePath, source);
      this.trackRequest(startTime, true);
      return {
        content: [
          {
            type: "text",
            text: stringify({
              status: "success",
              filePath: file.full,
              bytes: file.bytes,
              lines: file.lines,
              objectName: target.objectName,
              objectUrl: target.lockUrl,
              sourceUrl: target.sourceUrl,
            }),
          },
        ],
      };
    } catch (error: any) {
      this.trackRequest(startTime, false);
      throw error;
    }
  }

  async handleUploadSourceFile(args: any): Promise<any> {
    const startTime = performance.now();
    const target = resolveSourceTarget(args);
    const source = await readLocalSource(args.filePath);
    const transport = String(args.transport ?? "").trim();
    this.adtclient.stateful = session_types.stateful;
    let handle = "";
    let unlockError = "";
    try {
      const lock = await this.adtclient.lock(target.lockUrl);
      handle = lock.LOCK_HANDLE;
      if (String(lock.MODIFICATION_SUPPORT).toLowerCase() === "false")
        throw new McpError(
          ErrorCode.InvalidParams,
          "Object cannot be modified. Check the transport request and whether the object is read-only.",
        );
      await this.adtclient.setObjectSource(
        target.sourceUrl,
        source.text,
        handle,
        transport || undefined,
      );
      this.sourceCache.set(target.sourceUrl, source.text);
    } catch (error: any) {
      this.trackRequest(startTime, false);
      throw error;
    } finally {
      if (handle) {
        try {
          await this.adtclient.unLock(target.lockUrl, handle);
        } catch (error) {
          unlockError = safeError(error);
        }
      }
    }

    let syntax = null;
    let syntaxError = "";
    try {
      syntax = summarizeSyntax(
        await this.adtclient.syntaxCheck(
          target.sourceUrl,
          target.sourceUrl,
          source.text,
        ),
      );
    } catch (error) {
      syntaxError = safeError(error);
    }

    let activated = false;
    let activation: unknown = null;
    if (args.activate) {
      if (syntaxError || !syntax || syntax.errorCount > 0) {
        activation = {
          success: false,
          skipped: syntaxError
            ? "Syntax check failed, so the object was not activated"
            : "Syntax errors found, so the object was not activated",
        };
      } else {
        try {
          activation = await this.adtclient.activate(
            target.objectName,
            target.lockUrl,
          );
          activated = Boolean(
            activation &&
              typeof activation === "object" &&
              (activation as { success?: boolean }).success,
          );
        } catch (error) {
          activation = { success: false, error: safeError(error) };
        }
      }
    }
    this.trackRequest(startTime, true);
    return {
      content: [
        {
          type: "text",
          text: stringify({
            status: "success",
            filePath: source.full,
            bytes: source.bytes,
            lines: source.lines,
            objectName: target.objectName,
            objectUrl: target.lockUrl,
            sourceUrl: target.sourceUrl,
            transport: transport || null,
            written: true,
            syntax,
            syntaxError: syntaxError || null,
            activated,
            activation,
            unlockError: unlockError || null,
          }),
        },
      ],
    };
  }
}

function summarizeSyntax(messages: unknown) {
  const list = Array.isArray(messages) ? messages : [];
  const errorCount = list.filter((item) =>
    /[EAX]/i.test(String(item?.severity ?? "")),
  ).length;
  return {
    errorCount,
    warningCount: list.length - errorCount,
    messages: list.slice(0, 30).map((item) => ({
      severity: String(item?.severity ?? ""),
      text: String(item?.text ?? ""),
      line: Number(item?.line ?? 0),
      offset: Number(item?.offset ?? 0),
    })),
  };
}
