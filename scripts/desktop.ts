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
// renamex_np with RENAME_EXCL keeps an unrelated destination from being
// replaced between a check and the move. This desktop installer is macOS-only.
export function exclusiveMove(source: string, destination: string) {
  const library = Deno.dlopen("/usr/lib/libSystem.B.dylib", {
    renamex_np: { parameters: ["buffer", "buffer", "u32"], result: "i32" },
  });
  try {
    const encode = (value: string) => new TextEncoder().encode(value + "\0");
    if (
      library.symbols.renamex_np(encode(source), encode(destination), 4) !== 0
    ) {
      throw new Error(`Exclusive move failed: ${source} -> ${destination}`);
    }
  } finally {
    library.close();
  }
}

async function fileIdentity(path: string) {
  const info = await Deno.lstat(path);
  if (
    info.isSymlink || !info.isDirectory || info.dev === null ||
    info.ino === null
  ) {
    throw new Error(`Unsafe bundle or directory: ${path}`);
  }
  return `${info.dev}:${info.ino}`;
}

export async function acquireDesktopLock(applications: string) {
  const lock = `${applications}/.Grant-install.lock`;
  try {
    await Deno.mkdir(lock, { mode: 0o700 });
  } catch (error) {
    if (error instanceof Deno.errors.AlreadyExists) {
      throw new Error(`Another install or a retained lock exists: ${lock}`);
    }
    throw error;
  }
  const identity = await fileIdentity(lock);
  return async () => {
    if (await fileIdentity(lock) !== identity) {
      throw new Error(`Install lock changed; inspect ${lock}`);
    }
    await Deno.remove(lock);
  };
}

export async function checkLauncher(path: string, content: string) {
  if (!await exists(path)) return false;
  const info = await Deno.lstat(path);
  if (
    info.isSymlink || !info.isFile ||
    await Deno.readTextFile(path) !== content ||
    (info.mode !== null && (info.mode & 0o111) === 0)
  ) {
    throw new Error(
      `Existing launcher differs or is not an executable regular file; not overwritten: ${path}`,
    );
  }
  return true;
}

// The caller validates signatures before quit and invokes this only inside the
// cooperative install lock. A failed move never overwrites an existing path.
export async function replaceDesktopBundle(
  stage: string,
  destination: string,
  backup: string | null,
  previousIdentity: string | null,
  verify: (path: string) => Promise<void>,
  move = exclusiveMove,
) {
  const candidateIdentity = await fileIdentity(stage);
  let previousMoved = false;
  try {
    if (backup && previousIdentity) {
      if (await fileIdentity(destination) !== previousIdentity) {
        throw new Error("Existing app changed before replacement.");
      }
      move(destination, backup);
      previousMoved = true;
      if (await fileIdentity(backup) !== previousIdentity) {
        throw new Error("Backup identity changed during replacement.");
      }
    }
    if (await fileIdentity(stage) !== candidateIdentity) {
      throw new Error("Candidate changed before replacement.");
    }
    move(stage, destination);
    if (await fileIdentity(destination) !== candidateIdentity) {
      throw new Error("Installed candidate changed during replacement.");
    }
    await verify(destination);
  } catch (error) {
    let recovery = "";
    // Restore only into an empty destination; if a candidate or another app is
    // present, preserve both and report the backup for explicit recovery.
    if (
      previousMoved && backup && previousIdentity && !await exists(destination)
    ) {
      try {
        if (await fileIdentity(backup) !== previousIdentity) {
          throw new Error("Backup changed.");
        }
        move(backup, destination);
        recovery = " Previous app restored.";
      } catch (restoreError) {
        recovery = ` Restore failed: ${restoreError}.`;
      }
    }
    throw new Error(
      `${error}.${recovery} Candidate: ${stage}; destination: ${destination}; previous backup: ${
        backup ?? "none"
      }`,
    );
  }
}

