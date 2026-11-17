-- Immutable, allowlisted Space Garden designs. These are in-experience creations.
local Blueprints={}
local function clone(t)
	if type(t)~="table"then return t end
	local result={}for k,v in pairs(t)do result[k]=clone(v)end return result
end
local function integer(v,min,max)return type(v)=="number"and v==v and v%1==0 and v>=min and v<=max end
function Blueprints.NormalizeCode(value)
	if type(value)~="string"or #value~=36 then return nil end
	local a,b,c,d,e=value:match("^(%x+)%-(%x+)%-(%x+)%-(%x+)%-(%x+)$")
	if not a or #a~=8 or #b~=4 or #c~=4 or #d~=4 or #e~=12 then return nil end
	return string.lower(value)
end
function Blueprints.new(store,validate,options)
	options=options or{}
	local now=options.Now or os.time
	local cache={};local cacheOrder={}
	local self={Available=store~=nil}
	local function normalize(record)
		if type(record)~="table"or record.version~=1 or not integer(record.creatorId,1,9007199254740991)or not integer(record.createdAt,0,9007199254740991)then return nil end
		local design=validate(record.design)
		if not design then return nil end
		return {version=1,creatorId=record.creatorId,createdAt=record.createdAt,design=design}
	end
	local function remember(code,value,seconds)
		if not cache[code]then table.insert(cacheOrder,code)end
		cache[code]={record=value,expires=now()+seconds}
		while #cacheOrder>128 do local first=table.remove(cacheOrder,1);cache[first]=nil end
	end
	function self:Publish(code,userId,raw,createdAt)
		code=Blueprints.NormalizeCode(code)
		local design=validate(raw)
		if not code or not design or not integer(userId,1,9007199254740991)then return false,"Nieprawidłowy projekt."end
		if not self.Available then return false,"Publikowanie kodów wymaga gry z trwałym zapisem."end
		local candidate={version=1,creatorId=userId,createdAt=integer(createdAt,0,9007199254740991)and createdAt or now(),design=design}
		local ok,result=pcall(function()
			return store:UpdateAsync("b_"..code,function(old)
				if old==nil then return clone(candidate)end
				local existing=normalize(old)
				if existing and existing.creatorId==userId and existing.design.shape==design.shape and existing.design.palette==design.palette and existing.design.scale==design.scale then return old end
				return nil -- a code is immutable, including creator identity
			end)
		end)
		if ok and result then remember(code,normalize(result),60);return true end
		return false,"Stacja nie potwierdziła publikacji. Projekt pozostaje w kolejce."
	end
	function self:Fetch(code)
		code=Blueprints.NormalizeCode(code)
		if not code then return nil,"Kod musi mieć format UUID (36 znaków)."end
		if not self.Available then return nil,"Import kodów wymaga opublikowanej gry i trwałego zapisu."end
		local cached=cache[code]
		if cached and cached.expires>now()then
			if cached.record then return clone(cached.record)end
			return nil,"Nie znaleziono projektu."
		end
		if options.CanRead and not options.CanRead()then return nil,"Stacja jest zajęta. Spróbuj za chwilę."end
		local ok,raw=pcall(function()return store:GetAsync("b_"..code)end)
		if not ok then return nil,"Nie udało się pobrać projektu. Spróbuj ponownie."end
		local record=normalize(raw)
		remember(code,record,record and 60 or 15)
		if record then return clone(record)end
		return nil,"Nie znaleziono poprawnego projektu."
	end
	return self
end
function Blueprints.RunTests()
	local rows,reads={},0
	local fake={}
	function fake:UpdateAsync(key,fn)local r=fn(clone(rows[key]));if r then rows[key]=clone(r)end return clone(r)end
	function fake:GetAsync(key)reads+=1;return clone(rows[key])end
	local function validate(d)
		if type(d)~="table"or d.shape~="OrbitBloom"or d.palette~="Aurora"or d.scale~=1 then return nil end
		for k in pairs(d)do if k~="shape"and k~="palette"and k~="scale"then return nil end end
		return clone(d)
	end
	local checked={}
	local function check(name,value)assert(value,name);table.insert(checked,name)end
	local api=Blueprints.new(fake,validate,{Now=function()return 1793620000 end})
	local code="12345678-abcd-4abc-9abc-123456789abc"
	local design={shape="OrbitBloom",palette="Aurora",scale=1}
	check("UUID normalization",Blueprints.NormalizeCode(string.upper(code))==code)
	check("invalid code rejected",not Blueprints.NormalizeCode("https://example.test/script"))
	check("publish immutable design",api:Publish(code,123,design))
	check("idempotent retry",api:Publish(code,123,design))
	check("creator cannot be replaced",not api:Publish(code,456,design))
	local malicious=clone(design);malicious.assetId=123
	check("arbitrary assets rejected",not api:Publish(code,123,malicious))
	local r=api:Fetch(code);check("sanitized fetch",r and r.creatorId==123 and r.design.shape=="OrbitBloom")
	r.design.shape="Injected";r=api:Fetch(code);check("cached records are copied",r.design.shape=="OrbitBloom")
	local misses=reads;api:Fetch("aaaaaaaa-abcd-4abc-9abc-123456789abc");api:Fetch("aaaaaaaa-abcd-4abc-9abc-123456789abc")
	check("negative cache limits reads",reads==misses+1)
	local disabled=Blueprints.new(nil,validate);check("Studio publication disabled",not disabled:Publish(code,123,design))
	function fake:GetAsync()error("outage")end
	check("read outage handled",not api:Fetch("bbbbbbbb-abcd-4abc-9abc-123456789abc"))
	rows["b_cccccccc-abcd-4abc-9abc-123456789abc"]={version=999,creatorId=123,createdAt=0,design=design}
	check("unknown record version protected",not api:Publish("cccccccc-abcd-4abc-9abc-123456789abc",123,design))
	return {passed=#checked,checks=checked}
end
return Blueprints
