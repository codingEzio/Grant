import {
  activationRule,
  candidateRule,
  restorationRule,
  type Rule,
  samePolicy,
} from "../scripts/policy.ts";

function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}

function rejected(rule: Rule) {
  let didReject = false;
  try {
    candidateRule(rule);
  } catch {
    didReject = true;
  }
  assert(didReject, "unexpected rule must fail closed");
}

Deno.test("replace only the stock credential UI; preserve Apple validation and policy", () => {
  const original: Rule = {
    class: "evaluate-mechanisms",
    shared: true,
    tries: 10000,
    version: 1,
    mechanisms: [
      "builtin:authenticate",
      "builtin:reset-password,privileged",
      "builtin:authenticate,privileged",
    ],
  };
  const updated = candidateRule(original);
  assert(
    JSON.stringify(original.mechanisms).includes('builtin:authenticate"'),
    "input mutated",
  );
  assert(
    (updated.mechanisms as string[])[0] === "Grant:credentials",
    "custom view missing",
  );
  assert(
    JSON.stringify((updated.mechanisms as string[]).slice(1)) ===
      JSON.stringify((original.mechanisms as string[]).slice(1)),
    "downstream changed",
  );
  assert(
    updated.shared === original.shared && updated.tries === original.tries,
    "policy changed",
  );
});

Deno.test("unknown OS chain is rejected", () => {
  rejected({
    class: "evaluate-mechanisms",
    mechanisms: ["builtin:authenticate", "new-step"],
  });
});
Deno.test("already customized chain is rejected", () => {
  rejected({
    class: "evaluate-mechanisms",
    mechanisms: ["Other:ui", "builtin:authenticate,privileged"],
  });
});
Deno.test("user/group policy cannot be replaced as a mechanism rule", () => {
  rejected({
    class: "user",
    group: "admin",
    mechanisms: ["builtin:authenticate"],
  });
});

const baseline: Rule = {
  class: "evaluate-mechanisms",
  shared: true,
  version: 1,
  mechanisms: [
    "builtin:authenticate",
    "builtin:reset-password,privileged",
    "builtin:authenticate,privileged",
  ],
};
function refuses(action: () => unknown) {
  let rejected = false;
  try {
    action();
  } catch {
    rejected = true;
  }
  assert(rejected, "unsafe activation/restore was accepted");
}
Deno.test("global activation requires successful real probe and unchanged policy", () => {
  refuses(() => activationRule(baseline, baseline, false));
  refuses(() => activationRule(baseline, { ...baseline, shared: false }, true));
  const result = activationRule(baseline, baseline, true);
  assert(
    JSON.stringify(result) === JSON.stringify(candidateRule(baseline)),
    "unexpected global policy",
  );
});
Deno.test("rollback only replaces the exact owned rule and ignores dictionary order", () => {
  const candidate = candidateRule(baseline);
  const reordered = Object.fromEntries(Object.entries(candidate).reverse());
  assert(restorationRule(baseline, reordered).shared === true, "baseline lost");
  refuses(() => restorationRule(baseline, { ...candidate, timeout: 2 }));
});

Deno.test("authd audit timestamps do not invalidate policy readback or rollback", () => {
  const original = {
    class: "evaluate-mechanisms",
    mechanisms: [
      "builtin:authenticate",
      "builtin:reset-password,privileged",
      "builtin:authenticate,privileged",
    ],
    shared: true,
    tries: 10000,
    created: 1,
    modified: 1,
  };
  const installed = { ...candidateRule(original), modified: 2 };
  assert(
    samePolicy(installed, candidateRule(original)),
    "OS timestamp must not cause false activation failure",
  );
  assert(
    samePolicy(restorationRule(original, installed), {
      ...original,
      modified: 3,
    }),
    "restore must accept OS audit update",
  );
  assert(
    !samePolicy(installed, { ...installed, tries: 0 }),
    "authentication policy changes still reject",
  );
  assert(
    !samePolicy(installed, { ...installed, requirement: "allow" }),
    "signing requirement changes still reject",
  );
});
