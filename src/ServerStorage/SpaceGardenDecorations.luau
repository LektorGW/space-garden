-- Server-only, fixed-budget renderer for original in-game garden designs.
-- Public API: Validate(raw), SanitizeProfile(raw), Render(farm, decorations), Clear(farm).
-- No currency, networking, marketplace publishing, profile persistence or arbitrary assets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Catalog = require(ReplicatedStorage:WaitForChild("SpaceGarden"):WaitForChild("DecorCatalog"))
local Decorations = {}
local renderCache = setmetatable({}, {__mode="k"})
local ALLOWED_KEYS = {shape=true,palette=true,scale=true}
local WHITE = Color3.fromRGB(233,249,255)
local NAVY = Color3.fromRGB(20,34,52)
local METAL = Color3.fromRGB(76,96,112)
local MAX_RENDER_PARTS = 320

local function finite(value)
    return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
end

function Decorations.Validate(raw)
    if type(raw)~="table" or getmetatable(raw)~=nil then
        return nil,"Projekt musi zawierać wyłącznie kształt, paletę i skalę."
    end
    local count=0
    for key in pairs(raw) do
        count+=1
        if count>3 or type(key)~="string" or not ALLOWED_KEYS[key] then
            return nil,"Projekt zawiera niedozwolone dane."
        end
    end
    if type(raw.shape)~="string" or #raw.shape>32 or not Catalog.Shapes[raw.shape] then
        return nil,"Wybierz kształt z katalogu."
    end
    if type(raw.palette)~="string" or #raw.palette>32 or not Catalog.Palettes[raw.palette] then
        return nil,"Wybierz paletę z katalogu."
    end
    if not finite(raw.scale) or raw.scale<Catalog.MinScale or raw.scale>Catalog.MaxScale then
        return nil,"Skala projektu musi mieścić się w zakresie 0,7–1,4."
    end
    -- Canonical hundredths bound persisted data and make render signatures stable.
    local scale=math.clamp(math.floor(raw.scale*100+.5)/100,Catalog.MinScale,Catalog.MaxScale)
    return {shape=raw.shape,palette=raw.palette,scale=scale}
end

function Decorations.SanitizeProfile(raw)
    local result={designs={},stands={}}
    if type(raw)~="table" then return result end
    local designs=type(raw.designs)=="table" and raw.designs or {}
    local stands=type(raw.stands)=="table" and raw.stands or {}
    for slot=1,Catalog.MaxDesigns do
        local key=tostring(slot)
        local candidate=designs[key]
        if candidate==nil then candidate=designs[slot] end
        local design=Decorations.Validate(candidate)
        if design then result.designs[key]=design end
    end
    for stand=1,Catalog.MaxStands do
        local key=tostring(stand)
        local slot=stands[key]
        if slot==nil then slot=stands[stand] end
        if finite(slot) and slot%1==0 and slot>=1 and slot<=Catalog.MaxDesigns and result.designs[tostring(slot)] then
            result.stands[key]=slot
        end
    end
    return result
end

local function validFarm(farm)
    return typeof(farm)=="Instance" and farm:IsA("Model")
end

function Decorations.Clear(farm)
    if not validFarm(farm) then return end
    local folder=farm:FindFirstChild("GeneratedDecorations")
    if folder then folder:Destroy() end
    renderCache[farm]=nil
end

local function signatureOf(profile)
    local pieces={}
    for stand=1,Catalog.MaxStands do
        local slot=profile.stands[tostring(stand)]
        local design=slot and profile.designs[tostring(slot)]
        pieces[stand]=design and table.concat({stand,slot,design.shape,design.palette,string.format("%.2f",design.scale)},":") or tostring(stand)..":empty"
    end
    return table.concat(pieces,"|")
end