async function designatedRequirement(path: string) {
  await run("/usr/bin/codesign", ["--verify", "--strict", path]);
  const result = await new Deno.Command("/usr/bin/codesign", {
    args: ["-d", "-r-", path],
    stdout: "piped",
    stderr: "piped",
  }).output();
  const text = new TextDecoder().decode(result.stdout) +
    new TextDecoder().decode(result.stderr);
  const requirement = text.split("\n").find((line) =>
    line.startsWith("designated => ")
  );
  if (!result.success || !requirement) {
    throw new Error(`Cannot read signed app requirement: ${path}`);
  }
  return requirement;
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
export async function writePreferences(_root: string, settings: unknown) {
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
export async function releaseDesktopLock(
  releaseLock: () => Promise<void>,
  operationFailure: Error | null,
  stageRoot: string | null,
  backup: string | null,
): Promise<void> {
  try {
    await releaseLock();
  } catch (error) {
    throw new Error(
      `${
        operationFailure ?? "Desktop operation completed"
      }; lock cleanup failed: ${error}. Retained stage: ${
        stageRoot ?? "none"
      }; previous backup: ${backup ?? "none"}`,
    );
  }
}

export async function installDesktop(root: string, candidate: string) {
  if (Deno.uid() === 0) {
    throw new Error("Install the desktop app as your regular user.");
  }
  const source = `${candidate}/Grant.app`;
  const applications = `${home}/Applications`;
  await Deno.mkdir(applications, { recursive: true });
  const releaseLock = await acquireDesktopLock(applications);
  let stageRoot: string | null = null;
  let backup: string | null = null;
  let installedAndVerified = false;
  let operationFailure: Error | null = null;
  try {
    const requirement = await designatedRequirement(source);
    const sourceID = new TextDecoder().decode(
      await run("/usr/libexec/PlistBuddy", [
        "-c",
        "Print :CFBundleIdentifier",
        `${source}/Contents/Info.plist`,
      ]),
    ).trim();
    if (sourceID !== "com.alex.Grant.Preview") {
      throw new Error("Unexpected candidate bundle ID.");
    }
    const settings = await readPreferences(root);
    const bin = `${home}/.local/bin`;
    const launcher = `${bin}/grant`;
    const launcherContent = `#!/bin/sh\n# Managed by M-Grant\nexec ${
      quote(`${root}/grant`)
    } "$@"\n`;
    await checkLauncher(launcher, launcherContent);
    stageRoot = await Deno.makeTempDir({
      dir: applications,
      prefix: ".Grant-stage-",
    });
    const stage = `${stageRoot}/Grant.app`;
    await run("/usr/bin/ditto", [source, stage]);
    if (await designatedRequirement(stage) !== requirement) {
      throw new Error("Staged signature differs from candidate.");
    }
    let previousIdentity: string | null = null;
    if (await exists(installedApp)) {
      previousIdentity = await fileIdentity(installedApp);
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
      if (await designatedRequirement(installedApp) !== requirement) {
        throw new Error(
          "Installed app signing requirement differs; it was not replaced.",
        );
      }
      if (await fileIdentity(installedApp) !== previousIdentity) {
        throw new Error("Installed app changed during verification.");
      }
      await run(`${installedApp}/Contents/MacOS/GrantPreview`, [
        "--quit-preview",
        "--owned-root",
        root,
      ]);
      const backupParent = `${root}/Local/DesktopBackups`;
      await Deno.mkdir(backupParent, { recursive: true });
      backup = `${await Deno.makeTempDir({
        dir: backupParent,
        prefix: "install-",
      })}/Grant.app`;
      console.error(`Desktop stage: ${stageRoot}; previous backup: ${backup}`);
    } else {
      await run(`${source}/Contents/MacOS/GrantPreview`, [
        "--quit-preview",
        "--owned-root",
        root,
      ]);
    }
    await replaceDesktopBundle(
      stage,
      installedApp,
      backup,
      previousIdentity,
      async (path) => {
        if (await designatedRequirement(path) !== requirement) {
          throw new Error("Installed signature differs from candidate.");
        }
      },
    );
    installedAndVerified = true;
    await Deno.remove(stageRoot);
    stageRoot = null;
    if (!await exists(await preferencesPath())) {
      await writePreferences(root, settings);
    }
    await Deno.mkdir(bin, { recursive: true });
    if (!await exists(launcher)) {
      await Deno.writeTextFile(launcher, launcherContent, {
        mode: 0o755,
        createNew: true,
      });
    }
    if (!await checkLauncher(launcher, launcherContent)) {
      throw new Error("Launcher disappeared after creation.");
    }
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
      `Installed ${installedApp}\nCommand: ${launcher}\nPreferences: ${await preferencesPath()}\nPrevious backup: ${
        backup ?? "none"
      }`,
    );
  } catch (error) {
    if (installedAndVerified) {
      operationFailure = new Error(
        `App replacement succeeded but later setup failed: ${error}. Installed: ${installedApp}; previous backup: ${
          backup ?? "none"
        }`,
      );
    } else {
      operationFailure = new Error(
        `${error}. Retained stage: ${stageRoot ?? "none"}; previous backup: ${
          backup ?? "none"
        }`,
      );
    }
    throw operationFailure;
  } finally {
    await releaseDesktopLock(releaseLock, operationFailure, stageRoot, backup);
  }
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
