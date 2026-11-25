import { ErrorCode, McpError } from "./errors.js";

export const TEXT_PARTS = {
  symbols: {
    path: "source/symbols",
    accept: "application/vnd.sap.adt.textelements.symbols.v1",
  },
  selections: {
    path: "source/selections",
    accept: "application/vnd.sap.adt.textelements.selections.v1",
  },
  headings: {
    path: "source/headings",
    accept: "application/vnd.sap.adt.textelements.headings.v1",
  },
} as const;

export type TextKind = keyof typeof TEXT_PARTS;

export interface TextUpdate {
  name?: string;
  text?: string;
}

export function programName(name: unknown): string {
  const value = String(name ?? "").trim().toUpperCase();
  if (!/^[A-Z][A-Z0-9_]{0,39}$/.test(value))
    throw new McpError(ErrorCode.InvalidParams, "Program name is invalid");
  return value;
}

export function textRoot(program: string): string {
  return `/sap/bc/adt/textelements/programs/${program.toLowerCase()}`;
}

export function toCrlf(text: string): string {
  return text.replace(/\r\n/g, "\n").replace(/\n/g, "\r\n");
}

export function parseSymbolSource(source: string) {
  const entries: { name: string; text: string; maxLength: number | null }[] =
    [];
  const lines = source.replace(/\r\n/g, "\n").split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const max = /^@MaxLength:(\d+)$/.exec(lines[index].trim());
    const line = max ? lines[index + 1] || "" : lines[index];
    const matched = /^([A-Z0-9]{1,3})=(.*)$/.exec(line.trim());
    if (!matched) continue;
    entries.push({
      name: matched[1],
      text: matched[2],
      maxLength: max ? Number(max[1]) : null,
    });
    if (max) index += 1;
  }
  return entries;
}

export function parseSelectionSource(source: string) {
  const entries: { name: string; text: string }[] = [];
  for (const line of source.replace(/\r\n/g, "\n").split("\n")) {
    const matched = /^([A-Z][A-Z0-9_]{0,7})\s*=(.*)$/.exec(line.trim());
    if (!matched) continue;
    entries.push({ name: matched[1], text: matched[2] });
  }
  return entries;
}

export function parseHeadingSource(source: string) {
  const entries: { name: string; text: string }[] = [];
  for (const line of source.replace(/\r\n/g, "\n").split("\n")) {
    const matched = /^([A-Za-z][A-Za-z0-9_]{0,30})=(.*)$/.exec(line.trim());
    if (!matched) continue;
    entries.push({ name: matched[1], text: matched[2] });
  }
  return entries;
}

function assertSingleLine(text: string, label: string) {
  if (/[\r\n]/.test(text))
    throw new McpError(
      ErrorCode.InvalidParams,
      `${label} must be a single line`,
    );
}

export function applySymbolUpdates(source: string, updates: TextUpdate[]) {
  let text = source.replace(/\r\n/g, "\n");
  for (const update of updates) {
    const name = String(update.name ?? "").trim().toUpperCase();
    if (!/^[A-Z0-9]{1,3}$/.test(name))
      throw new McpError(
        ErrorCode.InvalidParams,
        `Invalid text symbol name: ${update.name ?? ""}`,
      );
    const value = update.text ?? "";
    assertSingleLine(value, "Text symbol");
    const withMax = new RegExp(`@MaxLength:(\\d+)\\n${name}=.*`);
    if (withMax.test(text)) {
      text = text.replace(withMax, (_, length) => {
        const maxLength = Math.max(Number(length), value.length);
        return `@MaxLength:${maxLength}\n${name}=${value}`;
      });
      continue;
    }
    const plain = new RegExp(`^${name}=.*$`, "m");
    if (plain.test(text)) {
      text = text.replace(plain, () => `${name}=${value}`);
      continue;
    }
    const block = `@MaxLength:${Math.max(value.length, 1)}\n${name}=${value}`;
    text = text.trimEnd();
    text = text.length ? `${text}\n\n${block}` : block;
  }
  return toCrlf(text);
}

export function applySelectionUpdates(source: string, updates: TextUpdate[]) {
  let text = source.replace(/\r\n/g, "\n");
  for (const update of updates) {
    const name = String(update.name ?? "").trim().toUpperCase();
    if (!/^[A-Z][A-Z0-9_]{0,7}$/.test(name))
      throw new McpError(
        ErrorCode.InvalidParams,
        `Invalid selection text name: ${update.name ?? ""}`,
      );
    const value = update.text ?? "";
    assertSingleLine(value, "Selection text");
    const current = new RegExp(`^${name}\\s*=.*$`, "m");
    const line = `${name.padEnd(8, " ")}=${value}`;
    if (current.test(text)) {
      text = text.replace(current, () => line);
      continue;
    }
    text = text.trimEnd();
    text = text.length ? `${text}\n\n${line}` : line;
  }
  return toCrlf(text);
}

export function applyHeadingUpdates(source: string, updates: TextUpdate[]) {
  let text = source.replace(/\r\n/g, "\n");
  for (const update of updates) {
    const name = String(update.name ?? "").trim();
    if (!/^[A-Za-z][A-Za-z0-9_]{0,30}$/.test(name))
      throw new McpError(
        ErrorCode.InvalidParams,
        `Invalid heading name: ${update.name ?? ""}`,
      );
    const value = update.text ?? "";
    assertSingleLine(value, "Heading");
    const current = new RegExp(`^${name}=.*$`, "m");
    if (current.test(text)) {
      text = text.replace(current, () => `${name}=${value}`);
      continue;
    }
    text = text.trimEnd();
    text = text.length ? `${text}\n${name}=${value}` : `${name}=${value}`;
  }
  return toCrlf(text);
}

export const TEXT_APPLY = {
  symbols: applySymbolUpdates,
  selections: applySelectionUpdates,
  headings: applyHeadingUpdates,
};
