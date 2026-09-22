export const componentDescriptors = {
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
