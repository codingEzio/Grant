import {
  acquireDesktopLock,
  checkLauncher,
  exclusiveMove,
  releaseDesktopLock,
  replaceDesktopBundle,
  verifyTrustedRequirement,
} from "../scripts/desktop.ts";

async function exists(path: string) {
  try {
    await Deno.lstat(path);
    return true;
  } catch (e) {
    if (e instanceof Deno.errors.NotFound) return false;
    throw e;
  }
}
async function bundle(path: string, marker: string) {
  await Deno.mkdir(path);
  await Deno.writeTextFile(`${path}/marker`, marker);
}
async function identity(path: string) {
  const s = await Deno.lstat(path);
  return `${s.dev}:${s.ino}`;
}
async function fixture(fn: (root: string) => Promise<void>) {
  const root = await Deno.makeTempDir({
    dir: "/private/tmp",
    prefix: "grant-desktop-fixture-",
  });
  try {
    await fn(root);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
}
function assert(value: boolean, message: string) {
  if (!value) throw new Error(message);
}
async function rejected(fn: () => Promise<unknown>) {
  try {
    await fn();
  } catch {
    return;
  }
  throw new Error("Expected failure");
}

Deno.test("exclusive move refuses an occupied destination", () =>
  fixture(async (root) => {
    await bundle(`${root}/source`, "source");
    await bundle(`${root}/target`, "other");
    await rejected(() => {
      exclusiveMove(`${root}/source`, `${root}/target`);
      return Promise.resolve();
    });
    assert(
      await Deno.readTextFile(`${root}/target/marker`) === "other",
      "destination changed",
    );
    assert(await exists(`${root}/source`), "source disappeared");
  }));

Deno.test("successful replacement retains the prior bundle", () =>
  fixture(async (root) => {
    const stage = `${root}/stage`,
      app = `${root}/app`,
      backup = `${root}/backup`;
    await bundle(stage, "new");
    await bundle(app, "old");
    await replaceDesktopBundle(
      stage,
      app,
      backup,
      await identity(app),
      async () => {},
    );
    assert(
      await Deno.readTextFile(`${app}/marker`) === "new",
      "candidate absent",
    );
    assert(
      await Deno.readTextFile(`${backup}/marker`) === "old",
      "backup absent",
    );
  }));

Deno.test("failed candidate move restores the prior bundle", () =>
  fixture(async (root) => {
    const stage = `${root}/stage`,
      app = `${root}/app`,
      backup = `${root}/backup`;
    await bundle(stage, "new");
    await bundle(app, "old");
    const previous = await identity(app);
    await rejected(() =>
      replaceDesktopBundle(
        stage,
        app,
        backup,
        previous,
        async () => {},
        (from, to) => {
          if (from === stage) throw new Error("synthetic move failure");
          exclusiveMove(from, to);
        },
      )
    );
    assert(
      await Deno.readTextFile(`${app}/marker`) === "old",
      "previous not restored",
    );
    assert(await Deno.readTextFile(`${stage}/marker`) === "new", "stage lost");
  }));

Deno.test("conflicting destination and verification failure preserve both bundles", () =>
  fixture(async (root) => {
    const stage = `${root}/stage`,
      app = `${root}/app`,
      backup = `${root}/backup`;
    await bundle(stage, "new");
    await bundle(app, "old");
    const previous = await identity(app);
    await rejected(() =>
      replaceDesktopBundle(
        stage,
        app,
        backup,
        previous,
        async () => {},
        (from, to) => {
          if (from === stage) {
            Deno.mkdirSync(app);
            Deno.writeTextFileSync(`${app}/marker`, "other");
          }
          exclusiveMove(from, to);
        },
      )
    );
    assert(
      await Deno.readTextFile(`${app}/marker`) === "other",
      "other overwritten",
    );
    assert(
      await Deno.readTextFile(`${backup}/marker`) === "old",
      "backup lost",
    );
    assert(await Deno.readTextFile(`${stage}/marker`) === "new", "stage lost");
  }));

Deno.test("failed post-move verification leaves candidate and backup for recovery", () =>
  fixture(async (root) => {
    const stage = `${root}/stage`,
      app = `${root}/app`,
      backup = `${root}/backup`;
    await bundle(stage, "new");
    await bundle(app, "old");
    const previous = await identity(app);
    await rejected(() =>
      replaceDesktopBundle(
        stage,
        app,
        backup,
        previous,
        () => Promise.reject(new Error("synthetic verification failure")),
      )
    );
    assert(
      await Deno.readTextFile(`${app}/marker`) === "new",
      "candidate lost",
    );
    assert(
      await Deno.readTextFile(`${backup}/marker`) === "old",
      "previous lost",
    );
  }));

Deno.test("cooperative lock rejects overlap and launcher rejects links", () =>
  fixture(async (root) => {
    const release = await acquireDesktopLock(root);
    await rejected(() => acquireDesktopLock(root));
    await release();
    const other = `${root}/other`, link = `${root}/grant`;
    await Deno.writeTextFile(other, "managed", { mode: 0o755 });
    const linked = await new Deno.Command("/bin/ln", {
      args: ["-s", other, link],
    }).output();
    assert(linked.success, "fixture symlink creation failed");
    await rejected(() => checkLauncher(link, "managed"));
    assert(
      await Deno.readTextFile(other) === "managed",
      "symlink target changed",
    );
  }));

Deno.test("lock cleanup failure retains operation and recovery context", async () => {
  const original = new Error("synthetic operation failure");
  let output = "";
  try {
    await releaseDesktopLock(
      () => Promise.reject(new Error("synthetic cleanup failure")),
      original,
      "fixture-stage",
      "fixture-backup",
    );
  } catch (error) {
    output = String(error);
  }
  assert(
    output.includes("synthetic operation failure"),
    "operation cause missing",
  );
  assert(output.includes("synthetic cleanup failure"), "cleanup cause missing");
  assert(
    output.includes("fixture-stage") && output.includes("fixture-backup"),
    "recovery context missing",
  );
  let cleaned = false;
  await releaseDesktopLock(
    () => {
      cleaned = true;
      return Promise.resolve();
    },
    null,
    null,
    null,
  );
  assert(cleaned, "successful release not called");
});

// codesign inspects signatures only; neither fixture nor system binary is run.
Deno.test("trusted leaf requirement rejects an ad-hoc lookalike", () =>
  fixture(async (root) => {
    const prefix = `${root}/cert`;
    const extracted = await new Deno.Command("/usr/bin/codesign", {
      args: ["--display", `--extract-certificates=${prefix}`, "/usr/bin/true"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(extracted.success, "could not read system signing certificate");
    const cert = await Deno.readFile(`${prefix}0`);
    const leaf = [...new Uint8Array(await crypto.subtle.digest("SHA-1", cert))]
      .map((n) => n.toString(16).padStart(2, "0")).join("");
    const requirement =
      `identifier "com.apple.true" and certificate leaf = H"${leaf}"`;
    const fixtureBinary = `${root}/fixture`;
    await Deno.copyFile("/usr/bin/true", fixtureBinary);
    const signed = await new Deno.Command("/usr/bin/codesign", {
      args: [
        "--force",
        "--sign",
        "-",
        "--identifier",
        "com.apple.true",
        "--requirements",
        `=designated => ${requirement}`,
        fixtureBinary,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(signed.success, "could not sign fixture");
    const basic = await new Deno.Command("/usr/bin/codesign", {
      args: ["--verify", "--strict", fixtureBinary],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(basic.success, "fixture must pass ordinary signature verification");
    const displayed = await new Deno.Command("/usr/bin/codesign", {
      args: ["-d", "-r-", fixtureBinary],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const text = new TextDecoder().decode(displayed.stdout) +
      new TextDecoder().decode(displayed.stderr);
    assert(
      text.toLowerCase().includes(requirement.toLowerCase()),
      "fixture must claim the same requirement",
    );
    await rejected(() =>
      verifyTrustedRequirement(fixtureBinary, requirement, leaf)
    );
    await verifyTrustedRequirement("/usr/bin/true", requirement, leaf);
  }));
