import {
  activationRule,
  candidateRule,
  restorationRule,
  type Rule,
  samePolicy,
  sameValue,
} from "./policy.ts";
import {
  desktopCommand,
  installDesktop,
  installedApp,
  readPreferences,
  sharedPreferences,
} from "./desktop.ts";

const root = decodeURIComponent(new URL("../", import.meta.url).pathname)
  .replace(/\/$/, "");
const local = `${root}/Local`;
const installedPlugin = "/Library/Security/SecurityAgentPlugins/Grant.bundle";
const installedSettings = "/Library/Application Support/Grant/settings.json";
const receiptDirectory = "/Library/Application Support/Grant/Receipts";
const probeRight = "com.alex.Grant.probe";
const command = Deno.args[0] ?? "help";
const needsCandidate = [
  "check",
  "preview",
  "stop-preview",
  "render",
  "original",
  "render-original",
  "plan",
  "probe",
  "install-probe",
  "install-app",
  "install-system",
  "_install-system",
].includes(command);
const latest = needsCandidate
  ? JSON.parse(await Deno.readTextFile(`${local}/latest-build.json`))
  : null;
if (
  latest &&
  (latest.schemaVersion !== 1 ||
    !latest.directory.startsWith(`${local}/Builds/`) ||
    !/^[0-9a-f-]{36}$/.test(latest.directory.slice(`${local}/Builds/`.length)))
) {
  throw new Error("Invalid candidate metadata; rebuild before use.");
}
const artifactRoot = latest?.directory ?? local;
const plugin = `${artifactRoot}/Grant.bundle`;
const appBundle = `${artifactRoot}/Grant.app`;
const appBinary = `${appBundle}/Contents/MacOS/GrantPreview`;
const originalBundle = `${artifactRoot}/GrantSetupReference.app`;

