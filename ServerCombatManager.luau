local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local config = ReplicatedStorage.Config

local constants = config.Constants
local SharedConstants = require(constants.SharedConstants)

local templates = config.Templates
local SharedTemplates = require(templates.SharedTemplates)

local sharedActions = config.SharedActions
local PlayerDataMapActions = require(sharedActions.PlayerDataMap)
local PlayerEphemeralDataMapActions = require(sharedActions.PlayerEphemeralDataMap)

local utils = ReplicatedStorage.Utils
local Packets = require(utils.Packets)
local SharedHelperFunctions = require(utils.SharedHelperFunctions)
local SharedConfigFunctions = require(utils.SharedConfigFunctions)
local SharedStateFunctions = require(utils.SharedStateFunctions)
local Misc = require(ReplicatedStorage.Modules.Misc)

local typeExports = ReplicatedStorage.TypeExports
local SharedTypes = require(typeExports.SharedTypes)

type CurrencyType = SharedTypes.CurrencyType
type PlayerFlagType = SharedTypes.PlayerFlagType
type PlayerSettingType = SharedTypes.PlayerSettingType
type CodeType = SharedTypes.CodeType
type OmnitrixType = SharedTypes.OmnitrixType
type AlienType = SharedTypes.AlienType
type AlienSkinType = SharedTypes.AlienSkinType
type AlienStatType = SharedTypes.AlienStatType
type AlienAbilityType = SharedTypes.AlienAbilityType

type PlayerState = SharedTypes.PlayerState
type MovementState = SharedTypes.MovementState
type CombatState = SharedTypes.CombatState

type PlayerDataMap = SharedTypes.PlayerDataMap
type PlayerData = SharedTypes.PlayerData
type PlayerSaveSlotData = SharedTypes.PlayerSaveSlotData
type PlayerSaveSlotEntryData = SharedTypes.PlayerSaveSlotEntryData
type PlayerStatsData = SharedTypes.PlayerStatsData
type PlayerCurrencyData = SharedTypes.PlayerCurrencyData
type PlayerFlagsData = SharedTypes.PlayerFlagsData
type PlayerSettingsData = SharedTypes.PlayerSettingsData
type PlayerHistoryData = SharedTypes.PlayerHistoryData
type PlayerCodeHistoryData = SharedTypes.PlayerCodeHistoryData
type PlayerSpecData = SharedTypes.PlayerSpecData
type PlayerOmnitrixDataMap = SharedTypes.PlayerOmnitrixDataMap
type PlayerAlienDataMap = SharedTypes.PlayerAlienDataMap
type PlayerOmnitrixData = SharedTypes.PlayerOmnitrixData
type PlayerAlienData = SharedTypes.PlayerAlienData
type PlayerGamePassHistoryData = SharedTypes.PlayerGamePassHistoryData
type GamePassPurchaseData = SharedTypes.GamePassPurchaseData
type PlayerDevProductHistoryData = SharedTypes.PlayerDevProductHistoryData
type DevProductPurchaseData = SharedTypes.DevProductPurchaseData

type PlayerEphemeralDataMap = SharedTypes.PlayerEphemeralDataMap
type PlayerEphemeralData = SharedTypes.PlayerEphemeralData

type OmnitrixConfig = SharedTypes.OmnitrixConfig
type OmnitrixAlienPoolConfig = SharedTypes.OmnitrixAlienPoolConfig
type OmnitrixAlienPoolItem = SharedTypes.OmnitrixAlienPoolItem
type AlienConfig = SharedTypes.AlienConfig
type AlienSkinMapConfig = SharedTypes.AlienSkinMapConfig
type AlienSkinConfig = SharedTypes.AlienSkinConfig
type AlienStatConfig = SharedTypes.AlienStatConfig
type AlienStatOverrideConfig = SharedTypes.AlienStatOverrideConfig
type AlienAbilityMapConfig = SharedTypes.AlienAbilityMapConfig
type AlienAbilityConfig = SharedTypes.AlienAbilityConfig

local DEFAULT_WALK_SPEED = SharedConstants.DEFAULT_WALK_SPEED
local SPRINT_WALK_SPEED = SharedConstants.SPRINT_WALK_SPEED

local playerEphemeralDataTemplate = SharedTemplates.playerEphemeralData

local knockbackDirection = Vector3.new(0, 0, 0)

local ServerCombatManager = {}

function ServerCombatManager.playPunchRockEffect(attackerRootPart, targetRootPart, effectType)
	if not attackerRootPart or not targetRootPart then return end
	
	local direction = (targetRootPart.Position - attackerRootPart.Position).Unit
	local PunchRock = require(ReplicatedStorage.Modules.PunchRock)
	
	local configs = {
		Slam = {
			direction = Vector3.new(0, -10, 0),
			angle = 15,
			lines = 2,
			distance = 30,
			startSize = 0.6,
			endSize = 0.9,
			rockCount = 15,
			lifetime = 3,
			startDistance = 2,
			popupTime = 0.6,
			retractTime = 3
		},
		FinalPunch = {
			direction = Vector3.new(0, -5, 0),
			angle = 10,
			lines = 1,
			distance = 20,
			startSize = 0.4,
			endSize = 0.7,
			rockCount = 8,
			lifetime = 2,
			startDistance = 1,
			popupTime = 0.4,
			retractTime = 2
		},
		Knockdown = {
			direction = Vector3.new(0, -10, 0),
			angle = 15,
			lines = 2,
			distance = 30,
			startSize = 0.6,
			endSize = 0.9,
			rockCount = 15,
			lifetime = 3,
			startDistance = 2,
			popupTime = 0.6,
			retractTime = 3
		}
	}
	
	local config = configs[effectType]
	
	PunchRock.Punch(
		attackerRootPart.Position,
		direction,
		config.direction,
		config.angle,
		config.lines,
		config.distance,
		config.startSize,
		config.endSize,
		config.rockCount,
		config.lifetime,
		config.startDistance,
		config.popupTime,
		config.retractTime
	)
end

local CombatStates = {
	Idle = "Idle",
	Attacking = "Attacking",
	Blocking = "Blocking",
	Parrying = "Parrying",
	Stunned = "Stunned"
}

local Cooldowns = {}
local ActiveBlocks = {}
local ActiveParryWindows = {}
local ActiveDashes = {}
local PlayerCombos = {}
local KnockedDownPlayers = {}
local HitDebounces = {}
local TargetComboProgress = {}

local DEFAULT_DASH_CONFIG = {
	distance = 30,
	duration = 0.3,
	cooldown = 2.0,
}

local ANIMATION_NAMES = {
	Attack = "Attack",
	Block = "Block",
	Parry = "Parry",
	Stun = "Stunned",
	Hit = "Hit"
}

function ServerCombatManager.init()
end

