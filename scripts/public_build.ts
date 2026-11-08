throw new Error(
  "Public builds are disabled until reviewed snapshot builds are restored.",
);
// Compile source-only artifacts separately from signed/installed candidates.
import { dirname, join } from "node:path";
import { hash, root, verifyInputs } from "./check_source.ts";
if (Deno.args.some((arg) => arg !== "public-build" && arg !== "--build")) {
  throw Error("Unknown public-build argument");
}
const selection = JSON.parse(
  await Deno.readTextFile(join(root, "public-source.json")),
);
if (
  selection.schemaVersion !== 1 ||
  selection.releaseStatus !== "source-approved" ||
  !Array.isArray(selection.files) ||
  new Set(selection.files).size !== selection.files.length
) throw Error("Invalid source selection");
type FileRecord = { path: string; mode: number; bytes: number; sha256: string };
async function filesAt(directory: string, prefix = ""): Promise<string[]> {
  const files: string[] = [];
  for await (const file of Deno.readDir(directory)) {
    const path = prefix + file.name;
    if (file.isDirectory) {
      files.push(...await filesAt(join(directory, file.name), path + "/"));
    } else if (file.isFile) files.push(path);
    else throw Error("Nonregular candidate path: " + path);
  }
  return files.sort();
}
async function entry(directory: string, path: string): Promise<FileRecord> {
  if (
    !path || path.startsWith("/") || path.includes("\\") ||
    [...path].some((c) => c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127) ||
    path.split("/").some((p) => !p || p === "." || p === "..")
  ) throw Error("Invalid source path");
  const absolute = join(directory, path);
  const stat = await Deno.lstat(absolute);
  if (!stat.isFile || await Deno.realPath(absolute) !== absolute) {
    throw Error("Source must be a regular file: " + path);
  }
  const data = await Deno.readFile(absolute);
  return {
    path,
    mode: stat.mode! & 0o777,
    bytes: data.length,
    sha256: await hash(data),
  };
}
const externalFonts = (JSON.parse(
  await Deno.readTextFile(join(root, "Resources/Licenses/fonts.json")),
).assets as { path: string }[]).map((a) => a.path).filter((path) =>
  path.startsWith("Resources/Fonts/")
);
await verifyInputs();
const sourceFiles = await Promise.all(
  [...selection.files, ...externalFonts].sort().map((path: string) =>
    entry(root, path)
  ),
);
for (const directory of ["Sources", "Resources", "References"]) {
  const actual = (await filesAt(join(root, directory))).map((path) =>
    directory + "/" + path
  );
  const expected = [...selection.files, ...externalFonts].filter((
    path: string,
  ) => path.startsWith(directory + "/")).sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw Error("Build inputs differ from source selection: " + directory);
  }
}
const sourceSeal = await hash(
  new TextEncoder().encode(JSON.stringify(sourceFiles)),
);
const parent = join(root, "Local/public-build");
await Deno.mkdir(parent, { recursive: true });
if (await Deno.realPath(parent) !== parent) {
  throw Error("Public output must not use symlinks");
}
const output = join(parent, sourceSeal);
const receiptPath = join(output, "BUILD-RECEIPT.json");
const signedPointer = join(root, "Local/latest-build.json");
async function optionalBytes(path: string) {
  try {
    return await Deno.readFile(path);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return null;
    throw error;
  }
}
const signedBefore = await optionalBytes(signedPointer);
const existed = (await optionalBytes(receiptPath)) !== null;
let expectedReceipt: string;
if (!existed) {
  // Retain interrupted copies, but a compiler failure must not reserve a seal.
  try {
    await Deno.lstat(output);
    throw Error("Incomplete candidate retained without overwrite");
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  const result = await new Deno.Command("/bin/bash", {
    cwd: root,
    args: ["scripts/build.sh", "--unsigned"],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) {
    throw Error(
      `Unsigned compilation failed (${result.code})\n${
        new TextDecoder().decode(result.stderr)
      }`,
    );
  }
  const built = JSON.parse(
    await Deno.readTextFile(join(root, "Local/latest-unsigned-build.json")),
  );
  if (
    built.signing !== "unsigned-source-only" ||
    !built.directory.startsWith(join(root, "Local/UnsignedBuilds") + "/") ||
    !/^[0-9a-f-]{36}$/.test(built.directory.split("/").at(-1))
  ) throw Error("Invalid unsigned output pointer");
  await Deno.mkdir(output);
  const files: FileRecord[] = [];
  for (
    const bundle of ["Grant.app", "Grant.bundle", "GrantSetupReference.app"]
  ) {
    for (const path of await filesAt(join(built.directory, bundle))) {
      const relative = bundle + "/" + path;
      if (/GrantSystem(?:Setup|Restore)\.command$/.test(path)) {
        throw Error("Unsigned artifacts must omit activation launchers");
      }
      const file = await entry(built.directory, relative);
      files.push(file);
      const target = join(output, relative);
      await Deno.mkdir(dirname(target), { recursive: true });
      await Deno.writeFile(
        target,
        await Deno.readFile(join(built.directory, relative)),
        { createNew: true, mode: file.mode },
      );
    }
  }
  files.sort((a, b) => a.path.localeCompare(b.path, "en"));
  // Preserve complete code/art/reference notices alongside the compiled artifact.
  for (
    const path of [
      "LICENSE",
      "ARTWORK-LICENSE.md",
      "DEPENDENCIES.md",
      "References/Setup/README.md",
      "References/Setup/provenance.json",
    ]
  ) {
    const relative = "notices/" + path;
    const file = { ...await entry(root, path), path: relative };
    files.push(file);
    const target = join(output, relative);
    await Deno.mkdir(dirname(target), { recursive: true });
    await Deno.writeFile(target, await Deno.readFile(join(root, path)), {
      createNew: true,
      mode: file.mode,
    });
  }
  files.sort((a, b) => a.path.localeCompare(b.path, "en"));
  const artifactSeal = await hash(
    new TextEncoder().encode(JSON.stringify(files)),
  );
  expectedReceipt = JSON.stringify(
    {
      schemaVersion: 1,
      sourceSeal,
      sourceFiles,
      artifactSeal,
      files,
      signing: "unsigned-source-only",
      releaseReady: false,
      limits: selection.limitations,
    },
    null,
    2,
  ) + "\n";
  await Deno.writeTextFile(receiptPath, expectedReceipt, {
    createNew: true,
    mode: 0o644,
  });
} else expectedReceipt = await Deno.readTextFile(receiptPath);
if (await Deno.realPath(output) !== output) {
  throw Error("Public candidate must not be a symlink");
}
const receipt = JSON.parse(expectedReceipt);
if (
  receipt.schemaVersion !== 1 || receipt.sourceSeal !== sourceSeal ||
  receipt.signing !== "unsigned-source-only" ||
  receipt.releaseReady !== false ||
  JSON.stringify(receipt.sourceFiles) !== JSON.stringify(sourceFiles) ||
  JSON.stringify(receipt.limits) !== JSON.stringify(selection.limitations)
) throw Error("Build receipt metadata differs");
if (
  receipt.artifactSeal !==
    await hash(new TextEncoder().encode(JSON.stringify(receipt.files)))
) throw Error("Artifact receipt seal differs");
const expected = [
  ...receipt.files.map((file: FileRecord) => file.path),
  "BUILD-RECEIPT.json",
].sort();
if (JSON.stringify(await filesAt(output)) !== JSON.stringify(expected)) {
  throw Error("Candidate file collection differs");
}
for (const file of receipt.files as FileRecord[]) {
  if (/GrantSystem(?:Setup|Restore)\.command$/.test(file.path)) {
    throw Error("Unsigned artifacts must omit activation launchers");
  }
  const payload = await Deno.readFile(join(output, file.path));
  if (new TextDecoder().decode(payload).includes(root)) {
    throw Error("Candidate includes private checkout path: " + file.path);
  }
  if (JSON.stringify(await entry(output, file.path)) !== JSON.stringify(file)) {
    throw Error("Candidate readback differs: " + file.path);
  }
}
if (await Deno.readTextFile(receiptPath) !== expectedReceipt) {
  throw Error("Receipt readback differs");
}
// Inspect binaries and plist metadata only; never load or execute these artifacts.
for (
  const [bundle, executable, identifier] of [
    ["Grant.app", "GrantPreview", "com.alex.Grant.Preview"],
    ["Grant.bundle", "Grant", "com.alex.Grant.AuthorizationPlugin"],
    [
      "GrantSetupReference.app",
      "GrantSetupReference",
      "com.alex.Grant.SetupOriginal",
    ],
    [
      "Grant.app/Contents/Resources/Original/GrantSetupReference.app",
      "GrantSetupReference",
      "com.alex.Grant.SetupOriginal",
    ],
  ]
) {
  const binary = await Deno.readFile(
    join(output, bundle, "Contents/MacOS", executable),
  );
  const view = new DataView(
    binary.buffer,
    binary.byteOffset,
    binary.byteLength,
  );
  if (
    view.getUint32(0, true) !== 0xfeedfacf ||
    view.getUint32(4, true) !== 0x0100000c
  ) throw Error("Expected arm64 Mach-O: " + bundle);
  let offset = 32;
  for (let i = 0; i < view.getUint32(16, true); i++) {
    const command = view.getUint32(offset, true),
      size = view.getUint32(offset + 4, true);
    if (command === 0x1d) {
      throw Error("Unsigned artifact contains a code signature: " + bundle);
    }
    if (size < 8 || offset + size > binary.length) {
      throw Error("Invalid Mach-O command");
    }
    offset += size;
  }
  const info = await new Deno.Command("/usr/bin/plutil", {
    args: [
      "-convert",
      "json",
      "-o",
      "-",
      join(output, bundle, "Contents/Info.plist"),
    ],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!info.success) throw Error("Invalid bundle metadata");
  const metadata = JSON.parse(new TextDecoder().decode(info.stdout));
  if (
    metadata.CFBundleIdentifier !== identifier ||
    metadata.CFBundleExecutable !== executable ||
    metadata.CFBundleShortVersionString !== "0.2.3" ||
    metadata.CFBundleVersion !== "7"
  ) throw Error("Bundle identity/version differs: " + bundle);
}
for (const bundle of ["Grant.app", "Grant.bundle"]) {
  for (
    const source of sourceFiles.filter((f) => f.path.startsWith("Resources/"))
  ) {
    const relative = source.path.slice("Resources/".length);
    if (
      await hash(
        await Deno.readFile(
          join(output, bundle, "Contents/Resources", relative),
        ),
      ) !== source.sha256
    ) throw Error("Bundled resource differs: " + relative);
  }
}

const signedAfter = await optionalBytes(signedPointer);
if (
  (signedBefore === null) !== (signedAfter === null) ||
  (signedBefore && signedAfter &&
    await hash(signedBefore) !== await hash(signedAfter))
) throw Error("Signed candidate pointer changed unexpectedly");
console.log(JSON.stringify({
  sourceSeal,
  artifactSeal: receipt.artifactSeal,
  files: receipt.files.length,
  output: "Local/public-build/" + sourceSeal,
  readback: "exact",
  existing: existed,
  signedPointer: "unchanged",
  releaseReady: false,
}));
