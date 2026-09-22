// Wotex Lab semantic token catalogue; sha256:cfb97858f216286b8f41b4f1a11926e591d372032a286ae2a7f04d0a9ef1a879.
export const tokenDigest = "sha256:cfb97858f216286b8f41b4f1a11926e591d372032a286ae2a7f04d0a9ef1a879" as const
export const tokenThemes = ["system","light","dark","contrast"] as const
export type TokenTheme = (typeof tokenThemes)[number]
export const tokenRoles = {
  "semantic.color.canvas": {
    "type": "color",
    "values": {
      "system": "#f4f2ee",
      "light": "#f4f2ee",
      "dark": "#142b50",
      "contrast": "#000000"
    }
  },
  "semantic.color.surface": {
    "type": "color",
    "values": {
      "system": "#fbfaf7",
      "light": "#fbfaf7",
      "dark": "#1b3864",
      "contrast": "#000000"
    }
  },
  "semantic.color.text": {
    "type": "color",
    "values": {
      "system": "#263044",
      "light": "#263044",
      "dark": "#e0f4ff",
      "contrast": "#ffffff"
    }
  },
  "semantic.color.muted": {
    "type": "color",
    "values": {
      "system": "#5c6370",
      "light": "#5c6370",
      "dark": "#acc8da",
      "contrast": "#ffffff"
    }
  },
  "semantic.color.border": {
    "type": "color",
    "values": {
      "system": "#737984",
      "light": "#737984",
      "dark": "#879db5",
      "contrast": "#ffffff"
    }
  },
  "semantic.color.accent": {
    "type": "color",
    "values": {
      "system": "#294f77",
      "light": "#294f77",
      "dark": "#e0f4ff",
      "contrast": "#ffff00"
    }
  },
  "semantic.color.accentText": {
    "type": "color",
    "values": {
      "system": "#ffffff",
      "light": "#ffffff",
      "dark": "#142b50",
      "contrast": "#000000"
    }
  },
  "semantic.color.focus": {
    "type": "color",
    "values": {
      "system": "#1d4f91",
      "light": "#1d4f91",
      "dark": "#a8d8ff",
      "contrast": "#ffff00"
    }
  },
  "semantic.color.danger": {
    "type": "color",
    "values": {
      "system": "#b42318",
      "light": "#b42318",
      "dark": "#ffb4aa",
      "contrast": "#ff6060"
    }
  },
  "semantic.color.warning": {
    "type": "color",
    "values": {
      "system": "#815000",
      "light": "#815000",
      "dark": "#f4ca82",
      "contrast": "#ffff00"
    }
  },
  "semantic.color.success": {
    "type": "color",
    "values": {
      "system": "#17633b",
      "light": "#17633b",
      "dark": "#8cd7ab",
      "contrast": "#00ff90"
    }
  },
  "semantic.space.controlX": {
    "type": "dimension",
    "values": {
      "system": "0.75rem",
      "light": "0.75rem",
      "dark": "0.75rem",
      "contrast": "0.75rem"
    }
  },
  "semantic.space.controlY": {
    "type": "dimension",
    "values": {
      "system": "0.5rem",
      "light": "0.5rem",
      "dark": "0.5rem",
      "contrast": "0.5rem"
    }
  },
  "semantic.space.panel": {
    "type": "dimension",
    "values": {
      "system": "1rem",
      "light": "1rem",
      "dark": "1rem",
      "contrast": "1rem"
    }
  },
  "semantic.space.section": {
    "type": "dimension",
    "values": {
      "system": "2rem",
      "light": "2rem",
      "dark": "2rem",
      "contrast": "2rem"
    }
  },
  "semantic.radius.control": {
    "type": "dimension",
    "values": {
      "system": "0.625rem",
      "light": "0.625rem",
      "dark": "0.625rem",
      "contrast": "0.625rem"
    }
  },
  "semantic.radius.panel": {
    "type": "dimension",
    "values": {
      "system": "0.875rem",
      "light": "0.875rem",
      "dark": "0.875rem",
      "contrast": "0.875rem"
    }
  },
  "semantic.motion.interaction": {
    "type": "duration",
    "values": {
      "system": "120ms",
      "light": "120ms",
      "dark": "120ms",
      "contrast": "120ms"
    }
  },
  "semantic.motion.panel": {
    "type": "duration",
    "values": {
      "system": "180ms",
      "light": "180ms",
      "dark": "180ms",
      "contrast": "180ms"
    }
  }
} as const
export type TokenRole = keyof typeof tokenRoles
