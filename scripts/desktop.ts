// User-owned desktop installation and cosmetic preferences; never changes policy.
export const sharedPreferences =
  "/Library/Application Support/Grant/Preferences/settings.json";
export const themes = [
  "paper",
  "dot",
  "swiss",
  "hard-edge",
  "blueprint",
  "original",
];
const home = Deno.env.get("HOME")!;
export const installedApp = `${home}/Applications/Grant.app`;
export async function exists(path: string) {
  try {
    await Deno.lstat(path);
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}
export async function preferencesPath() {
  return await exists(
      sharedPreferences.slice(0, sharedPreferences.lastIndexOf("/")),
    )
    ? sharedPreferences
    : `${home}/Library/Application Support/Grant/settings.json`;
}
async function run(program: string, args: string[]) {
  const result = await new Deno.Command(program, {
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) {
    throw new Error(
      new TextDecoder().decode(result.stderr) || `${program}: ${result.code}`,
    );
  }
  return result.stdout;
}
export async function readPreferences(root: string) {
  const path = await preferencesPath();
  const source = await exists(path)
    ? path
    : await exists(`${root}/Local/Preview/settings.json`)
    ? `${root}/Local/Preview/settings.json`
    : `${root}/Resources/defaults.json`;
  if ((await Deno.stat(source)).size > 65536) {
    throw new Error("Grant preferences exceed 64 KiB.");
  }
  return JSON.parse(await Deno.readTextFile(source));
}
export async function writePreferences(root: string, settings: unknown) {
  // Unknown flags make older app versions enter their UI loop. Do not send a
  // validation request until the installed reader explicitly declares support.
  let capability: string;
  try {
    capability = new TextDecoder().decode(
      await run("/usr/bin/plutil", [
        "-extract",
        "GRSettingsValidationVersion",
        "raw",
        "-o",
        "-",
        `${installedApp}/Contents/Info.plist`,
      ]),
    ).trim();
  } catch {
    throw new Error(
      "Install the latest Grant.app before changing preferences: grant install-app",
    );
  }
  if (capability !== "2") {
    throw new Error(
      "Unsupported installed settings reader; install the latest Grant.app.",
    );
  }
  const path = await preferencesPath();
  const directory = path.slice(0, path.lastIndexOf("/"));
  await Deno.mkdir(directory, { recursive: true, mode: 0o755 });
  const temporary = `${directory}/.settings-${crypto.randomUUID()}.json`;
  try {
    await Deno.writeTextFile(
      temporary,
      JSON.stringify(settings, null, 2) + "\n",
      { mode: 0o644 },
    );
    const binary = `${installedApp}/Contents/MacOS/GrantPreview`;
    await run(binary, ["--validate-compatible-settings", temporary]);
    await Deno.rename(temporary, path);
    if (
      JSON.stringify(JSON.parse(await Deno.readTextFile(path))) !==
        JSON.stringify(settings)
    ) throw new Error("Preference readback mismatch.");
    await run(binary, ["--notify-settings"]);
  } finally {
    if (await exists(temporary)) await Deno.remove(temporary);
  }
}
function quote(value: string) {
  return "'" + value.replaceAll("'", "'\\''") + "'";
}
export async function installDesktop(root: string, candidate: string) {
  if (Deno.uid() === 0) {
    throw new Error("Install the desktop app as your regular user.");
  }
  const source = `${candidate}/Grant.app`;
  await run("/usr/bin/codesign", ["--verify", "--strict", source]);
  const settings = await readPreferences(root);
  const applications = `${home}/Applications`;
  await Deno.mkdir(applications, { recursive: true });
  const stage = `${applications}/.Grant-${crypto.randomUUID()}.app`;
  await run("/usr/bin/ditto", [source, stage]);
  await run("/usr/bin/codesign", ["--verify", "--strict", stage]);
  if (await exists(installedApp)) {
    const identity = new TextDecoder().decode(
      await run("/usr/libexec/PlistBuddy", [
        "-c",
        "Print :CFBundleIdentifier",
        `${installedApp}/Contents/Info.plist`,
      ]),
    ).trim();
    if (identity !== "com.alex.Grant.Preview") {
      throw new Error("An unrelated Grant.app exists; it was not replaced.");
    }
    await run(`${installedApp}/Contents/MacOS/GrantPreview`, [
      "--quit-preview",
      "--owned-root",
      root,
    ]);
    const backup = `${root}/Local/DesktopBackups/${crypto.randomUUID()}`;
    await Deno.mkdir(backup, { recursive: true });
    await Deno.rename(installedApp, `${backup}/Grant.app`);
  } else {
    await run(`${source}/Contents/MacOS/GrantPreview`, [
      "--quit-preview",
      "--owned-root",
      root,
    ]);
  }
  await Deno.rename(stage, installedApp);
  await run("/usr/bin/codesign", ["--verify", "--strict", installedApp]);
  if (!await exists(await preferencesPath())) {
    await writePreferences(root, settings);
  }
  const bin = `${home}/.local/bin`;
  await Deno.mkdir(bin, { recursive: true });
  const launcher = `${bin}/grant`;
  if (
    await exists(launcher) &&
    !(await Deno.readTextFile(launcher)).includes("# Managed by M-Grant") &&
    !(await Deno.readTextFile(launcher)).includes("# Managed by X-Grant")
  ) throw new Error("Unrelated grant command exists; not overwritten.");
  await Deno.writeTextFile(
    launcher,
    `#!/bin/sh\n# Managed by M-Grant\nexec ${quote(`${root}/grant`)} "$@"\n`,
    { mode: 0o755 },
  );
  await Deno.chmod(launcher, 0o755);
  const registry =
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";
  // Preserve dev builds on disk, but prefer the one installed app for discovery.
  for await (const entry of Deno.readDir(`${root}/Local/Builds`)) {
    if (entry.isDirectory && /^[0-9a-f-]{36}$/.test(entry.name)) {
      const candidateApp = `${root}/Local/Builds/${entry.name}/Grant.app`;
      if (await exists(candidateApp)) {
        const result = await new Deno.Command(registry, {
          args: ["-u", candidateApp],
          stdout: "piped",
          stderr: "piped",
        }).output();
        const output = new TextDecoder().decode(result.stdout) +
          new TextDecoder().decode(result.stderr);
        // kLSApplicationNotFoundErr: an unregistered dev build needs no removal.
        if (!result.success && !output.includes(": -10814")) {
          throw new Error(`Cannot unregister dev build: ${output}`);
        }
      }
    }
  }
  await run(
    registry,
    ["-f", installedApp],
  );
  console.log(
    `Installed ${installedApp}\nCommand: ${launcher}\nPreferences: ${await preferencesPath()}`,
  );
}
export async function desktopCommand(
  root: string,
  command: string,
  args: string[],
) {
  if (!await exists(installedApp)) {
    throw new Error("Install Grant.app first: ./grant install-app");
  }
  if (command === "settings") {
    await run("/usr/bin/open", [installedApp, "--args", "--show-settings"]);
  } else if (command === "theme") {
    const settings = await readPreferences(root);
    if (!args[0]) {
      console.log(`${settings.style}\nChoices: ${themes.join(" | ")}`);
      return;
    }
    if (!themes.includes(args[0])) {
      throw new Error(`Unknown theme. Choices: ${themes.join(", ")}`);
    }
    settings.style = args[0];
    await writePreferences(root, settings);
    console.log(
      `Theme: ${settings.style}\nSaved and read back: ${await preferencesPath()}`,
    );
  } else if (command === "status") {
    console.log(
      new TextDecoder().decode(
        await run(`${installedApp}/Contents/MacOS/GrantPreview`, [
          "--system-status",
        ]),
      ).trim(),
    );
    const statusFile = "/Library/Application Support/Grant/status.json";
    if (await exists(statusFile)) {
      const status = JSON.parse(await Deno.readTextFile(statusFile));
      console.log(
        `Installer: ${status.stage} (receipt ${status.receiptID})${
          status.probeStatus === undefined
            ? ""
            : `; probe status ${status.probeStatus}`
        }`,
      );
    }
    console.log(
      `App: ${installedApp}\nPreferences: ${await preferencesPath()}\nTheme: ${
        (await readPreferences(root)).style
      }`,
    );
    const settings = await readPreferences(root);
    console.log(
      `Terminal sudo GUI: ${
        settings.terminalSudo === true ? "enabled" : "disabled"
      }; helper ${
        await exists(`${installedApp}/Contents/Resources/GrantAskpass`)
          ? "installed"
          : "missing"
      }. Existing zsh tabs: source ~/.zshrc (current shell not inspected).`,
    );
  }
}
