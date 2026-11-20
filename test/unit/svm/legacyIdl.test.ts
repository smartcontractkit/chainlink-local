import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { convertLegacyIdl } from "../../../scripts/svm/legacyIdl.ts";

const legacy = {
  version: "0.1.0",
  name: "demo",
  instructions: [
    {
      name: "setRejectAll",
      accounts: [
        { name: "counter", isMut: true, isSigner: false },
        { name: "group", accounts: [{ name: "authority", isMut: false, isSigner: true }] },
      ],
      args: [{ name: "flag", type: "bool" }, { name: "owner", type: "publicKey" }, { name: "msg", type: { defined: "Msg" } }],
    },
  ],
  accounts: [{ name: "Counter", type: { kind: "struct", fields: [{ name: "value", type: "u64" }] } }],
  types: [{ name: "Msg", type: { kind: "struct", fields: [{ name: "ids", type: { vec: { array: ["u8", 32] } } }] } }],
};

describe("convertLegacyIdl", () => {
  const idl = convertLegacyIdl(legacy, "11111111111111111111111111111111");

  it("adds the address and converts accounts, args and types to the 1.x format", () => {
    assert.equal(idl.address, "11111111111111111111111111111111");
    const [instruction] = idl.instructions;
    assert.deepEqual(instruction.accounts, [
      { name: "counter", writable: true, signer: false },
      { name: "group", accounts: [{ name: "authority", writable: false, signer: true }] },
    ]);
    assert.deepEqual(instruction.args.map((arg: { type: unknown }) => arg.type), ["bool", "pubkey", { defined: { name: "Msg" } }]);
    assert.deepEqual(idl.types.map((type: { name: string }) => type.name), ["Msg", "Counter"]);
  });

  it("computes Anchor discriminators from the snake_case name", () => {
    // sha256("global:set_reject_all")[0..8] and sha256("account:Counter")[0..8]
    assert.equal(Buffer.from(idl.instructions[0].discriminator).toString("hex"), "2a5a1e2007638297");
    assert.equal(Buffer.from(idl.accounts[0].discriminator).toString("hex"), "ffb004f5bcfd7c19");
  });

  it("throws on a type the IDL does not define, unless it is supplied", () => {
    const broken = { ...legacy, types: [] };
    assert.throws(() => convertLegacyIdl(broken, "1"), /references type Msg/);
    assert.doesNotThrow(() => convertLegacyIdl(broken, "1", legacy.types));
  });
});
