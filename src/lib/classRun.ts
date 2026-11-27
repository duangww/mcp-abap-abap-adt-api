import type { ADTClient } from "abap-adt-api";
import { ErrorCode, McpError } from "./errors.js";

export async function postClassRun(
  client: ADTClient,
  className: string,
  payload: string,
) {
  const name = className.trim().toUpperCase();
  if (!name) {
    throw new McpError(ErrorCode.InvalidParams, "className is required");
  }
  const headers: Record<string, string> = {
    "Content-Type": "text/plain; charset=utf-8",
  };
  if (payload.length <= 2000 && !/[\r\n]/.test(payload)) {
    headers["x-run-payload"] = payload;
  }
  const qs: Record<string, string> = {};
  if (payload.length <= 1500) {
    qs.payload = payload;
  }
  const response = await client.httpClient.request(
    `/sap/bc/adt/oo/classrun/${name}`,
    { method: "POST", headers, qs, body: payload },
  );
  return parseClassRunResult("" + response.body);
}

export function parseClassRunResult(body: string) {
  const text = body.trim();
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) return text;
  try {
    const value = JSON.parse(text.slice(start, end + 1));
    if (
      value &&
      typeof value === "object" &&
      !Array.isArray(value) &&
      "success" in value &&
      ("rows" in value || "exporting" in value || "function" in value)
    ) {
      return value;
    }
  } catch {
    return text;
  }
  return text;
}

export function abapName(value: unknown, label: string, max: number) {
  const name = String(value ?? "")
    .trim()
    .toUpperCase();
  if (!/^[A-Z][A-Z0-9_/$]*$/.test(name) || name.length > max) {
    throw new McpError(ErrorCode.InvalidParams, `${label} is not a valid ABAP name`);
  }
  return name;
}

export function namedJson(value: unknown) {
  if (value === undefined || value === null) return [];
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new McpError(
      ErrorCode.InvalidParams,
      "Function parameters must be an object of parameter names",
    );
  }
  return Object.entries(value).map(([name, item]) => ({
    name,
    json: JSON.stringify(item ?? null),
  }));
}
