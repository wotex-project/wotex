// Wotex Lab semantic token catalogue; sha256:af4dcaee8b8f0d82894ed3979417a74faa592557a77dab843abb6c09267aa82c.
export const tokenDigest =
  "sha256:af4dcaee8b8f0d82894ed3979417a74faa592557a77dab843abb6c09267aa82c" as const
export const tokenThemes = ["system", "light", "dark", "contrast"] as const
export type TokenTheme = (typeof tokenThemes)[number]
export const tokenRoles = {
  "semantic.color.accent": {
    type: "color",
    values: {
      system: "#181d27",
      light: "#181d27",
      dark: "#303644",
      contrast: "#181d27",
    },
  },
  "semantic.color.accentText": {
    type: "color",
    values: {
      system: "#ffffff",
      light: "#ffffff",
      dark: "#ffffff",
      contrast: "#ffffff",
    },
  },
  "semantic.color.border": {
    type: "color",
    values: {
      system: "#d6dbe3",
      light: "#d6dbe3",
      dark: "#444b5a",
      contrast: "#181d27",
    },
  },
  "semantic.color.canvas": {
    type: "color",
    values: {
      system: "#f4f5f7",
      light: "#f4f5f7",
      dark: "#181d27",
      contrast: "#ffffff",
    },
  },
  "semantic.color.controlBorder": {
    type: "color",
    values: {
      system: "#818a9d",
      light: "#818a9d",
      dark: "#818a9d",
      contrast: "#181d27",
    },
  },
  "semantic.color.danger": {
    type: "color",
    values: {
      system: "#181d27",
      light: "#181d27",
      dark: "#d6dbe3",
      contrast: "#181d27",
    },
  },
  "semantic.color.focus": {
    type: "color",
    values: {
      system: "#181d27",
      light: "#181d27",
      dark: "#818a9d",
      contrast: "#181d27",
    },
  },
  "semantic.color.muted": {
    type: "color",
    values: {
      system: "#606775",
      light: "#606775",
      dark: "#9097a5",
      contrast: "#303644",
    },
  },
  "semantic.color.success": {
    type: "color",
    values: {
      system: "#181d27",
      light: "#181d27",
      dark: "#d6dbe3",
      contrast: "#181d27",
    },
  },
  "semantic.color.surface": {
    type: "color",
    values: {
      system: "#ffffff",
      light: "#ffffff",
      dark: "#232936",
      contrast: "#ffffff",
    },
  },
  "semantic.color.text": {
    type: "color",
    values: {
      system: "#181d27",
      light: "#181d27",
      dark: "#d6dbe3",
      contrast: "#181d27",
    },
  },
  "semantic.color.warning": {
    type: "color",
    values: {
      system: "#181d27",
      light: "#181d27",
      dark: "#d6dbe3",
      contrast: "#181d27",
    },
  },
  "semantic.motion.interaction": {
    type: "duration",
    values: {
      system: "120ms",
      light: "120ms",
      dark: "120ms",
      contrast: "120ms",
    },
  },
  "semantic.motion.panel": {
    type: "duration",
    values: {
      system: "180ms",
      light: "180ms",
      dark: "180ms",
      contrast: "180ms",
    },
  },
  "semantic.radius.control": {
    type: "dimension",
    values: {
      system: "0.25rem",
      light: "0.25rem",
      dark: "0.25rem",
      contrast: "0.25rem",
    },
  },
  "semantic.radius.panel": {
    type: "dimension",
    values: {
      system: "0.25rem",
      light: "0.25rem",
      dark: "0.25rem",
      contrast: "0.25rem",
    },
  },
  "semantic.space.controlX": {
    type: "dimension",
    values: {
      system: "0.5rem",
      light: "0.5rem",
      dark: "0.5rem",
      contrast: "0.5rem",
    },
  },
  "semantic.space.controlY": {
    type: "dimension",
    values: {
      system: "0.25rem",
      light: "0.25rem",
      dark: "0.25rem",
      contrast: "0.25rem",
    },
  },
  "semantic.space.panel": {
    type: "dimension",
    values: {
      system: "0.75rem",
      light: "0.75rem",
      dark: "0.75rem",
      contrast: "0.75rem",
    },
  },
  "semantic.space.section": {
    type: "dimension",
    values: {
      system: "1.5rem",
      light: "1.5rem",
      dark: "1.5rem",
      contrast: "1.5rem",
    },
  },
} as const
export type TokenRole = keyof typeof tokenRoles