function ServerCombatManager.onPlayerAdded(player)
	SharedHelperFunctions.onCharacterAdded(player, function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.WalkSpeed = DEFAULT_WALK_SPEED


		ServerCombatManager.ensureHitbox(character)

		humanoid.Died:Connect(function()
			ServerCombatManager.onPlayerDied(player)
		end)
	end)
end

function ServerCombatManager.onPlayerDied(player)
	Cooldowns[player.UserId] = nil
	ActiveBlocks[player.UserId] = nil
	ActiveParryWindows[player.UserId] = nil
	ActiveDashes[player.UserId] = nil
	PlayerCombos[player.UserId] = nil
	KnockedDownPlayers[player.UserId] = nil
	
	for targetKey, comboData in pairs(TargetComboProgress) do
		if comboData.attacker == player then
			TargetComboProgress[targetKey] = nil
		end
	end
end

function ServerCombatManager.onRequestToStartSprintingReceived(player)
	local character = player.Character
	if not character then return end

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.WalkSpeed = SPRINT_WALK_SPEED

	local playerEphemeralData = SharedStateFunctions.getPlayerEphemeralData(player)
	local alienType = playerEphemeralData and playerEphemeralData.selectedAlienType

	if alienType then
		Packets.PlayAlienAnimation:Fire(player, "Sprint", alienType)
	else
		Packets.PlayAnimation:Fire(player, "Movement/Sprint", "")
	end

	SharedHelperFunctions.log(player.Name .. " requested to start sprinting")
end

function ServerCombatManager.onRequestToStopSprintingReceived(player)
	local character = player.Character
	if not character then return end

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.WalkSpeed = DEFAULT_WALK_SPEED

	SharedHelperFunctions.log(player.Name .. " requested to stop sprinting")
end

function ServerCombatManager.onRequestToDashReceived(player, keyCode)
	local userId = player.UserId

	if ServerCombatManager.isOnCooldown(userId, "dash") then 
		SharedHelperFunctions.log(player.Name .. " dash is on cooldown")
		local Replicate = ReplicatedStorage.Remotes.Replicate
		Replicate:FireClient(player, "Combat", "DashCooldown")
		return 
	end

	local playerEphemeralData = SharedStateFunctions.getPlayerEphemeralData(player)

	local dashAbility = DEFAULT_DASH_CONFIG
	local selectedAlienType = nil

	if playerEphemeralData and playerEphemeralData.selectedAlienType then
		selectedAlienType = playerEphemeralData.selectedAlienType
		local alienConfig = ServerCombatManager.getAlienConfig(player, selectedAlienType)
		if alienConfig and alienConfig.abilityMapConfig and alienConfig.abilityMapConfig.Dash then
			dashAbility = alienConfig.abilityMapConfig.Dash
		end
	end

	local dashDistance = dashAbility.distance or 25
	local dashDuration = dashAbility.duration or 0.3
	local dashCooldown = dashAbility.cooldown or 1.5

	local character = player.Character
	if not character then return end

	local primaryPart = character.PrimaryPart
	if not primaryPart then 
		SharedHelperFunctions.log(player.Name .. " no primary part")
		return 
	end

	local directionAnim = "W"
	local dashDirection = Vector3.new(0, 0, 0)
	local cframe = primaryPart.CFrame

	local forward = cframe.LookVector
	local right = cframe.RightVector

	forward = Vector3.new(forward.X, 0, forward.Z).Unit
	right = Vector3.new(right.X, 0, right.Z).Unit

	if keyCode == Enum.KeyCode.W then
		directionAnim = "W"
		dashDirection = forward
	elseif keyCode == Enum.KeyCode.S then 
		directionAnim = "S"
		dashDirection = -forward
	elseif keyCode == Enum.KeyCode.A then 
		directionAnim = "A"
		dashDirection = -right
	elseif keyCode == Enum.KeyCode.D then 
		directionAnim = "D"
		dashDirection = right
	else
		directionAnim = "W"
		dashDirection = forward
	end

	if dashDirection.Magnitude == 0 then 
		dashDirection = forward
		directionAnim = "W"
	end

	dashDirection = dashDirection.Unit

	Packets.PlayAnimation:Fire(player, "Movement/Dash/" .. directionAnim, "")
	ServerCombatManager.setCooldown(userId, "dash", dashCooldown)
	
	local dashSound = ReplicatedStorage.Storage.Sounds:FindFirstChild("DashS")
	if dashSound then
		local soundClone = dashSound:Clone()
		soundClone.Parent = character
		soundClone.Volume = 1.5
		soundClone.PlaybackSpeed = 1.0
		soundClone:Play()
		game.Debris:AddItem(soundClone, 3)
	end
	
	local Replicate = ReplicatedStorage.Remotes.Replicate

	local dashSpeed = dashDistance / dashDuration
	local dashVelocity = dashDirection * dashSpeed

	local existingDash = primaryPart:FindFirstChild("DashAttachment")
	if existingDash then
		local existingLV = primaryPart:FindFirstChild("DashLinearVelocity")
		if existingLV then existingLV:Destroy() end
		existingDash:Destroy()
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = primaryPart

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "DashLinearVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = 1e6
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VectorVelocity = dashDirection * dashSpeed
	linearVelocity.Parent = primaryPart

		local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	local originalWalkSpeed = humanoid and humanoid.WalkSpeed or DEFAULT_WALK_SPEED
	local originalJumpPower = humanoid and humanoid.JumpPower or 50

	ActiveDashes[userId] = {
		linearVelocity = linearVelocity,
		attachment = attachment,
		startTime = os.clock(),
		duration = dashDuration,
		originalWalkSpeed = originalWalkSpeed,
		originalJumpPower = originalJumpPower
	}

	task.delay(dashDuration, function()
		if ActiveDashes[userId] then
			local dashData = ActiveDashes[userId]
			if dashData.linearVelocity and dashData.linearVelocity.Parent then
				dashData.linearVelocity.Enabled = false
				dashData.linearVelocity.VectorVelocity = Vector3.zero
				dashData.linearVelocity:Destroy()
			end
			if dashData.attachment and dashData.attachment.Parent then
				dashData.attachment:Destroy()
			end
			
			local character = player.Character
			if character then
				local humanoid = character:FindFirstChild("Humanoid")
			if humanoid and dashData.originalWalkSpeed then
					humanoid.WalkSpeed = dashData.originalWalkSpeed
				end
				if humanoid and dashData.originalJumpPower then
					humanoid.JumpPower = dashData.originalJumpPower
				end
			end
			
			ActiveDashes[userId] = nil
		end
	end)

	SharedHelperFunctions.log(player.Name .. " dashed" .. 
		" speed: " .. dashSpeed .. " cooldown: " .. dashCooldown .. " direction: " .. tostring(dashDirection) ..
		" (Alien: " .. tostring(selectedAlienType) .. ")")
end