function Decorations.Render(farm,rawProfile)
    if not validFarm(farm) then return nil,"Nieprawidłowy ogród." end
    local floor=farm:FindFirstChild("Floor")
    local spawn=farm:FindFirstChild("Spawn")
    if not floor or not floor:IsA("BasePart") or not spawn or not spawn:IsA("BasePart") then
        return nil,"Brak punktów mocowania dekoracji."
    end
    local profile=Decorations.SanitizeProfile(rawProfile)
    local signature=signatureOf(profile)
    local old=farm:FindFirstChild("GeneratedDecorations")
    if old and renderCache[farm]==signature then return old end

    -- Build off the live tree. At most three bounded sculptures (<320 parts).
    local generated=Instance.new("Folder")
    generated.Name="GeneratedDecorations"
    local count=0
    local front=floor.CFrame:PointToObjectSpace(spawn.Position).Z>=0 and 1 or -1

    local function renderSculpture(standIndex,design)
        local sculpture=Instance.new("Model")
        sculpture.Name="Stand"..standIndex
        sculpture:SetAttribute("DesignShape",design.shape)
        sculpture:SetAttribute("DesignPalette",design.palette)
        sculpture:SetAttribute("DesignScale",design.scale)
        sculpture.Parent=generated
        local palette=Catalog.Palettes[design.palette].Color
        local soft=palette:Lerp(WHITE,.48)
        local dark=palette:Lerp(NAVY,.45)
        local scale=design.scale
        -- Beds end at |z|=25.5, window at |z|=35.5. The rear strip at
        -- |z|=31 leaves entrances and every bed free, including maximum scale.
        local origin=floor.CFrame*CFrame.new((standIndex-2)*22,floor.Size.Y/2+.15,-front*31)

        local function part(name,size,localCF,color,material,shape,transparency,className)
            count+=1
            assert(count<=MAX_RENDER_PARTS,"Decoration geometry budget exceeded")
            local p=Instance.new(className or "Part")
            p.Name=name
            p.Size=size*scale
            p.CFrame=origin*CFrame.new(localCF.Position*scale)*localCF.Rotation
            p.Color=color or palette
            p.Material=material or Enum.Material.SmoothPlastic
            p.Transparency=transparency or 0
            p.Anchored=true
            p.CanCollide=false
            p.CanTouch=false
            p.CanQuery=false
            p.CastShadow=false
            p.TopSurface=Enum.SurfaceType.Smooth
            p.BottomSurface=Enum.SurfaceType.Smooth
            if shape and p:IsA("Part") then p.Shape=shape end
            p.Parent=sculpture
            return p
        end
        local function ball(name,pos,size,color,transparency)
            return part(name,size,CFrame.new(pos),color,Enum.Material.SmoothPlastic,Enum.PartType.Ball,transparency)
        end
        local function rod(name,a,b,width,color,neon)
            return part(name,Vector3.new(width,width,(b-a).Magnitude),CFrame.lookAt((a+b)/2,b),color,neon and Enum.Material.Neon or Enum.Material.SmoothPlastic)
        end
        local function disk(name,y,diameter,height,color,neon)
            return part(name,Vector3.new(height,diameter,diameter),CFrame.new(0,y,0)*CFrame.Angles(0,0,math.pi/2),color,neon and Enum.Material.Neon or Enum.Material.Metal,Enum.PartType.Cylinder)
        end
        local function petal(name,center,direction,size,color)
            return part(name,size,CFrame.lookAt(center,center+direction)*CFrame.Angles(math.pi/2,0,0),color,Enum.Material.SmoothPlastic,Enum.PartType.Ball)
        end
        disk("ExhibitFoot",.2,5.1,.4,NAVY)
        disk("ExhibitRim",.43,4.85,.12,palette,true)
        disk("ExhibitInset",.54,4.55,.16,METAL)
        disk("RootPlatform",.67,3.7,.13,dark)
        for i=1,8 do
            local a=i*math.pi/4
            part("BaseIndicator",Vector3.new(.26,.07,.5),CFrame.new(math.cos(a)*2.18,.66,math.sin(a)*2.18)*CFrame.Angles(0,-a,0),soft,Enum.Material.Neon)
        end

        if design.shape=="OrbitBloom" then
            rod("Stem",Vector3.new(0,.75,0),Vector3.new(0,4.3,0),.34,dark)
            rod("StemLight",Vector3.new(.18,1,0),Vector3.new(.18,4.1,0),.09,palette,true)
            local center=Vector3.new(0,4.8,0)
            ball("OrbitalBud",center,Vector3.new(1.7,1.7,1.7),palette)
            part("BudLight",Vector3.new(.8,.8,.8),CFrame.new(center),soft,Enum.Material.Neon,Enum.PartType.Ball)
            for orbit=1,2 do
                local cf=CFrame.new(center)*CFrame.Angles(math.rad(orbit==1 and 28 or 112),0,math.rad(orbit==1 and 30 or -25))
                local radius=orbit==1 and 2.08 or 1.81
                for segment=1,24 do
                    local a,b=(segment-1)*math.pi/12,segment*math.pi/12
                    local p1=cf:PointToWorldSpace(Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius))
                    local p2=cf:PointToWorldSpace(Vector3.new(math.cos(b)*radius,0,math.sin(b)*radius))
                    rod("OrbitHalo",p1,p2,orbit==1 and .12 or .08,orbit==1 and palette or soft,true)
                end
            end
            for i=1,6 do
                local a=i*math.pi/3
                local dir=Vector3.new(math.cos(a),.55,math.sin(a))
                petal("BudSepal",Vector3.new(math.cos(a)*.8,3.9,math.sin(a)*.8),dir,Vector3.new(.55,1.65,.8),dark)
            end
        elseif design.shape=="PrismSpire" then
            for i=1,5 do
                local a=(i-1)*math.pi/2
                local radial=i==5 and 0 or 1.25
                local height=i==5 and 5.45 or 3.3+(i%3)*.55
                local x,z=math.cos(a)*radial,math.sin(a)*radial
                local crystal=CFrame.new(x,.88+height/2,z)*CFrame.Angles(math.sin(a)*.11,a+math.pi/4,math.cos(a)*.11)
                part("PrismCrystal",Vector3.new(.95,height,.95),crystal,i==5 and soft or palette,Enum.Material.Glass,nil,.16)
                part("CrystalCore",Vector3.new(.27,height*.88,.27),crystal,palette,Enum.Material.Neon)
                part("PrismApex",Vector3.new(.95,1.3,.95),crystal*CFrame.new(0,height/2+.32,0),soft,Enum.Material.SmoothPlastic,nil,0,"WedgePart")
                for j=1,2 do
                    part("FacetCollar",Vector3.new(1.05,.09,1.05),crystal*CFrame.new(0,(j==1 and -.3 or .3)*height,0),dark,Enum.Material.Metal)
                end
                if i<5 then rod("CrystalLink",Vector3.new(0,1.05,0),Vector3.new(x,1.05,z),.08,soft,true) end
            end
        elseif design.shape=="HelixFern" then
            rod("FernStem",Vector3.new(0,.8,0),Vector3.new(0,6.25,0),.22,dark)
            for i=1,9 do
                local a=i*.8
                local y=1.15+i*.48
                local radius=2.05-i*.11
                local tip=Vector3.new(math.cos(a)*radius,y+.5,math.sin(a)*radius)
                local opposite=Vector3.new(-math.cos(a)*radius*.7,y+.38,-math.sin(a)*radius*.7)
                for leafIndex,position in ipairs({tip,opposite}) do
                    local base=Vector3.new(0,y,0)
                    local direction=(position-base).Unit
                    rod("LeafVein",base,position,.09,soft,true)
                    petal("SpiralLeaf",base+(position-base)*.72,direction,Vector3.new(.5,1.3,.8),leafIndex==1 and palette or dark)
                end
                if i>1 then
                    local previousAngle=(i-1)*.8
                    rod("HelicalFilament",Vector3.new(math.cos(previousAngle)*.38,y-.48,math.sin(previousAngle)*.38),Vector3.new(math.cos(a)*.38,y,math.sin(a)*.38),.085,palette,true)
                end
            end
            ball("FernCrown",Vector3.new(0,6.32,0),Vector3.new(.6,.9,.6),soft)
        elseif design.shape=="SatelliteLotus" then
            rod("LotusStem",Vector3.new(0,.75,0),Vector3.new(0,3.5,0),.34,dark)
            for layer=1,2 do
                local petals=layer==1 and 8 or 6
                for i=1,petals do
                    local a=i*math.pi*2/petals+(layer==2 and .3 or 0)
                    local radius=layer==1 and 1.2 or .65
                    local center=Vector3.new(math.cos(a)*radius,layer==1 and 3.45 or 4.25,math.sin(a)*radius)
                    local dir=Vector3.new(math.cos(a)*(layer==1 and 1 or .5),layer==1 and .48 or 1,math.sin(a)*(layer==1 and 1 or .5))
                    petal("LotusPetal",center,dir,Vector3.new(.95,layer==1 and 2.55 or 2.5,1.12),layer==1 and dark or palette)
                    if layer==1 then
                        ball("PetalDew",center+Vector3.new(math.cos(a)*.7,.4,math.sin(a)*.7),Vector3.new(.2,.2,.2),soft)
                    end
                end
            end
            part("LotusHeart",Vector3.new(.88,1.2,.88),CFrame.new(0,4.85,0)*CFrame.Angles(0,math.pi/4,0),soft,Enum.Material.Neon)
            for i=1,5 do
                local a=i*math.pi*2/5
                rod("LotusStamen",Vector3.new(0,4.4,0),Vector3.new(math.cos(a)*.65,5.3,math.sin(a)*.65),.065,soft,true)
                ball("StamenBud",Vector3.new(math.cos(a)*.65,5.3,math.sin(a)*.65),Vector3.new(.24,.24,.24),palette)
            end
        end
    end

    local ok,err=pcall(function()
        for stand=1,Catalog.MaxStands do
            local slot=profile.stands[tostring(stand)]
            local design=slot and profile.designs[tostring(slot)]
            if design then renderSculpture(stand,design) end
        end
    end)
    if not ok then generated:Destroy();return nil,tostring(err) end
    generated:SetAttribute("PartCount",count)
    if old then old:Destroy() end
    generated.Parent=farm
    renderCache[farm]=signature
    return generated