async function run(
  program: string,
  args: string[],
  input?: Uint8Array,
  allowFailure = false,
) {
  const child = new Deno.Command(program, {
    args,
    cwd: root,
    stdin: input ? "piped" : "null",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  if (input) {
    const writer = child.stdin.getWriter();
    await writer.write(input);
    await writer.close();
  }
  const result = await child.output();
  if (!result.success && !allowFailure) {
    throw new Error(
      `${program}: ${
        new TextDecoder().decode(result.stderr).trim() || `exit ${result.code}`
      }`,
    );
  }
  return result;
}
async function hash(data: Uint8Array) {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(data).buffer),
    ),
  )
    .map((x) => x.toString(16).padStart(2, "0")).join("");
}
async function exists(path: string) {
  try {
    await Deno.lstat(path);
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}
async function rule(name: string, absentAllowed = false) {
  const result = await run(
    "/usr/bin/security",
    ["authorizationdb", "read", name],
    undefined,
    absentAllowed,
  );
  if (!result.success) return null;
  const converted = await run("/usr/bin/plutil", [
    "-convert",
    "json",
    "-o",
    "-",
    "-",
  ], result.stdout);
  return {
    raw: result.stdout,
    value: JSON.parse(new TextDecoder().decode(converted.stdout)) as Rule,
  };
}
async function plist(value: unknown) {
  return (await run(
    "/usr/bin/plutil",
    ["-convert", "xml1", "-o", "-", "-"],
    new TextEncoder().encode(JSON.stringify(value)),
  )).stdout;
}
async function manifest(
  path: string,
  prefix = "",
): Promise<Record<string, string>> {
  const entries: Record<string, string> = {};
  for await (const entry of Deno.readDir(path)) {
    const name = prefix + entry.name;
    if (entry.isSymlink) {
      throw new Error(`Symlink is not allowed in candidate bundle: ${name}`);
    }
    if (entry.isDirectory) {
      Object.assign(
        entries,
        await manifest(`${path}/${entry.name}`, `${name}/`),
      );
    } else if (entry.isFile) {
      entries[name] = await hash(await Deno.readFile(`${path}/${entry.name}`));
    } else throw new Error(`Unexpected file type: ${name}`);
  }
  return Object.fromEntries(
    Object.entries(entries).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0),
  );
}
function same(a: unknown, b: unknown) {
  return sameValue(a, b);
}
async function json(path: string, value: unknown) {
  await Deno.mkdir(path.slice(0, path.lastIndexOf("/")), { recursive: true });
  const staging = `${path}.${crypto.randomUUID()}.tmp`;
  await Deno.writeTextFile(staging, JSON.stringify(value, null, 2) + "\n");
  await Deno.rename(staging, path);
  if (
    Deno.uid() === 0 && path.startsWith(`${receiptDirectory}/`) &&
    path.endsWith("/receipt.json")
  ) {
    const receipt = value as {
      plan: { id: string };
      stage: string;
      globalPolicyChanged: unknown;
      probeStatus?: number;
    };
    const publicPath = "/Library/Application Support/Grant/status.json";
    await json(publicPath, {
      receiptID: receipt.plan.id,
      stage: receipt.stage,
      globalPolicyChanged: receipt.globalPolicyChanged,
      probeStatus: receipt.probeStatus,
      updatedAt: new Date().toISOString(),
    });
    await Deno.chmod(publicPath, 0o644);
  }
}
async function build() {
  const result = await run("/bin/bash", ["scripts/build.sh"]);
  console.log(new TextDecoder().decode(result.stdout));
}
async function check() {
  for (const [path, expected] of Object.entries(latest.sourceFiles)) {
    if (await hash(await Deno.readFile(`${root}/${path}`)) !== expected) {
      throw new Error(
        `Source changed after candidate build: ${path}; rebuild before checking.`,
      );
    }
  }
  const fontManifest = JSON.parse(
    await Deno.readTextFile(`${root}/Resources/Licenses/fonts.json`),
  );
  for (const asset of fontManifest.assets) {
    if (
      await hash(await Deno.readFile(`${root}/${asset.path}`)) !== asset.sha256
    ) throw new Error(`Bundled asset drift: ${asset.path}`);
  }
  const languages = ["en", "zh-Hans", "zh-Hant"];
  let expectedKeys: string[] | undefined;
  for (const language of languages) {
    const strings = JSON.parse(
      await Deno.readTextFile(
        `${root}/Resources/Localization/${language}.json`,
      ),
    );
    const keys = Object.keys(strings).sort();
    if (expectedKeys && !same(expectedKeys, keys)) {
      throw new Error(`Incomplete localization: ${language}`);
    }
    if (Object.values(strings).some((x) => typeof x !== "string" || !x)) {
      throw new Error(`Empty localized string: ${language}`);
    }
    expectedKeys = keys;
  }
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
    "Local/context-check",
  ]);
  const native = await run(`${local}/context-check`, []);
  await run("/usr/bin/xcrun", [
    "clang",
    "-fobjc-arc",
    "-framework",
    "Foundation",
    "-framework",
    "Security",
    "-framework",
    "Cocoa",
    "-framework",
    "SecurityInterface",
    "Tests/plugin_entry.m",
    "-o",
    "Local/plugin-entry-check",
  ]);
  const entry = await run(`${local}/plugin-entry-check`, [
    `${plugin}/Contents/MacOS/Grant`,
  ]);
  await run("/bin/zsh", ["-f", "Tests/sudo_routing.zsh"]);
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
    "Local/sudo-response-check",
  ]);
  const sudoResponse = await run(`${local}/sudo-response-check`, []);
  console.log(new TextDecoder().decode(sudoResponse.stdout).trim());
  const refusal = await run(
    `${appBundle}/Contents/Resources/GrantAskpass`,
    ["test prompt"],
    undefined,
    true,
  );
  if (refusal.success || refusal.stdout.length) {
    throw new Error(
      "Askpass direct invocation did not refuse with empty stdout.",
    );
  }
  const shell = await run(Deno.execPath(), [
    "test",
    "--allow-read=Resources/grant_shell.zsh,/private/tmp",
    "--allow-write=/private/tmp",
    "--allow-run=/bin/zsh",
    "Tests/sudo_shell_test.ts",
  ]);
  console.log(new TextDecoder().decode(shell.stdout).trim());
  const reader = await run(Deno.execPath(), [
    "test",
    "--allow-env=HOME",
    "--allow-read=scripts/desktop.ts,/private/tmp",
    "--allow-write=/private/tmp",
    "--allow-run",
    "Tests/settings_reader_test.ts",
  ]);
  console.log(new TextDecoder().decode(reader.stdout).trim());
  const policy = await run(Deno.execPath(), ["test", "Tests/policy_test.ts"]);
  await run("/usr/bin/codesign", ["--verify", "--strict", plugin]);
  await run("/usr/bin/codesign", [
    "--verify",
    "--strict",
    appBundle,
  ]);
  console.log(new TextDecoder().decode(native.stdout).trim());
  await run("/usr/bin/codesign", ["--verify", "--strict", originalBundle]);
  console.log(new TextDecoder().decode(entry.stdout).trim());
  console.log(new TextDecoder().decode(policy.stdout).trim());
  console.log(
    "PASS bundled source hashes, three complete locales, all three candidate signatures",
  );
}
async function previousInstalledPlan(): Promise<string | null> {
  if (!await exists(installedPlugin)) return null;
  const installed = await manifest(installedPlugin);
  let id =
    JSON.parse(await Deno.readTextFile(`${local}/Activation/latest.json`)).id;
  const seen = new Set<string>();
  while (
    typeof id === "string" && /^[0-9a-f-]{36}$/.test(id) && !seen.has(id) &&
    seen.size < 16
  ) {
    seen.add(id);
    const plan = JSON.parse(
      await Deno.readTextFile(`${local}/Activation/${id}/plan.json`),
    );
    if (same(plan.pluginManifest, installed)) return id;
    id = plan.previousInstallation;
  }
  throw new Error(
    "Installed plugin has no matching local plan; automatic repair refused.",
  );
}

