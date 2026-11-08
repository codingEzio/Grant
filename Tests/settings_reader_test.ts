// Old readers must never receive an unknown validation flag or write shared
// preferences. Everything, including the imported writer's paths, is isolated.
Deno.test("settings writer refuses old readers before launching or writing", async () => {
  const fixture = await Deno.makeTempDir({
    dir: "/private/tmp",
    prefix: "grant-reader-",
  });
  const originalHome = Deno.env.get("HOME");
  try {
    const contents = `${fixture}/Applications/Grant.app/Contents`;
    await Deno.mkdir(`${contents}/MacOS`, { recursive: true });
    const binary = `${contents}/MacOS/GrantPreview`;
    await Deno.writeTextFile(binary, '#!/bin/sh\n: > "$0.called"\nexit 1\n', {
      mode: 0o755,
    });
    const preferences = `${fixture}/Preferences/settings.json`;
    const source = (await Deno.readTextFile("scripts/desktop.ts")).replace(
      '"/Library/Application Support/Grant/Preferences/settings.json"',
      JSON.stringify(preferences),
    );
    const module = `${fixture}/desktop.ts`;
    await Deno.writeTextFile(module, source);
    Deno.env.set("HOME", fixture);
    const { writePreferences } = await import(`file://${module}`);
    const missing = async (path: string) => {
      try {
        await Deno.stat(path);
        return false;
      } catch (error) {
        if (error instanceof Deno.errors.NotFound) return true;
        throw error;
      }
    };
    for (const capability of [undefined, 1, 3]) {
      await Deno.writeTextFile(
        `${contents}/Info.plist`,
        JSON.stringify({
          CFBundleShortVersionString: "0.2.2",
          GRSettingsValidationVersion: capability,
        }),
      );
      let refused = false;
      try {
        await writePreferences(fixture, { style: "original" });
      } catch {
        refused = true;
      }
      if (
        !refused || !await missing(`${binary}.called`) ||
        !await missing(`${fixture}/Preferences`)
      ) {
        throw new Error(
          "An unsupported reader was launched or preferences were touched",
        );
      }
    }
    // A supported reader can reject validation: preserve existing durable data.
    await Deno.writeTextFile(
      `${contents}/Info.plist`,
      JSON.stringify({ GRSettingsValidationVersion: 2 }),
    );
    await Deno.mkdir(`${fixture}/Preferences`);
    const prior = '{"style":"paper"}\n';
    await Deno.writeTextFile(preferences, prior);
    let refused = false;
    try {
      await writePreferences(fixture, { style: "original" });
    } catch {
      refused = true;
    }
    if (
      !refused || await missing(`${binary}.called`) ||
      await Deno.readTextFile(preferences) !== prior
    ) {
      throw new Error("Rejected validation changed saved preferences");
    }
    for await (const entry of Deno.readDir(`${fixture}/Preferences`)) {
      if (entry.name !== "settings.json") {
        throw new Error("Validation temporary file leaked");
      }
    }
  } finally {
    if (originalHome === undefined) Deno.env.delete("HOME");
    else Deno.env.set("HOME", originalHome);
    await Deno.remove(fixture, { recursive: true });
  }
});
