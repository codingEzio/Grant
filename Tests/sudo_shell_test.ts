// Isolated shell fixtures. The test copy replaces absolute sudo with a recorder
// and simulates tty presence. Shipping code has no command-path/test override.
const source = await Deno.readTextFile("Resources/grant_shell.zsh");
const quote = (s: string) => "'" + s.replaceAll("'", "'\\''") + "'";
Deno.test("interactive sudo routing preserves argv, environment and exit status", async () => {
  const fixture = await Deno.makeTempDir({
    dir: "/private/tmp",
    prefix: "grant-sudo-fixture-",
  });
  try {
    const helper = `${fixture}/askpass`;
    const prefs = `${fixture}/settings.json`;
    await Deno.writeTextFile(helper, "#!/bin/sh\nexit 99\n", { mode: 0o755 });
    const routed = source.replaceAll("/usr/bin/sudo", "grant_fixture_record")
      .replace("-t 0 && -t 1", "1 == 1")
      .replace(
        '"$HOME/Applications/Grant.app/Contents/Resources/GrantAskpass"',
        quote(helper),
      )
      .replace(
        "'/Library/Application Support/Grant/Preferences/settings.json'",
        quote(prefs),
      );
    const cases = [
      { args: ["ls"], gui: true },
      { args: ["-p", "ASn %p", "--", "echo", "中文 $() space"], gui: true },
      { args: ["-uASn", "ls"], gui: true },
      { args: ["-n", "true"], gui: false },
      { args: ["-Sn", "true"], gui: false },
      { args: ["--ask", "true"], gui: false },
      { args: ["true"], env: "SSH_CONNECTION=x", gui: false },
      { args: ["true"], env: "SSH_CLIENT=x", gui: false },
      { args: ["true"], env: "SSH_TTY=x", gui: false },
      { args: ["true"], env: "TMUX=x", gui: false },
      {
        args: ["true"],
        env: "SUDO_ASKPASS=custom-helper",
        gui: false,
        inherited: "custom-helper",
      },
      { args: ["true"], disabled: true, gui: false },
      { args: ["true"], missing: true, gui: false },
    ];
    for (const c of cases) {
      await Deno.writeTextFile(
        prefs,
        JSON.stringify({ terminalSudo: !c.disabled }),
      );
      const code =
        `unset SSH_CONNECTION SSH_CLIENT SSH_TTY TMUX STY SUDO_ASKPASS
        grant_fixture_record() { printf '%s\\0' "\${SUDO_ASKPASS-}" "$@"; return 37; }
        ${routed}
        ${
          c.missing
            ? `/bin/chmod 600 ${quote(helper)}`
            : `/bin/chmod 755 ${quote(helper)}`
        }
        ${c.env ?? ""} sudo ${c.args.map(quote).join(" ")}`;
      const result = await new Deno.Command("/bin/zsh", {
        args: ["-fic", code],
        stdout: "piped",
        stderr: "piped",
      }).output();
      const values = new TextDecoder().decode(result.stdout).split("\0").slice(
        0,
        -1,
      );
      const expected = [
        c.gui ? helper : c.inherited ?? "",
        ...(c.gui ? ["-A"] : []),
        ...c.args,
      ];
      if (
        result.code !== 37 ||
        JSON.stringify(values) !== JSON.stringify(expected)
      ) {
        throw new Error(
          `Route mismatch ${JSON.stringify(c)}: ${result.code} ${
            JSON.stringify(values)
          }`,
        );
      }
    }
    const native = await new Deno.Command("/bin/zsh", {
      args: ["-fc", `${routed}\n(( $+functions[sudo] )) && exit 1; exit 0`],
    }).output();
    if (!native.success) throw new Error("Noninteractive shell was overridden");
  } finally {
    await Deno.remove(fixture, { recursive: true });
  }
});
