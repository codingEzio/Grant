// Load this module from its reviewed Git-object bytes, not from an unverified
// worktree path. Build only from the approved bytes in a fresh local snapshot.
export type ReviewedEntry = {
  path: string;
  mode: string;
  sha256: string;
  data: Uint8Array;
};

const required = [
  "scripts/build.sh",
  "scripts/public_build.ts",
  "scripts/check_source.ts",
  "public-source.json",
  "LICENSE",
  "ARTWORK-LICENSE.md",
  "DEPENDENCIES.md",
  "References/Setup/README.md",
  "References/Setup/LICENSE",
  "References/Setup/provenance.json",
  "docs/INTEGRATION.md",
  "docs/INTEGRATION.zh-Hans.md",
  "docs/INTEGRATION.zh-Hant.md",
  "docs/TYPOGRAPHY.md",
  "docs/TYPOGRAPHY.zh-Hans.md",
  "docs/TYPOGRAPHY.zh-Hant.md",
];
const trees = ["Sources", "Resources", "References"];
const hash = async (bytes: Uint8Array) =>
  Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");

function validPath(path: string): boolean {
  return !!path && !path.startsWith("/") && !/[\\\0\r\n\t]/.test(path) &&
    !path.split("/").some((part) => !part || part === "." || part === "..");
}

async function treeFiles(root: string, prefix: string): Promise<string[]> {
  const result: string[] = [];
  for await (const entry of Deno.readDir(`${root}/${prefix}`)) {
    const path = `${prefix}/${entry.name}`;
    if (entry.isSymlink) throw Error(`Source tree contains a link: ${path}`);
    if (entry.isDirectory) result.push(...await treeFiles(root, path));
    else if (entry.isFile) result.push(path);
    else throw Error(`Nonregular source tree entry: ${path}`);
  }
  return result;
}

export async function buildReviewedSnapshot(
  projectRoot: string,
  entries: ReviewedEntry[],
): Promise<
  { output: string; result: Record<string, unknown> }
