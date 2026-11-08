// Local review/export of the explicitly selected Git index, never Git history.
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
const root = dirname(dirname(fileURLToPath(import.meta.url)));
const args = Deno.args[0] === "public-prepare"
  ? ["--prepare", ...Deno.args.slice(1)]
  : Deno.args[0] === "public-check"
  ? Deno.args.slice(1)
  : Deno.args;
const exportCandidate = args.includes("--prepare");
const buildCandidate = args.length === 1 &&
  (args[0] === "--build" || args[0] === "public-build");
if (!buildCandidate && args.some((arg) => arg !== "--prepare")) {
  throw Error("Unknown argument");
}
async function git(...args: string[]): Promise<Uint8Array> {
  const result = await new Deno.Command("git", {
    cwd: root,
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) throw Error(`Git index read failed (${args[0]})`);
  return result.stdout;
}
const decode = (b: Uint8Array) => new TextDecoder().decode(b);
const hash = async (b: Uint8Array) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", Uint8Array.from(b)))]
    .map((n) => n.toString(16).padStart(2, "0")).join("");
// The hash is changed only as part of a review of the complete selection.
// The running helper itself must match the staged regular file; like any local
// tool, its code and the embedded anchor must be reviewed before trusting it.
const reviewHash =
  "8a15c4ea73ff7f24aaff6247f0ff2ab0edf7e72984619d4bf3990cca5404067a";
const sidecarPath = "scripts/source-review-hashes.json";
const helperPath = "scripts/public_prepare.ts";
const indexText = decode(await git("ls-files", "--stage", "-z"));
const indexed = new Map<string, { mode: string; oid: string }>();
for (const line of indexText.split("\0").filter(Boolean)) {
  const match = /^(100644|100755) ([0-9a-f]{40,64}) 0\t([^\0]+)$/.exec(line);
  if (!match || indexed.has(match[3])) throw Error("Invalid index entry");
  indexed.set(match[3], { mode: match[1], oid: match[2] });
}
async function reviewedBytes(path: string): Promise<Uint8Array> {
  const item = indexed.get(path);
  if (!item) throw Error(`Unreviewed index path: ${path}`);
  const absolute = join(root, path);
  const stat = await Deno.lstat(absolute);
  if (
    !stat.isFile || stat.isSymlink ||
    await Deno.realPath(absolute) !== absolute ||
    ((stat.mode ?? 0) & 0o111 ? "100755" : "100644") !== item.mode
  ) {
    throw Error(`Unreviewed worktree path: ${path}`);
  }
  const data = await git("cat-file", "blob", item.oid);
  if (await hash(await Deno.readFile(absolute)) !== await hash(data)) {
    throw Error(`Worktree differs from reviewed index: ${path}`);
  }
  return data;
}
const sidecar = await reviewedBytes(sidecarPath);
if (await hash(sidecar) !== reviewHash) throw Error("Review anchor differs");
const pins = JSON.parse(decode(sidecar)) as Record<
  string,
  { mode: string; sha256: string }
>;
const helperBytes = await reviewedBytes(helperPath);
if (
  await hash(helperBytes) !==
    await hash(await Deno.readFile(new URL(import.meta.url)))
) {
  throw Error("Executing helper differs from index");
}
const selectedConfig = JSON.parse(
  decode(await reviewedBytes("public-source.json")),
);
const selected = selectedConfig.files as string[];
if (
  !Array.isArray(selected) || new Set(selected).size !== selected.length ||
  JSON.stringify([...selected].sort()) !==
    JSON.stringify([...Object.keys(pins), sidecarPath].sort())
) {
  throw Error("Selection differs from reviewed inputs");
}
for (const [path, pin] of Object.entries(pins)) {
  const item = indexed.get(path);
  if (
    !item || item.mode !== pin.mode || !/^[a-f0-9]{64}$/.test(pin.sha256) ||
    await hash(
        path === helperPath
          ? new TextEncoder().encode(
            decode(await reviewedBytes(path)).replace(
              /(const reviewHash =\s*")[a-f0-9]{64}(";)/,
              "$1" + "0".repeat(64) + "$2",
            ),
          )
          : await reviewedBytes(path),
      ) !== pin.sha256
  ) {
    throw Error(`Source review mismatch: ${path}`);
  }
}
// Read selected content only by the immutable object IDs captured above.
const config = selectedConfig;
if (
  config.schemaVersion !== 1 || !Array.isArray(config.files) ||
  !config.files.length || config.releaseStatus !== "source-approved"
) throw Error("Invalid public source selection");
const paths = config.files as string[];
if (new Set(paths).size !== paths.length) {
  throw Error("Duplicate selected source path");
}
const entries: {
  path: string;
  mode: string;
  bytes: number;
  sha256: string;
  data: Uint8Array;
}[] = [];
for (const path of paths) {
  if (
    typeof path !== "string" || !path || path.startsWith("/") ||
    [...path].some((char) =>
      char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127
    ) ||
    path.includes("\\") || path.split("/").some((part) =>
      !part || part === "." || part === ".."
    )
  ) throw Error("Invalid selected source path");
  if (
    /^(?:Local|\.git|\.env|docs\/legacy)(?:\/|$)/.test(path) ||
    /(?:^|\/)(?:AGENTS\.md|TASKS\.md|PLAN\.md|ERRORLOG\.txt|SOURCE-MANIFEST\.json)$/
      .test(path)
  ) throw Error(`Private source selection: ${path}`);
  const mode = indexed.get(path)?.mode;
  if (mode !== "100644" && mode !== "100755") {
    throw Error(
      `Selected path is missing or not a regular indexed file: ${path}`,
    );
  }
  const data = await reviewedBytes(path);
  if (!data.includes(0)) {
    const text = decode(data);
    const rules = [
      ["home-path", /(?:\/Users\/|\/home\/)(?!\$\{)[^\s/]+\//],
      ["owner-workspace", /~\/X\//],
      ["private-key", /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
      ["token", /\b(?:ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b/],
    ] as const;
    for (const [category, pattern] of rules) {
      if (pattern.test(text)) {
        throw Error(
          `Review blocked: ${path} (${category}); contents suppressed`,
        );
      }
    }
  }
  entries.push({
    path,
    mode,
    bytes: data.length,
    sha256: await hash(data),
    data,
  });
}
const files = entries.map(({ data: _data, ...entry }) => entry);
const seal = await hash(new TextEncoder().encode(JSON.stringify(files)));
if (buildCandidate) {
  const builder = entries.find((entry) =>
    entry.path === "scripts/reviewed_snapshot.ts"
  );
  if (!builder) throw Error("Reviewed snapshot builder is not selected");
  const encoded = btoa(
    Array.from(builder.data, (byte) => String.fromCharCode(byte)).join(""),
  );
  const module = await import(`data:application/typescript;base64,${encoded}`);
  const result = await module.buildReviewedSnapshot(root, entries);
  console.log(JSON.stringify(result.result));
  Deno.exit(0);
}
if (exportCandidate) {
  const receipt = new TextEncoder().encode(
    JSON.stringify(
      {
        schemaVersion: 1,
        seal,
        files,
        releaseReady: false,
        limitations: config.limitations,
      },
      null,
      2,
    ) + "\n",
  );
  if (paths.includes("SOURCE-RECEIPT.json")) {
    throw Error("Reserved receipt path");
  }
  const payload = [...entries, {
    path: "SOURCE-RECEIPT.json",
    mode: "100644",
    bytes: receipt.length,
    sha256: await hash(receipt),
    data: receipt,
  }];
  const expected = new Map(payload.map((entry) => [entry.path, entry]));
  const directories = new Set<string>();
  for (const entry of payload) {
    let parent = dirname(entry.path);
    while (parent !== ".") {
      directories.add(parent);
      parent = dirname(parent);
    }
  }
  const ensureDirectory = async (path: string) => {
    try {
      await Deno.mkdir(path);
    } catch (error) {
      if (!(error instanceof Deno.errors.AlreadyExists)) throw error;
    }
    const stat = await Deno.lstat(path);
    if (!stat.isDirectory || stat.isSymlink) {
      throw Error("Candidate directory must not be a symlink");
    }
  };
  await ensureDirectory(join(root, "Local"));
  await ensureDirectory(join(root, "Local", "public-source"));
  const directory = join(root, "Local", "public-source", seal);
  let existing = false;
  try {
    await Deno.mkdir(directory);
  } catch (error) {
    if (!(error instanceof Deno.errors.AlreadyExists)) throw error;
    existing = true;
  }
  const stat = await Deno.lstat(directory);
  if (!stat.isDirectory || stat.isSymlink) {
    throw Error("Candidate must be a real directory");
  }
  if (!existing) {
    for (
      const path of [...directories].sort((a, b) =>
        a.split("/").length - b.split("/").length
      )
    ) await ensureDirectory(join(directory, path));
    for (const entry of payload) {
      await Deno.writeFile(join(directory, entry.path), entry.data, {
        createNew: true,
        mode: entry.mode === "100755" ? 0o755 : 0o644,
      });
    }
  }
  const seen = new Set<string>();
  const verifyDirectory = async (prefix = ""): Promise<void> => {
    for await (const entry of Deno.readDir(join(directory, prefix))) {
      const path = prefix ? prefix + "/" + entry.name : entry.name;
      if (entry.isSymlink) throw Error(`Candidate contains symlink: ${path}`);
      if (entry.isDirectory) {
        if (!directories.has(path)) {
          throw Error(`Unexpected candidate directory: ${path}`);
        }
        await verifyDirectory(path);
      } else {
        const wanted = expected.get(path);
        if (!entry.isFile || !wanted) {
          throw Error(`Unexpected candidate file: ${path}`);
        }
        const file = join(directory, path);
        const mode = (await Deno.lstat(file)).mode;
        if (
          mode !== null &&
          (mode & 0o777) !== (wanted.mode === "100755" ? 0o755 : 0o644)
        ) throw Error(`Candidate mode mismatch: ${path}`);
        if (await hash(await Deno.readFile(file)) !== wanted.sha256) {
          throw Error(`Candidate readback failed: ${path}`);
        }
        seen.add(path);
      }
    }
  };
  await verifyDirectory();
  if (seen.size !== payload.length) {
    throw Error("Candidate is incomplete; retained without overwrite");
  }
  console.log(
    `Candidate: Local/public-source/${seal} (${
      existing ? "verified existing" : "created and verified"
    })`,
  );
}
console.log(
  JSON.stringify({
    selectedFiles: files.length,
    seal,
    snapshot: "git-index",
    releaseReady: false,
    limitations: config.limitations,
  }),
);