function ServerCombatManager.onRequestToM1Received(player, comboIndex, isFinal)

	local playerEphemeralData = SharedStateFunctions.getPlayerEphemeralData(player)
	if not playerEphemeralData then return end

	local selectedAlienType = playerEphemeralData.selectedAlienType

	if ActiveBlocks[player.UserId] then return end

	if ServerCombatManager.isOnCooldown(player.UserId, "attack") then return end

	local attackAbility = nil
	local damage = 10
	local cooldown = 0.25

	if selectedAlienType then
		local alienConfig = ServerCombatManager.getAlienConfig(player, selectedAlienType)
		if alienConfig and alienConfig.abilityMapConfig and alienConfig.abilityMapConfig.BasicAttack then
			attackAbility = alienConfig.abilityMapConfig.BasicAttack
			damage = ServerCombatManager.getBaseDamage(player)
			cooldown = attackAbility.cooldown or 0.5
		end
	end

	if comboIndex then
		local comboMultiplier = 1 + (comboIndex - 1) * 0.2
		damage = damage * comboMultiplier
	end

	local range = (attackAbility and attackAbility.range) or 8
	local angle = (attackAbility and attackAbility.angle) or 120
	local damageMultiplier = (attackAbility and attackAbility.damageMultiplier) or 1.0



	local hitResults = ServerCombatManager.performMeleeAttack(player, {
		range = range,
		angle = angle,
		damageMultiplier = damageMultiplier,
		baseDamage = damage
	})


	for _, hitResult in ipairs(hitResults) do
		local targetId = hitResult.target
		if HitDebounces[targetId] then
			continue
		end

		HitDebounces[targetId] = true
		task.delay(0.2, function()
			HitDebounces[targetId] = nil
		end)

		local targetKey = tostring(targetId)
		if not TargetComboProgress[targetKey] then
			TargetComboProgress[targetKey] = {
				attacker = player,
				comboCount = 0,
				lastHitTime = 0
			}
		end

		local comboData = TargetComboProgress[targetKey]
		local currentTime = os.clock()

		if currentTime - comboData.lastHitTime > 2.0 then
			comboData.comboCount = 0
		end

		comboData.comboCount = comboData.comboCount + 1
		comboData.lastHitTime = currentTime
		comboData.attacker = player

		local isFullCombo = comboData.comboCount >= 4



		ServerCombatManager.applyDamage(player, hitResult.target, hitResult.damage, "BasicAttack", false)

		local targetPlayer = Players:GetPlayerFromCharacter(hitResult.target)
		if targetPlayer then
			ServerCombatManager.stunPlayer(targetPlayer, 0.3)
		end

		local hitPosition = hitResult.hitbox and hitResult.hitbox.Position or hitResult.hitPosition
		local Replicate = ReplicatedStorage.Remotes.Replicate
		Replicate:FireAllClients("Combat", "HitFX", "Basic Hit", hitPosition)

		if isFullCombo then
			local attackerCharacter = player.Character
			local attackerRootPart = attackerCharacter and attackerCharacter.PrimaryPart
			if attackerRootPart and hitResult.target.PrimaryPart then
				ServerCombatManager.applyKnockdown(hitResult.target, player)

				TargetComboProgress[targetKey] = nil

				SharedHelperFunctions.log(player.Name .. " completed full combo on " .. hitResult.target.Name .. "")
			end
		end

		if isFinal and isFullCombo then
			local attackerCharacter = player.Character
			local attackerRootPart = attackerCharacter and attackerCharacter.PrimaryPart
			if attackerRootPart and hitResult.target.PrimaryPart then
				local targetPlayer = Players:GetPlayerFromCharacter(hitResult.target)
				if targetPlayer then
					ServerCombatManager.applyKnockdown(hitResult.target, player)
				else
					local target = hitResult.target
					local humanoid = target:FindFirstChild("Humanoid")
					if humanoid then
						local originalWalkSpeed = humanoid.WalkSpeed
						local originalJumpPower = humanoid.JumpPower

						target:SetAttribute("KnockedDownStartTime", os.clock())
						target:SetAttribute("OriginalWalkSpeed", originalWalkSpeed)
						target:SetAttribute("OriginalJumpPower", originalJumpPower)

						ServerCombatManager.applyR15RagdollFromSample(hitResult.target, knockbackDirection * 20, hitResult.target.PrimaryPart.Position)

						local targetId = tick() .. math.random(1000, 9999)
						target:SetAttribute("RecoveryTaskId", targetId)

						task.delay(2.0, function()
							if target and target.Parent and target:GetAttribute("RecoveryTaskId") == targetId then
								for _, descendant in ipairs(target:GetDescendants()) do
									if descendant:IsA("BodyVelocity") or descendant:IsA("BodyAngularVelocity") or descendant:IsA("LinearVelocity") then
										descendant:Destroy()
									end
								end

								for _, part in ipairs(target:GetDescendants()) do
									if part:IsA("BasePart") then
										part.CustomPhysicalProperties = nil
										part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
										part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
									end
								end

								local CollectionService = game:GetService("CollectionService")
								if CollectionService:HasTag(target, "Ragdoll") then
									CollectionService:RemoveTag(target, "Ragdoll")
								end

								for _, joint in ipairs(target:GetDescendants()) do
									if joint:IsA("Motor6D") then
										joint.Enabled = true
									end
								end

								local npcHumanoid = target:FindFirstChild("Humanoid")
								if npcHumanoid then
									npcHumanoid.WalkSpeed = target:GetAttribute("OriginalWalkSpeed") or 16
									npcHumanoid.JumpPower = target:GetAttribute("OriginalJumpPower") or 50
									npcHumanoid.PlatformStand = false
									npcHumanoid.AutoRotate = true

									target:SetAttribute("KnockedDownStartTime", nil)
									target:SetAttribute("OriginalWalkSpeed", nil)
									target:SetAttribute("OriginalJumpPower", nil)
									target:SetAttribute("RecoveryTaskId", nil)


									if npcHumanoid.Health > 0 then
										npcHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
										task.wait(0.5)
										if npcHumanoid.Health > 0 then
											npcHumanoid:ChangeState(Enum.HumanoidStateType.Running)
										end
									end
								end
							end
						end)
					end
				end
			end
		end
	end

	local character = player.Character
	if character then
		local sfx = ReplicatedStorage.Storage.Sounds.FistSwing:Clone()
		sfx.Parent = character
		sfx.Volume = 1.5
		sfx.PlaybackSpeed = 1.0
		sfx:Play()
		game.Debris:AddItem(sfx, 5)	end

	ServerCombatManager.setCooldown(player.UserId, "attack", cooldown)

	SharedHelperFunctions.log(player.Name .. " performed M1 attack! (Combo: " .. tostring(comboIndex) .. ", Final: " .. tostring(isFinal) .. ", Alien: " .. tostring(selectedAlienType) .. ")")
