export const componentDescriptors = {
  canvas: {
    props: {
      label: { type: "string", required: true, max_bytes: 256 },
      nodes: { type: "item_list", required: true, max_items: 32 },
      edges: { type: "item_list", required: true, max_items: 64 },
      pins: { type: "item_list", max_items: 16 },
      view: { type: "item_list", max_items: 1 },
      layout_revision: { type: "string", max_bytes: 32 },
    },
    events: {
      inspect: { payload: "id", effectful: false },
      open: { payload: "id", effectful: false },
      save_layout: { payload: "layout", effectful: false },
      pin_refresh: { payload: "id", effectful: false },
      pin_pause: { payload: "id", effectful: false },
      pin_resume: { payload: "id", effectful: false },
      pin_remove: { payload: "id", effectful: false },
    },
  },
  chart: {
    props: {
      title: { type: "string", required: true, max_bytes: 256 },
      series: { type: "item_list", required: true, max_items: 8 },
      points: { type: "item_list", required: true, max_items: 2000 },
    },
    events: { inspect: { payload: "key", effectful: false } },
  },
  "data-grid": {
    props: {
      label: { type: "string", required: true, max_bytes: 256 },
      columns: { type: "item_list", required: true, max_items: 64 },
      rows: { type: "item_list", required: true, max_items: 2000 },
    },
    events: {
      select: { payload: "key", effectful: false },
      activate: { payload: "key", effectful: true },
    },
  },
  tabs: {
    props: {
      label: { type: "string", required: true, max_bytes: 256 },
      tabs: { type: "item_list", required: true, max_items: 32 },
      selected: { type: "string", max_bytes: 256 },
    },
    events: { select: { payload: "id", effectful: false } },
  },
} as const

export type IslandComponentName = keyof typeof componentDescriptors

export const componentDescriptor = (name: string) =>
  componentDescriptors[name as IslandComponentName]
