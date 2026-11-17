-- Space Garden: replayable global projections of committed player profiles.
-- Monthly counters use a fixed radix-128 tree. Every record has <=128 slots;
-- absolute max updates make retries and out-of-order servers idempotent.
-- No IncrementAsync, client-derived values, listing scans, or unbounded shard maps.
local GlobalProgress = {}
local RADIX, ROOT_LEVEL, VALUE_CAP, MAX_EXACT = 128, 7, 1000000000, 9007199254740991

local function clone(value)
	if type(value) ~= "table" then return value end
	local result = {}; for key, item in pairs(value) do result[key] = clone(item) end; return result
end
local function integer(value, minimum, maximum)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge and value % 1 == 0 and value >= minimum and value <= maximum
end
local function validPeriod(value)
	if type(value) ~= "string" then return false end
	local year, month = value:match("^(%d%d%d%d)%-(%d%d)$")
	return year ~= nil and tonumber(year) >= 2000 and tonumber(month) >= 1 and tonumber(month) <= 12
end
local function nodeKey(period, level, node)
	return "m_" .. period .. "_l" .. level .. "_n" .. string.format("%.0f", node)
end
local function readNode(raw, period, level, node)
	if raw == nil then return {v = 1, period = period, level = level, node = node, values = {}, total = 0} end
	if type(raw) ~= "table" or raw.v ~= 1 or raw.period ~= period or raw.level ~= level or raw.node ~= node or type(raw.values) ~= "table" then error("Global progress schema mismatch") end
	local result = {v = 1, period = period, level = level, node = node, values = {}, total = 0}
	local count = 0
	for slot, value in pairs(raw.values) do
		count += 1
		local index = type(slot) == "string" and tonumber(slot)
		if count > RADIX or not integer(index, 0, RADIX - 1) or tostring(index) ~= slot or not integer(value, 0, level == 0 and VALUE_CAP or MAX_EXACT) then error("Invalid global progress slot") end
		result.values[slot] = value
		result.total = math.min(MAX_EXACT, result.total + value)
	end
	return result
end

