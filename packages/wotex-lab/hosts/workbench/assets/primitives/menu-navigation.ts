export const nextItemIndex = (key: string, current: number, count: number): number | null => {
  if (count < 1) {
    return null
  }
  if (key === "Home") {
    return 0
  }
  if (key === "End") {
    return count - 1
  }
  if (!["ArrowDown", "ArrowUp", "ArrowRight", "ArrowLeft"].includes(key)) {
    return null
  }
  const backwards = key === "ArrowUp" || key === "ArrowLeft"
  if (current < 0) {
    return backwards ? count - 1 : 0
  }
  return (current + (backwards ? -1 : 1) + count) % count
}
