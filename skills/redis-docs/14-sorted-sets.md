# Redis — Sorted Sets (ZSET)

Sets ordenados por score. Para rankings, leaderboards, scheduling.

## Comandos

```bash
ZADD key score member         # Agregar con score
ZADD key 100 p1 200 p2        # Múltiples
ZINCRBY key 10 member         # Incrementar score
ZSCORE key member             # Obtener score
ZRANK key member              # Posición (menor→mayor)
ZREVRANK key member           # Posición (mayor→menor)
ZRANGE key 0 9                # Top 10 (menor→mayor)
ZRANGE key 0 9 REV            # Top 10 (mayor→menor)
ZRANGE key 0 9 REV WITHSCORES # Con scores
ZRANGEBYSCORE key 100 200     # Por rango de score
ZREM key member               # Eliminar
ZCARD key                     # Cantidad
```

```typescript
// Agregar scores
await redis.zadd(
  "leaderboard",
  1500,
  "player1",
  1200,
  "player2",
  1800,
  "player3",
);

// Incrementar
await redis.zincrby("leaderboard", 100, "player1"); // 1600

// Top 10
const top10 = await redis.zrange("leaderboard", 0, 9, "REV", "WITHSCORES");
// ['player3', '1800', 'player1', '1600', 'player2', '1200']

// Posición de un jugador
const rank = await redis.zrevrank("leaderboard", "player1"); // 1 (segundo)
```

## Leaderboard Completo

```typescript
class Leaderboard {
  constructor(
    private redis: Redis,
    private name: string,
  ) {}
  private get key() {
    return `lb:${this.name}`;
  }

  async setScore(member: string, score: number): Promise<void> {
    await this.redis.zadd(this.key, score, member);
  }

  async incrScore(member: string, delta: number): Promise<number> {
    return parseFloat(await this.redis.zincrby(this.key, delta, member));
  }

  async getTop(
    n = 10,
  ): Promise<Array<{ member: string; score: number; rank: number }>> {
    const result = await this.redis.zrange(
      this.key,
      0,
      n - 1,
      "REV",
      "WITHSCORES",
    );
    const entries = [];
    for (let i = 0; i < result.length; i += 2) {
      entries.push({
        member: result[i],
        score: parseFloat(result[i + 1]),
        rank: i / 2 + 1,
      });
    }
    return entries;
  }

  async getRank(member: string): Promise<number | null> {
    const rank = await this.redis.zrevrank(this.key, member);
    return rank !== null ? rank + 1 : null;
  }

  async getAroundMember(member: string, range = 5): Promise<any[]> {
    const rank = await this.redis.zrevrank(this.key, member);
    if (rank === null) return [];
    const start = Math.max(0, rank - range);
    const result = await this.redis.zrange(
      this.key,
      start,
      rank + range,
      "REV",
      "WITHSCORES",
    );
    return this.parseWithScores(result, start);
  }

  private parseWithScores(result: string[], startRank: number) {
    const entries = [];
    for (let i = 0; i < result.length; i += 2) {
      entries.push({
        member: result[i],
        score: parseFloat(result[i + 1]),
        rank: startRank + i / 2 + 1,
      });
    }
    return entries;
  }
}
```

## Rate Limiting (Sliding Window)

```typescript
class RateLimiter {
  constructor(private redis: Redis) {}

  async isAllowed(
    key: string,
    limit: number,
    windowSec: number,
  ): Promise<boolean> {
    const now = Date.now();
    const k = `rl:${key}`;

    await this.redis.zremrangebyscore(k, 0, now - windowSec * 1000);
    const count = await this.redis.zcard(k);

    if (count >= limit) return false;

    await this.redis.zadd(k, now, `${now}-${Math.random()}`);
    await this.redis.expire(k, windowSec);
    return true;
  }
}
```

## Delayed Jobs

```typescript
class DelayedQueue {
  constructor(
    private redis: Redis,
    private name: string,
  ) {}
  private get key() {
    return `delayed:${this.name}`;
  }

  async schedule(job: object, runAt: Date): Promise<void> {
    await this.redis.zadd(this.key, runAt.getTime(), JSON.stringify(job));
  }

  async getReady(limit = 10): Promise<object[]> {
    const now = Date.now();
    const jobs = await this.redis.zrangebyscore(
      this.key,
      0,
      now,
      "LIMIT",
      0,
      limit,
    );
    return jobs.map((j) => JSON.parse(j));
  }

  async markDone(job: object): Promise<void> {
    await this.redis.zrem(this.key, JSON.stringify(job));
  }
}
```

## Trending con Decay

```typescript
class Trending {
  constructor(private redis: Redis) {}

  async recordEvent(
    category: string,
    itemId: string,
    weight = 1,
  ): Promise<void> {
    await this.redis.zincrby(`trending:${category}`, weight, itemId);
  }

  async getTop(category: string, n = 10): Promise<string[]> {
    return this.redis.zrange(`trending:${category}`, 0, n - 1, "REV");
  }

  // Ejecutar periódicamente para decay
  async applyDecay(category: string, factor = 0.9): Promise<void> {
    const script = `
      local members = redis.call('ZRANGE', KEYS[1], 0, -1, 'WITHSCORES')
      for i = 1, #members, 2 do
        local newScore = tonumber(members[i + 1]) * tonumber(ARGV[1])
        if newScore < 1 then redis.call('ZREM', KEYS[1], members[i])
        else redis.call('ZADD', KEYS[1], newScore, members[i]) end
      end
    `;
    await this.redis.eval(script, 1, `trending:${category}`, factor);
  }
}
```
