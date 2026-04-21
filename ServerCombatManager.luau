--[[
	Simple M1 Combat System
	- 4-hit combo with knockback on final hit
	- Blocking, parry, ragdoll, and sound effects
	- Uses hitbox scaling, random pitch sounds, and CollectionService tags
--]]

-- SERVICES
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CS = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

-- FOLDERS (create missing ones to avoid errors)
local Remotes = RS:FindFirstChild("Remotes") or Instance.new("Folder", RS)
Remotes.Name = "Remotes"
local Modules = RS:FindFirstChild("Modules") or Instance.new("Folder", RS)
Modules.Name = "Modules"
local Hitboxes = RS:FindFirstChild("Hitboxes") or Instance.new("Folder", RS)
Hitboxes.Name = "Hitboxes"
local Sounds = RS:FindFirstChild("Sounds") or Instance.new("Folder", RS)
Sounds.Name = "Sounds"

-- MODULES (try to load, skip if missing)
local zonePlus = require(Modules.Zone)  -- hitbox detection
local Misc = require(Modules.Misc)      -- ragdoll & disable
local PunchRock = require(Modules.PunchRock)  -- rock debris

-- REMOTES
local attackRemote = script.Parent:WaitForChild("Attack")
local Replicate = Remotes.Replicate

-- ANIMATIONS
local combatAnims = RS.Animations.Combat
local getHitAnims = RS.Animations.GetHit

-- SETTINGS
local M1Debounce = false      -- prevents spam
local Combo = 1               -- current combo step (1-4)
local doingCombo = 0          -- which hit we're on (1-4)
local hit = {}                -- stores already hit targets
local ImmunityTag = "Immunity"

-- play a sound with random pitch (0.8 to 1.2)
local function playRandomSound(soundTemplate, parent)
	local sound = soundTemplate:Clone()
	sound.Parent = parent
	sound.PlaybackSpeed = math.random(8, 12) / 10
	sound:Play()
	Debris:AddItem(sound, 3)
end

-- create hitbox and handle damage / block / parry
local function createHitbox(character, hrp, player, currentCombo)
	local hitbox = Hitboxes.Combat.M1:Clone()
	hitbox.Size = hitbox.Size * 0.7   -- smaller hitbox
	hitbox.CFrame = hrp.CFrame
	hitbox.Parent = hrp

	-- weld hitbox to character
	local weld = Instance.new("Weld")
	weld.Part0 = hrp
	weld.Part1 = hitbox
	weld.C1 = require(hitbox.weldCF)
	weld.Parent = hitbox

	local hitzone = zonePlus.new(hitbox)
	hitzone:setAccuracy("Precise")

	local anyHit = false

	for _, part in pairs(hitzone:getParts()) do
		if part.Parent ~= character then
			local target = part.Parent
			local targetHumanoid = target:FindFirstChild("Humanoid")
			if targetHumanoid and not hit[target.Name] then
				if not CS:HasTag(target, ImmunityTag) then
					CS:AddTag(target, ImmunityTag)
					table.insert(hit, target.Name)
					anyHit = true

					local targetHRP = target:FindFirstChild("HumanoidRootPart")
					local isPlayer = Players:FindFirstChild(target.Name)
					local isBlocking = (isPlayer and isPlayer:FindFirstChild("isBlocking")) or target:FindFirstChild("isBlocking")

					-- perfect block (parry) check
					if CS:HasTag(target, "Perfect Block") then
						Replicate:FireAllClients("Combat", "HitFX", "Parry", targetHRP)
						local parryAnim = character.Humanoid:LoadAnimation(combatAnims.Parry)
						parryAnim:Play()
						task.delay(1, function() if parryAnim then parryAnim:Stop() end end)
						Misc.InsertDisabled(character, 0.7)
					else
						-- block check (must be facing attacker)
						local blocking = isBlocking and isBlocking.Value
						local dot = hrp.CFrame.lookVector:Dot(targetHRP.CFrame.lookVector)
						if blocking and targetHRP and dot < 0.7 then
							-- blocked hit
							local blockBar = target:FindFirstChild("BlockBar")
							if blockBar then
								Replicate:FireAllClients("Combat", "HitFX", "BlockedHit", targetHRP)
								blockBar.Value = blockBar.Value - 5
								-- push back a little
								local bv = Instance.new("BodyVelocity")
								bv.MaxForce = Vector3.new(5e4, 5e2, 5e4)
								bv.Velocity = hrp.CFrame.lookVector * 10
								bv.Parent = targetHRP
								Debris:AddItem(bv, 0.16)
							end
						else
							-- normal hit
							targetHumanoid:TakeDamage(5)
							Replicate:FireAllClients("Combat", "HitFX", "NormalHit", targetHRP)

							-- play hurt animation
							local hurtAnim = targetHumanoid:LoadAnimation(getHitAnims.Hit1)
							hurtAnim:Play(0.01, 0.7, 1.3)

							-- final combo hit: ragdoll + knockback
							if doingCombo == 4 then
								PunchRock.Punch(hrp.Position, hrp.CFrame.LookVector, Vector3.new(0, -10, 0), 15, 2, 30, 0.6, 0.9, 15, 3, 2, 0.6, 1)
								CS:AddTag(target, "Ragdoll")   -- ragdoll for 3 seconds
								task.delay(3, function()
									if target and target.Parent then CS:RemoveTag(target, "Ragdoll") end
								end)
								-- knockback 25 studs
								local knock = Instance.new("BodyVelocity")
								knock.MaxForce = Vector3.new(1e6, 1e6, 1e6)
								knock.Velocity = hrp.CFrame.lookVector * 25
								knock.Parent = targetHRP
								Debris:AddItem(knock, 0.5)
							else
								Misc.InsertDisabled(target, 0.5)  -- small stun
							end
						end
					end

					-- remove immunity after a short time
					task.delay(0.2, function()
						CS:RemoveTag(target, ImmunityTag)
					end)
				end
			end
		end
	end

	-- play hit sound only if we actually hit something
	if anyHit then
		playRandomSound(Sounds.Hit, character)
	end

	Debris:AddItem(hitbox, 0.3)
