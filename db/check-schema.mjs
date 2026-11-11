#!/usr/bin/env node
/**
 * db/check-schema.mjs — authoring pipeline step 4.
 *
 * Validates the seed bank against db/schema/question-bank.schema.json with ajv in
 * STRICT mode. This is deliberately separate from db/validate.mjs:
 *
 *   check-schema.mjs  → "is the document shaped correctly?"        (structural)
 *   validate.mjs      → "is the document true and fair?"           (semantic)
 *
 * A schema nobody executes is a wish, and a schema run in lenient mode hides exactly
 * the authoring mistakes worth catching (a `required` on a property you never defined,
 * a `minItems` on something that is not an array).
 *
 * Usage: node db/check-schema.mjs
 */

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const here = dirname(fileURLToPath(import.meta.url));
const schemaPath = resolve(here, "schema/question-bank.schema.json");
const bankPath = resolve(here, "seed/bank.en-ar.v1.json");

const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
const bank = JSON.parse(readFileSync(bankPath, "utf8"));

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);

let validate;
try {
  validate = ajv.compile(schema);
} catch (error) {
  console.error(`✖ schema does not compile: ${error.message}`);
  process.exit(1);
}

if (validate(bank)) {
  console.log(`✓ schema: ${bank.questions.length} questions validate against JSON Schema 2020-12`);
} else {
  console.error("✖ bank rejected by the schema:");
  for (const err of (validate.errors ?? []).slice(0, 20)) {
    console.error(`  ${err.instancePath || "/"} ${err.message} ${JSON.stringify(err.params)}`);
  }
  process.exit(1);
}
