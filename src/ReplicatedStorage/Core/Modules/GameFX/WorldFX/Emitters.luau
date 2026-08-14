--!strict
-- Attribute-driven particle emitter helpers used by reveal VFX.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Emitters = {}
local _warnedMissingTemplateFor: { [string]: boolean } = {}
local DEFAULT_REVEAL_SIZE_SCALE = 0.35
local DEFAULT_REVEAL_COUNT_SCALE = 0.55

local function _findChildIgnoreCase(parent: Instance, name: string): Instance?
	for _, ch in parent:GetChildren() do
		if string.lower(ch.Name) == string.lower(name) then
			return ch
		end
	end
	return nil
end

local function _resolveRarityTemplate(rarity: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local roots: { Instance } = {}
	local vfx = assets:FindFirstChild("VFX")
	if vfx then
		table.insert(roots, vfx)
	end
	local particles = assets:FindFirstChild("Particles")
	if particles then
		table.insert(roots, particles)
	end

	for _, root in roots do
		local rarityFolder = root:FindFirstChild("Rarity")
			or root:FindFirstChild("Rarities")
			or _findChildIgnoreCase(root, "Rarity")
			or _findChildIgnoreCase(root, "Rarities")
			or root:FindFirstChild("PetRarities", true)
		if rarityFolder then
			local hit = rarityFolder:FindFirstChild(rarity)
				or _findChildIgnoreCase(rarityFolder, rarity)
				or rarityFolder:FindFirstChild("Common")
				or _findChildIgnoreCase(rarityFolder, "Common")
			if hit then
				return hit
			end
		end
	end

	return nil
end

local function _firstBasePart(root: Instance): BasePart?
	if root:IsA("BasePart") then
		return root
	end
	return root:FindFirstChildWhichIsA("BasePart", true)
end

local function _resolvePetPart(petModel: Model): BasePart?
	if petModel.PrimaryPart then
		return petModel.PrimaryPart
	end
	return petModel:FindFirstChildWhichIsA("BasePart", true)
end

local function _getOrCreateAttachedParticle(petPart: BasePart): Attachment
	local attached = petPart:FindFirstChild("AttachedParticle")
	if attached and attached:IsA("Attachment") then
		return attached
	end
	local center = petPart:FindFirstChild("center") or petPart:FindFirstChild("Center")
	if center and center:IsA("Attachment") then
		local cloned = (center :: Attachment):Clone()
		cloned.Name = "AttachedParticle"
		cloned.Parent = petPart
		return cloned
	end
	local att = Instance.new("Attachment")
	att.Name = "AttachedParticle"
	att.Parent = petPart
	return att
end

function Emitters.findEmitters(root: Instance): { ParticleEmitter }
	local out: { ParticleEmitter } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			table.insert(out, d)
		end
	end
	return out
end

local function _numberAttr(inst: Instance, name: string, defaultValue: number): number
	local v = inst:GetAttribute(name)
	if type(v) == "number" then
		return v
	end
	return defaultValue
end

local function _scaleNumberSequence(seq: NumberSequence, scale: number): NumberSequence
	local keypoints = seq.Keypoints
	local out: { NumberSequenceKeypoint } = table.create(#keypoints)
	for i, kp in keypoints do
		out[i] = NumberSequenceKeypoint.new(kp.Time, kp.Value * scale, kp.Envelope * scale)
	end
	return NumberSequence.new(out)
end

function Emitters.emitFromSettings(rootOrEmitters: Instance | { ParticleEmitter })
	local emitters: { ParticleEmitter }
	if type(rootOrEmitters) == "table" then
		emitters = rootOrEmitters
	else
		emitters = Emitters.findEmitters(rootOrEmitters)
	end

	local maxWindow = 0
	for _, emitter in emitters do
		local emitCountBase = _numberAttr(emitter, "EmitCount", 1)
		local emitCountScale = math.max(0.01, _numberAttr(emitter, "EmitCountScale", 1))
		local emitCount = math.max(0, math.floor(emitCountBase * emitCountScale + 0.5))
		local emitDelay = math.max(0, _numberAttr(emitter, "EmitDelay", 0))
		local emitDuration = math.max(0, _numberAttr(emitter, "EmitDuration", 0))
		local disableAfter = _numberAttr(emitter, "DisableAfterEmit", 1) >= 1
		local runFor = emitDelay + emitDuration
		if runFor > maxWindow then
			maxWindow = runFor
		end

		task.delay(emitDelay, function()
			if not emitter.Parent then
				return
			end
			if emitDuration > 0 then
				emitter.Enabled = true
				if emitCount > 0 then
					emitter:Emit(emitCount)
				end
				if disableAfter then
					task.delay(emitDuration, function()
						if emitter.Parent then
							emitter.Enabled = false
						end
					end)
				end
			elseif emitCount > 0 then
				emitter:Emit(emitCount)
			end
		end)
	end

	return maxWindow
end

--- Clones rarity VFX template and attaches it to the pet model, then emits using emitter attributes.
--- Template path: ReplicatedStorage.Assets.VFX.Rarity.<RarityName> (fallback Common).
function Emitters.ShowRevealVFX(petModel: Model, rarity: string): boolean
	local petPart = _resolvePetPart(petModel)
	if not petPart then
		return false
	end
	local template = _resolveRarityTemplate(rarity)
	if not template then
		local key = string.lower(rarity)
		if not _warnedMissingTemplateFor[key] then
			_warnedMissingTemplateFor[key] = true
			warn("[GameFX.Emitters] Missing reveal template for rarity:", rarity)
		end
		return false
	end

	local templateClone = template:Clone()
	templateClone.Name = "_RevealVFXTemplate"
	local sizeScale = math.max(0.05, _numberAttr(templateClone, "ParticleScale", DEFAULT_REVEAL_SIZE_SCALE))
	local countScale = math.max(0.05, _numberAttr(templateClone, "EmitCountScale", DEFAULT_REVEAL_COUNT_SCALE))

	local srcPart = _firstBasePart(templateClone)
	if not srcPart then
		templateClone:Destroy()
		return false
	end

	local holder = Instance.new("Folder")
	holder.Name = "_RevealVFX"
	holder.Parent = petModel

	local anchor = Instance.new("Part")
	anchor.Name = "RevealVFXAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Anchored = false
	anchor.Massless = true
	anchor.CFrame = petPart.CFrame
	anchor.Parent = holder

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = petPart
	weld.Part1 = anchor
	weld.Parent = anchor

	local anchorAttachment = _getOrCreateAttachedParticle(anchor)

	local emitters: { ParticleEmitter } = {}
	local createdAttachments = 0

	for _, srcAttInst in srcPart:GetDescendants() do
		if srcAttInst:IsA("Attachment") then
			local srcAtt = srcAttInst :: Attachment
			local att = Instance.new("Attachment")
			att.Name = srcAtt.Name
			att.Position = srcAtt.Position
			att.Orientation = srcAtt.Orientation
			att.Axis = srcAtt.Axis
			att.SecondaryAxis = srcAtt.SecondaryAxis
			att.Parent = anchorAttachment
			createdAttachments += 1

			for _, child in srcAtt:GetChildren() do
				if child:IsA("ParticleEmitter") then
					local em = child:Clone()
					em.Size = _scaleNumberSequence(em.Size, sizeScale)
					em:SetAttribute("EmitCountScale", _numberAttr(em, "EmitCountScale", countScale))
					em.Parent = att
					table.insert(emitters, em)
				end
			end
		end
	end

	if createdAttachments == 0 then
		-- Fallback: clone top-level emitters directly to the pet part.
		for _, child in srcPart:GetDescendants() do
			if child:IsA("ParticleEmitter") then
				local em = child:Clone()
				em.Size = _scaleNumberSequence(em.Size, sizeScale)
				em:SetAttribute("EmitCountScale", _numberAttr(em, "EmitCountScale", countScale))
				em.Parent = anchorAttachment
				table.insert(emitters, em)
			end
		end
	end

	templateClone:Destroy()
	if #emitters == 0 then
		holder:Destroy()
		return false
	end

	local window = Emitters.emitFromSettings(emitters)
	local cleanupAfter = math.max(window + 2, 2.5)
	task.delay(cleanupAfter, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)

	return true
end

return Emitters
