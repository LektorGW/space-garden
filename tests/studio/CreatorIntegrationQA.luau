return function(api,player)
	local ss=game:GetService("ServerStorage")
	local Decor=require(ss.SpaceGardenDecorations)
	local Catalog=require(game.ReplicatedStorage.SpaceGarden.DecorCatalog)
	local profile=api.Profiles[player]
	profile.data=api.NewData();profile.render={}
	local checks={}
	local function check(value,label)assert(value,label);table.insert(checks,label)end
	local function request(action,args)
		task.wait(1.05)
		return api.Request(player,action,args or{})
	end
	local r=request("SaveDesign",{slot=1,shape="OrbitBloom",palette="Aurora",scale=1})
	check(r.ok and r.state.decorations.designs[1].design.shape=="OrbitBloom","four-field design save schema and snapshot")
	r=request("PlaceDesign",{stand=1,slot=1})
	check(r.ok and profile.farm.GeneratedDecorations:FindFirstChild("Stand1"),"saved design appears in own greenhouse")
	local stand=profile.farm.GeneratedDecorations.Stand1
	check(stand:GetAttribute("DesignShape")=="OrbitBloom","rendered design matches selected species")
	r=api.Request(player,"SaveDesign",{slot=1,shape="PrismSpire",palette="Nebula",scale=1})
	check(not r.ok and profile.data.decorations.designs["1"].shape=="OrbitBloom","rapid design changes are throttled")
	r=request("SaveDesign",{slot=1,shape="Injected",palette="Aurora",scale=1})
	check(not r.ok and profile.data.decorations.designs["1"].shape=="OrbitBloom","unknown geometry rejected without changing saved design")
	r=request("SaveDesign",{slot=1,shape="OrbitBloom",palette="Aurora",scale=math.huge})
	check(not r.ok,"non-finite scale rejected through real request")
	r=api.Request(player,"SaveDesign",{slot=1,shape="OrbitBloom",palette="Aurora",scale=1,source="return 1"})
	check(not r.ok,"extra script payload rejected by remote schema")
	r=request("PlaceDesign",{stand=1,slot=1,farm="Farm2"})
	check(not r.ok,"client cannot choose another player's farm")
	r=request("SaveDesign",{slot=2,shape="HelixFern",palette="Nebula",scale=1.4})
	check(r.ok and r.state.decorations.designs[2].design.scale==1.4,"second design slot preserves maximum canonical scale")
	r=request("PlaceDesign",{stand=3,slot=2})
	check(r.ok and profile.farm.GeneratedDecorations.Stand3:GetAttribute("DesignShape")=="HelixFern","third stand uses saved design reference")
	r=request("RemoveDesign",{stand=1})
	check(r.ok and not profile.farm.GeneratedDecorations:FindFirstChild("Stand1"),"removing display clears only selected stand")
	r=request("PublishDesign",{slot=2});check(not r.ok and not r.code,"Studio cannot publish external blueprint")
	r=request("ImportDesign",{slot=3,code="12345678-abcd-4abc-9abc-123456789abc"});check(not r.ok,"Studio import fails closed without live datastore")
	r=request("GlobalSeason",{});check(not r.ok,"Studio cannot mint global live reward")
	check(r.state.globalRanking.scope=="studio"and not r.state.globalRanking.available,"ranking fallback explicitly reports Studio scope")
	local sanitized=api.Sanitize(profile.data)
	check(sanitized.decorations.designs["2"].shape=="HelixFern"and sanitized.decorations.stands["3"]==2,"profile sanitizer preserves design and display references")
	local clone=profile.farm:Clone()
	local combinations=0
	for _,shape in ipairs(Catalog.ShapeOrder)do
		for _,palette in ipairs(Catalog.PaletteOrder)do
			local design={shape=shape,palette=palette,scale=1.4}
			local data={designs={["1"]=design},stands={["1"]=1,["2"]=1,["3"]=1}}
			local folder,reason=Decor.Render(clone,data);assert(folder,reason)
			check(folder:GetAttribute("PartCount")<=320,"geometry budget "..shape.." / "..palette)
			for _,part in ipairs(folder:GetDescendants())do if part:IsA("BasePart")then assert(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery,"passive display geometry")end end
			assert(Decor.Render(clone,data)==folder,"unchanged render is cached")
			combinations+=1;if combinations%4==0 then task.wait()end
		end
	end
	Decor.Clear(clone);check(not clone:FindFirstChild("GeneratedDecorations"),"renderer cleanup removes generated display")
	clone:Destroy()
	profile.data=api.NewData();profile.render={};task.wait(2)
	return{passed=#checks,checks=checks,renderedCombinations=combinations}
end
