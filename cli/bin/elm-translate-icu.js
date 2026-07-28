#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const USAGE = `elm-translate-icu — generate a type-safe Elm module from ICU MessageFormat translations

Usage:
  elm-translate-icu <master.json> --module <ModuleName> [--output <file>]

Arguments:
  <master.json>          Master-language translations: a JSON object mapping keys
                         to ICU message strings. Nested objects are flattened
                         with dots (e.g. { "inbox": { "count": "..." } } becomes
                         key "inbox.count").

Options:
  --module <name>        Fully-qualified module name to generate (required),
                         e.g. Translations or App.I18n.
  --output <file>, -o    Where to write the generated .elm file. Defaults to
                         <ModuleName segments>.elm in the current directory.
  --stdout               Write the generated source to stdout instead of a file.
  --help, -h             Show this help.

Exit codes:
  0  success
  1  usage error
  2  one or more messages failed to parse as ICU
`;

function fail(message, code) {
  process.stderr.write(message + "\n");
  process.exit(code == null ? 1 : code);
}

function parseArgs(argv) {
  const opts = { input: null, moduleName: null, output: null, toStdout: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      process.stdout.write(USAGE);
      process.exit(0);
    } else if (arg === "--module") {
      opts.moduleName = argv[++i];
    } else if (arg === "--output" || arg === "-o") {
      opts.output = argv[++i];
    } else if (arg === "--stdout") {
      opts.toStdout = true;
    } else if (arg.startsWith("-")) {
      fail(`Unknown option: ${arg}\n\n${USAGE}`, 1);
    } else if (opts.input === null) {
      opts.input = arg;
    } else {
      fail(`Unexpected argument: ${arg}`, 1);
    }
  }
  return opts;
}

// Flatten a nested JSON object into dotted-key -> string pairs, preserving the
// document order. Rejects non-string leaves so misconfigured files fail loudly.
function flatten(obj, prefix, out) {
  for (const key of Object.keys(obj)) {
    const value = obj[key];
    const full = prefix ? `${prefix}.${key}` : key;
    if (typeof value === "string") {
      out[full] = value;
    } else if (value && typeof value === "object" && !Array.isArray(value)) {
      flatten(value, full, out);
    } else {
      fail(`Value at "${full}" is not a string or object (got ${typeof value}).`, 1);
    }
  }
  return out;
}

function moduleToPath(moduleName) {
  return moduleName.split(".").join("/") + ".elm";
}

function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (!opts.input) fail(`Missing <master.json>.\n\n${USAGE}`, 1);
  if (!opts.moduleName) fail(`Missing --module.\n\n${USAGE}`, 1);

  let raw;
  try {
    raw = fs.readFileSync(opts.input, "utf8");
  } catch (e) {
    fail(`Could not read ${opts.input}: ${e.message}`, 1);
  }

  let json;
  try {
    json = JSON.parse(raw);
  } catch (e) {
    fail(`${opts.input} is not valid JSON: ${e.message}`, 1);
  }
  if (!json || typeof json !== "object" || Array.isArray(json)) {
    fail(`${opts.input} must contain a JSON object at the top level.`, 1);
  }

  const pairs = flatten(json, "", {});

  const { Elm } = require(path.join(__dirname, "..", "worker.js"));
  const app = Elm.Worker.init({
    flags: { moduleName: opts.moduleName, pairs },
  });

  app.ports.generated.subscribe((result) => {
    if (!result.ok) {
      const lines = result.errors
        .map((e) => `  ${e.key}: ${e.message}`)
        .join("\n");
      fail(`Failed to parse ${result.errors.length} message(s):\n${lines}`, 2);
    }

    if (opts.toStdout) {
      process.stdout.write(result.source);
      process.exit(0);
    }

    const outPath = opts.output || moduleToPath(opts.moduleName);
    try {
      fs.mkdirSync(path.dirname(outPath), { recursive: true });
      fs.writeFileSync(outPath, result.source);
    } catch (e) {
      fail(`Could not write ${outPath}: ${e.message}`, 1);
    }
    process.stdout.write(`Generated ${opts.moduleName} → ${outPath}\n`);
    process.exit(0);
  });
}

main();
