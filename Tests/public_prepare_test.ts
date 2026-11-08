import { strict as assert } from "node:assert";
import { join } from "node:path";

Deno.test("reviewed export rejects staged and working tree drift", async () => {
  const root = await Deno.makeTempDir({
    dir: "/private/tmp",
    prefix: "grant-review-fixture-",
  });
  const sha = async (data: Uint8Array) =>
    [
      ...new Uint8Array(
        await crypto.subtle.digest("SHA-256", Uint8Array.from(data)),
      ),
    ].map((n) => n.toString(16).padStart(2, "0")).join("");
  const run = async (program: string, args: string[]) =>
    await new Deno.Command(program, {
      cwd: root,
      args,
      stdout: "piped",
      stderr: "piped",
    }).output();
  const git = async (...args: string[]) =>
    assert.equal((await run("git", args)).code, 0);
  try {
    await Deno.mkdir(join(root, "scripts"));
    await Deno.writeTextFile(join(root, "README.md"), "Reviewed source.\n");
    const selected = [
      "README.md",
      "public-source.json",
      "scripts/public_prepare.ts",
      "scripts/source-review-hashes.json",
    ];
    await Deno.writeTextFile(
      join(root, "public-source.json"),
      JSON.stringify({
        schemaVersion: 1,
        releaseStatus: "source-approved",
        files: selected,
        limitations: ["fixture"],
      }),
    );
    const pins: Record<string, { mode: string; sha256: string }> = {};
    for (const path of ["README.md", "public-source.json"]) {
      pins[path] = {
        mode: "100644",
        sha256: await sha(await Deno.readFile(join(root, path))),
      };
    }
    const original = await Deno.readTextFile("scripts/public_prepare.ts");
    const normalized = original.replace(
      /(const reviewHash =\s*")[a-f0-9]{64}(";)/,
      "$1" + "0".repeat(64) + "$2",
    );
    pins["scripts/public_prepare.ts"] = {
      mode: "100644",
      sha256: await sha(new TextEncoder().encode(normalized)),
    };
    const sidecar = new TextEncoder().encode(JSON.stringify(pins));
    await Deno.writeFile(
      join(root, "scripts/source-review-hashes.json"),
      sidecar,
    );
    const helper = original.replace(
      /(const reviewHash =\s*")[a-f0-9]{64}(";)/,
      `$1${await sha(sidecar)}$2`,
    );
    assert.notEqual(helper, original);
    await Deno.writeTextFile(join(root, "scripts/public_prepare.ts"), helper);
    await git("init", "-q");
    await git("add", ...selected);
    const prepare = () =>
      run("deno", [
        "run",
        "--no-config",
        "--allow-read",
        "--allow-write=Local",
        "--allow-run=git",
        "scripts/public_prepare.ts",
        "--prepare",
      ]);
    const first = await prepare();
    assert.equal(first.code, 0, new TextDecoder().decode(first.stderr));
    assert.equal((await prepare()).code, 0);
    const output = new TextDecoder().decode(first.stdout).match(
      /Candidate: (Local\/public-source\/[a-f0-9]{64})/,
    )![1];
    await Deno.writeTextFile(join(root, "README.md"), "Unreviewed worktree.\n");
    assert.notEqual((await prepare()).code, 0, "unstaged source accepted");
    await git("add", "README.md");
    assert.notEqual((await prepare()).code, 0, "staged source accepted");
    await Deno.writeTextFile(join(root, "README.md"), "Reviewed source.\n");
    await git("add", "README.md");
    await Deno.writeTextFile(join(root, output, "extra"), "fixture");
    assert.notEqual((await prepare()).code, 0, "extra output accepted");
    await Deno.remove(join(root, output, "extra"));
    await Deno.writeTextFile(join(root, output, "README.md"), "tampered");
    assert.notEqual((await prepare()).code, 0, "tampered output accepted");
    await Deno.writeTextFile(
      join(root, "scripts/source-review-hashes.json"),
      "{}",
    );
    await git("add", "scripts/source-review-hashes.json");
    assert.notEqual((await prepare()).code, 0, "unreviewed sidecar accepted");
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