async function makePlan() {
  await run("/usr/bin/codesign", ["--verify", "--strict", plugin]);
  const baseline = await rule("authenticate");
  if (!baseline) {
    throw new Error(
      "Cannot read authenticate policy; use approved host access.",
    );
  }
  const previousInstallation = await previousInstalledPlan();
  const requiresStockRestore =
    (baseline.value.mechanisms as string[] | undefined)?.[0] ===
      "Grant:credentials";
  let originalRule = baseline.value;
  if (requiresStockRestore) {
    if (!previousInstallation) {
      throw new Error("Active Grant has no owned baseline; upgrade refused.");
    }
    const previous = JSON.parse(
      await Deno.readTextFile(
        `${local}/Activation/${previousInstallation}/plan.json`,
      ),
    );
    originalRule = restorationRule(previous.originalRule, baseline.value);
  }
  const candidate = candidateRule(originalRule);
  const admin = await rule("system.privilege.admin");
  if (admin?.value.class !== "user" || admin.value.group !== "admin") {
    throw new Error("Administrator policy requires manual inspection.");
  }
  const id = crypto.randomUUID();
  const directory = `${local}/Activation/${id}`;
  await Deno.mkdir(directory, { recursive: true });
  await Deno.writeFile(
    `${directory}/before.plist`,
    requiresStockRestore ? await plist(originalRule) : baseline.raw,
  );
  await Deno.writeFile(`${directory}/after.plist`, await plist(candidate));
  const plan = {
    schemaVersion: 1,
    id,
    observedAt: new Date().toISOString(),
    stage: "reviewable-local-plan",
    sourcePlugin: plugin,
    pluginManifest: await manifest(plugin),
    baselineHash: await hash(baseline.raw),
    originalRule,
    observedRule: baseline.value,
    requiresStockRestore,
    candidateRule: candidate,
    unchangedAdminPolicy: admin.value,
    pluginDestination: installedPlugin,
    settings: await readPreferences(root),
    ownerUID: Deno.uid(),
    validationClient: `${installedApp}/Contents/MacOS/GrantPreview`,
    validationAppManifest: await manifest(appBundle),
    isolatedProbeRight: probeRight,
    previousInstallation,
    globalEffect:
      "Replacing authenticate affects all authorization paths that use this rule; exact app coverage requires live proof.",
    preserved: [
      "password reset mechanism",
      "privileged Apple password authentication",
      "administrator/group rules",
    ],
    pending: [
      "isolated host loading",
      "correct and incorrect password",
      "cancel/Escape",
      "keyboard focus",
      "Touch ID behavior",
      "real application coverage",
    ],
    authorization:
      "System installation and global activation have not been performed.",
  };
  await json(`${directory}/plan.json`, plan);
  await json(`${directory}/settings.json`, plan.settings);
  await run(appBinary, ["--validate-settings", `${directory}/settings.json`]);
  await json(`${local}/Activation/latest.json`, {
    id,
    path: `${directory}/plan.json`,
  });
  console.log(`${directory}/plan.json`);
  console.log("Prepared only. The authenticate policy is unchanged.");
  return `${directory}/plan.json`;
}
async function copyBundle(source: string, destination: string) {
  await Deno.mkdir(destination, { recursive: true, mode: 0o755 });
  for await (const entry of Deno.readDir(source)) {
    const next = `${destination}/${entry.name}`;
    if (entry.isSymlink) {
      throw new Error("Symlink refused during installation.");
    }
    if (entry.isDirectory) await copyBundle(`${source}/${entry.name}`, next);
    else if (entry.isFile) {
      await Deno.copyFile(`${source}/${entry.name}`, next);
      await Deno.chmod(next, next.includes("/Contents/MacOS/") ? 0o555 : 0o444);
    } else throw new Error("Unexpected source file type.");
  }
}
function requireRoot() {
  if (Deno.uid() !== 0) {
    throw new Error(
      "Requires explicitly authorized administrator installation; run as root only after reviewing the plan.",
    );
  }
}
async function ownedDirectory(path: string, mode = 0o755) {
  const parent = path.slice(0, path.lastIndexOf("/")) || "/";
  if (parent !== "/") await ownedDirectory(parent);
  if (!await exists(path)) await Deno.mkdir(path, { mode });
  const info = await Deno.lstat(path);
  if (
    !info.isDirectory || info.isSymlink || info.uid !== 0 ||
    ((info.mode ?? 0) & 0o022)
  ) {
    throw new Error(
      `Unsafe installation directory ownership/type/mode: ${path}`,
    );
  }
}
async function installProbe() {
  requireRoot();
  const planPath = Deno.args[1];
  if (!planPath) throw new Error("Specify the exact reviewed plan.json path.");
  const plan = JSON.parse(await Deno.readTextFile(planPath));
  if (
    plan.schemaVersion !== 1 || !/^[0-9a-f-]{36}$/.test(plan.id) ||
    plan.sourcePlugin !== plugin || plan.pluginDestination !== installedPlugin
  ) throw new Error("Unsupported plan.");
  if (
    !Number.isInteger(plan.ownerUID) || plan.ownerUID <= 0 ||
    Number(Deno.env.get("SUDO_UID")) !== plan.ownerUID
  ) throw new Error("Installation user does not match the reviewed plan.");
  if (!same(plan.pluginManifest, await manifest(plugin))) {
    throw new Error("Candidate changed since review.");
  }
  const baseline = await rule("authenticate");
  if (!baseline || !samePolicy(baseline.value, plan.originalRule)) {
    throw new Error("System rule changed since review; prepare a fresh plan.");
  }
  if (!samePolicy(candidateRule(baseline.value), plan.candidateRule)) {
    throw new Error(
      "Planned rule differs from the preserved baseline transform.",
    );
  }
  await run("/usr/bin/codesign", ["--verify", "--strict", plugin]);
  const replacing = await exists(installedPlugin);
  let previousReceipt: any = null;
  if (replacing) {
    const previousId = plan.previousInstallation;
    if (
      typeof previousId !== "string" || !/^[0-9a-f-]{36}$/.test(previousId) ||
      previousId === plan.id
    ) {
      throw new Error(
        "Existing installation has no distinct reviewed repair receipt.",
      );
    }
    previousReceipt = JSON.parse(
      await Deno.readTextFile(`${receiptDirectory}/${previousId}/receipt.json`),
    );
    const previousProbe = await rule(probeRight, true);
    if (
      previousReceipt.plan.id !== previousId ||
      previousReceipt.globalPolicyChanged !== false ||
      !same(previousReceipt.plan.originalRule, plan.originalRule) ||
      !same(
        previousReceipt.plan.unchangedAdminPolicy,
        plan.unchangedAdminPolicy,
      ) ||
      !same(
        await manifest(installedPlugin),
        previousReceipt.plan.pluginManifest,
      ) ||
      !previousProbe ||
      !same(previousProbe.value, previousReceipt.probeReadback)
    ) {
      throw new Error(
        "Existing probe/receipt/policy changed; automatic repair refused.",
      );
    }
    const preferencesInfo = await Deno.lstat(
      sharedPreferences.slice(0, sharedPreferences.lastIndexOf("/")),
    );
    if (
      !preferencesInfo.isDirectory || preferencesInfo.isSymlink ||
      preferencesInfo.uid !== plan.ownerUID
    ) {
      throw new Error("Shared appearance directory ownership changed.");
    }
  } else if (
    await exists(installedSettings) ||
    await exists(
      sharedPreferences.slice(0, sharedPreferences.lastIndexOf("/")),
    ) ||
    await rule(probeRight, true)
  ) {
    throw new Error(
      "Existing Grant data/probe must be reviewed; nothing overwritten.",
    );
  }
  await ownedDirectory("/Library/Security/SecurityAgentPlugins");
  await ownedDirectory(receiptDirectory);
  const receipt = `${receiptDirectory}/${plan.id}`;
  await ownedDirectory(receipt, 0o700);
  await json(`${receipt}/receipt.json`, {
    plan,
    stage: "preparing-probe",
    globalPolicyChanged: false,
  });
  await Deno.writeFile(`${receipt}/before.plist`, baseline.raw, {
    mode: 0o600,
  });
  const settings = plan.settings;
  if (replacing) {
    const staged = `${installedPlugin}.staged-${plan.id}`;
    const backup = `${receipt}/PluginBeforeRepair.bundle`;
    await copyBundle(plugin, staged);
    if (!same(await manifest(staged), plan.pluginManifest)) {
      throw new Error("Staged repair differs from reviewed candidate.");
    }
    await run("/usr/bin/codesign", ["--verify", "--strict", staged]);
    await Deno.rename(installedPlugin, backup);
    try {
      await Deno.rename(staged, installedPlugin);
    } catch (error) {
      await Deno.rename(backup, installedPlugin);
      throw error;
    }
  } else await copyBundle(plugin, installedPlugin);
  if (!same(await manifest(installedPlugin), plan.pluginManifest)) {
    throw new Error(
      "Installed bundle readback mismatch; use restore-probe with this receipt.",
    );
  }
  await run("/usr/bin/codesign", ["--verify", "--strict", installedPlugin]);
  if (!replacing) await json(installedSettings, settings);
  await Deno.chmod(installedSettings, 0o444);
  const preferencesDirectory = sharedPreferences.slice(
    0,
    sharedPreferences.lastIndexOf("/"),
  );
  if (!replacing) {
    await Deno.mkdir(preferencesDirectory, { mode: 0o755 });
    await Deno.chown(preferencesDirectory, plan.ownerUID, -1);
    await json(sharedPreferences, settings);
    await Deno.chown(sharedPreferences, plan.ownerUID, -1);
    await Deno.chmod(sharedPreferences, 0o644);
  }
  await run(
    "/usr/bin/security",
    ["authorizationdb", "write", probeRight],
    await plist(plan.candidateRule),
  );
  const readback = await rule(probeRight);
  if (!same(readback?.value.mechanisms, plan.candidateRule.mechanisms)) {
    throw new Error("Probe rule readback mismatch.");
  }
  const unchanged = await rule("authenticate");
  if (!unchanged || !samePolicy(unchanged.value, plan.originalRule)) {
    throw new Error(
      "Unexpected global-policy change: inspect before continuing.",
    );
  }
  await json(`${receipt}/receipt.json`, {
    plan,
    stage: "probe-installed",
    installedAt: new Date().toISOString(),
    globalPolicyChanged: false,
    probeReadback: readback?.value,
  });
  console.log(
    `Installed isolated probe only. Receipt: ${receipt}/receipt.json`,
  );
  console.log(
    "authenticate is unchanged. Run ./grant probe as your regular user to request the test right.",
  );
}
async function restoreProbe() {
  requireRoot();
  const id = Deno.args[1];
  if (!id || !/^[0-9a-f-]{36}$/.test(id)) {
    throw new Error("Specify the recorded receipt UUID.");
  }
  const receiptPath = `${receiptDirectory}/${id}/receipt.json`;
  const receipt = JSON.parse(await Deno.readTextFile(receiptPath));
  if (receipt.plan.id !== id || receipt.globalPolicyChanged !== false) {
    throw new Error("Receipt requires manual review.");
  }
  const baseline = await rule("authenticate");
  if (!baseline || !samePolicy(baseline.value, receipt.plan.originalRule)) {
    throw new Error(
      "Global policy drift; this isolated restore will not overwrite it.",
    );
  }
  const current = await rule(probeRight, true);
  if (
    current &&
    !same(current.value.mechanisms, receipt.plan.candidateRule.mechanisms)
  ) throw new Error("Probe ownership changed.");
  if (current) {
    await run("/usr/bin/security", ["authorizationdb", "remove", probeRight]);
  }
  if (await rule(probeRight, true)) {
    throw new Error("Probe removal not verified.");
  }
  // Preserve the installed bundle and config for recovery; source deletion is separate.
  await json(receiptPath, {
    ...receipt,
    stage: "probe-rule-removed",
    restoredAt: new Date().toISOString(),
  });
  console.log(
    "Removed the isolated probe rule; global authenticate rule unchanged. Bundle and receipt preserved.",
  );
}

