local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(Player)
	Player.CharacterAdded:Connect(function(Character)
		Character.Humanoid.BreakJointsOnDeath = false

		Character.Humanoid.Died:Connect(function()
			for _, v in pairs(Character:GetDescendants()) do


				if v:IsA("Motor6D") then
					local Attachment0, Attachment1 = Instance.new("Attachment"), Instance.new("Attachment")
					Attachment0.CFrame = v.C0
					Attachment1.CFrame = v.C1
					Attachment0.Parent = v.Part0
					Attachment1.Parent = v.Part1

					local BallSocketConstraint = Instance.new("BallSocketConstraint")
					BallSocketConstraint.Attachment0 = Attachment0
					BallSocketConstraint.Attachment1 = Attachment1
					BallSocketConstraint.Parent = v.Parent

					v:Destroy()
				end

			end

			Character.HumanoidRootPart.CanCollide = false
			Character.Head.CanCollide = true

			wait(0.3)
		end)

	end)
end)