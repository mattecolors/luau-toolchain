# luau-toolchain

Luau-toolchain introduces production-grade Luau utilities for Roblox. They are three independent, zero-dependency packages that are built around type correctness and predictable runtime behavior.

[(https://github.com/mattecolors/luau-toolchain/actions/workflows/ci.yml/badge.svg)](https://github.com/mattecolors/luau-toolchain/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Packages

| Package | Description | Install |
|---------|-------------|---------|
| [`signal`](packages/signal/) | Strongly-typed, zero-instance event connections | `wally add luau-toolchain/signal@^1.0.0` |
| [`promise`](packages/promise/) | Promise/A+ with cancellation and task-aware scheduling | `wally add luau-toolchain/promise@^1.0.0` |
| [`net`](packages/net/) | Schema-validated network layer over a single Remote pair | `wally add luau-toolchain/net@^1.0.0` |

---

## Motivation

Most Roblox codebases accumulate one RemoteEvent per game event, BindableEvents for internal communication, and ad-hoc async patterns using bare coroutines.
This library replaces all three with typed, predictable abstractions that catch mistakes at the call site rather than at runtime.

---

## Signal

A typed event system that allocates no Roblox Instances.
Connections are nodes in a singly-linked list; firing iterates the list in O(n) with no table copies.

```luau
local Signal = require(Packages.Signal)

local playerDied = Signal.new() :: Signal.Signal<Player, string>

-- Connect a permanent listener
local conn = playerDied:Connect(function(player: Player, cause: string)
    print(player.Name, "died from", cause)
end)

-- ConnectOnce — fires once, then auto-disconnects
playerDied:ConnectOnce(function(player, cause)
    Achievements:unlock(player, "FirstBlood")
end)

-- Yield the current coroutine until the next fire
local p, cause = playerDied:Wait()

-- Fire synchronously (same thread)
playerDied:Fire(somePlayer, "fall damage")

-- Fire on the next Heartbeat (deferred signal semantics)
playerDied:FireDeferred(somePlayer, "explosion")

-- Cleanup
conn:Disconnect()
playerDied:Destroy()
```

### Safe mid-fire disconnects

Disconnecting a handler while its Signal is actively iterating queues the removal
and flushes it after the fire cycle completes. You will never skip or double-fire
a handler by accident.

---

## Promise

Promise/A+ implementation with Roblox-specific extensions.
All scheduling uses `task.spawn` / `task.defer` — never raw `coroutine.wrap`.

```luau
local Promise = require(Packages.Promise)

-- Retry a DataStore load up to 3 times with 1-second gaps
local p = Promise.retry(function()
    return Promise.new(function(resolve, reject, onCancel)
        local thread = task.spawn(function()
            local ok, data = pcall(DataStore.GetAsync, DataStore, userId)
            if ok then resolve(data) else reject(data) end
        end)
        onCancel(function() task.cancel(thread) end)
    end)
end, 3, 1)

p:andThen(function(data)
        applyPlayerData(data)
    end)
    :catch(function(err)
        warn("Failed to load data:", err)
    end)
    :finally(function(status)
        hideLoadingScreen()
    end)

-- Race a load against a timeout
local inventory = Promise.race({
    fetchInventory(player),
    Promise.delay(5):andThen(function() return {} end),
}):expect()

-- Await inside a task
task.spawn(function()
    local ok, data = p:await()
    if ok then print("loaded:", data) end
end)
```

### Cancellation

```luau
local p = Promise.new(function(resolve, _, onCancel)
    local conn = RunService.Heartbeat:Connect(function(dt)
        resolve(dt)
    end)
    onCancel(function()
        conn:Disconnect()
    end)
end)

p:cancel()  -- fires the onCancel hook immediately
```

Cancellation propagates to parent Promises in the chain.

---

## Net

A typed network bridge over a **single** `RemoteEvent` + `RemoteFunction` pair.
Packets are tagged with namespace and event name; routing happens in Luau, not
in the Instance tree.

### Defining a namespace (shared module)

```luau
-- ReplicatedStorage/Network.luau
local Net = require(Packages.Net)

Net.useMiddleware(Net.Middleware.rateLimit(20))  -- 20 events/s per player
Net.useMiddleware(Net.Middleware.logger())

return Net.defineNamespace("Combat", function(define)
    define.event("DealDamage", {
        target = "string",
        amount = "number",
    })
    define.request("GetStats", {}, {
        health    = "number",
        maxHealth = "number",
    })
end)
```

### Server

```luau
local Combat = require(Network)

Combat.DealDamage:On(function(player: Player, data)
    -- data.target: string, data.amount: number — validated before reaching here
    applyDamage(player, data.target, data.amount)
end)

Combat.GetStats:Handle(function(player: Player, _request)
    local char = player.Character
    return {
        health    = char.Humanoid.Health,
        maxHealth = char.Humanoid.MaxHealth,
    }
end)

-- Broadcast to all clients
Combat.DealDamage:FireAll({ target = "Boss", amount = 100 })
```

### Client

```luau
local Combat = require(Network)

-- Fire toward server — payload validated against schema before sending
Combat.DealDamage:Fire({ target = "Enemy_01", amount = 35 })

-- Typed request/response
local stats = Combat.GetStats:Invoke({})
print(stats.health, "/", stats.maxHealth)

-- Listen to server-broadcast events
Combat.DealDamage:On(function(_, data)
    UI:showDamageNumber(data.target, data.amount)
end)
```

### Schema types

| Type string | Luau check |
|-------------|------------|
| `"string"`  | `type(v) == "string"` |
| `"number"`  | `type(v) == "number"` |
| `"boolean"` | `type(v) == "boolean"` |
| `"table"`   | `type(v) == "table"` |
| `"Vector3"` | `typeof(v) == "Vector3"` |
| `"CFrame"`  | `typeof(v) == "CFrame"` |
| `"Color3"`  | `typeof(v) == "Color3"` |
| `"UDim2"`   | `typeof(v) == "UDim2"` |
| `"any"`     | always passes |

---

## Installation

### Via Wally (recommended)

Add to your `wally.toml`:

```toml
[dependencies]
Signal  = "luau-toolchain/signal@^1.0.0"
Promise = "luau-toolchain/promise@^1.0.0"
Net     = "luau-toolchain/net@^1.0.0"
```

Then run:

```sh
wally install
```

### Manual

Copy the `packages/<name>/init.luau` file for whichever packages you need
into your project's Packages folder.

---

## Development

This project uses [Rokit](https://github.com/rojo-rbx/rokit) for toolchain management.

```sh
# Install tools (rojo, wally, luau-lsp, lune, stylua)
rokit install

# Type-check all packages
luau-lsp analyze packages/signal/init.luau packages/promise/init.luau packages/net/init.luau

# Run tests
lune run scripts/test.luau

# Format
stylua packages/
```

---

## License

MIT © mattecolors