async function sudoCommand(command: string, argument: string) {
  const child = new Deno.Command("/usr/bin/sudo", {
    args: [
      Deno.execPath(),
      "run",
      "-A",
      `${root}/scripts/grant.ts`,
      command,
      argument,
    ],
    cwd: root,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  }).spawn();
  const result = await child.status;
  if (!result.success) Deno.exit(result.code);
}

async function installSystem() {
  requireRoot();
  const path = Deno.args[1];
  if (!path) throw new Error("Specify the reviewed plan.json.");
  const plan = JSON.parse(await Deno.readTextFile(path));
  if (
    plan.schemaVersion !== 1 || !/^[0-9a-f-]{36}$/.test(plan.id) ||
    plan.sourcePlugin !== plugin || !Number.isInteger(plan.ownerUID) ||
    plan.ownerUID <= 0 || Number(Deno.env.get("SUDO_UID")) !== plan.ownerUID
  ) throw new Error("Plan/calling user mismatch.");
  const callingApp = `/Users/${
    Deno.env.get("SUDO_USER")
  }/Applications/Grant.app`;
  if (plan.validationClient !== `${callingApp}/Contents/MacOS/GrantPreview`) {
    throw new Error("Unexpected validation app path.");
  }
  const receiptPath = `${receiptDirectory}/${plan.id}/receipt.json`;
  if (!await exists(receiptPath)) {
    if (plan.requiresStockRestore) {
      const previousId = plan.previousInstallation;
      if (
        typeof previousId !== "string" || !/^[0-9a-f-]{36}$/.test(previousId)
      ) throw new Error("Missing owned upgrade receipt.");
      const previous = JSON.parse(
        await Deno.readTextFile(
          `${receiptDirectory}/${previousId}/receipt.json`,
        ),
      );
      const global = await rule("authenticate");
      const admin = await rule("system.privilege.admin");
      const stillActive = previous.stage === "system-active" &&
        previous.globalPolicyChanged === true &&
        global && samePolicy(global.value, previous.plan.candidateRule);
      const stockRestored = previous.stage === "system-restored" &&
        previous.globalPolicyChanged === false &&
        global && samePolicy(global.value, previous.plan.originalRule);
      if (
        (!stillActive && !stockRestored) ||
        !samePolicy(previous.plan.originalRule, plan.originalRule) ||
        !same(previous.plan.unchangedAdminPolicy, plan.unchangedAdminPolicy) ||
        !admin ||
        !same(admin.value, plan.unchangedAdminPolicy) ||
        !same(await manifest(installedPlugin), previous.plan.pluginManifest) ||
        !same(await manifest(plugin), plan.pluginManifest) ||
        !same(await manifest(callingApp), plan.validationAppManifest)
      ) {
        throw new Error("Active upgrade drift; no rule or bundle changed.");
      }
      await run("/usr/bin/codesign", ["--verify", "--strict", plugin]);
      if (stillActive) {
        restorationRule(previous.plan.originalRule, global!.value);
        console.log(
          "Temporarily restoring the verified Apple rule before replacing the owned plugin. A failed or cancelled new probe leaves Apple authorization active.",
        );
        await restoreSystem(previousId);
      } else console.log("Resuming the verified stock-restored upgrade.");
    }
    await installProbe();
  }
  let receipt = JSON.parse(await Deno.readTextFile(receiptPath));
  if (
    !same(receipt.plan, plan) ||
    !same(await manifest(installedPlugin), plan.pluginManifest)
  ) throw new Error("Installed probe differs from reviewed plan.");
  const admin = await rule("system.privilege.admin");
  const current = await rule("authenticate");
  if (
    receipt.stage === "system-active" && current &&
    samePolicy(current.value, plan.candidateRule) && admin &&
    same(admin.value, plan.unchangedAdminPolicy)
  ) {
    console.log(
      `Grant is already selected in system authorization. Receipt: ${receiptPath}`,
    );
    return;
  }
  if (
    !admin || !same(admin.value, plan.unchangedAdminPolicy) || !current ||
    !samePolicy(current.value, plan.originalRule)
  ) throw new Error("System policy drift before isolated test.");
  // Freeze the user-mode verification client into a root-owned readable location.
  const clientDirectory =
    `/Library/Application Support/Grant/Clients/${plan.id}`;
  await ownedDirectory(clientDirectory);
  const client = `${clientDirectory}/Grant.app`;
  const sourceApp = plan.validationClient.replace(
    /\/Contents\/MacOS\/GrantPreview$/,
    "",
  );
  if (
    sourceApp !== `/Users/${Deno.env.get("SUDO_USER")}/Applications/Grant.app`
  ) throw new Error("Unexpected installed validation client.");
  if (!same(await manifest(sourceApp), plan.validationAppManifest)) {
    throw new Error("Installed app changed since plan review.");
  }
  if (!await exists(client)) await copyBundle(sourceApp, client);
  if (!same(await manifest(sourceApp), await manifest(client))) {
    throw new Error("Verification client copy mismatch.");
  }
  await run("/usr/bin/codesign", ["--verify", "--strict", client]);
  console.log(
    "Grant will now show an isolated authorization request. Enter your password in that system window; Cancel leaves global authorization unchanged.",
  );
  const result = await new Deno.Command("/usr/bin/sudo", {
    args: [
      "-u",
      `#${plan.ownerUID}`,
      `${client}/Contents/MacOS/GrantPreview`,
      "--probe-auth",
    ],
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  }).spawn().status;
  if (!result.success) {
    await json(receiptPath, {
      ...receipt,
      stage: "probe-not-accepted",
      probeStatus: result.code,
    });
    throw new Error(
      "Isolated authorization did not pass. Global authenticate remains unchanged. The same plan can be retried.",
    );
  }
  const beforeActivation = await rule("authenticate");
  const adminBefore = await rule("system.privilege.admin");
  if (
    !beforeActivation || !adminBefore ||
    !same(adminBefore.value, plan.unchangedAdminPolicy)
  ) throw new Error("Policy drift after probe; not activated.");
  const target = activationRule(
    plan.originalRule,
    beforeActivation.value,
    true,
  );
  receipt = {
    ...receipt,
    stage: "probe-accepted",
    probeAcceptedAt: new Date().toISOString(),
  };
  await json(receiptPath, {
    ...receipt,
    stage: "activating-system",
    globalPolicyChanged: "pending",
  });
  try {
    await run(
      "/usr/bin/security",
      ["authorizationdb", "write", "authenticate"],
      await plist(target),
    );
    const readback = await rule("authenticate");
    const adminReadback = await rule("system.privilege.admin");
    if (
      !readback || !samePolicy(readback.value, target) || !adminReadback ||
      !same(adminReadback.value, plan.unchangedAdminPolicy)
    ) throw new Error("Global activation readback mismatch.");
    await json(receiptPath, {
      ...receipt,
      stage: "system-active",
      globalPolicyChanged: true,
      activatedAt: new Date().toISOString(),
      readback: readback.value,
    });
  } catch (error) {
    await run(
      "/usr/bin/security",
      ["authorizationdb", "write", "authenticate"],
      await Deno.readFile(`${receiptDirectory}/${plan.id}/before.plist`),
    );
    const restored = await rule("authenticate");
    const rolledBack = samePolicy(restored?.value, plan.originalRule);
    await json(receiptPath, {
      ...receipt,
      stage: "activation-failed",
      rollbackVerified: rolledBack,
      globalPolicyChanged: !rolledBack,
    });
    throw new Error(
      `Activation failed; rollback verified=${rolledBack}: ${error}`,
    );
  }
  console.log(
    `Grant selected in system authorization. Receipt: ${receiptPath}\nRollback: grant restore-system ${plan.id}\nTheme: grant theme blueprint`,
  );
  const notified = await run(
    "/usr/bin/sudo",
    ["-u", `#${plan.ownerUID}`, plan.validationClient, "--notify-settings"],
    undefined,
    true,
  );
  if (!notified.success) {
    console.error(
      "System rule is active; reopen Grant to refresh its status display.",
    );
  }
}

