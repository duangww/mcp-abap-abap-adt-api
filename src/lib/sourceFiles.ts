import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { ErrorCode, McpError } from "./errors.js";

/** Tool results stay under this size. Larger sources go to a local file. */
export const INLINE_SOURCE_CHARS = 12000;
export const MAX_SOURCE_BYTES = 2 * 1024 * 1024;

const KIND_URL: Record<string, (name: string) => string> = {
  class: (name) => `/sap/bc/adt/oo/classes/${name}`,
  program: (name) => `/sap/bc/adt/programs/programs/${name}`,
  include: (name) => `/sap/bc/adt/programs/includes/${name}`,
  interface: (name) => `/sap/bc/adt/oo/interfaces/${name}`,
  ddls: (name) => `/sap/bc/adt/ddic/ddl/sources/${name}`,
  bdef: (name) => `/sap/bc/adt/bo/behaviordefinitions/${name}`,
  srvd: (name) => `/sap/bc/adt/ddic/srvd/sources/${name}`,
  table: (name) => `/sap/bc/adt/ddic/tables/${name}`,
};

export interface SourceTarget {
  lockUrl: string;
  sourceUrl: string;
  objectName: string;
}

export function resolveSourceTarget(args: {
  objectUrl?: string;
  objectName?: string;
  objectKind?: string;
  sourceUrl?: string;
}): SourceTarget {
  let lockUrl = String(args.objectUrl ?? "").trim();
  if (!lockUrl) {
    const build = KIND_URL[String(args.objectKind ?? "").toLowerCase()];
    const objectName = String(args.objectName ?? "").trim();
    if (!objectName || !build)
      throw new McpError(
        ErrorCode.InvalidParams,
        "Pass objectUrl, or both objectName and objectKind (class, program, include, interface, ddls, bdef, srvd, table)",
      );
    if (!/^[A-Za-z0-9_/]+$/.test(objectName))
      throw new McpError(
        ErrorCode.InvalidParams,
        "Object name contains unsupported characters",
      );
    lockUrl = build(objectName.toLowerCase());
  }
  lockUrl = lockUrl.split("?")[0];
  let sourceUrl = String(args.sourceUrl ?? "").trim();
  if (lockUrl.endsWith("/source/main")) {
    if (!sourceUrl) sourceUrl = lockUrl;
    lockUrl = lockUrl.slice(0, -"/source/main".length);
  }
  if (!sourceUrl) sourceUrl = `${lockUrl}/source/main`;
  sourceUrl = sourceUrl.split("?")[0];
  for (const url of [lockUrl, sourceUrl]) {
    if (
      !url.startsWith("/sap/bc/adt/") ||
      url.includes("..") ||
      url.includes("\\") ||
      url.includes("//")
    )
      throw new McpError(
        ErrorCode.InvalidParams,
        `Object URL must be a /sap/bc/adt/ path: ${url}`,
      );
  }
  const objectName = lockUrl.split("/").filter(Boolean).pop()!.toUpperCase();
  return { lockUrl, sourceUrl, objectName };
}

export function assertAbsoluteFile(filePath: string): string {
  const raw = String(filePath ?? "").trim();
  if (!raw || !path.isAbsolute(raw))
    throw new McpError(
      ErrorCode.InvalidParams,
      "filePath must be an absolute path",
    );
  const full = path.resolve(raw);
  if (full.includes("\0"))
    throw new McpError(ErrorCode.InvalidParams, "filePath is invalid");
  return full;
}

export async function readLocalSource(filePath: string) {
  const full = assertAbsoluteFile(filePath);
  let info;
  try {
    info = await stat(full);
  } catch {
    throw new McpError(ErrorCode.InvalidParams, `File not found: ${full}`);
  }
  if (!info.isFile())
    throw new McpError(ErrorCode.InvalidParams, "Path is not a file");
  if (info.size > MAX_SOURCE_BYTES)
    throw new McpError(
      ErrorCode.InvalidParams,
      `File exceeds ${MAX_SOURCE_BYTES} bytes`,
    );
  let text = await readFile(full, "utf8");
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  text = text.replace(/\r\n/g, "\n");
  if (Buffer.byteLength(text) > MAX_SOURCE_BYTES)
    throw new McpError(
      ErrorCode.InvalidParams,
      `File exceeds ${MAX_SOURCE_BYTES} bytes`,
    );
  return { full, text, ...sourceStats(text) };
}

export async function writeLocalSource(filePath: string, source: string) {
  const full = assertAbsoluteFile(filePath);
  if (Buffer.byteLength(source) > MAX_SOURCE_BYTES)
    throw new McpError(
      ErrorCode.InvalidParams,
      `Source exceeds ${MAX_SOURCE_BYTES} bytes`,
    );
  await mkdir(path.dirname(full), { recursive: true });
  await writeFile(full, source, "utf8");
  return { full, ...sourceStats(source) };
}

export function sourceStats(source: string) {
  return {
    bytes: Buffer.byteLength(source),
    lines: source.length === 0 ? 0 : source.split(/\r\n|\n|\r/).length,
  };
}
