function clampBounds(bounds, areas) {
  const overlap = (a, b) => Math.max(0, Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x)) * Math.max(0, Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y));
  const area = [...areas].sort((a, b) => overlap(bounds, b) - overlap(bounds, a))[0];
  if (!area) return bounds;
  const width = Math.min(bounds.width, area.width); const height = Math.min(bounds.height, area.height);
  return { x: Math.max(area.x, Math.min(bounds.x, area.x + area.width - width)), y: Math.max(area.y, Math.min(bounds.y, area.y + area.height - height)), width, height };
}
function snapBounds(bounds, area) {
  const b = { ...bounds };
  if (Math.abs(b.x - area.x) < 14) b.x = area.x + 8;
  if (Math.abs(b.x + b.width - area.x - area.width) < 14) b.x = area.x + area.width - b.width - 8;
  if (Math.abs(b.y - area.y) < 14) b.y = area.y + 8;
  if (Math.abs(b.y + b.height - area.y - area.height) < 14) b.y = area.y + area.height - b.height - 8;
  return b;
}
module.exports = { clampBounds, snapBounds };