function GlobalProgress.new(options)
	options = options or {}
	local self = {}
	local studio = options.Studio == true
	local config = options.Config or {}
	local adapters = options.Adapters or {}
	local now = adapters.Now or os.time
	local clock = adapters.Clock or os.clock
	local wait = adapters.Wait or task.wait
	local spawn = adapters.Spawn or task.spawn
	local month = function() return os.date("!%Y-%m", now()) end
	local seasonStore, rankStore = adapters.SeasonStore, adapters.RankingStore
	local requestAllowed = adapters.CanRequest
	local resolveUser = adapters.ResolveUser
	local enabled, initializationError = not studio, nil
	if not studio and (not seasonStore or not rankStore) then
		local ok, result = pcall(function()
			local dataStores = game:GetService("DataStoreService")
			local prefix = config.GlobalStorePrefix or "SpaceGardenGlobal_v1"
			return {season = dataStores:GetDataStore(prefix .. "_Month"), ranking = dataStores:GetOrderedDataStore(prefix .. "_Harvest")}
		end)
		if ok then seasonStore = result.season; rankStore = result.ranking else enabled = false; initializationError = tostring(result) end
	end
	if not requestAllowed then
		requestAllowed = function(kind)
			local ok, allowed = pcall(function()
				local service = game:GetService("DataStoreService")
				if kind == "season-write" then
					return service:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardRead) >= 4 and service:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardWrite) >= 4
				elseif kind == "rank-write" then
					return service:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedRead) >= 2 and service:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedWrite) >= 2
				elseif kind == "rank-read" then
					return service:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedList) >= 1
				end
				return service:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardRead) >= 2
			end)
			return ok and allowed
		end
	end
	if not resolveUser then resolveUser = function(userId) return game:GetService("Players"):GetNameFromUserIdAsync(userId) end end
	local maxPending = math.clamp(options.MaxPending or 256, 1, 512)
	local queue, queueCount, committed, cacheOrder = {}, 0, {}, {}
	local names, nameOrder = {}, {}
	local currentPeriod = month()
	local total, seasonUpdated, seasonAvailable, seasonLoading = 0, 0, false, false
	local ranking, rankingUpdated, rankingAvailable, rankingLoading = {}, 0, false, false
	local seasonAttempted, rankingAttempted = false, false
	local nextSeasonRead, nextRankingRead = -math.huge, -math.huge
	local refreshing, flushing, started, closed = false, false, false, false
	local lastError = initializationError
	local function rollover()
		local period = month()
		if currentPeriod ~= period then
			currentPeriod = period; total = 0; seasonUpdated = 0; seasonAvailable = false; seasonAttempted = false; nextSeasonRead = -math.huge
		end
	end
	local function checkRequest(kind, deadline)
		if deadline and clock() >= deadline then error("Global flush deadline") end
		if not requestAllowed(kind) then error("Global request budget reserved for player profiles") end
	end
	local function remember(userId, harvested, period, progress)
		local key = tostring(userId)
		if not committed[key] then
			table.insert(cacheOrder, key)
			if #cacheOrder > 256 then committed[table.remove(cacheOrder, 1)] = nil end
		end
		local old = committed[key] or {harvested = 0, period = period, progress = 0}
		old.harvested = math.max(old.harvested, harvested)
		if old.period ~= period then old.period = period; old.progress = progress else old.progress = math.max(old.progress, progress) end
		committed[key] = old
	end
	local function updateMonthly(userId, period, progress, deadline)
		local node = math.floor(userId / RADIX)
		local slot = tostring(userId % RADIX)
		local absolute = progress
		for level = 0, ROOT_LEVEL do
			checkRequest("season-write", deadline)
			local thisNode, thisSlot, thisAbsolute, thisLevel = node, slot, absolute, level
			local record = seasonStore:UpdateAsync(nodeKey(period, thisLevel, thisNode), function(old)
				local updated = readNode(old, period, thisLevel, thisNode)
				updated.values[thisSlot] = math.max(updated.values[thisSlot] or 0, thisAbsolute)
				updated.total = 0
				for _, value in pairs(updated.values) do updated.total = math.min(MAX_EXACT, updated.total + value) end
				return updated
			end)
			if not record then error("Global update cancelled") end
			absolute = readNode(record, period, thisLevel, thisNode).total
			slot = tostring(node % RADIX); node = math.floor(node / RADIX)
		end
		if period == month() then
			rollover(); total = math.max(total, absolute); seasonAvailable = true; seasonUpdated = now()
		end
	end
	function self:Submit(userId, harvested, period, progress)
		if not enabled or closed then return false, studio and "Studio" or "Unavailable" end
		if not integer(userId, 1, MAX_EXACT) or not integer(harvested, 0, VALUE_CAP) or not validPeriod(period) or not integer(progress, 0, VALUE_CAP) then return false, "Invalid committed counters" end
		rollover()
		local key, current = tostring(userId), month()
		local old = queue[key]
		local seen = committed[key]
		local rankDirty = harvested > (seen and seen.harvested or 0)
		local seasonDirty = period == current and progress > (seen and seen.period == period and seen.progress or 0)
		if not old and not rankDirty and not seasonDirty then return true end
		if not old then
			if queueCount >= maxPending then lastError = "Global projection queue full; committed profile will repair on rejoin"; return false, "QueueFull" end
			old = {userId = userId, harvested = 0, period = current, progress = 0, version = 0, nextAttempt = 0, failures = 0}
			queue[key] = old; queueCount += 1
		end
		old.harvested = math.max(old.harvested, harvested)
		if old.period ~= current then old.period = current; old.progress = 0 end
		if period == current then old.progress = math.max(old.progress, progress) end
		old.version += 1
		return true
	end
	function self:Flush(limit, deadline, ignoreBackoff)
		if not enabled or flushing then return false, "Unavailable or busy" end
		flushing = true
		rollover()
		local attempted, completed = 0, 0
		local keys = {}; for key in pairs(queue) do table.insert(keys, key) end
		table.sort(keys, function(a, b) return queue[a].nextAttempt < queue[b].nextAttempt end)
		for _, key in ipairs(keys) do
			if attempted >= (limit or 4) or (deadline and clock() >= deadline) then break end
			local entry = queue[key]
			if entry and (ignoreBackoff or entry.nextAttempt <= clock()) then
				attempted += 1
				local work = clone(entry)
				local ok, err = pcall(function()
					local seen = committed[key]
					if work.harvested > (seen and seen.harvested or 0) then
						checkRequest("rank-write", deadline)
						local stored = rankStore:UpdateAsync(key, function(old)
							if old ~= nil and not integer(old, 0, VALUE_CAP) then error("Invalid ordered harvest counter") end
							return math.max(old or 0, work.harvested)
						end)
						if not integer(stored, 0, VALUE_CAP) then error("Ranking update cancelled") end
					end
					if work.period == month() and work.progress > (seen and seen.period == work.period and seen.progress or 0) then updateMonthly(work.userId, work.period, work.progress, deadline) end
				end)
				if ok then
					remember(work.userId, work.harvested, work.period, work.progress)
					if queue[key] and queue[key].version == work.version then queue[key] = nil; queueCount -= 1 else entry.failures = 0; entry.nextAttempt = 0 end
					completed += 1
				else
					lastError = tostring(err)
					entry.failures += 1; entry.nextAttempt = clock() + math.min(120, 2 ^ math.min(6, entry.failures))
				end
			end
		end
		flushing = false
		return true, {attempted = attempted, completed = completed, pending = queueCount}
	end
	local function userName(userId, remaining)
		local key = tostring(userId)
		local cached = names[key]
		if cached and cached.expires > now() then return cached.name, cached.displayName end
		if remaining.count <= 0 then return cached and cached.name or ("Ogrodnik " .. key), cached and cached.displayName or ("Ogrodnik " .. key) end
		remaining.count -= 1
		local ok, name, displayName = pcall(resolveUser, userId)
		if not ok or type(name) ~= "string" or #name < 1 then name = "Ogrodnik " .. key; displayName = name end
		if type(displayName) ~= "string" or #displayName < 1 then displayName = name end
		if not names[key] then table.insert(nameOrder, key); if #nameOrder > 256 then names[table.remove(nameOrder, 1)] = nil end end
		names[key] = {name = name, displayName = displayName, expires = now() + (ok and 3600 or 60)}
		return name, displayName
	end
	function self:Refresh()
		if not enabled or refreshing or closed then return false end
		refreshing = true
		rollover()
		local period = currentPeriod
		if clock() >= nextSeasonRead then
			seasonLoading = true; seasonAttempted = true; nextSeasonRead = clock() + 30
			local ok, value = pcall(function()
				checkRequest("season-read")
				return readNode(seasonStore:GetAsync(nodeKey(period, ROOT_LEVEL, 0)), period, ROOT_LEVEL, 0).total
			end)
			if period == month() then
				if ok then total = math.max(total, value); seasonUpdated = now(); seasonAvailable = true else lastError = tostring(value); seasonAvailable = false end
			end
			seasonLoading = false
		end
		if clock() >= nextRankingRead then
			rankingLoading = true; rankingAttempted = true; nextRankingRead = clock() + 60
			local ok, result = pcall(function()
				checkRequest("rank-read")
				local rows = rankStore:GetSortedAsync(false, 20):GetCurrentPage()
				local entries, remaining = {}, {count = 4}
				for index, row in ipairs(rows) do
					if index > 20 then break end
					local userId = tonumber(row.key)
					if integer(userId, 1, MAX_EXACT) and integer(row.value, 0, VALUE_CAP) then
						local name, displayName = userName(userId, remaining)
						table.insert(entries, {userId = userId, name = name, displayName = displayName, harvested = row.value})
					end
				end
				return entries
			end)
			if ok then ranking = result; rankingUpdated = now(); rankingAvailable = true else lastError = tostring(result); rankingAvailable = false end
			rankingLoading = false
		end
		refreshing = false
		return true
	end
	function self:Snapshot(fallbackEntries, fallbackTotal)
		rollover()
		local freshSeason = enabled and seasonAvailable and now() - seasonUpdated <= 180
		local freshRanking = enabled and rankingAvailable and now() - rankingUpdated <= 300
		return {
			globalRanking = {available = freshRanking, loading = rankingLoading or (enabled and not rankingAttempted), updatedAt = rankingUpdated, scope = studio and "studio" or "global", entries = clone(studio and (fallbackEntries or {}) or ranking)},
			season = {available = freshSeason, loading = seasonLoading or (enabled and not seasonAttempted), total = studio and (fallbackTotal or 0) or total, updatedAt = seasonUpdated, period = currentPeriod, scope = studio and "studio" or "global"},
			pending = queueCount, live = enabled, error = lastError,
		}
	end
	function self:Start()
		if started or not enabled then return end
		started = true
		spawn(function()
			local nextFlush = clock() + 90
			while not closed do
				if clock() >= nextFlush then self:Flush(4, clock() + 12); nextFlush = clock() + 90 end
				self:Refresh()
				wait(10)
			end
		end)
	end
	function self:Close(deadline)
		closed = true
		deadline = deadline or clock() + 10
		while flushing and clock() < deadline do wait(0.05) end
		if enabled and queueCount > 0 and clock() < deadline then self:Flush(maxPending, deadline, true) end
		return queueCount == 0
	end
	return self
