// Wotex Lab component catalogue; sha256:4befde319fa5377550ae7a50adb6dfd1a22a638ebc27020b3ddf796088c6bbef.
export const componentDigest = "sha256:4befde319fa5377550ae7a50adb6dfd1a22a638ebc27020b3ddf796088c6bbef" as const
export const componentDescriptors = [
  {
    "id": "button",
    "story_id": "primitives-button",
    "element": "button",
    "role": null,
    "name_from": "text",
    "focus": "self",
    "keyboard": [
      "Enter activates",
      "Space activates"
    ],
    "tokens": [
      "semantic.color.accent",
      "semantic.color.focus"
    ],
    "variants": [
      "primary",
      "secondary",
      "danger"
    ],
    "sizes": [
      "sm",
      "md",
      "lg"
    ],
    "states": [
      "default",
      "hover",
      "focus-visible",
      "active",
      "disabled",
      "loading"
    ],
    "capabilities": [
      "static",
      "enhanced"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "disabled": {
        "type": "boolean"
      }
    },
    "events": {
      "activate": {
        "payload": "empty",
        "effectful": true
      }
    },
    "fallback": "enabled native button",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "icon-button",
    "story_id": "primitives-icon-button",
    "element": "button",
    "role": null,
    "name_from": "label",
    "focus": "self",
    "keyboard": [
      "Enter activates",
      "Space activates"
    ],
    "tokens": [
      "semantic.color.accent",
      "semantic.color.focus"
    ],
    "variants": [
      "plain",
      "secondary",
      "danger"
    ],
    "sizes": [
      "sm",
      "md",
      "lg"
    ],
    "states": [
      "default",
      "hover",
      "focus-visible",
      "active",
      "disabled",
      "loading"
    ],
    "capabilities": [
      "static",
      "enhanced"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "icon": {
        "type": "enum",
        "values": [
          "search",
          "menu",
          "close",
          "copy",
          "theme",
          "chevron"
        ]
      }
    },
    "events": {
      "activate": {
        "payload": "empty",
        "effectful": true
      }
    },
    "fallback": "labelled native button",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "link",
    "story_id": "primitives-link",
    "element": "a",
    "role": null,
    "name_from": "text",
    "focus": "self",
    "keyboard": [
      "Enter follows link"
    ],
    "tokens": [
      "semantic.color.accent",
      "semantic.color.focus"
    ],
    "variants": [
      "default",
      "quiet"
    ],
    "sizes": [
      "md"
    ],
    "states": [
      "default",
      "hover",
      "focus-visible",
      "visited"
    ],
    "capabilities": [
      "static",
      "enhanced"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 512
      },
      "href": {
        "type": "url",
        "required": true,
        "max_bytes": 2048
      }
    },
    "events": {},
    "fallback": "ordinary link",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "field",
    "story_id": "forms-field",
    "element": "input",
    "role": null,
    "name_from": "label",
    "focus": "input",
    "keyboard": [
      "Tab enters field"
    ],
    "tokens": [
      "semantic.color.border",
      "semantic.color.focus"
    ],
    "variants": [
      "text",
      "search",
      "email",
      "password"
    ],
    "sizes": [
      "sm",
      "md",
      "lg"
    ],
    "states": [
      "default",
      "focus-visible",
      "disabled",
      "invalid",
      "loading"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "value": {
        "type": "string",
        "max_bytes": 8192
      },
      "name": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      }
    },
    "events": {
      "change": {
        "payload": "value",
        "effectful": false
      },
      "submit": {
        "payload": "value",
        "effectful": true
      }
    },
    "fallback": "labelled native input",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "select",
    "story_id": "forms-select",
    "element": "select",
    "role": null,
    "name_from": "label",
    "focus": "select",
    "keyboard": [
      "Native select keyboard behavior"
    ],
    "tokens": [
      "semantic.color.border",
      "semantic.color.focus"
    ],
    "variants": [
      "default"
    ],
    "sizes": [
      "sm",
      "md",
      "lg"
    ],
    "states": [
      "default",
      "focus-visible",
      "disabled",
      "invalid"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "value": {
        "type": "string",
        "max_bytes": 256
      },
      "options": {
        "type": "string_list",
        "max_items": 256
      }
    },
    "events": {
      "change": {
        "payload": "value",
        "effectful": false
      }
    },
    "fallback": "native select",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "checkbox",
    "story_id": "forms-checkbox",
    "element": "input",
    "role": null,
    "name_from": "label",
    "focus": "input",
    "keyboard": [
      "Space toggles"
    ],
    "tokens": [
      "semantic.color.accent",
      "semantic.color.focus"
    ],
    "variants": [
      "default"
    ],
    "sizes": [
      "md"
    ],
    "states": [
      "default",
      "checked",
      "disabled",
      "invalid"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "checked": {
        "type": "boolean"
      }
    },
    "events": {
      "change": {
        "payload": "checked",
        "effectful": false
      }
    },
    "fallback": "native checkbox",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "radio-group",
    "story_id": "forms-radio-group",
    "element": "fieldset",
    "role": "radiogroup",
    "name_from": "legend",
    "focus": "checked radio",
    "keyboard": [
      "Arrow keys change selection",
      "Space selects"
    ],
    "tokens": [
      "semantic.color.accent",
      "semantic.color.focus"
    ],
    "variants": [
      "default"
    ],
    "sizes": [
      "md"
    ],
    "states": [
      "default",
      "selected",
      "disabled",
      "invalid"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "legend": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "value": {
        "type": "string",
        "max_bytes": 256
      },
      "options": {
        "type": "string_list",
        "max_items": 32
      }
    },
    "events": {
      "change": {
        "payload": "value",
        "effectful": false
      }
    },
    "fallback": "native radio fieldset",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "tabs",
    "story_id": "navigation-tabs",
    "element": "div",
    "role": "tablist",
    "name_from": "label",
    "focus": "active tab",
    "keyboard": [
      "Arrow keys move focus",
      "Home selects first",
      "End selects last",
      "Enter activates"
    ],
    "tokens": [
      "semantic.color.accent",
      "semantic.color.focus"
    ],
    "variants": [
      "line",
      "pill"
    ],
    "sizes": [
      "sm",
      "md"
    ],
    "states": [
      "default",
      "selected",
      "disabled"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "tabs": {
        "type": "item_list",
        "required": true,
        "max_items": 32
      },
      "selected": {
        "type": "string",
        "max_bytes": 256
      }
    },
    "events": {
      "select": {
        "payload": "id",
        "effectful": false
      }
    },
    "fallback": "stacked labelled sections",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "disclosure",
    "story_id": "navigation-disclosure",
    "element": "details",
    "role": null,
    "name_from": "summary",
    "focus": "summary",
    "keyboard": [
      "Enter toggles",
      "Space toggles"
    ],
    "tokens": [
      "semantic.color.border",
      "semantic.color.focus"
    ],
    "variants": [
      "default",
      "quiet"
    ],
    "sizes": [
      "md"
    ],
    "states": [
      "closed",
      "open",
      "disabled"
    ],
    "capabilities": [
      "static",
      "enhanced"
    ],
    "props": {
      "summary": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "open": {
        "type": "boolean"
      }
    },
    "events": {
      "toggle": {
        "payload": "open",
        "effectful": false
      }
    },
    "fallback": "native details element",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "dialog",
    "story_id": "overlays-dialog",
    "element": "dialog",
    "role": "dialog",
    "name_from": "title",
    "focus": "first admitted control",
    "keyboard": [
      "Escape closes",
      "Tab remains inside"
    ],
    "tokens": [
      "semantic.color.surface",
      "semantic.color.focus"
    ],
    "variants": [
      "modal",
      "nonmodal"
    ],
    "sizes": [
      "sm",
      "md",
      "lg"
    ],
    "states": [
      "closed",
      "open",
      "loading",
      "error"
    ],
    "capabilities": [
      "enhanced",
      "live"
    ],
    "props": {
      "title": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "open": {
        "type": "boolean"
      }
    },
    "events": {
      "close": {
        "payload": "reason",
        "effectful": false
      }
    },
    "fallback": "inline labelled region",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "status-badge",
    "story_id": "feedback-status-badge",
    "element": "span",
    "role": null,
    "name_from": "text",
    "focus": "none",
    "keyboard": [],
    "tokens": [
      "semantic.color.text",
      "semantic.color.surface"
    ],
    "variants": [
      "neutral",
      "success",
      "warning",
      "danger"
    ],
    "sizes": [
      "sm",
      "md"
    ],
    "states": [
      "default"
    ],
    "capabilities": [
      "static"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "kind": {
        "type": "enum",
        "values": [
          "neutral",
          "success",
          "warning",
          "danger"
        ]
      }
    },
    "events": {},
    "fallback": "labelled text",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "callout",
    "story_id": "feedback-callout",
    "element": "aside",
    "role": "note",
    "name_from": "title",
    "focus": "none",
    "keyboard": [],
    "tokens": [
      "semantic.color.surface",
      "semantic.color.border"
    ],
    "variants": [
      "note",
      "tip",
      "warning",
      "danger"
    ],
    "sizes": [
      "md"
    ],
    "states": [
      "default"
    ],
    "capabilities": [
      "static"
    ],
    "props": {
      "title": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "kind": {
        "type": "enum",
        "values": [
          "note",
          "tip",
          "warning",
          "danger"
        ]
      }
    },
    "events": {},
    "fallback": "labelled note",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "state",
    "story_id": "feedback-state",
    "element": "section",
    "role": "status",
    "name_from": "title",
    "focus": "recovery action",
    "keyboard": [
      "Tab reaches recovery action"
    ],
    "tokens": [
      "semantic.color.surface",
      "semantic.color.muted"
    ],
    "variants": [
      "empty",
      "error",
      "loading",
      "disconnected"
    ],
    "sizes": [
      "md"
    ],
    "states": [
      "default"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "title": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "message": {
        "type": "string",
        "required": true,
        "max_bytes": 2048
      }
    },
    "events": {
      "retry": {
        "payload": "empty",
        "effectful": true
      }
    },
    "fallback": "status text",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "panel",
    "story_id": "layout-panel",
    "element": "section",
    "role": "region",
    "name_from": "title",
    "focus": "none",
    "keyboard": [],
    "tokens": [
      "semantic.color.surface",
      "semantic.color.border"
    ],
    "variants": [
      "plain",
      "raised"
    ],
    "sizes": [
      "sm",
      "md",
      "lg"
    ],
    "states": [
      "default",
      "loading",
      "error"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "title": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      }
    },
    "events": {},
    "fallback": "labelled section",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "navigation",
    "story_id": "navigation-list",
    "element": "nav",
    "role": null,
    "name_from": "label",
    "focus": "current or first link",
    "keyboard": [
      "Tab follows document order"
    ],
    "tokens": [
      "semantic.color.accent",
      "semantic.color.focus"
    ],
    "variants": [
      "sidebar",
      "horizontal",
      "breadcrumbs"
    ],
    "sizes": [
      "md"
    ],
    "states": [
      "default",
      "current",
      "collapsed"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "items": {
        "type": "item_list",
        "required": true,
        "max_items": 512
      }
    },
    "events": {
      "select": {
        "payload": "id",
        "effectful": false
      }
    },
    "fallback": "nested link list",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "table",
    "story_id": "data-table",
    "element": "table",
    "role": null,
    "name_from": "caption",
    "focus": "overflow region",
    "keyboard": [
      "Tab enters overflow region"
    ],
    "tokens": [
      "semantic.color.border",
      "semantic.color.focus"
    ],
    "variants": [
      "default",
      "striped"
    ],
    "sizes": [
      "sm",
      "md"
    ],
    "states": [
      "default",
      "empty",
      "loading",
      "error"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "caption": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "columns": {
        "type": "item_list",
        "required": true,
        "max_items": 64
      },
      "rows": {
        "type": "item_list",
        "required": true,
        "max_items": 2000
      }
    },
    "events": {},
    "fallback": "semantic table",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "data-grid",
    "story_id": "data-grid",
    "element": "div",
    "role": "grid",
    "name_from": "label",
    "focus": "active cell",
    "keyboard": [
      "Arrow keys move cells",
      "Home and End move within row",
      "Page keys move viewport"
    ],
    "tokens": [
      "semantic.color.border",
      "semantic.color.focus"
    ],
    "variants": [
      "default"
    ],
    "sizes": [
      "md",
      "dense"
    ],
    "states": [
      "default",
      "selected",
      "loading",
      "empty",
      "error",
      "disconnected"
    ],
    "capabilities": [
      "enhanced",
      "live"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "columns": {
        "type": "item_list",
        "required": true,
        "max_items": 64
      },
      "rows": {
        "type": "item_list",
        "required": true,
        "max_items": 2000
      }
    },
    "events": {
      "select": {
        "payload": "key",
        "effectful": false
      },
      "activate": {
        "payload": "key",
        "effectful": true
      }
    },
    "fallback": "semantic table",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "tooltip",
    "story_id": "overlays-tooltip",
    "element": "span",
    "role": "tooltip",
    "name_from": "text",
    "focus": "trigger",
    "keyboard": [
      "Escape dismisses"
    ],
    "tokens": [
      "semantic.color.text",
      "semantic.color.surface"
    ],
    "variants": [
      "default"
    ],
    "sizes": [
      "sm"
    ],
    "states": [
      "hidden",
      "visible"
    ],
    "capabilities": [
      "enhanced"
    ],
    "props": {
      "text": {
        "type": "string",
        "required": true,
        "max_bytes": 512
      }
    },
    "events": {},
    "fallback": "accessible description",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "menu",
    "story_id": "overlays-menu",
    "element": "div",
    "role": "menu",
    "name_from": "trigger",
    "focus": "active item",
    "keyboard": [
      "Arrow keys move focus",
      "Home selects first",
      "End selects last",
      "Escape closes"
    ],
    "tokens": [
      "semantic.color.surface",
      "semantic.color.focus"
    ],
    "variants": [
      "default"
    ],
    "sizes": [
      "md"
    ],
    "states": [
      "closed",
      "open",
      "disabled"
    ],
    "capabilities": [
      "enhanced",
      "live"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "items": {
        "type": "item_list",
        "required": true,
        "max_items": 64
      }
    },
    "events": {
      "select": {
        "payload": "id",
        "effectful": true
      }
    },
    "fallback": "ordinary action list",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "toast",
    "story_id": "feedback-toast",
    "element": "div",
    "role": "status",
    "name_from": "message",
    "focus": "optional action",
    "keyboard": [
      "Tab reaches action"
    ],
    "tokens": [
      "semantic.color.surface",
      "semantic.color.text"
    ],
    "variants": [
      "neutral",
      "success",
      "warning",
      "danger"
    ],
    "sizes": [
      "md"
    ],
    "states": [
      "visible",
      "dismissed"
    ],
    "capabilities": [
      "enhanced",
      "live"
    ],
    "props": {
      "message": {
        "type": "string",
        "required": true,
        "max_bytes": 2048
      }
    },
    "events": {
      "dismiss": {
        "payload": "empty",
        "effectful": false
      }
    },
    "fallback": "live status text",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "progress",
    "story_id": "feedback-progress",
    "element": "progress",
    "role": null,
    "name_from": "label",
    "focus": "none",
    "keyboard": [],
    "tokens": [
      "semantic.color.accent",
      "semantic.color.surface"
    ],
    "variants": [
      "determinate",
      "indeterminate"
    ],
    "sizes": [
      "sm",
      "md"
    ],
    "states": [
      "default",
      "complete",
      "error"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "value": {
        "type": "number",
        "minimum": 0,
        "maximum": 100
      }
    },
    "events": {},
    "fallback": "native progress",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "chart",
    "story_id": "reporting-chart",
    "element": "figure",
    "role": "group",
    "name_from": "title",
    "focus": "inspection controls",
    "keyboard": [
      "Arrow keys inspect points",
      "Tab reaches table view"
    ],
    "tokens": [
      "semantic.color.accent",
      "semantic.color.focus"
    ],
    "variants": [
      "line",
      "bar",
      "area",
      "scatter",
      "heatmap"
    ],
    "sizes": [
      "sm",
      "md",
      "lg"
    ],
    "states": [
      "default",
      "loading",
      "empty",
      "error",
      "disconnected"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "title": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "series": {
        "type": "item_list",
        "required": true,
        "max_items": 8
      },
      "points": {
        "type": "item_list",
        "required": true,
        "max_items": 2000
      }
    },
    "events": {
      "inspect": {
        "payload": "key",
        "effectful": false
      }
    },
    "fallback": "summary and data table",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "legend",
    "story_id": "reporting-legend",
    "element": "section",
    "role": "region",
    "name_from": "label",
    "focus": "none",
    "keyboard": [],
    "tokens": [
      "semantic.color.border",
      "semantic.color.text"
    ],
    "variants": [
      "inline",
      "stacked"
    ],
    "sizes": [
      "sm",
      "md"
    ],
    "states": [
      "default",
      "empty"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "label": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "items": {
        "type": "item_list",
        "required": true,
        "max_items": 32
      }
    },
    "events": {},
    "fallback": "labelled list",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "filter",
    "story_id": "reporting-filter",
    "element": "fieldset",
    "role": null,
    "name_from": "legend",
    "focus": "first control",
    "keyboard": [
      "Tab follows filter order"
    ],
    "tokens": [
      "semantic.color.border",
      "semantic.color.focus"
    ],
    "variants": [
      "inline",
      "panel"
    ],
    "sizes": [
      "sm",
      "md"
    ],
    "states": [
      "default",
      "dirty",
      "loading",
      "invalid"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "legend": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "fields": {
        "type": "item_list",
        "required": true,
        "max_items": 32
      }
    },
    "events": {
      "change": {
        "payload": "values",
        "effectful": false
      },
      "apply": {
        "payload": "values",
        "effectful": true
      }
    },
    "fallback": "native fieldset",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  },
  {
    "id": "inspector",
    "story_id": "reporting-inspector",
    "element": "aside",
    "role": "complementary",
    "name_from": "title",
    "focus": "close control",
    "keyboard": [
      "Escape closes",
      "Tab follows document order"
    ],
    "tokens": [
      "semantic.color.surface",
      "semantic.color.focus"
    ],
    "variants": [
      "inline",
      "drawer"
    ],
    "sizes": [
      "md",
      "lg"
    ],
    "states": [
      "closed",
      "open",
      "loading",
      "error"
    ],
    "capabilities": [
      "static",
      "enhanced",
      "live"
    ],
    "props": {
      "title": {
        "type": "string",
        "required": true,
        "max_bytes": 256
      },
      "fields": {
        "type": "item_list",
        "required": true,
        "max_items": 128
      }
    },
    "events": {
      "close": {
        "payload": "reason",
        "effectful": false
      }
    },
    "fallback": "labelled details list",
    "since": "0.4.0",
    "deprecated": false,
    "compatibility": {
      "svelte": "5",
      "live_view": "1.1"
    }
  }
] as const
export type ComponentId = (typeof componentDescriptors)[number]["id"]
export const isComponentId = (id: string): id is ComponentId => componentDescriptors.some((component) => component.id === id)
export const componentDescriptor = (id: string) => isComponentId(id) ? componentDescriptors.find((component) => component.id === id) : undefined