end

function ServerCombatManager.onRequestToBlockReceived(player)
	local playerEphemeralData = SharedStateFunctions.getPlayerEphemeralData(player)
	local selectedAlienType = playerEphemeralData and playerEphemeralData.selectedAlienType

	if ActiveBlocks[player.UserId] then return end

	if ServerCombatManager.isOnCooldown(player.UserId, "block") then return end

	player:SetAttribute("IsBlocking", true)

	if selectedAlienType then
		local alienConfig = ServerCombatManager.getAlienConfig(player, selectedAlienType)
		if alienConfig and alienConfig.abilityMapConfig and alienConfig.abilityMapConfig.Block then
			local blockAbility = alienConfig.abilityMapConfig.Block
			Packets.PlayAlienAnimation:Fire(player, "BlockingIdle", selectedAlienType)
			ActiveBlocks[player.UserId] = {
				startTime = os.clock(),
				config = blockAbility,
				damageReduction = blockAbility.damageReduction or 0.6
			}
		else
			Packets.PlayAnimation:Fire(player, "Combat/BlockingIdle", "")
			ActiveBlocks[player.UserId] = {
				startTime = os.clock(),
				config = {damageReduction = 0.6},
				damageReduction = 0.6
			}
		end
	else
		Packets.PlayAnimation:Fire(player, "Combat/BlockingIdle", "")
		ActiveBlocks[player.UserId] = {
			startTime = os.clock(),
			config = {damageReduction = 0.6},
			damageReduction = 0.6
		}
	end

	SharedHelperFunctions.log(player.Name .. " started blocking!")
end

function ServerCombatManager.onRequestToStopBlockingReceived(player)
	if ActiveBlocks[player.UserId] then
		ActiveBlocks[player.UserId] = nil
		
		player:SetAttribute("IsBlocking", false)
		
		local playerEphemeralData = SharedStateFunctions.getPlayerEphemeralData(player)
		local selectedAlienType = playerEphemeralData and playerEphemeralData.selectedAlienType
		
		if selectedAlienType then
			local alienConfig = ServerCombatManager.getAlienConfig(player, selectedAlienType)
			if alienConfig and alienConfig.abilityMapConfig and alienConfig.abilityMapConfig.Block then
				Packets.StopAlienAnimation:Fire(player, "BlockingIdle", selectedAlienType)
			else
				Packets.StopAnimation:Fire(player, "Combat/BlockingIdle", "")
			end
		else
			Packets.StopAnimation:Fire(player, "Combat/BlockingIdle", "")
		end
		
		SharedHelperFunctions.log(player.Name .. " stopped blocking!")
	end
end

function ServerCombatManager.onRequestToParryReceived(player)
	local playerEphemeralData = SharedStateFunctions.getPlayerEphemeralData(player)
	if not playerEphemeralData then return end

	local selectedAlienType = playerEphemeralData.selectedAlienType
	if not selectedAlienType then return end

	local alienConfig = ServerCombatManager.getAlienConfig(player, selectedAlienType)
	if not alienConfig then return end

	if ServerCombatManager.isOnCooldown(player.UserId, "parry") then return end

	Packets.PlayAnimation:Fire(player, "Parry", "")

	local parryAbility = alienConfig.abilityMapConfig.Parry
	if not parryAbility then return end

	ActiveParryWindows[player.UserId] = {
		startTime = os.clock(),
		window = parryAbility.activationWindow or 0.2,
		active = true
	}

	task.delay(parryAbility.activationWindow or 0.2, function()
		if ActiveParryWindows[player.UserId] then
			ActiveParryWindows[player.UserId].active = false
		end
	end)

	ServerCombatManager.setCooldown(player.UserId, "parry", parryAbility.cooldown or 2.0)

	SharedHelperFunctions.log(player.Name .. " attempted parry!")
end

function ServerCombatManager.getAlienConfig(player, alienType)
	local configFolder = ReplicatedStorage:FindFirstChild("Config")
	if not configFolder then return nil end

	local aliensFolder = configFolder:FindFirstChild("Aliens")
	if not aliensFolder then return nil end

	local prototypeFolder = aliensFolder:FindFirstChild("Prototype")
	if not prototypeFolder then return nil end

	local alienConfigModule = prototypeFolder:FindFirstChild(alienType)
	if alienConfigModule and alienConfigModule:IsA("ModuleScript") then
		return require(alienConfigModule)
	end
	return nil
end

function ServerCombatManager.isOnCooldown(userId, cooldownType)
	local userCooldowns = Cooldowns[userId]
	if not userCooldowns then return false end

	local cooldownEnd = userCooldowns[cooldownType]
	if not cooldownEnd then return false end

	local currentTime = os.clock()
	local result = currentTime < cooldownEnd

	if result then
		SharedHelperFunctions.log("Cooldown active: " .. cooldownType .. " for user: " .. userId .. 
			" time left: " .. string.format("%.2f", cooldownEnd - currentTime) .. "s")
	end

	return result
end

function ServerCombatManager.setCooldown(userId, cooldownType, duration)
	Cooldowns[userId] = Cooldowns[userId] or {}
	local currentTime = os.clock()
	Cooldowns[userId][cooldownType] = currentTime + duration

	SharedHelperFunctions.log("Set cooldown: " .. cooldownType .. " for user: " .. userId .. 
		" duration: " .. duration .. "s, ends at: " .. string.format("%.2f", Cooldowns[userId][cooldownType]))
end