end

function GlobalProgress.RunTests()
	local rows, ranks, failuresBefore, failuresAfter = {}, {}, {}, {}
	local epoch, tick = 1793577600, 0 -- 2026-11-02 UTC
	local writes, reads, nameCalls = 0, 0, 0
	local store, ranking = {}, {}
	function store:UpdateAsync(key, transform)
		writes += 1
		if failuresBefore[key] then error("Injected before commit") end
		local result = transform(clone(rows[key])); if result then rows[key] = clone(result) end
		if failuresAfter[key] then error("Injected after commit timeout") end
		return clone(result)
	end
	function store:GetAsync(key) reads += 1; if failuresBefore[key] then error("Injected read failure") end; return clone(rows[key]) end
	function ranking:UpdateAsync(key, transform)
		writes += 1
		if failuresBefore["rank:" .. key] then error("Injected ordered failure") end
		local result = transform(ranks[key]); ranks[key] = result
		if failuresAfter["rank:" .. key] then error("Injected ordered timeout") end
		return result
	end
	function ranking:GetSortedAsync(_, pageSize)
		reads += 1
		local entries = {}; for key, value in pairs(ranks) do table.insert(entries, {key = key, value = value}) end
		table.sort(entries, function(a, b) return a.value > b.value end)
		while #entries > pageSize do table.remove(entries) end
		return {GetCurrentPage = function() return entries end}
	end
	local adapters = {SeasonStore = store, RankingStore = ranking, Now = function() return epoch end, Clock = function() return tick end, CanRequest = function() return true end, ResolveUser = function(id) nameCalls += 1; return "Player" .. id end}
	local a, b = GlobalProgress.new({Adapters = adapters}), GlobalProgress.new({Adapters = adapters})
	local period = os.date("!%Y-%m", epoch)
	local checks = {}
	local function check(condition, label) assert(condition, label); table.insert(checks, label) end
	check(a:Submit(1, 10, period, 10), "accept committed absolute checkpoint")
	a:Submit(1, 20, period, 20); a:Submit(2, 5, period, 5); a:Flush(4)
	check(a:Snapshot().season.total == 25 and ranks["1"] == 20, "coalesce latest counters before writes")
	local oldWrites = writes; a:Submit(1, 20, period, 20); a:Flush(4)
	check(writes == oldWrites, "repeated acknowledged checkpoints do not write")
	b:Submit(1, 15, period, 15); b:Flush(4); b:Refresh()
	check(b:Snapshot().season.total == 25 and ranks["1"] == 20, "second server cannot lower user or global counters")
	b:Submit(129, 30, period, 30); b:Flush(4); tick += 31; a:Refresh()
	check(a:Snapshot().season.total == 55, "two servers aggregate distinct leaf buckets")
	local failedKey = nodeKey(period, 3, 0)
	failuresBefore[failedKey] = true; a:Submit(3, 8, period, 8); a:Flush(4)
	check(a:Snapshot().pending == 1, "partial tree failure retains queued checkpoint")
	failuresBefore[failedKey] = nil; tick += 3; a:Flush(4); tick += 31; a:Refresh()
	check(a:Snapshot().season.total == 63 and a:Snapshot().pending == 0, "partial tree retry repairs rollups without duplicating")
	failuresAfter[nodeKey(period, 0, 0)] = true; b:Submit(4, 9, period, 9); b:Flush(4)
	check(b:Snapshot().pending == 1, "timeout after leaf commit remains retryable")
	failuresAfter[nodeKey(period, 0, 0)] = nil; tick += 3; b:Flush(4); tick += 31; b:Refresh()
	check(b:Snapshot().season.total == 72, "committed leaf replay counts once")
	failuresAfter["rank:5"] = true; a:Submit(5, 12, period, 12); a:Flush(4)
	failuresAfter["rank:5"] = nil; tick += 3; a:Flush(4); tick += 31; a:Refresh()
	check(a:Snapshot().season.total == 84 and ranks["5"] == 12, "ordered timeout and replay remain monotonic")
	for _, record in pairs(rows) do local count = 0; for _ in pairs(record.values) do count += 1 end; assert(count <= RADIX, "bounded slots") end
	check(true, "all sparse tree schemas are bounded to 128 slots")
	oldWrites = writes; b:Submit(6, 8, "2026-10", 500); b:Flush(4); tick += 31; b:Refresh()
	check(b:Snapshot().season.total == 84 and ranks["6"] == 8 and writes == oldWrites + 1, "old-month counts never enter current-month challenge")
	local oldReads = reads; b:Refresh(); b:Refresh()
	check(reads == oldReads, "cached reads cannot be spammed by snapshots or refresh calls")
	check(#b:Snapshot().globalRanking.entries <= 20 and nameCalls <= 20, "ranking and username queries are bounded and cached")
	epoch = 1796083200 -- 2026-12-01 UTC
	check(a:Snapshot().season.total == 0 and not a:Snapshot().season.available, "month rollover invalidates old global cache immediately")
	a:Submit(1, 21, period, 21); a:Flush(4); a:Refresh()
	check(a:Snapshot().season.total == 0 and ranks["1"] == 21, "stale checkpoint after rollover only advances lifetime ranking")
	local december = os.date("!%Y-%m", epoch)
	a:Submit(1, 22, december, 1); a:Flush(4)
	check(a:Snapshot().season.total == 1, "new month starts from new absolute contribution")
	local tiny = GlobalProgress.new({Adapters = adapters, MaxPending = 1})
	check(tiny:Submit(7, 1, december, 1) and not tiny:Submit(8, 1, december, 1), "pending memory is bounded without accepting dropped work")
	local studio = GlobalProgress.new({Studio = true})
	check(not studio:Submit(1, 10, december, 10) and studio:Snapshot({{userId = -1, harvested = 3}}, 3).globalRanking.scope == "studio" and not studio:Snapshot().season.available, "Studio fallback never claims real global service")
	check(not a:Submit(0 / 0, 1, december, 1) and not a:Submit(1, math.huge, december, 1) and not a:Submit(1, 1, "2026-99", 1), "invalid and non-finite committed counters rejected")
	return {passed = #checks, checks = checks, writes = writes, reads = reads}
end

return GlobalProgress