end

-- Pure validation regression checks; does not create instances or mutate profiles.
function Decorations.RunValidationTests()
    local passed=0
    local function check(value,message) assert(value,message);passed+=1 end
    local valid={shape="OrbitBloom",palette="Aurora",scale=1}
    local copy=Decorations.Validate(valid)
    check(copy and copy~=valid and copy.shape==valid.shape,"valid design must be copied")
    for _,value in ipairs({"injected",12,true,false}) do check(Decorations.Validate(value)==nil,"reject non-table") end
    check(Decorations.Validate({shape="OrbitBloom",palette="Aurora",scale=.7})~=nil,"minimum scale")
    check(Decorations.Validate({shape="OrbitBloom",palette="Aurora",scale=1.4})~=nil,"maximum scale")
    for _,scale in ipairs({.699,1.401,math.huge,-math.huge,0/0}) do
        check(Decorations.Validate({shape="OrbitBloom",palette="Aurora",scale=scale})==nil,"reject invalid scale")
    end
    check(Decorations.Validate({shape="Injected",palette="Aurora",scale=1})==nil,"reject unknown shape")
    check(Decorations.Validate({shape="OrbitBloom",palette="Injected",scale=1})==nil,"reject unknown palette")
    check(Decorations.Validate({shape="OrbitBloom",palette="Aurora",scale=1,assetId=123})==nil,"reject arbitrary assets")
    check(Decorations.Validate({shape="OrbitBloom",palette="Aurora",scale=1,source="return 1"})==nil,"reject code")
    check(Decorations.Validate({shape="OrbitBloom",palette="Aurora",scale="1"})==nil,"reject coercion")
    check(Decorations.Validate({shape="OrbitBloom",palette="Aurora"})==nil,"require scale")
    check(Decorations.Validate({shape="OrbitBloom",palette="Aurora",scale=1.001}).scale==1,"canonical scale")
    local source={designs={["1"]=valid,["4"]=valid},stands={["1"]=1,["2"]=2,["3"]=1,["4"]=1}}
    local cleaned=Decorations.SanitizeProfile(source)
    check(cleaned.designs["1"] and not cleaned.designs["4"],"design cap")
    check(cleaned.stands["1"]==1 and cleaned.stands["3"]==1 and not cleaned.stands["4"],"stand cap")
    check(cleaned.stands["2"]==nil,"discard dangling references")
    check(cleaned.designs["1"]~=valid,"sanitizer must copy nested design")
    local malformed=Decorations.SanitizeProfile({designs={["1"]={shape="OrbitBloom",palette="Aurora",scale=math.huge}},stands={["1"]=1}})
    check(next(malformed.designs)==nil and next(malformed.stands)==nil,"discard corrupt design and reference")
    local floatSlot=Decorations.SanitizeProfile({designs={["1"]=valid},stands={["1"]=1.5,["2"]=math.huge,["3"]="1"}})
    check(next(floatSlot.stands)==nil,"reject fractional/non-number slots")
    check(next(Decorations.SanitizeProfile(false).designs)==nil,"malformed profile")
    return {passed=passed}
end

return Decorations
