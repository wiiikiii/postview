function csrf() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

export async function prefGet(key) {
  try {
    const resp = await fetch(`/preferences?key=${encodeURIComponent(key)}`, {
      headers: { Accept: "application/json" },
    })
    if (!resp.ok) return null
    const { value } = await resp.json()
    return value ?? null
  } catch {
    return null
  }
}

export async function prefSet(key, value) {
  try {
    await fetch("/preferences", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrf(),
      },
      body: JSON.stringify({ key, value }),
    })
  } catch (_) {}
}
