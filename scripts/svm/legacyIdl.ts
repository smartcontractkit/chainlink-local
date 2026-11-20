// Converts an Anchor 0.29 IDL (what the CCIP 1.6 bundle ships) to the format `@anchor-lang/core` 1.x reads.
//
// The 1.x `Program` needs an `address`, explicit 8-byte discriminators and `pubkey` / `{ defined: { name } }`
// types, and finds account layouts in `types`. The `anchor idl convert` CLI does this too; this is the part
// the CCIP programs need (instructions, accounts and types; events and constants are dropped). Names stay
// camelCase, which the 1.x client uses as is; discriminators are computed from the snake_case names the
// on-chain programs hash.

import { createHash } from "node:crypto";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any;

const snakeCase = (name: string): string => name.replace(/[A-Z]/g, (c, i) => (i === 0 ? "" : "_") + c.toLowerCase());

function discriminator(namespace: "global" | "account", name: string): number[] {
  return [...createHash("sha256").update(`${namespace}:${name}`).digest().subarray(0, 8)];
}

function convertType(type: Json): Json {
  if (type === "publicKey") return "pubkey";
  if (typeof type === "string") return type;
  if (type.defined !== undefined) return { defined: { name: type.defined } };
  if (type.vec) return { vec: convertType(type.vec) };
  if (type.option) return { option: convertType(type.option) };
  if (type.array) return { array: [convertType(type.array[0]), type.array[1]] };
  if (type.tuple) return { tuple: type.tuple.map(convertType) };
  throw new Error(`legacyIdl: unsupported type ${JSON.stringify(type)}`);
}

function convertFields(fields: Json[]): Json[] {
  return fields.map((field) => ({ name: field.name, type: convertType(field.type) }));
}

function convertTypeDef(def: Json): Json {
  const { kind } = def.type;
  if (kind === "struct") return { name: def.name, type: { kind, fields: convertFields(def.type.fields) } };
  if (kind === "enum") {
    const variants = def.type.variants.map((variant: Json) => {
      if (!variant.fields) return { name: variant.name };
      // Named fields are objects with a name, tuple fields bare types.
      const named = typeof variant.fields[0] === "object" && "name" in variant.fields[0];
      return { name: variant.name, fields: named ? convertFields(variant.fields) : variant.fields.map(convertType) };
    });
    return { name: def.name, type: { kind, variants } };
  }
  throw new Error(`legacyIdl: unsupported type definition ${def.name}`);
}

function convertAccounts(accounts: Json[]): Json[] {
  return accounts.map((account) =>
    account.accounts
      ? { name: account.name, accounts: convertAccounts(account.accounts) }
      : { name: account.name, writable: !!account.isMut, signer: !!account.isSigner },
  );
}

/**
 * `idl` is the parsed legacy JSON; `address` the program id (legacy IDLs do not carry it). `extraTypes` are
 * legacy-format type definitions the IDL references but Anchor 0.29 left out (types of an external crate).
 * Throws if a referenced type is still undefined, instead of letting `anchor.Program` fail on it later.
 */
export function convertLegacyIdl(idl: Json, address: string, extraTypes: Json[] = []): Json {
  const defined = new Set([...(idl.types ?? []), ...(idl.accounts ?? []), ...extraTypes].map((def: Json) => def.name));
  const check = (node: Json): void => {
    if (!node || typeof node !== "object") return;
    if (typeof node.defined === "string" && !defined.has(node.defined)) {
      throw new Error(`legacyIdl: ${idl.name} references type ${node.defined}, which its IDL does not define`);
    }
    Object.values(node).forEach(check);
  };
  check(idl.instructions);
  check([...(idl.types ?? []), ...(idl.accounts ?? []), ...extraTypes]);
  return {
    address,
    metadata: { name: idl.name, version: idl.version, spec: "0.1.0" },
    instructions: idl.instructions.map((instruction: Json) => ({
      name: instruction.name,
      discriminator: discriminator("global", snakeCase(instruction.name)),
      accounts: convertAccounts(instruction.accounts),
      args: convertFields(instruction.args),
    })),
    accounts: (idl.accounts ?? []).map((account: Json) => ({
      name: account.name,
      discriminator: discriminator("account", account.name),
    })),
    types: [...(idl.types ?? []), ...(idl.accounts ?? []), ...extraTypes].map(convertTypeDef),
    errors: idl.errors ?? [],
  };
}
