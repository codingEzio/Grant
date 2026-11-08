import type { ReviewedEntry } from "../scripts/reviewed_snapshot.ts";

// Match the caller contract: run the reviewed module bytes, never an unverified
// worktree import. The surrounding Git-object review is tested by the caller.
const moduleBytes = await Deno.readFile(
  new URL("../scripts/reviewed_snapshot.ts", import.meta.url),
);
const moduleUrl = "data:application/typescript;base64," +
  btoa(Array.from(moduleBytes, (byte) => String.fromCharCode(byte)).join(""));
const { buildReviewedSnapshot } = await import(
  moduleUrl
) as typeof import("../scripts/reviewed_snapshot.ts");

const digest = async (data: Uint8Array) =>
  Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(data))),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
const encoder = new TextEncoder();
const assert = (value: unknown, label: string) => {
  if (!value) throw Error(label);
};

Deno.test("reviewed source snapshot prevents unreviewed compilation", async () => {
  const root = await Deno.realPath(
    await Deno.makeTempDir({ prefix: "grant-source-build-test-" }),
  );
  try {
    const source: Record<string, string> = {
      "Sources/App/main.swift": "synthetic source",
      "Resources/Localization/en.json": "{}",
      "Resources/Licenses/fonts.json": JSON.stringify({ assets: [] }),
      "References/Setup/README.md": "synthetic reference",
      "References/Setup/LICENSE": "synthetic reference license",
      "References/Setup/provenance.json": "{}",
      "docs/INTEGRATION.md": "synthetic",
      "docs/INTEGRATION.zh-Hans.md": "synthetic",
      "docs/INTEGRATION.zh-Hant.md": "synthetic",
      "docs/TYPOGRAPHY.md": "synthetic",
      "docs/TYPOGRAPHY.zh-Hans.md": "synthetic",
      "docs/TYPOGRAPHY.zh-Hant.md": "synthetic",
      "LICENSE": "synthetic license",
      "ARTWORK-LICENSE.md": "synthetic artwork license",
      "DEPENDENCIES.md": "synthetic dependencies",
      "public-source.json": "{}",
      "scripts/build.sh": "#!/bin/sh\nexit 0\n",
      "scripts/check_source.ts": "export const checked = true;\n",
      "scripts/public_build.ts": `
        if (Deno.args.join() !== "--build") throw Error("argument");
        if (await Deno.readTextFile("Sources/App/main.swift") !== "synthetic source") throw Error("source");
        const enc = new TextEncoder();
        const hash = async data => Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", data)), b => b.toString(16).padStart(2,"0")).join("");
        const selection = JSON.parse(await Deno.readTextFile("public-source.json")).files;
        const assets = JSON.parse(await Deno.readTextFile("Resources/Licenses/fonts.json")).assets;
        const sourceFiles = [];
        for (const path of [...selection, ...assets.map(a => a.path)].sort()) {
          const data = await Deno.readFile(path);
          const stat = await Deno.stat(path);
          sourceFiles.push({path, mode: stat.mode & 0o777, bytes: data.length, sha256: await hash(data)});
        }
        const sourceSeal = await hash(enc.encode(JSON.stringify(sourceFiles)));
        const output = "Local/public-build/" + sourceSeal;
        try {
          await Deno.stat(output);
          const receipt = JSON.parse(await Deno.readTextFile(output + "/BUILD-RECEIPT.json"));
          const existing = await Deno.readFile(output + "/result.json");
          if (await hash(existing) !== receipt.files[0].sha256) throw Error("tampered candidate");
          console.log(JSON.stringify({sourceSeal,artifactSeal:receipt.artifactSeal,files:receipt.files.length,output,readback:"exact",existing:true,reused:true,signedPointer:"unchanged",releaseReady:false}));
          Deno.exit(0);
        } catch (error) {
          if (!(error instanceof Deno.errors.NotFound)) throw error;
        }
        await Deno.mkdir(output, {recursive:true});
        const data = enc.encode(JSON.stringify({identity:"org.example.grant", fakeCompiler:true}));
        await Deno.writeFile(output+"/result.json", data, {mode:0o644});
        const files = [{path:"result.json",mode:0o644,bytes:data.length,sha256:await hash(data)}];
        const artifactSeal = await hash(enc.encode(JSON.stringify(files)));
        await Deno.writeTextFile(output+"/BUILD-RECEIPT.json", JSON.stringify({sourceSeal,artifactSeal,files,releaseReady:false}));
        console.log(JSON.stringify({sourceSeal,artifactSeal,files:files.length,output,readback:"exact",existing:false,signedPointer:"unchanged",releaseReady:false}));
      `,
    };
    source["public-source.json"] = JSON.stringify({
      files: Object.keys(source),
    });
    const font = encoder.encode("synthetic font");
    source["Resources/Licenses/fonts.json"] = JSON.stringify({
      assets: [{
        path: "Resources/Fonts/fixture.ttf",
        bytes: font.length,
        sha256: await digest(font),
      }],
    });
    const entries: ReviewedEntry[] = [];
    for (const [path, content] of Object.entries(source)) {
      const data = encoder.encode(content);
      const mode = path.endsWith("build-public-unsigned.sh")
        ? "100755"
        : "100644";
      const absolute = `${root}/${path}`;
      await Deno.mkdir(absolute.slice(0, absolute.lastIndexOf("/")), {
        recursive: true,
      });
      await Deno.writeFile(absolute, data);
      await Deno.chmod(absolute, mode === "100755" ? 0o755 : 0o644);
      entries.push({ path, mode, sha256: await digest(data), data });
    }
    await Deno.mkdir(`${root}/Resources/Fonts`);
    await Deno.writeFile(`${root}/Resources/Fonts/fixture.ttf`, font);
    const fails = async (candidate: ReviewedEntry[], label: string) => {
      let failed = false;
      try {
        await buildReviewedSnapshot(root, candidate);
      } catch {
        failed = true;
      }
      assert(failed, `${label} should fail`);
      try {
        await Deno.lstat(`${root}/Local`);
        throw Error(`${label} created output before validation`);
      } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
      }
    };
    await Deno.writeTextFile(
      `${root}/Resources/Fonts/fixture.ttf`,
      "altered font!",
    );
    await fails(entries, "unreviewed font");
    await Deno.writeFile(`${root}/Resources/Fonts/fixture.ttf`, font);
    await fails(
      entries.filter((entry) => entry.path !== "scripts/build.sh"),
      "missing script",
    );
    const altered = entries.map((entry, i) =>
      i ? entry : { ...entry, data: encoder.encode("different object") }
    );
    await fails(altered, "unapproved object");
    const file = `${root}/Sources/App/main.swift`;
    await Deno.writeTextFile(file, "unreviewed working tree source");
    await fails(entries, "changed working tree");
    await Deno.writeTextFile(file, source["Sources/App/main.swift"]);
    await Deno.writeTextFile(`${root}/Resources/unreviewed.txt`, "unreviewed");
    await fails(entries, "extra resource");
    await Deno.remove(`${root}/Resources/unreviewed.txt`);
    await Deno.remove(file);
    await Deno.symlink("../../LICENSE", file);
    await fails(entries, "source symlink");
    await Deno.remove(file);
    await Deno.writeTextFile(file, source["Sources/App/main.swift"]);
    const result = await buildReviewedSnapshot(root, entries);
    const built = JSON.parse(
      await Deno.readTextFile(`${result.output}/result.json`),
    );
    assert(
      built.fakeCompiler === true && built.identity === "org.example.grant",
      "synthetic compiler output",
    );
    const snapshots = async () => {
      const found: string[] = [];
      for await (const entry of Deno.readDir(`${root}/Local`)) {
        if (entry.name.startsWith("public-build-source-")) {
          found.push(entry.name);
        }
      }
      return found;
    };
    assert((await snapshots()).length === 0, "successful snapshot removed");
    assert(
      result.result.existing === false &&
        result.result.signedPointer === "not-accessed",
      "new output metadata",
    );
    const again = await buildReviewedSnapshot(root, entries);
    assert(
      again.output === result.output && again.result.existing === true &&
        again.result.reused === true,
      "identical output readback",
    );
    assert((await snapshots()).length === 0, "repeated snapshot removed");
    await Deno.writeTextFile(
      `${result.output}/result.json`,
      "unknown existing data",
    );
    let conflict = false;
    try {
      await buildReviewedSnapshot(root, entries);
    } catch {
      conflict = true;
    }
    assert(
      conflict &&
        await Deno.readTextFile(`${result.output}/result.json`) ===
          "unknown existing data",
      "different existing output preserved",
    );
    assert((await snapshots()).length === 1, "failed snapshot retained");
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
