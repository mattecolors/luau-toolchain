-- scripts/test.luau
-- Runs the unit test suite via Lune (https://lune-org.github.io/lune)
-- Execute with: lune run scripts/test.luau

local function describe(suite: string, fn: () -> ())
	print(`\n◆ {suite}`)
	fn()
end

local function it(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		print(`  ✓ {label}`)
	else
		print(`  ✗ {label}`)
		print(`    {err}`)
	end
end

local function assertEqual<T>(a: T, b: T, msg: string?)
	if a ~= b then
		error(msg or `expected {tostring(a)} == {tostring(b)}`, 2)
	end
end

local function assertFails(fn: () -> (), msg: string?)
	local ok = pcall(fn)
	if ok then
		error(msg or "expected function to throw but it did not", 2)
	end
end

-- ─── Load packages ────────────────────────────────────────────────────────────
-- In Lune, `require` works relative to the project root.

local Signal  = require("packages/signal")
local Promise = require("packages/promise")

-- ─── Signal tests ─────────────────────────────────────────────────────────────

describe("Signal", function()
	it("fires connected handlers", function()
		local s = Signal.new()
		local fired = false
		s:Connect(function() fired = true end)
		s:Fire()
		assertEqual(fired, true)
	end)

	it("passes arguments to handlers", function()
		local s = Signal.new()
		local received: number = 0
		s:Connect(function(n: number) received = n end)
		s:Fire(42)
		assertEqual(received, 42)
	end)

	it("tracks connection count", function()
		local s = Signal.new()
		assertEqual(s:GetConnectionCount(), 0)
		local c1 = s:Connect(function() end)
		local c2 = s:Connect(function() end)
		assertEqual(s:GetConnectionCount(), 2)
		c1:Disconnect()
		assertEqual(s:GetConnectionCount(), 1)
		c2:Disconnect()
		assertEqual(s:GetConnectionCount(), 0)
	end)

	it("does not fire disconnected handlers", function()
		local s = Signal.new()
		local count = 0
		local conn = s:Connect(function() count += 1 end)
		s:Fire()
		conn:Disconnect()
		s:Fire()
		assertEqual(count, 1)
	end)

	it("ConnectOnce fires exactly once", function()
		local s = Signal.new()
		local count = 0
		s:ConnectOnce(function() count += 1 end)
		s:Fire()
		s:Fire()
		s:Fire()
		assertEqual(count, 1)
	end)

	it("handles disconnect during fire (safe iteration)", function()
		local s = Signal.new()
		local conn: any
		local count = 0
		conn = s:Connect(function()
			count += 1
			conn:Disconnect()
		end)
		s:Fire()
		s:Fire()
		-- Only the first fire should increment because conn is disconnected inside it
		assertEqual(count, 1)
	end)

	it("DisconnectAll removes all handlers", function()
		local s = Signal.new()
		local count = 0
		s:Connect(function() count += 1 end)
		s:Connect(function() count += 1 end)
		s:DisconnectAll()
		s:Fire()
		assertEqual(count, 0)
		assertEqual(s:GetConnectionCount(), 0)
	end)

	it("Destroy cleans up all connections", function()
		local s = Signal.new()
		local count = 0
		s:Connect(function() count += 1 end)
		s:Destroy()
		s:Fire()
		assertEqual(count, 0)
	end)
end)

-- ─── Promise tests ────────────────────────────────────────────────────────────

describe("Promise", function()
	it("resolves synchronously", function()
		local p = Promise.resolve(99)
		assertEqual(p:isResolved(), true)
	end)

	it("rejects synchronously", function()
		local p = Promise.reject("boom")
		assertEqual(p:isRejected(), true)
	end)

	it("andThen receives resolved value", function()
		local result: number = 0
		Promise.resolve(7):andThen(function(n: number)
			result = n
		end)
		-- task.spawn fires the handler asynchronously — give it a tick
		task.wait()
		assertEqual(result, 7)
	end)

	it("catch receives rejection reason", function()
		local reason: string = ""
		Promise.reject("bad"):catch(function(r: string)
			reason = r
		end)
		task.wait()
		assertEqual(reason, "bad")
	end)

	it("chains andThen calls", function()
		local final: number = 0
		Promise.resolve(1)
			:andThen(function(n: number) return n + 1 end)
			:andThen(function(n: number) return n * 10 end)
			:andThen(function(n: number) final = n end)
		task.wait()
		assertEqual(final, 20)
	end)

	it("Promise.all resolves when all resolve", function()
		local result: { number } = {}
		Promise.all({
			Promise.resolve(1),
			Promise.resolve(2),
			Promise.resolve(3),
		}):andThen(function(values: { number })
			result = values
		end)
		task.wait()
		assertEqual(result[1], 1)
		assertEqual(result[2], 2)
		assertEqual(result[3], 3)
	end)

	it("Promise.all rejects when any reject", function()
		local rejected = false
		Promise.all({
			Promise.resolve(1),
			Promise.reject("fail"),
		}):catch(function()
			rejected = true
		end)
		task.wait()
		assertEqual(rejected, true)
	end)

	it("cancel prevents handler execution", function()
		local fired = false
		local p = Promise.new(function(resolve)
			task.delay(0.1, resolve, true)
		end)
		p:andThen(function() fired = true end)
		p:cancel()
		task.wait(0.2)
		assertEqual(fired, false)
		assertEqual(p:isCancelled(), true)
	end)

	it("isPending is true before resolution", function()
		local p = Promise.new(function() end) -- never resolves
		assertEqual(p:isPending(), true)
	end)

	it("status transitions correctly", function()
		local p = Promise.resolve("x")
		assertEqual(p:status(), "Resolved")
	end)
end)

print("\n✔ All tests complete.\n")