async function restoreSystem(id: string | undefined = Deno.args[1]) {
  requireRoot();
  if (!id || !/^[0-9a-f-]{36}$/.test(id)) {
    throw new Error("Specify the recorded receipt UUID.");
  }
  const path = `${receiptDirectory}/${id}/receipt.json`;
  const receipt = JSON.parse(await Deno.readTextFile(path));
  const current = await rule("authenticate");
  if (!current || receipt.plan.id !== id) {
    throw new Error("Receipt/policy unavailable.");
  }
  if (!samePolicy(current.value, receipt.plan.originalRule)) {
    restorationRule(receipt.plan.originalRule, current.value);
    await run(
      "/usr/bin/security",
      ["authorizationdb", "write", "authenticate"],
      await Deno.readFile(`${receiptDirectory}/${id}/before.plist`),
    );
  }
  const readback = await rule("authenticate");
  if (!samePolicy(readback?.value, receipt.plan.originalRule)) {
    throw new Error("Rollback readback mismatch.");
  }
  await json(path, {
    ...receipt,
    stage: "system-restored",
    globalPolicyChanged: false,
    restoredAt: new Date().toISOString(),
  });
  console.log(
    "Original Apple authenticate policy restored and read back. App, appearance settings, bundle and receipt retained.",
  );
}

