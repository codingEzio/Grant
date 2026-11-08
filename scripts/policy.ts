export type Rule = Record<string, unknown>;

export function sameValue(a: unknown, b: unknown): boolean {
  function ordered(value: unknown): unknown {
    if (Array.isArray(value)) return value.map(ordered);
    if (value && typeof value === "object") {
      return Object.fromEntries(
        Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map((
          [key, item],
        ) => [key, ordered(item)]),
      );
    }
    return value;
  }
  return JSON.stringify(ordered(a)) === JSON.stringify(ordered(b));
}

// authd rewrites audit timestamps on every commit, including restoration.
// Preserve and compare every actual policy field, including signing requirements.
export function samePolicy(a: unknown, b: unknown): boolean {
  function fields(value: unknown) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return value;
    }
    return Object.fromEntries(
      Object.entries(value).filter(([key]) =>
        key !== "created" && key !== "modified"
      ),
    );
  }
  return sameValue(fields(a), fields(b));
}

export function activationRule(
  original: Rule,
  current: Rule,
  probeAccepted: boolean,
): Rule {
  if (!probeAccepted) {
    throw new Error(
      "Real isolated authorization has not passed; global policy unchanged.",
    );
  }
  if (!samePolicy(original, current)) {
    throw new Error(
      "Authorization policy changed since planning; nothing overwritten.",
    );
  }
  return candidateRule(original);
}

export function restorationRule(original: Rule, current: Rule): Rule {
  if (!samePolicy(candidateRule(original), current)) {
    throw new Error(
      "Authorization policy is no longer owned by Grant; nothing overwritten.",
    );
  }
  return original;
}

export function candidateRule(original: Rule): Rule {
  const expected = [
    "builtin:authenticate",
    "builtin:reset-password,privileged",
    "builtin:authenticate,privileged",
  ];
  if (
    original.class !== "evaluate-mechanisms" ||
    JSON.stringify(original.mechanisms) !== JSON.stringify(expected)
  ) {
    throw new Error(
      "Unknown authenticate rule: inspect this OS before replacing its UI.",
    );
  }
  return {
    ...original,
    mechanisms: ["Grant:credentials", ...expected.slice(1)],
  };
}
