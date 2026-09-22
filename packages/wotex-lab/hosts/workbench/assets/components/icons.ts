export const icons = {
  search:
    "M11 4a7 7 0 1 0 4.9 12l4.6 4.5 1.4-1.4-4.5-4.6A7 7 0 0 0 11 4Zm0 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10Z",
  menu: "M3 6h18v2H3V6Zm0 5h18v2H3v-2Zm0 5h18v2H3v-2Z",
  close: "m5.6 4.2 14.2 14.2-1.4 1.4L4.2 5.6l1.4-1.4Zm12.8 0 1.4 1.4L5.6 19.8l-1.4-1.4L18.4 4.2Z",
  copy: "M8 7V3h13v13h-4v5H3V7h5Zm2 0h7v7h2V5h-9v2Zm5 2H5v10h10V9Z",
  theme: "M12 2a10 10 0 1 0 0 20V2Zm-2 2.3v15.4A8 8 0 0 1 10 4.3Z",
  chevron: "m7.4 8 4.6 4.6L16.6 8 18 9.4l-6 6-6-6L7.4 8Z",
} as const

export type IconName = keyof typeof icons