function ServerCombatManager.calculateHitPosition(origin, target)
	local targetRoot = target.PrimaryPart
	if not targetRoot then return targetRoot.Position end
	
	local closestPart = targetRoot
	local closestDistance = (targetRoot.Position - origin).Magnitude
	
	for _, part in ipairs(target:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			local parent = part.Parent
			local isAccessory = false
			while parent and parent ~= target do
				if parent:IsA("Accessory") or parent:IsA("Hat") or parent:IsA("HairAccessory") or 
				   parent:IsA("FaceAccessory") or parent:IsA("NeckAccessory") or 
				   parent:IsA("ShoulderAccessory") or parent:IsA("BackAccessory") or 
				   parent:IsA("WaistAccessory") or parent:IsA("ShirtAccessory") or 
				   parent:IsA("PantsAccessory") then
					isAccessory = true
					break
				end
				parent = parent.Parent
			end
			
			if not isAccessory then
				local distance = (part.Position - origin).Magnitude
				if distance < closestDistance then
					closestDistance = distance
					closestPart = part
				end
			end
		end
	end
	
	return closestPart.Position
end

function ServerCombatManager.createHitbox(character)
	if not character then return nil end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return nil end

	local existingHitbox = humanoidRootPart:FindFirstChild("Hitbox")
	if existingHitbox then return existingHitbox end

	local cframe, size = character:GetBoundingBox()

	local hitboxSize = Vector3.new(
		math.max(size.X * 1.2, 3),
		math.max(size.Y * 0.8, 5),
		math.max(size.Z * 1.2, 3)
	)

	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or humanoidRootPart
	local targetCFrame = torso.CFrame

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = hitboxSize
	hitbox.CFrame = targetCFrame
	hitbox.Color = Color3.new(1, 0, 0)
	hitbox.Transparency = 0.7
	hitbox.Anchored = false
	hitbox.Massless = true

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = humanoidRootPart
	weld.Part1 = hitbox
	weld.Parent = hitbox
	hitbox.Parent = humanoidRootPart
	task.wait(0.01)
	hitbox.CanCollide = false
	return hitbox
end

function ServerCombatManager.ensureHitbox(character)
	if not character then return nil end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return nil end
	
	local hitbox = humanoidRootPart:FindFirstChild("Hitbox")
	if not hitbox then
		hitbox = ServerCombatManager.createHitbox(character)
	end
	
	return hitbox
end

function ServerCombatManager.performMeleeAttack(player, attackConfig)
	local character = player.Character
	if not character then return {} end

	local rootPart = character.PrimaryPart
	if not rootPart then return {} end

	local hitResults = {}
	local range = attackConfig.range or 8
	local angle = attackConfig.angle or 120

	local origin = rootPart.Position
	local direction = rootPart.CFrame.LookVector

	local attackerHitbox = ServerCombatManager.ensureHitbox(character)
	local attackerHitboxPos = attackerHitbox and attackerHitbox.Position or origin

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local targetChar = otherPlayer.Character
			if targetChar then
				local targetHitbox = ServerCombatManager.ensureHitbox(targetChar)
				if targetHitbox then
					local hitboxPos = targetHitbox.Position
					local distance = (hitboxPos - attackerHitboxPos).Magnitude

					if distance <= 3 then
						local toTarget = (hitboxPos - attackerHitboxPos).Unit
						local dot = direction:Dot(toTarget)
						local angleRad = math.rad(angle / 2)

						if dot > math.cos(angleRad) then
							local hitPosition = ServerCombatManager.calculateHitPosition(origin, targetChar)
							table.insert(hitResults, {
								target = targetChar,
								damage = attackConfig.baseDamage,
								hitPosition = hitPosition,
								hitbox = targetHitbox
							})
						end
					elseif distance <= range then
						local toTarget = (hitboxPos - attackerHitboxPos).Unit
						local dot = direction:Dot(toTarget)
						local angleRad = math.rad(angle / 2)

						if dot > math.cos(angleRad) then
							local hitPosition = ServerCombatManager.calculateHitPosition(origin, targetChar)
							table.insert(hitResults, {
								target = targetChar,
								damage = attackConfig.baseDamage,
								hitPosition = hitPosition,
								hitbox = targetHitbox
							})
						end
					end
				end
			end
		end
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("Model") and descendant ~= character then
			local humanoid = descendant:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local targetHitbox = ServerCombatManager.ensureHitbox(descendant)
				if targetHitbox then
					local hitboxPos = targetHitbox.Position
					local distance = (hitboxPos - attackerHitboxPos).Magnitude

					if distance <= 3 then
						local toTarget = (hitboxPos - attackerHitboxPos).Unit
						local dot = direction:Dot(toTarget)
						local angleRad = math.rad(angle / 2)

						if dot > math.cos(angleRad) then
							local hitPosition = ServerCombatManager.calculateHitPosition(origin, descendant)
							table.insert(hitResults, {
								target = descendant,
								damage = attackConfig.baseDamage,
								hitPosition = hitPosition,
								hitbox = targetHitbox
							})
						end
					elseif distance <= range then
						local toTarget = (hitboxPos - attackerHitboxPos).Unit
						local dot = direction:Dot(toTarget)
						local angleRad = math.rad(angle / 2)

						if dot > math.cos(angleRad) then
							local hitPosition = ServerCombatManager.calculateHitPosition(origin, descendant)
							table.insert(hitResults, {
								target = descendant,
								damage = attackConfig.baseDamage,
								hitPosition = hitPosition,
								hitbox = targetHitbox
							})
						end
					end
				end
			end
		end
	end
	return hitResults
end

function ServerCombatManager.getBaseDamage(player)
	local playerEphemeralData = SharedStateFunctions.getPlayerEphemeralData(player)
	if not playerEphemeralData then return 10 end

	local alienType = playerEphemeralData.selectedAlienType
	if not alienType then return 10 end

	local alienConfig = ServerCombatManager.getAlienConfig(player, alienType)
	if not alienConfig then return 10 end

	local damage = alienConfig.statConfig.Damage or 10
	return damage
end

function ServerCombatManager.applyDamage(attacker, target, damage, attackType, isFinalPunch)
	local humanoid = target:FindFirstChild("Humanoid")
	if not humanoid then return end

	local targetPlayer = Players:GetPlayerFromCharacter(target)
	local isBlocked = false
	local isParried = false

	local function isAttackFromFront(attacker, target)
		local attackerRoot = attacker.Character and attacker.Character.PrimaryPart
		local targetRoot = target.PrimaryPart
		if not attackerRoot or not targetRoot then return true end

		local toAttacker = (attackerRoot.Position - targetRoot.Position).Unit
		local targetForward = targetRoot.CFrame.LookVector
		local dot = targetForward:Dot(toAttacker)

		return dot > 0
	end

	if targetPlayer then
		if KnockedDownPlayers[targetPlayer.UserId] then
			return
		end

		local blockData = ActiveBlocks[targetPlayer.UserId]
		local parryData = ActiveParryWindows[targetPlayer.UserId]

		if parryData and parryData.active then
			ServerCombatManager.stunPlayer(attacker, 1.0)
			local targetAlienType = SharedStateFunctions.getPlayerEphemeralData(targetPlayer).selectedAlienType
			Packets.PlayAlienAnimation:Fire(targetPlayer, "Parry", targetAlienType)
			local Replicate = ReplicatedStorage.Remotes.Replicate
			Replicate:FireAllClients("Combat", "HitFX", "Perfect Block", target.PrimaryPart)

			local parrySound = ReplicatedStorage.Storage.Sounds:FindFirstChild("Parry")
			if parrySound then
				local soundClone = parrySound:Clone()
				soundClone.Parent = target.PrimaryPart
				soundClone.Volume = 1.0
				soundClone.PlaybackSpeed = 1.0
				soundClone:Play()
				game.Debris:AddItem(soundClone, 3)
			end

			PlayerCombos[attacker.UserId] = nil

			for targetKey, comboData in pairs(TargetComboProgress) do
				if comboData.attacker == attacker then
					TargetComboProgress[targetKey] = nil
				end
			end

			isParried = true
			return
		elseif blockData and isAttackFromFront(attacker, target) then
			damage = damage * (1 - (blockData.damageReduction or 0.6))
			local Replicate = ReplicatedStorage.Remotes.Replicate
			Replicate:FireAllClients("Combat", "HitFX", "Block Hit", target.PrimaryPart)
			local targetAlienType = SharedStateFunctions.getPlayerEphemeralData(targetPlayer).selectedAlienType
			Packets.PlayAlienAnimation:Fire(targetPlayer, "BlockingIdle", targetAlienType)

			local blockSound = ReplicatedStorage.Storage.Sounds:FindFirstChild("Block")
			if blockSound then
				local soundClone = blockSound:Clone()
				soundClone.Parent = target.PrimaryPart
				soundClone.Volume = 1.0
				soundClone.PlaybackSpeed = 1.0
				soundClone:Play()
				game.Debris:AddItem(soundClone, 3)
			end

			PlayerCombos[attacker.UserId] = nil

			for targetKey, comboData in pairs(TargetComboProgress) do
				if comboData.attacker == attacker then
					TargetComboProgress[targetKey] = nil
				end
			end

			isBlocked = true
		end
	else
		local isBlocking = target:FindFirstChild("isBlocking")
		local PBTime = target:FindFirstChild("PBTime")
		local Knocked = target:FindFirstChild("Knocked")

		if PBTime and PBTime.Value and (not Knocked or not Knocked.Value) then
			ServerCombatManager.stunPlayer(attacker, 1.0)
			Packets.PlayAnimation:Fire(target, "Combat/Parry", "")
			local Replicate = ReplicatedStorage.Remotes.Replicate
			Replicate:FireAllClients("Combat", "HitFX", "Perfect Block", target.PrimaryPart)

			local parrySound = ReplicatedStorage.Storage.Sounds.Combat:FindFirstChild("PerfectBlock1")
			if parrySound then
				local soundClone = parrySound:Clone()
				soundClone.Parent = target.PrimaryPart
				soundClone.Volume = 1.0
				soundClone.PlaybackSpeed = 1.0
				soundClone:Play()
				game.Debris:AddItem(soundClone, 3)
			end

			PlayerCombos[attacker.UserId] = nil

			for targetKey, comboData in pairs(TargetComboProgress) do
				if comboData.attacker == attacker then
					TargetComboProgress[targetKey] = nil
				end
			end

			isParried = true
		elseif isBlocking and isBlocking.Value and (not Knocked or not Knocked.Value) and isAttackFromFront(attacker, target) then
			damage = damage * 0.5
			local Replicate = ReplicatedStorage.Remotes.Replicate
			Replicate:FireAllClients("Combat", "HitFX", "Block Hit", target.PrimaryPart)
			Packets.PlayAnimation:Fire(target, "Combat/BlockingIdle", "")

			local blockSound = ReplicatedStorage.Storage.Sounds.Combat:FindFirstChild("BlockHit")
			if blockSound then
				local soundClone = blockSound:Clone()
				soundClone.Parent = target.PrimaryPart
				soundClone.Volume = 1.0
				soundClone.PlaybackSpeed = 1.0
				soundClone:Play()
				game.Debris:AddItem(soundClone, 3)
			end

			PlayerCombos[attacker.UserId] = nil

			for targetKey, comboData in pairs(TargetComboProgress) do
				if comboData.attacker == attacker then
					TargetComboProgress[targetKey] = nil
				end
			end

			isBlocked = true
		end
	end

	if not isBlocked and not isParried then
		if targetPlayer then
			if target:GetAttribute("KnockedDownStartTime") then
				return
			end
		end

		humanoid:TakeDamage(damage)
		Packets.ShowDamageNumber:Fire(target.PrimaryPart.Position, math.floor(damage))
		ServerCombatManager.playRandomHitAnimation(target, attacker)

		local hitSound = ReplicatedStorage.Storage.Sounds.Combat:FindFirstChild("BasicHit")
		if hitSound then
			local soundClone = hitSound:Clone()
			soundClone.Parent = target.PrimaryPart
			soundClone.Volume = 1.0
			soundClone.PlaybackSpeed = 1.0
			soundClone:Play()
			game.Debris:AddItem(soundClone, 3)
		end
	end
end

function ServerCombatManager.playRandomHitAnimation(target, attacker)
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	
	local hitAnimation = "Hit1"
	
	if attacker and attacker.Character then
		local isFromFront = ServerCombatManager.isAttackFromFront(attacker, target)
		hitAnimation = isFromFront and "Hit1" or "Hit2"
	end
	
	if targetPlayer then
		Packets.PlayAnimation:Fire(targetPlayer, `Combat/Hits/{hitAnimation}`, "")
	else
		Packets.PlayAnimation:Fire(target, `Combat/Hits/{hitAnimation}`, "")
	end
end

function ServerCombatManager.isAttackFromFront(attacker, target)
	local attackerRoot = attacker.Character and attacker.Character.PrimaryPart
	local targetRoot = target.PrimaryPart
	if not attackerRoot or not targetRoot then return true end
	
	local toAttacker = (attackerRoot.Position - targetRoot.Position).Unit
	local targetForward = targetRoot.CFrame.LookVector
	local dot = targetForward:Dot(toAttacker)
	
	return dot > 0
end

function ServerCombatManager.applyKnockdown(target, attacker)
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	local attackerCharacter = attacker and attacker.Character
	local attackerRootPart = attackerCharacter and attackerCharacter.PrimaryPart

	if attackerRootPart and target.PrimaryPart then
		knockbackDirection = (target.PrimaryPart.Position - attackerRootPart.Position).Unit
		knockbackDirection = Vector3.new(knockbackDirection.X, 0, knockbackDirection.Z).Unit

		local targetRootPart = target.PrimaryPart

		local desiredDistance = 20
		local knockDuration = 0.5

		local horizontalVelocity = (desiredDistance / knockDuration)
		local velocityVector = knockbackDirection * horizontalVelocity

		velocityVector = Vector3.new(velocityVector.X, -30, velocityVector.Z)

		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.Velocity = velocityVector
		bodyVelocity.MaxForce = Vector3.new(1000000, 1000000, 1000000)
		bodyVelocity.P = 50000
		bodyVelocity.Parent = targetRootPart

		task.delay(knockDuration, function()
			if bodyVelocity and bodyVelocity.Parent then
				bodyVelocity:Destroy()
			end
		end)
	end

	ServerCombatManager.applyR15RagdollFromSample(target, knockbackDirection * 20, target.PrimaryPart.Position)

	if not targetPlayer then
		local humanoid = target:FindFirstChild("Humanoid")
		if not humanoid then return end
		
		local originalWalkSpeed = humanoid.WalkSpeed
		local originalJumpPower = humanoid.JumpPower
		
		target:SetAttribute("KnockedDownStartTime", os.clock())
		target:SetAttribute("OriginalWalkSpeed", originalWalkSpeed)
		target:SetAttribute("OriginalJumpPower", originalJumpPower)
		
		local Replicate = ReplicatedStorage.Remotes.Replicate
		Replicate:FireAllClients("Combat", "HitFX", "Knockdown", ServerCombatManager.calculateHitPosition(attackerCharacter.PrimaryPart.Position, target))
	
	local PunchRock = require(ReplicatedStorage.Modules.PunchRock)
	local attackerRootPart = attackerCharacter and attackerCharacter.PrimaryPart
	if attackerRootPart and target.PrimaryPart then
		ServerCombatManager.playPunchRockEffect(attackerRootPart, target.PrimaryPart, "Knockdown")
	end
		
		task.delay(2.0, function()
			if target and target.Parent then
				for _, descendant in ipairs(target:GetDescendants()) do
					if descendant:IsA("BodyVelocity") or descendant:IsA("BodyAngularVelocity") or descendant:IsA("LinearVelocity") then
						descendant:Destroy()
					end
				end
				
				for _, part in ipairs(target:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CustomPhysicalProperties = nil
						part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
						part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
					end
				end
				
				local CollectionService = game:GetService("CollectionService")
				if CollectionService:HasTag(target, "Ragdoll") then
					CollectionService:RemoveTag(target, "Ragdoll")
				end
				
				for _, joint in ipairs(target:GetDescendants()) do
					if joint:IsA("Motor6D") then
						joint.Enabled = true
					end
				end
				
				local npcHumanoid = target:FindFirstChild("Humanoid")
				if npcHumanoid then
					npcHumanoid.WalkSpeed = target:GetAttribute("OriginalWalkSpeed") or 16
					npcHumanoid.JumpPower = target:GetAttribute("OriginalJumpPower") or 50
					npcHumanoid.PlatformStand = false
					npcHumanoid.AutoRotate = true
					
					target:SetAttribute("KnockedDownStartTime", nil)
					target:SetAttribute("OriginalWalkSpeed", nil)
					target:SetAttribute("OriginalJumpPower", nil)
					
					if npcHumanoid.Health > 0 then
						npcHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
						task.wait(0.5)
						if npcHumanoid.Health > 0 then
							npcHumanoid:ChangeState(Enum.HumanoidStateType.Running)
						end
					end
				end
			end
		end)
		
		SharedHelperFunctions.log("NPC was knocked back 20 studs ragdolled for 3 seconds")
		return
	end
	
	if KnockedDownPlayers[targetPlayer.UserId] then return end
	
	local humanoid = target:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	local originalWalkSpeed = humanoid.WalkSpeed
	local originalJumpPower = humanoid.JumpPower
	
	KnockedDownPlayers[targetPlayer.UserId] = {
		startTime = os.clock(),
		duration = 2.0,
		originalWalkSpeed = originalWalkSpeed,
		originalJumpPower = originalJumpPower,
		isRagdolled = true
	}
	
	local Replicate = ReplicatedStorage.Remotes.Replicate
	Replicate:FireAllClients("Combat", "HitFX", "Basic Hit", target.PrimaryPart)
	
	task.delay(3.0, function()
		ServerCombatManager.recoverFromKnockdown(targetPlayer)
	end)
	
	SharedHelperFunctions.log(targetPlayer.Name .. " was knocked back 20 studs and ragdolled for 3 seconds!")
end

function ServerCombatManager.recoverFromKnockdown(targetPlayer)
	if not targetPlayer then return end
	
	local knockdownData = KnockedDownPlayers[targetPlayer.UserId]
	if not knockdownData then return end
	
	local character = targetPlayer.Character
	if not character then return end
	
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BodyVelocity") or descendant:IsA("BodyAngularVelocity") or descendant:IsA("LinearVelocity") then
			descendant:Destroy()
		end
	end
	
	ServerCombatManager.recoverFromR15RagdollFromSample(character)
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	humanoid.WalkSpeed = knockdownData.originalWalkSpeed or 16
	humanoid.JumpPower = knockdownData.originalJumpPower or 50
	humanoid.AutoRotate = true
	
	task.wait(0.1)
	if humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
	
	KnockedDownPlayers[targetPlayer.UserId] = nil
	
	local Replicate = ReplicatedStorage.Remotes.Replicate
	Replicate:FireAllClients("Combat", "HitFX", "Basic Hit", character.PrimaryPart)
	
	SharedHelperFunctions.log(targetPlayer.Name .. " recovered from ragdoll!")
end

function ServerCombatManager.stunPlayer(player, duration)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local originalWalkSpeed = humanoid.WalkSpeed
	local originalJumpPower = humanoid.JumpPower

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	task.delay(duration, function()
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = originalWalkSpeed
			humanoid.JumpPower = originalJumpPower
		end
	end)

	local Replicate = ReplicatedStorage.Remotes.Replicate
	Replicate:FireAllClients("Combat", "HitFX", "Basic Hit", character.PrimaryPart)
end

local R15_JOINTS = {
	"Neck",
	"Waist",
	"LeftShoulder", "RightShoulder",
	"LeftElbow", "RightElbow",
	"LeftWrist", "RightWrist",
	"LeftHip", "RightHip",
	"LeftKnee", "RightKnee",
	"LeftAnkle", "RightAnkle",
	"RootJoint"
}

local R15_CONSTRAINTS = {
	"BallSocketConstraint",
	"HingeConstraint",
	"PrismaticConstraint"
}

local originalJointProperties = {}

function ServerCombatManager.applyR15Ragdoll(character, impactForce, impactPoint)
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	originalJointProperties[character] = {}

	local originalState = {
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		AutoRotate = humanoid.AutoRotate,
		PlatformStand = humanoid.PlatformStand
	}

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	for _, jointName in ipairs(R15_JOINTS) do
		local joint = character:FindFirstChild(jointName)
		if joint and joint:IsA("Motor6D") then
			originalJointProperties[character][joint] = {
				Enabled = joint.Enabled,
				Transform = joint.Transform,
				C0 = joint.C0,
				C1 = joint.C1
			}

			joint.Enabled = false
		end
	end

	for _, part in ipairs(character:GetDescendants()) do
		for _, constraintType in ipairs(R15_CONSTRAINTS) do
			if part:IsA(constraintType) then
				originalJointProperties[character][part] = {
					Enabled = part.Enabled
				}
				part.Enabled = false
			end
		end

		if part:IsA("BasePart") then
			part.CustomPhysicalProperties = PhysicalProperties.new(
				0.5,
				0.3,
				0.4
			)

			part.CanCollide = true
		end
	end

	if impactForce and impactPoint then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				local distance = (part.Position - impactPoint).Magnitude
				local forceMultiplier = math.max(0, 1 - (distance / 10))

				if forceMultiplier > 0 then
					part:ApplyImpulse(impactForce * forceMultiplier)

					local angularImpulse = Vector3.new(
						math.random(-100, 100),
						math.random(-100, 100),
						math.random(-100, 100)
					) * forceMultiplier

					part.RotVelocity += angularImpulse
				end
			end
		end
	else
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				local randomForce = Vector3.new(
					math.random(-500, 500),
					math.random(200, 500),
					math.random(-500, 500)
				)
				part:ApplyImpulse(randomForce)
			end
		end
	end

	character:SetAttribute("R15OriginalState", originalState)
end

function ServerCombatManager.recoverFromR15Ragdoll(character)
	if not character or not originalJointProperties[character] then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	for joint, properties in pairs(originalJointProperties[character]) do
		if joint and joint.Parent then
			if joint:IsA("Motor6D") then
				joint.Enabled = properties.Enabled
				joint.Transform = properties.Transform or joint.Transform
				joint.C0 = properties.C0 or joint.C0
				joint.C1 = properties.C1 or joint.C1
			elseif properties.Enabled ~= nil then
				joint.Enabled = properties.Enabled
			end
		end
	end

	local originalState = character:GetAttribute("R15OriginalState")
	if originalState then
		humanoid.WalkSpeed = originalState.WalkSpeed
		humanoid.JumpPower = originalState.JumpPower
		humanoid.AutoRotate = originalState.AutoRotate
		humanoid.PlatformStand = originalState.PlatformStand or false
	end

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CustomPhysicalProperties = nil
		end
	end

	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	task.wait(0.5)
	if humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end

	originalJointProperties[character] = nil
	character:SetAttribute("R15OriginalState", nil)
end

function ServerCombatManager.applyR15RagdollFromSample(character, impactForce, impactPoint)
	if not character then return end

	local CollectionService = game:GetService("CollectionService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	
	local RagdollHandler = ReplicatedStorage:FindFirstChild("RagdollHandler")
	if not RagdollHandler then
		local sampleRagdoll = game.StarterPack:FindFirstChild("SampleCombat")
		if sampleRagdoll then
			local sampleServerScript = sampleRagdoll:FindFirstChild("ServerScriptService")
			if sampleServerScript then
				local sampleRagdollFolder = sampleServerScript:FindFirstChild("R15Ragdoll")
				if sampleRagdollFolder then
					RagdollHandler = sampleRagdollFolder:FindFirstChild("RagdollHandler")
				end
			end
		end
	end
	
	if not RagdollHandler then
		SharedHelperFunctions.log("RagdollHandler not found, falling back to basic ragdoll")
		ServerCombatManager.applyR15Ragdoll(character, impactForce, impactPoint)
		return
	end
	
	CollectionService:AddTag(character, "Ragdoll")
	
	if impactForce and impactPoint and character.PrimaryPart then
		local bodyVelocity = Instance.new("BodyVelocity")
		local adjustedForce = Vector3.new(impactForce.X, impactForce.Y - 200, impactForce.Z)
		bodyVelocity.Velocity = adjustedForce
		bodyVelocity.MaxForce = Vector3.new(1e6, 1e6, 1e6)
		bodyVelocity.Parent = character.PrimaryPart
		
		task.delay(0.5, function()
			if bodyVelocity and bodyVelocity.Parent then
				bodyVelocity:Destroy()
			end
		end)
	end
	
	SharedHelperFunctions.log(character.Name .. " was ragdolled using sample system!")
end

function ServerCombatManager.recoverFromR15RagdollFromSample(character)
	if not character then return end

	local CollectionService = game:GetService("CollectionService")
	
	CollectionService:RemoveTag(character, "Ragdoll")
	
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local vfxFolder = ReplicatedStorage:FindFirstChild("Storage")
	if vfxFolder then
		local vfxObjects = vfxFolder:FindFirstChild("VfxObjects")
		if vfxObjects then
			local combatVfx = vfxObjects:FindFirstChild("Combat")
			if combatVfx then
				local basicHitVfx = combatVfx:FindFirstChild("Basic Hit")
				if basicHitVfx and character.PrimaryPart then
					local hitClone = basicHitVfx:Clone()
					hitClone.Parent = workspace.Debris
					hitClone.CFrame = CFrame.new(character.PrimaryPart.Position)
					game.Debris:AddItem(hitClone, 3)
					
					task.delay(0.01, function()
						for _, particle in ipairs(hitClone:GetDescendants()) do
							if particle:IsA("ParticleEmitter") then
								particle:Emit(particle:GetAttribute("EmitCount") or 5)
							end
						end
					end)
				end
			end
		end
	end
	
	SharedHelperFunctions.log(character.Name .. " recovered from sample ragdoll!")
end

function ServerCombatManager.enableRagdoll(character, enable)
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	if enable then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)

		for _, child in ipairs(character:GetDescendants()) do
			if child:IsA("Motor6D") then
				child.Enabled = false
			end
		end
	else
		for _, child in ipairs(character:GetDescendants()) do
			if child:IsA("Motor6D") then
				child.Enabled = true
			end
		end

		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

function ServerCombatManager.applyKnockup(target, force)
	local rootPart = target.PrimaryPart
	if not rootPart then return end

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Velocity = Vector3.new(0, force, 0)
	bodyVelocity.MaxForce = Vector3.new(0, 10000, 0)
	bodyVelocity.P = 10000
	bodyVelocity.Parent = rootPart

	task.delay(0.5, function()
		if bodyVelocity then
			bodyVelocity:Destroy()
		end
	end)
end



function ServerCombatManager.registerEventListeners()
	Players.PlayerAdded:Connect(ServerCombatManager.onPlayerAdded)

	Packets.RequestToStartSprinting.OnServerEvent:Connect(ServerCombatManager.onRequestToStartSprintingReceived)
	Packets.RequestToStopSprinting.OnServerEvent:Connect(ServerCombatManager.onRequestToStopSprintingReceived)
	Packets.RequestToDash.OnServerEvent:Connect(ServerCombatManager.onRequestToDashReceived)
	Packets.RequestToM1.OnServerEvent:Connect(ServerCombatManager.onRequestToM1Received)
	Packets.RequestToBlock.OnServerEvent:Connect(ServerCombatManager.onRequestToBlockReceived)
	Packets.RequestToStopBlocking.OnServerEvent:Connect(ServerCombatManager.onRequestToStopBlockingReceived)
	Packets.RequestToParry.OnServerEvent:Connect(ServerCombatManager.onRequestToParryReceived)

	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Model") then
			local humanoid = descendant:FindFirstChild("Humanoid")
			if humanoid then
				task.delay(0.1, function()
					ServerCombatManager.ensureHitbox(descendant)
				end)
			end
		end
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			ServerCombatManager.onPlayerAdded(player)
		end)
	end
end



return ServerCombatManager