> {
  const root = await Deno.realPath(projectRoot);
  entries = [...entries];
  const selected = new Map<string, ReviewedEntry>();
  for (const entry of entries) {
    if (
      !validPath(entry.path) || selected.has(entry.path) ||
      !["100644", "100755"].includes(entry.mode) ||
      !/^[a-f0-9]{64}$/.test(entry.sha256) ||
      await hash(entry.data) !== entry.sha256
    ) throw Error("Invalid reviewed build input");
    selected.set(entry.path, entry);
  }
  if (required.some((path) => !selected.has(path))) {
    throw Error("Reviewed selection omits required build inputs");
  }
  // Fonts are separate pinned build inputs. Read only the exact bounded regular
  // files declared by the reviewed manifest, never arbitrary local assets.
  const fontsEntry = selected.get("Resources/Licenses/fonts.json");
  if (!fontsEntry) throw Error("Reviewed font manifest is missing");
  const assets = JSON.parse(new TextDecoder().decode(fontsEntry.data)).assets;
  if (!Array.isArray(assets)) throw Error("Invalid font manifest");
  for (
    const asset of assets.filter((item: { path?: string }) =>
      item.path?.startsWith("Resources/Fonts/")
    )
  ) {
    if (
      !/^Resources\/Fonts\/[A-Za-z0-9._-]+\.ttf$/.test(asset.path) ||
      selected.has(asset.path) || !Number.isInteger(asset.bytes) ||
      asset.bytes < 1 ||
      asset.bytes > 20_000_000 || !/^[a-f0-9]{64}$/.test(asset.sha256)
    ) throw Error("Invalid font input");
    const full = `${root}/${asset.path}`;
    let info: Deno.FileInfo;
    try {
      info = await Deno.lstat(full);
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) {
        throw Error("Font missing; run python3 scripts/get_fonts.py");
      }
      throw error;
    }
    if (
      !info.isFile || info.isSymlink || await Deno.realPath(full) !== full ||
      info.size !== asset.bytes
    ) throw Error("Font input differs");
    const data = await Deno.readFile(full);
    if (await hash(data) !== asset.sha256) throw Error("Font input differs");
    const item = {
      path: asset.path,
      mode: "100644",
      sha256: asset.sha256,
      data,
    };
    entries.push(item);
    selected.set(item.path, item);
  }
  for (const prefix of trees) {
    const actual = (await treeFiles(root, prefix)).sort();
    const expected = entries.map((entry) => entry.path).filter((path) =>
      path.startsWith(prefix + "/")
    ).sort();
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      throw Error(`Source tree differs from reviewed selection: ${prefix}`);
    }
  }
  for (const entry of entries) {
    const parts = entry.path.split("/");
    let path = root;
    for (const part of parts) {
      path += "/" + part;
      if ((await Deno.lstat(path)).isSymlink) {
        throw Error(`Reviewed source uses a link: ${entry.path}`);
      }
    }
    const stat = await Deno.lstat(path);
    if (
      !stat.isFile || await Deno.realPath(path) !== path ||
      ((stat.mode ?? 0) & 0o111 ? "100755" : "100644") !== entry.mode ||
      await hash(await Deno.readFile(path)) !== entry.sha256
    ) throw Error(`Worktree differs from reviewed source: ${entry.path}`);
  }
  const local = `${root}/Local`;
  try {
    await Deno.mkdir(local);
  } catch (error) {
    if (!(error instanceof Deno.errors.AlreadyExists)) throw error;
  }
  const localStat = await Deno.lstat(local);
  if (
    !localStat.isDirectory || localStat.isSymlink ||
    await Deno.realPath(local) !== local
  ) {
    throw Error("Local output must be a real directory");
  }
  const snapshot = await Deno.makeTempDir({
    dir: local,
    prefix: "public-build-source-",
  });
  for (const entry of entries) {
    const target = `${snapshot}/${entry.path}`;
    const parent = target.slice(0, target.lastIndexOf("/"));
    await Deno.mkdir(parent, { recursive: true });
    await Deno.writeFile(target, entry.data, {
      createNew: true,
      mode: entry.mode === "100755" ? 0o755 : 0o644,
    });
    await Deno.chmod(target, entry.mode === "100755" ? 0o755 : 0o644);
  }
  await Deno.mkdir(`${snapshot}/Local/home`, { recursive: true });
  await Deno.mkdir(`${snapshot}/Local/tmp`, { recursive: true });
  const reviewToken = crypto.randomUUID();
  await Deno.writeTextFile(
    `${snapshot}/Local/.reviewed-source-build.json`,
    JSON.stringify({ schemaVersion: 1, token: reviewToken }),
    { createNew: true, mode: 0o600 },
  );
  const process = await new Deno.Command(Deno.execPath(), {
    cwd: snapshot,
    args: [
      "run",
      `--allow-read=${snapshot}`,
      `--allow-write=${snapshot}`,
      "--allow-env=GRANT_REVIEW_TOKEN",
      "--allow-run=/bin/bash,/usr/bin/plutil",
      "scripts/public_build.ts",
      "--build",
    ],
    clearEnv: true,
    env: {
      PATH: "/usr/bin:/bin:/usr/sbin:/sbin",
      HOME: `${snapshot}/Local/home`,
      TMPDIR: `${snapshot}/Local/tmp`,
      GRANT_REVIEW_TOKEN: reviewToken,
    },
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!process.success) {
    // Avoid printing build output or private identifiers; retain local diagnostics.
    await Deno.writeFile(
      `${snapshot}/Local/build-failure.stdout`,
      process.stdout,
      { createNew: true },
    );
    await Deno.writeFile(
      `${snapshot}/Local/build-failure.stderr`,
      process.stderr,
      { createNew: true },
    );
    throw Error(
      `Source-only build failed (${process.code}); diagnostics retained in its local snapshot`,
    );
  }
  const result = JSON.parse(new TextDecoder().decode(process.stdout));
  if (
    typeof result.output !== "string" ||
    !/^Local\/public-build\/[a-f0-9]{64}$/.test(result.output) ||
    result.readback !== "exact" || result.releaseReady !== false
  ) throw Error("Invalid source-only build result");
  const sourceOutput = `${snapshot}/${result.output}`;
  const sourceOutputStat = await Deno.lstat(sourceOutput);
  const receiptPath = `${sourceOutput}/BUILD-RECEIPT.json`;
  const receiptStat = await Deno.lstat(receiptPath);
  if (
    !sourceOutputStat.isDirectory || sourceOutputStat.isSymlink ||
    await Deno.realPath(sourceOutput) !== sourceOutput ||
    !receiptStat.isFile || receiptStat.isSymlink
  ) throw Error("Invalid source-only artifact path");
  const receipt = JSON.parse(await Deno.readTextFile(receiptPath));
  if (
    receipt.releaseReady !== false ||
    receipt.sourceSeal !== result.output.split("/").at(-1) ||
    !Array.isArray(receipt.files) ||
    result.sourceSeal !== receipt.sourceSeal ||
    result.artifactSeal !== receipt.artifactSeal ||
    result.files !== receipt.files.length ||
    await hash(new TextEncoder().encode(JSON.stringify(receipt.files))) !==
      receipt.artifactSeal
  ) throw Error("Invalid source-only build receipt");
  const expected = new Map<
    string,
    { path: string; mode: number; bytes: number; sha256: string }
  >();
  for (const file of receipt.files) {
    if (
      !validPath(file.path) || file.path === "BUILD-RECEIPT.json" ||
      expected.has(file.path) || !Number.isInteger(file.mode) ||
      file.mode < 0 || file.mode > 0o777 ||
      !Number.isInteger(file.bytes) || !/^[a-f0-9]{64}$/.test(file.sha256)
    ) throw Error("Invalid source-only artifact entry");
    expected.set(file.path, file);
  }
  const actual = await treeFiles(sourceOutput, ".");
  if (
    JSON.stringify(actual.map((path) => path.slice(2)).sort()) !==
      JSON.stringify([...expected.keys(), "BUILD-RECEIPT.json"].sort())
  ) throw Error("Source-only artifact file list differs");
  for (const [path, file] of expected) {
    const full = `${sourceOutput}/${path}`;
    const stat = await Deno.lstat(full);
    const data = await Deno.readFile(full);
    if (
      (stat.mode! & 0o777) !== file.mode || data.length !== file.bytes ||
      await hash(data) !== file.sha256
    ) {
      throw Error("Source-only artifact verification failed");
    }
  }
  const outputRoot = `${local}/public-build`;
  try {
    await Deno.mkdir(outputRoot);
  } catch (error) {
    if (!(error instanceof Deno.errors.AlreadyExists)) throw error;
  }
  const outputRootStat = await Deno.lstat(outputRoot);
  if (
    !outputRootStat.isDirectory || outputRootStat.isSymlink ||
    await Deno.realPath(outputRoot) !== outputRoot
  ) {
    throw Error("Public build output must be a real directory");
  }
  const output = `${root}/${result.output}`;
  let existing = false;
  try {
    await Deno.mkdir(output);
  } catch (error) {
    if (!(error instanceof Deno.errors.AlreadyExists)) throw error;
    existing = true;
  }
  const outputStat = await Deno.lstat(output);
  if (
    !outputStat.isDirectory || outputStat.isSymlink ||
    await Deno.realPath(output) !== output
  ) {
    throw Error("Public build candidate must be a real directory");
  }
  const payload = [...expected.keys(), "BUILD-RECEIPT.json"].sort();
  if (!existing) {
    for (const path of payload) {
      const dest = `${output}/${path}`;
      await Deno.mkdir(dest.slice(0, dest.lastIndexOf("/")), {
        recursive: true,
      });
      const source = `${sourceOutput}/${path}`;
      const mode = (await Deno.lstat(source)).mode! & 0o777;
      await Deno.writeFile(dest, await Deno.readFile(source), {
        createNew: true,
        mode,
      });
      await Deno.chmod(dest, mode);
    }
  }
  const copied = (await treeFiles(output, ".")).map((path) => path.slice(2))
    .sort();
  if (JSON.stringify(copied) !== JSON.stringify(payload)) {
    throw Error("Existing public build differs; retained without overwrite");
  }
  for (const path of payload) {
    const source = `${sourceOutput}/${path}`;
    const dest = `${output}/${path}`;
    const a = await Deno.lstat(source);
    const b = await Deno.lstat(dest);
    if (
      !b.isFile || b.isSymlink || (a.mode! & 0o777) !== (b.mode! & 0o777) ||
      await hash(await Deno.readFile(source)) !==
        await hash(await Deno.readFile(dest))
    ) throw Error("Existing public build differs; retained without overwrite");
  }
  // The verified artifact is durable; successful build inputs are temporary.
  // A failure at any earlier point keeps the snapshot for diagnosis.
  try {
    await Deno.remove(snapshot, { recursive: true });
  } catch (error) {
    throw new Error(
      `Verified build saved at ${result.output}, but temporary source cleanup failed`,
      { cause: error },
    );
  }
  return {
    output,
    result: { ...result, existing, signedPointer: "not-accessed" },
  };
}