end

-- listen for attack / block inputs
attackRemote.OnServerEvent:Connect(function(player, action)
	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChild("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then return end

	local isBlocking = player:FindFirstChild("isBlocking")
	local disabled = char:FindFirstChild("Disabled")

	if action == "Attack" and humanoid.Health > 0 then
		if not M1Debounce and (not isBlocking or not isBlocking.Value) and not disabled then
			M1Debounce = true
			hit = {}   -- reset hit list for this swing

			-- load animations for all combo steps
			local anims = {
				humanoid:LoadAnimation(combatAnims.A1),
				humanoid:LoadAnimation(combatAnims.A2),
				humanoid:LoadAnimation(combatAnims.A3),
				humanoid:LoadAnimation(combatAnims.A4),
			}

			-- set IsAttacking flag (for other scripts)
			task.spawn(function()
				if char:FindFirstChild("Values") and char.Values.IsAttacking then
					char.Values.IsAttacking.Value = true
					task.wait(0.5)
					char.Values.IsAttacking.Value = false
				end
			end)

			-- play fist swing sound with random pitch
			playRandomSound(Sounds.FistSwing, char)

			-- play the correct animation based on combo
			local current = Combo
			doingCombo = current
			anims[current]:Play(0.1, 1, 0.9)   -- slower animation speed

			-- advance combo for next attack
			if Combo == 4 then
				Combo = 1
			else
				Combo = Combo + 1
			end

			local hitMarker = false
			local resetMarker = false

			-- when animation hits the "Hit" marker, create hitbox
			anims[current]:GetMarkerReachedSignal("Hit"):Connect(function()
				hitMarker = true
				createHitbox(char, hrp, player, doingCombo)
			end)

			-- when animation hits "DBReset", allow next attack
			anims[current]:GetMarkerReachedSignal("DBReset"):Connect(function()
				resetMarker = true
				M1Debounce = false
			end)

			-- fallbacks in case markers are missing
			task.delay(0.5, function()
				if not hitMarker then
					createHitbox(char, hrp, player, doingCombo)
				end
			end)

			task.delay(1.2, function()
				if not resetMarker then
					M1Debounce = false
				end
			end)

			-- reset combo if player stops attacking
			task.delay(1.5, function()
				if Combo == 1 and doingCombo ~= 0 then
					doingCombo = 0
				end
			end)
		end

	elseif action == "Block" and humanoid.Health > 0 then
		if not M1Debounce and not disabled then
			if isBlocking then isBlocking.Value = true end
		end
	elseif action == "Unblock" then
		if isBlocking then isBlocking.Value = false end
	end
end)