try {
  switch (command) {
    case "install-app":
      await check();
      await installDesktop(root, artifactRoot);
      break;
    case "settings":
    case "theme":
    case "status":
      await desktopCommand(root, command, Deno.args.slice(1));
      break;
    case "install-system": {
      if (!await exists(installedApp)) {
        throw new Error("Run grant install-app first.");
      }
      await check();
      let path = Deno.args[1];
      if (
        !path && await exists(installedPlugin) &&
        await exists(`${local}/Activation/latest.json`)
      ) {
        const previous = JSON.parse(
          await Deno.readTextFile(`${local}/Activation/latest.json`),
        );
        const previousPlan = JSON.parse(await Deno.readTextFile(previous.path));
        if (
          same(previousPlan.pluginManifest, await manifest(plugin)) &&
          same(previousPlan.validationAppManifest, await manifest(appBundle))
        ) path = previous.path;
      }
      path ??= await makePlan();
      await sudoCommand("_install-system", path);
      break;
    }
    case "_install-system":
      await installSystem();
      break;
    case "restore-system": {
      const id = Deno.args[1] ??
        (await exists(`${local}/Activation/latest.json`)
          ? JSON.parse(
            await Deno.readTextFile(`${local}/Activation/latest.json`),
          ).id
          : undefined);
      if (!id) throw new Error("No recorded receipt; specify its UUID.");
      await sudoCommand("_restore-system", id);
      break;
    }
    case "_restore-system":
      await restoreSystem();
      break;
    case "public-check":
      await import("./public_prepare.ts");
      break;
    case "public-prepare":
      await import("./public_prepare.ts");
      break;
    case "public-build":
      await import("./public_build.ts");
      break;
    case "check-source":
      await import("./check_source.ts");
      break;
    case "build":
      await build();
      break;
    case "check":
      await check();
      break;
    case "preview":
      await run("/usr/bin/open", [
        "-n",
        appBundle,
        "--args",
        "--state-dir",
        `${local}/Preview`,
      ]);
      break;
    case "stop-preview":
      await run(appBinary, ["--quit-preview", "--owned-root", root]);
      break;
    case "original":
      await run("/usr/bin/open", ["-n", originalBundle]);
      break;
    case "render-original": {
      const result = await run(
        `${originalBundle}/Contents/MacOS/GrantSetupReference`,
        ["--render", `${local}/Evidence/setup-original`],
      );
      console.log(new TextDecoder().decode(result.stdout));
      break;
    }
    case "render": {
      const result = await run(
        appBinary,
        ["--render", `${local}/Evidence/render`],
      );
      console.log(new TextDecoder().decode(result.stdout));
      break;
    }
    case "contacts": {
      if (!Deno.args[1]) {
        throw new Error(
          "Supply the existing Python-with-Pillow executable: ./grant contacts /absolute/python3",
        );
      }
      const result = await run(Deno.args[1], [
        "scripts/contact_sheet.py",
        `${local}/Evidence/render`,
      ]);
      console.log(new TextDecoder().decode(result.stdout).trim());
      break;
    }
    case "plan":
      await makePlan();
      break;
    case "install-probe":
      await installProbe();
      break;
    case "restore-probe":
      await restoreProbe();
      break;
    case "request-sudo": {
      const helper = `${installedApp}/Contents/Resources/GrantAskpass`;
      if (!await exists(helper)) {
        throw new Error("Install the latest Grant.app first.");
      }
      console.log(
        "Requesting a fresh sudo password challenge for /usr/bin/true. No settings or files will change; sudo controls credential caching.",
      );
      const result = await new Deno.Command("/usr/bin/sudo", {
        args: ["-A", "-k", "--", "/usr/bin/true"],
        env: { SUDO_ASKPASS: helper },
        stdin: "inherit",
        stdout: "inherit",
        stderr: "inherit",
      }).spawn().status;
      console.log(
        `sudo request: ${
          result.success ? "approved" : "cancelled or failed"
        } (${result.code})`,
      );
      Deno.exitCode = result.code;
      break;
    }
    case "request": {
      if (!await exists(installedApp)) {
        throw new Error("Install Grant.app first.");
      }
      const currentStatus = await run(
        `${installedApp}/Contents/MacOS/GrantPreview`,
        ["--system-status"],
      );
      console.log(new TextDecoder().decode(currentStatus.stdout).trim());
      console.log(
        "Requesting actual macOS administrator authorization using the selection above; no privileged operation will run.",
      );
      const result = await run(
        `${installedApp}/Contents/MacOS/GrantPreview`,
        ["--request-auth"],
        undefined,
        true,
      );
      console.log(new TextDecoder().decode(result.stdout).trim());
      if (!result.success) {
        console.error(new TextDecoder().decode(result.stderr).trim());
        Deno.exit(result.code);
      }
      break;
    }
    case "probe": {
      const result = await run(
        appBinary,
        ["--probe-auth"],
        undefined,
        true,
      );
      console.log(new TextDecoder().decode(result.stdout).trim());
      if (!result.success) {
        console.error(new TextDecoder().decode(result.stderr).trim());
        Deno.exit(result.code);
      }
      break;
    }
    default:
      console.log(
        "Grant: request | request-sudo | settings | theme [paper|dot|swiss|hard-edge|blueprint|original] | status | install-app | install-system [plan.json] | restore-system <receipt-id>\nSource preparation: check-source | public-check | public-prepare | public-build\nDevelopment: build | check | preview | original | render | plan | probe | install-probe <plan.json> | restore-probe <receipt-id>\nSystem installation runs the real isolated authorization check before activating the shared rule.",
      );
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  Deno.exit(1);
}
