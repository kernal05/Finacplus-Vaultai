const KEY = "vaultai-recent";
const MAX = 8;

export function saveRecent(dataUrl, label) {
  try {
    const existing = JSON.parse(localStorage.getItem(KEY) || "[]");
    const updated = [{ dataUrl, label, ts: Date.now() }, ...existing].slice(0, MAX);
    localStorage.setItem(KEY, JSON.stringify(updated));
  } catch (e) {
    // localStorage full or unavailable — non-critical, just skip saving
  }
}

export function getRecent() {
  try {
    return JSON.parse(localStorage.getItem(KEY) || "[]");
  } catch (e) {
    return [];
  }
}
