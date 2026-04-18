import type { EnrichedList } from "./index";

const LIST_TTL_SECONDS = 60 * 60 * 24 * 7; // 7 days

export async function readList(
  id: string,
  kv: KVNamespace,
): Promise<EnrichedList | null> {
  const raw = await kv.get(`list:${id}`);
  return raw ? (JSON.parse(raw) as EnrichedList) : null;
}

export async function writeList(
  list: EnrichedList,
  kv: KVNamespace,
): Promise<void> {
  await kv.put(`list:${list.id}`, JSON.stringify(list), {
    expirationTtl: LIST_TTL_SECONDS,
  });
}
