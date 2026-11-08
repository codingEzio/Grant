// Source-only checks: no installed app, plugin loading, authorization or real sudo.
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
export const root = dirname(dirname(fileURLToPath(import.meta.url)));
export const hash = async (data: Uint8Array) =>
  [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", Uint8Array.from(data)),
    ),
  ]
    .map((n) => n.toString(16).padStart(2, "0")).join("");
export async function verifyInputs() {
  const fonts = JSON.parse(
    await Deno.readTextFile(join(root, "Resources/Licenses/fonts.json")),
  );
  for (const asset of fonts.assets) {
    let data: Uint8Array;
    try {
      data = await Deno.readFile(join(root, asset.path));
    } catch (error) {
      if (error instanceof Deno.errors.NotFound && asset.path.startsWith("Resources/Fonts/")) {
        throw Error("Font missing. Run: python3 scripts/get_fonts.py");
      }
      throw error;
    }
    if (await hash(data) !== asset.sha256 || data.length !== asset.bytes) {
      throw Error("Bundled asset drift: " + asset.path);
    }
  }
  const reference = JSON.parse(
    await Deno.readTextFile(join(root, "References/Setup/provenance.json")),
  );
  for (const file of reference.files) {
    if (
      await hash(
        await Deno.readFile(join(root, "References/Setup", file.path)),
      ) !== file.sha256
    ) throw Error("Setup reference drift: " + file.path);
  }
  let expected: string | undefined;
  for (const language of ["en", "zh-Hans", "zh-Hant"]) {
    const strings = JSON.parse(
      await Deno.readTextFile(
        join(root, "Resources/Localization", language + ".json"),
      ),
    );
    const keys = JSON.stringify(Object.keys(strings).sort());
    if (
      (expected && expected !== keys) ||
      Object.values(strings).some((v) => typeof v !== "string" || !v)
    ) throw Error("Incomplete localization: " + language);
    expected = keys;
  }
  return {
    pinnedFontAssets: fonts.assets.length,
    pinnedReferenceFiles: reference.files.length,
    locales: 3,
  };
}
async function run(program: string, args: string[]) {
  const result = await new Deno.Command(program, {
    cwd: root,
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  const output = new TextDecoder().decode(result.stdout);
  if (!result.success) {
    throw Error(
      `${program} failed (${result.code})\n${output}${
        new TextDecoder().decode(result.stderr)
      }`,
    );
  }
  if (output.trim()) console.log(output.trim());
}
async function check() {
  const inputs = await verifyInputs();
  await Deno.mkdir(join(root, "Local/SourceChecks"), { recursive: true });
  const scratch = await Deno.makeTempDir({
    dir: join(root, "Local/SourceChecks"),
    prefix: "delete_after_use_",
  });
  try {
    await run("/bin/bash", ["-n", "scripts/build.sh"]);
    await run("python3", ["Tests/build_modes_test.py"]);
    await run("python3", ["Tests/compact_font_input_test.py"]);
    await run("python3", ["Tests/font_fetch_test.py"]);
    await run("/usr/bin/xcrun", [
      "clang",
      "-fobjc-arc",
      "-framework",
      "Foundation",
      "-framework",
      "Security",
      "-I",
      "Sources/Shared",
      "Tests/credential_context.m",
      "Sources/Shared/GRContext.m",
      "-o",
      join(scratch, "context-check"),
    ]);
    await run(join(scratch, "context-check"), []);
    await run("/usr/bin/xcrun", [
      "clang",
      "-fobjc-arc",
      "-I",
      "Sources/Shared",
      "Tests/sudo_response.m",
      "Sources/Shared/GRSudoChannel.m",
      "-framework",
      "AppKit",
      "-framework",
      "SystemConfiguration",
      "-o",
      join(scratch, "response-check"),
    ]);
    await run(join(scratch, "response-check"), []);
    await run("/bin/zsh", ["-f", "Tests/sudo_routing.zsh"]);
    await run(Deno.execPath(), [
      "test",
      "--allow-read=Resources/grant_shell.zsh,/private/tmp",
      "--allow-write=/private/tmp",
      "--allow-run=/bin/zsh",
      "Tests/sudo_shell_test.ts",
    ]);
    await run(Deno.execPath(), [
      "test",
      "--allow-env=HOME",
      "--allow-read=scripts/desktop.ts,/private/tmp",
      "--allow-write=/private/tmp",
      "--allow-run",
      "Tests/settings_reader_test.ts",
    ]);
    await run(Deno.execPath(), ["test", "Tests/policy_test.ts"]);
  } finally {
    await Deno.remove(scratch, { recursive: true });
  }
  console.log(
    JSON.stringify({
      ...inputs,
      scope: "source-only",
      skipped: [
        "plugin loading",
        "app launch",
        "askpass invocation",
        "authorization",
        "real sudo",
        "signing",
        "installation",
        "shell integration",
      ],
    }),
  );
}
if (import.meta.main || Deno.args[0] === "check-source") await check();
