--!strict
-- Weather system.
-- 8 presets blend smoothly; a button list picks the weather and one slider sets intensity (up to 160% overdrive).
-- Layers: sky color/atmosphere/clouds, 4 particle emitters (rain, snow, ground mist, embers), color grading, blur, gusting wind,
-- and storm lightning with forked bolts, a double flash and a delayed camera rumble. Every object is created here; no assets needed.

const Lighting = game:GetService('Lighting') -- Lighting service: sky mood, ambient light, exposure, atmosphere and post effects live here.
const Players = game:GetService('Players') -- Players service: gives access to the local player, their character and PlayerGui.
const RunService = game:GetService('RunService') -- RunService: RenderStepped fires every frame before rendering, ideal for visual blending.
const TweenService = game:GetService('TweenService') -- TweenService: smooth property animation for both the UI and the lightning flash.
const UserInputService = game:GetService('UserInputService') -- UserInputService: global input events for slider dragging and hotkeys.
const Workspace = game:GetService('Workspace') -- Workspace: parent of 3D objects, camera, terrain (clouds) and the Raycast API.

const player = Players.LocalPlayer :: Player -- Getting the local player via `Players` Service.
const playerGui = player:WaitForChild('PlayerGui') :: PlayerGui -- Container that holds every ScreenGui of this player.

const terrain = workspace.Terrain :: Terrain
const strikeFolder = Instance.new('Folder') -- A folder to contain all lightning bolts.
strikeFolder.Name = 'LightningStrikes'
strikeFolder.Parent = workspace

export type Look = {
	rain: number, -- Rain particle multiplier (0 = none, 1 = normal, 3 = deluge).
	snow: number, -- Snow/ash flake multiplier.
	mist: number, -- Ground mist / dust cloud multiplier (fog banks, sand walls, blizzard whiteout).
	ember: number, -- Glowing ember multiplier (ashfall only).
	cloud: number, -- Cloud cover from 0 to 1.
	fog: number, -- Fog thickness from 0 to 1 (drives Atmosphere density and haze).
	light: number, -- Lighting.Brightness: sun strength.
	wind: number, -- Wind speed in studs per second.
	sat: number, -- ColorCorrection saturation offset (-1 grey ... 1 vivid).
	blur: number, -- Screen blur in pixels, used for whiteouts and sandstorms.
	ambient: Color3, -- Ambient light color: fills shadows.
	tint: Color3, -- Atmosphere, cloud, mist and grading tint: the overall mood color.
	flake: Color3, -- Color of falling flakes (white snow versus grey ash).
}

export type Preset = {
	name: string, -- Text shown in the menu.
	look: Look, -- Target numbers for this weather type at 100% intensity.
	storm: boolean, -- True when this weather produces lightning.
}

const PRESETS: { Preset } = { -- The first entry doubles as the "no weather" baseline for the intensity slider.
	{
		name = 'Clear',
		storm = false,
		look = { -- Bright sky, thin clouds, light breeze.
			rain = 0,
			snow = 0,
			mist = 0,
			ember = 0,
			cloud = 0.2,
			fog = 0.15,
			light = 3,
			wind = 5,
			sat = 0.1,
			blur = 2, -- Nothing falls; slightly vivid colors.
			ambient = Color3.fromRGB(125, 125, 135),
			tint = Color3.fromRGB(199, 215, 235),
			flake = Color3.new(1, 1, 1), -- Cool daylight palette.
		},
	},
	{
		name = 'Cloudy',
		storm = false,
		look = { -- Heavy cloud cover and flat light, still dry.
			rain = 0,
			snow = 0,
			mist = 0,
			ember = 0,
			cloud = 0.85,
			fog = 0.3,
			light = 1.9,
			wind = 10,
			sat = -0.1,
			blur = 3, -- Overcast and a stiffer wind.
			ambient = Color3.fromRGB(100, 100, 110),
			tint = Color3.fromRGB(170, 180, 190),
			flake = Color3.new(1, 1, 1), -- Pale grey palette.
		},
	},
	{
		name = 'Rain',
		storm = false,
		look = { -- Steady downpour with low visibility.
			rain = 1.3,
			snow = 0,
			mist = 0.3,
			ember = 0,
			cloud = 0.9,
			fog = 0.55,
			light = 1.3,
			wind = 16,
			sat = -0.25,
			blur = 5, -- Dense rain, wind tilts the drops.
			ambient = Color3.fromRGB(78, 84, 96),
			tint = Color3.fromRGB(115, 127, 145),
			flake = Color3.new(1, 1, 1), -- Cold slate palette.
		},
	},
	{
		name = 'Storm',
		storm = true,
		look = { -- Deluge, near-black sky and lightning.
			rain = 2.8,
			snow = 0,
			mist = 0.9,
			ember = 0,
			cloud = 1,
			fog = 0.7,
			light = 0.6,
			wind = 38,
			sat = -0.4,
			blur = 5, -- Extreme rain and wind, colors drained.
			ambient = Color3.fromRGB(45, 50, 68),
			tint = Color3.fromRGB(70, 78, 98),
			flake = Color3.new(1, 1, 1), -- Dark blue-grey palette.
		},
	},
	{
		name = 'Snow',
		storm = false,
		look = { -- Soft, heavy flakes under bright overcast light.
			rain = 0,
			snow = 1.2,
			mist = 0.3,
			ember = 0,
			cloud = 0.85,
			fog = 0.55,
			light = 2,
			wind = 7,
			sat = -0.2,
			blur = 4, -- Gentle, lots of flakes.
			ambient = Color3.fromRGB(140, 145, 158),
			tint = Color3.fromRGB(222, 228, 238),
			flake = Color3.new(1, 1, 1), -- Cold white palette.
		},
	},
	{
		name = 'Blizzard',
		storm = false,
		look = { -- Whiteout: horizontal snow, thick drifting mist and blur.
			rain = 0,
			snow = 3.2,
			mist = 1.6,
			ember = 0,
			cloud = 1,
			fog = 0.85,
			light = 1.3,
			wind = 20,
			sat = -0.5,
			blur = 4, -- Maximum flakes, violent wind, soft focus.
			ambient = Color3.fromRGB(150, 155, 170),
			tint = Color3.fromRGB(205, 212, 225),
			flake = Color3.new(1, 1, 1), -- Washed-out white-blue palette.
		},
	},
	{
		name = 'Fog',
		storm = false,
		look = { -- Dead calm with rolling banks of mist.
			rain = 0,
			snow = 0,
			mist = 1.6,
			ember = 0,
			cloud = 0.6,
			fog = 1,
			light = 1.5,
			wind = 3,
			sat = -0.3,
			blur = 3, -- Maximum fog density and almost no wind.
			ambient = Color3.fromRGB(128, 130, 136),
			tint = Color3.fromRGB(185, 190, 198),
			flake = Color3.new(1, 1, 1), -- Milky grey palette.
		},
	},
	{
		name = 'Sandstorm',
		storm = false,
		look = { -- Desert sandstorm: orange walls of dust and blur.
			rain = 0,
			snow = 0,
			mist = 3,
			ember = 0,
			cloud = 0.3,
			fog = 0.8,
			light = 2.2,
			wind = 42,
			sat = 0.15,
			blur = 4, -- Dense dust blown by violent wind.
			ambient = Color3.fromRGB(170, 120, 70),
			tint = Color3.fromRGB(214, 160, 96),
			flake = Color3.fromRGB(200, 160, 110), -- Hot tan palette.
		},
	},
}

const CONFIG = {
	BlendRate = 1.2, -- Exponential blend speed: higher means faster transitions (about 2.5 seconds at 1.2).
	EmitterHeight = 40, -- How far above the camera the sky emitter floats.
	EmitterSize = 90, -- Width and depth of the sky emitter box in studs.
	RainRate = 1000, -- Rain particles per second at multiplier 1.
	SnowRate = 260, -- Snow particles per second at multiplier 1.
	SnowFall = 9, -- Terminal fall speed of snow in studs per second (acceleration = fall speed * drag).
	MistRate = 30, -- Mist puffs per second at multiplier 1.
	EmberRate = 90, -- Ember sparks per second at multiplier 1.
	BoltSegments = 10, -- Number of straight pieces in the main lightning bolt.
	BoltHeight = 240, -- Height above the ground from which lightning starts.
	StrikeMin = 1.5, -- Minimum seconds between strikes.
	StrikeMax = 6, -- Maximum seconds between strikes.
	StartClock = 14, -- Initial time of day (hours).
	RumberLength = 0.9, -- Lightning strike length in seconds.
	IntensitySlider = 1.6, -- Slider maximum: values above 1 are overdrive.
}

const WIND_DIRECTION: Vector3 = Vector3.new(1, 0, 0.4).Unit -- Fixed horizontal wind direction; only its strength changes.
const WIND_SIDEWAYS: Vector3 = Vector3.new(-WIND_DIRECTION.Z, 0, WIND_DIRECTION.X) -- Perpendicular direction, used for swirling.
const rng: Random = Random.new() -- One generator for all randomness; seeded automatically.

const atmosphere: Atmosphere = Lighting:FindFirstChildOfClass('Atmosphere') or Instance.new('Atmosphere') -- Reuse an existing one so we never stack two.
atmosphere.Parent = Lighting -- Atmosphere only works as a child of Lighting.
const clouds: Clouds = terrain:FindFirstChildOfClass('Clouds') or Instance.new('Clouds') -- Clouds live inside Terrain.
clouds.Parent = terrain -- Parent explicitly in case we just created it.

const function make(
	className: string,
	props: { [string]: any },
	parent: Instance?
): any -- Creates an Instance and applies props before parenting.
	const object = Instance.new(className) -- Create the raw instance.
	for key, value in pairs(props) do -- Visit every requested property.
		(object :: any)[key] = value -- Dynamic assignment needs the any cast under strict typing.
	end
	object.Parent = parent -- Parent last: avoids replicating or re-laying-out while properties change.
	return object -- Caller decides the more specific type.
end

const function tween(
	object: Instance,
	duration: number,
	props: { [string]: any },
	style: Enum.EasingStyle?
): Tween -- One-line tween with sane defaults.
	const info = TweenInfo.new(duration, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out) -- Quint-out: fast start, soft landing.
	const animation = TweenService:Create(object, info, props) -- Build the tween.
	animation:Play() -- Start immediately; a new tween on the same property cancels the old one.
	return animation -- Returned so callers can listen to Completed.
end

const function lerpLook(a: Look, b: Look, t: number, out: Look) -- Writes the blend of a and b into out; out may equal a (each field is independent).
	out.rain = a.rain + (b.rain - a.rain) * t -- Linear interpolation of a plain number.
	out.snow = a.snow + (b.snow - a.snow) * t -- Same formula for snow.
	out.mist = a.mist + (b.mist - a.mist) * t -- Same formula for mist.
	out.ember = a.ember + (b.ember - a.ember) * t -- Same formula for embers.
	out.cloud = a.cloud + (b.cloud - a.cloud) * t -- Same formula for cloud cover.
	out.fog = a.fog + (b.fog - a.fog) * t -- Same formula for fog.
	out.light = a.light + (b.light - a.light) * t -- Same formula for brightness.
	out.wind = a.wind + (b.wind - a.wind) * t -- Same formula for wind speed.
	out.sat = a.sat + (b.sat - a.sat) * t -- Same formula for saturation.
	out.blur = a.blur + (b.blur - a.blur) * t -- Same formula for blur.
	out.ambient = a.ambient:Lerp(b.ambient, t) -- Color3 has a built-in Lerp (RGB interpolation).
	out.tint = a.tint:Lerp(b.tint, t) -- Same for the mood tint.
	out.flake = a.flake:Lerp(b.flake, t) -- Same for the flake color.
end

const function gust(now: number): number -- Wind strength multiplier that breathes over time.
	return 1 + 0.3 * math.sin(now * 0.7) + 0.2 * math.sin(now * 1.9 + 1.3) -- Two sine waves with unrelated periods look irregular.
end

const grade: ColorCorrectionEffect = make('ColorCorrectionEffect', { Name = 'WeatherGrade' }, Lighting) -- Saturation and tint per weather.
const blurEffect: BlurEffect = make('BlurEffect', { Name = 'WeatherBlur', Size = 0 }, Lighting) -- Whiteout / dust blur.
Lighting.ClockTime = CONFIG.StartClock -- Start in the afternoon so the first frame is bright.

const skyPart: Part = make('Part', { -- Invisible box high above the camera: rain, snow and embers spawn inside it.
	Name = 'WeatherSky',
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false, -- Static and non-interactive.
	Transparency = 1,
	Size = Vector3.new(CONFIG.EmitterSize, 1, CONFIG.EmitterSize), -- Hidden, wide and flat.
}, workspace)
const mistPart: Part = make('Part', { -- Invisible box at eye level: mist and dust spawn inside it.
	Name = 'WeatherMist',
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false, -- Static and non-interactive.
	Transparency = 1,
	Size = Vector3.new(140, 8, 140), -- Hidden, wide and fairly flat.
}, workspace)
const rainEmitter: ParticleEmitter = make('ParticleEmitter', { -- Fast, stretched, glowing streaks.
	Rate = 0,
	Lifetime = NumberRange.new(0.9),
	Speed = NumberRange.new(85, 100), -- Short life, high speed.
	EmissionDirection = Enum.NormalId.Bottom,
	Orientation = Enum.ParticleOrientation.VelocityParallel, -- Spawn downwards and align to motion.
	Size = NumberSequence.new(0.14),
	Squash = NumberSequence.new(-2),
	Transparency = NumberSequence.new(0.45), -- Thin and stretched (flip the Squash sign if streaks look flat).
	LightEmission = 0.3,
	LightInfluence = 0.6,
	Color = ColorSequence.new(Color3.fromRGB(190, 205, 225)), -- Slightly glowing so rain stays visible at night.
}, skyPart)
const snowEmitter: ParticleEmitter = make('ParticleEmitter', { -- Soft flakes that swirl in the wind.
	Rate = 0,
	Lifetime = NumberRange.new(6),
	Speed = NumberRange.new(6, 10),
	Drag = 1.2, -- Long life, gentle fall; drag caps the wind push.
	EmissionDirection = Enum.NormalId.Bottom,
	SpreadAngle = Vector2.new(20, 20), -- Falls down with a little scatter.
	Size = NumberSequence.new(0.35),
	Transparency = NumberSequence.new(0.1),
	LightEmission = 0.5, -- Bigger and brighter than rain.
	RotSpeed = NumberRange.new(-60, 60), -- Tumbling flakes.
}, skyPart)
const emberEmitter: ParticleEmitter = make('ParticleEmitter', { -- Glowing sparks for ashfall.
	Rate = 0,
	Lifetime = NumberRange.new(5),
	Speed = NumberRange.new(3, 7),
	Drag = 1, -- Slow drifting sparks.
	EmissionDirection = Enum.NormalId.Bottom,
	SpreadAngle = Vector2.new(30, 30), -- Falls with scatter.
	Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }), -- Shrinks as it burns out.
	LightEmission = 1,
	LightInfluence = 0,
	Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(200, 50, 20)), -- Orange to red glow.
}, skyPart)
const mistEmitter: ParticleEmitter = make('ParticleEmitter', { -- Big soft clouds of mist, dust or whiteout.
	Rate = 0,
	Lifetime = NumberRange.new(6, 9),
	Speed = NumberRange.new(0, 2),
	Drag = 2, -- Long-lived and drag-limited drift.
	Texture = 'rbxasset://textures/particles/smoke_main.dds',
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-8, 8), -- Built-in smoke texture, randomly rotated.
	Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 12), NumberSequenceKeypoint.new(1, 32) }), -- Puffs grow as they drift.
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.82),
		NumberSequenceKeypoint.new(0.8, 0.82),
		NumberSequenceKeypoint.new(1, 1),
	}), -- Fade in and out.
	LightInfluence = 1, -- Mist darkens at night like real fog.
}, mistPart)

const current: Look = table.clone(PRESETS[1].look) -- Shallow clone is enough: Color3 values are immutable.
const target: Look = table.clone(PRESETS[1].look) -- Starts identical so nothing blends on startup.
local selected: number = 1 -- Index of the active preset.
local intensity: number = 1 -- 0..1.6: below 1 fades towards Clear, above 1 is overdrive.
local strikeBoost: number = 1 -- Overdrive multiplier; also shortens the time between lightning strikes.
local nextStrike: number = 0 -- os.clock() time of the next allowed strike.

const function retarget() -- Recomputes the target whenever the preset or a slider changes (event-driven, not per frame).
	lerpLook(PRESETS[1].look, PRESETS[selected].look, math.min(intensity, 1), target) -- Blend Clear -> preset by intensity (capped at 100%).
	strikeBoost = math.max(1, intensity) -- Overdrive factor above 100%.
	target.rain *= strikeBoost -- Overdrive adds more rain...
	target.snow *= strikeBoost -- ...more snow...
	target.mist *= strikeBoost -- ...thicker mist...
	target.ember *= strikeBoost -- ...and more embers.
end

const function applyLook(look: Look, now: number) -- Pushes numbers to the actual engine objects; runs every frame.
	Lighting.Brightness = look.light -- Sun strength.
	Lighting.Ambient = look.ambient -- Shadow fill.
	Lighting.OutdoorAmbient = look.ambient -- Outdoor fill uses the same mood color.
	atmosphere.Density = look.fog * 0.6 -- Scale: density 0.6 is already very thick.
	atmosphere.Haze = look.fog * 5 -- Haze makes the horizon milky.
	atmosphere.Color = look.tint -- Tint the scattered light.
	atmosphere.Decay = look.tint -- Tint the horizon decay as well so the sky matches.
	clouds.Cover = look.cloud -- How much of the sky is covered.
	clouds.Density = 0.35 + look.cloud * 0.5 -- Thicker clouds when more of the sky is covered.
	clouds.Color = Color3.new(1, 1, 1):Lerp(look.tint, look.cloud * 0.7) -- White clouds darken towards the mood color.
	grade.Saturation = look.sat -- Drain or boost color.
	grade.TintColor = Color3.new(1, 1, 1):Lerp(look.tint, 0.25) -- A quarter of the mood color tints the whole screen.
	blurEffect.Size = look.blur -- Whiteout / dust blur.
	rainEmitter.Rate = CONFIG.RainRate * look.rain -- Emission scales with the multipliers.
	snowEmitter.Rate = CONFIG.SnowRate * look.snow -- Snow density.
	emberEmitter.Rate = CONFIG.EmberRate * look.ember -- Ember density.
	mistEmitter.Rate = CONFIG.MistRate * look.mist -- Mist density.
	snowEmitter.Color = ColorSequence.new(look.flake) -- White snow versus grey ash.
	mistEmitter.Color = ColorSequence.new(look.tint) -- Mist takes the mood color (tan dust, white fog...).
	const drift: Vector3 = WIND_DIRECTION * look.wind * gust(now) -- Wind velocity with gusting.
	const swirl: Vector3 = WIND_SIDEWAYS * math.sin(now * 1.3) * look.wind * 0.12 -- Sideways swirl so flakes never fall in a straight line.
	rainEmitter.Acceleration = drift * 1.6 -- Rain is fast, so a modest push tilts it noticeably.
	snowEmitter.Acceleration = drift * 0.5 + swirl - Vector3.yAxis * CONFIG.SnowFall * snowEmitter.Drag -- Wind plus gravity: without the downward term, drag stops the flakes in mid-air.
	emberEmitter.Acceleration = drift * 0.4 + swirl -- Embers drift like snow.
	mistEmitter.Acceleration = drift * 0.9 -- Dust and mist are carried along by the wind.
end

const function buildBolt(
	from: Vector3,
	to: Vector3,
	segments: number,
	width: number,
	depth: number,
	parts: { Part },
	folder: Folder
) -- Recursive: each bolt may sprout branches.
	const length: number = (to - from).Magnitude -- Total length decides how far the path may wander.
	local previous: Vector3 = from -- Start of the segment being built.
	for index = 1, segments do -- One straight piece per iteration.
		local point: Vector3 = from:Lerp(to, index / segments) -- Evenly spaced point on the straight line.
		if index < segments then -- The last point must stay exactly on the target.
			point += Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * length * 0.06 -- Random sideways jitter makes it jagged.
		end
		const segment: Part = make('Part', { -- Neon bar stretched between the two points.
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Material = Enum.Material.Neon, -- Glowing, purely visual.
			Color = Color3.fromRGB(210, 225, 255),
			Size = Vector3.new(width, width, (point - previous).Magnitude), -- Blue-white, length equals the distance covered.
			CFrame = CFrame.lookAt(previous:Lerp(point, 0.5), point), -- Midpoint position, Z axis pointing at the end.
		}, folder)
		table.insert(parts, segment) -- Remember it so the whole bolt can fade out.
		if depth < 2 and index < segments and rng:NextNumber() < 0.3 then -- Occasionally fork, but only two levels deep.
			const drop = Vector3.new(rng:NextNumber(-1, 1), -rng:NextNumber(0.4, 0.9), rng:NextNumber(-1, 1))
				* length
				* 0.3 -- Branch heads downwards and sideways.
			buildBolt(point, point + drop, 4, width * 0.55, depth + 1, parts, folder) -- Thinner, shorter child bolt.
		end
		previous = point -- The next segment starts where this one ended.
	end
end

const function rumble(power: number) -- Thunder without audio: a decaying camera shake.
	const character: Model? = player.Character -- May be nil while respawning.
	const humanoid: Humanoid? = character and character:FindFirstChildOfClass('Humanoid') -- CameraOffset lives on the Humanoid.
	if not humanoid then -- No character, nothing to shake.
		return -- Leave quietly.
	end
	const started: number = os.clock() -- Shake start time.
	while os.clock() - started < CONFIG.RumberLength do -- Shake until the time is up.
		const fade: number = 1 - (os.clock() - started) / CONFIG.RumberLength -- Strength decays linearly to zero.
		humanoid.CameraOffset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), 0) * power * fade -- Random offset scaled by the fade.
		RunService.RenderStepped:Wait() -- One shake step per frame.
	end
	humanoid.CameraOffset = Vector3.zero -- Always restore the camera.
end

const function strike(origin: Vector3) -- Picks a point near the camera, draws a bolt, flashes the sky and rumbles.
	const angle: number = rng:NextNumber(0, 2 * math.pi) -- Random direction around the camera.
	const distance: number = rng:NextNumber(80, 170) -- Random distance so strikes are visible but not on top of the player.
	const x: number, z: number = origin.X + math.cos(angle) * distance, origin.Z + math.sin(angle) * distance -- Polar to Cartesian.
	const hit = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0)) -- Find the ground below the strike point.
	const ground: Vector3 = if hit then hit.Position else Vector3.new(x, 0, z) -- Fall back to y = 0 over the void.
	const parts: { Part } = {} -- Every segment, collected for the fade-out.
	buildBolt(ground + Vector3.yAxis * CONFIG.BoltHeight, ground, CONFIG.BoltSegments, 0.9, 0, parts, strikeFolder) -- Build the main bolt and its forks.
	for _, part in ipairs(parts) do -- Fade every segment out.
		tween(part, 0.45, { Transparency = 1 }, Enum.EasingStyle.Sine) -- Quick glow-out.
	end
	Lighting.ExposureCompensation = 2 -- First bright flash.
	task.wait(0.06) -- Short pause: the double flash is what makes lightning feel real.
	Lighting.ExposureCompensation = 0.8 -- Dim between flashes.
	task.wait(0.08) -- Second pause.
	Lighting.ExposureCompensation = 2.8 -- Second, stronger flash.
	tween(Lighting, 0.6, { ExposureCompensation = 0 }) -- Fade back to normal exposure.
	task.wait(distance / 200) -- Thunder arrives later the farther the strike is.
	rumble(0.35 + 0.15 * (distance < 110 and 1 or 0)) -- Close strikes shake harder.
end

const NORMAL: Color3 = Color3.fromRGB(55, 55, 55) -- Button color.
const SELECTED: Color3 = Color3.fromRGB(0, 120, 215) -- Color of the active preset button.
const WHITE: Color3 = Color3.new(1, 1, 1) -- Text color.

const gui: ScreenGui = make('ScreenGui', { Name = 'WeatherUI', ResetOnSpawn = false }, playerGui) -- ResetOnSpawn=false keeps the UI after respawn.
const panel: Frame = make('Frame', { -- Single container in the top-left corner.
	Size = UDim2.fromOffset(160, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.fromOffset(10, 10), -- Fixed width, height follows content.
	BackgroundColor3 = Color3.fromRGB(25, 25, 25),
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0, -- Dark and slightly see-through.
}, gui)
make('UIListLayout', { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, panel) -- Stack children vertically.
make(
	'UIPadding',
	{
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
	},
	panel
) -- Inner margin.

const buttons: { TextButton } = {} -- Preset buttons in preset order.
const function highlight() -- Colors the active preset button.
	for index, button in ipairs(buttons) do -- Visit every button.
		button.BackgroundColor3 = if index == selected then SELECTED else NORMAL -- Only the selected one is highlighted.
	end
end

for index, preset in ipairs(PRESETS) do -- One button per preset.
	const button: TextButton = make('TextButton', { -- Plain text button.
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = NORMAL,
		BorderSizePixel = 0,
		LayoutOrder = index, -- Full width, ordered like the presets.
		Font = Enum.Font.SourceSans,
		TextSize = 16,
		TextColor3 = WHITE,
		Text = preset.name, -- Readable label.
	}, panel)
	button.Activated:Connect(function() -- Click or tap.
		selected = index -- Remember the choice.
		retarget() -- Recompute the blend target.
		highlight() -- Update button colors.
	end)
	buttons[index] = button -- Keep for highlight().
end

const label: TextLabel = make('TextLabel', { -- Slider caption with the current value.
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
	LayoutOrder = #PRESETS + 1, -- Right below the buttons.
	Font = Enum.Font.SourceSans,
	TextSize = 16,
	TextColor3 = WHITE,
	Text = 'Intensity: 100%', -- Initial text matches intensity = 1.
}, panel)
const track: Frame = make(
	'Frame',
	{ Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = NORMAL, BorderSizePixel = 0, LayoutOrder = #PRESETS + 2 },
	panel
) -- Slider bar.
const fill: Frame = make(
	'Frame',
	{ Size = UDim2.fromScale(intensity / CONFIG.IntensitySlider, 1), BackgroundColor3 = SELECTED, BorderSizePixel = 0 },
	track
) -- Filled part.
local dragging: boolean = false -- True while the slider is being dragged.

const function setFromX(x: number) -- Converts a screen X coordinate into an intensity value.
	local alpha = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1) -- Position along the bar from 0 to 1.
	fill.Size = UDim2.fromScale(alpha, 1) -- Resize the fill.
	intensity = alpha * CONFIG.IntensitySlider -- Map the fraction to the intensity range.
	label.Text = string.format('Intensity: %d%%', math.floor(intensity * 100 + 0.5)) -- Rounded percent (%d needs an integer).
	retarget() -- Recompute the blend target.
end

track.InputBegan:Connect(function(input: InputObject) -- Start dragging on mouse press or touch.
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then -- Ignore other inputs.
		dragging = true -- Enable drag tracking.
		setFromX(input.Position.X) -- Jump to the pressed position.
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject) -- Global so dragging continues outside the bar.
	if
		dragging
		and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch)
	then -- Pointer moved during a drag.
		setFromX(input.Position.X) -- Follow the pointer.
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject) -- Stop dragging on release anywhere.
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then -- Same inputs that started it.
		dragging = false -- Disable drag tracking.
	end
end)

highlight() -- Highlight the initial preset.
retarget() -- Compute the initial target (equal to the current look).

RunService.RenderStepped:Connect(function(dt: number) -- dt is the frame time in seconds.
	const camera: Camera? = Workspace.CurrentCamera -- May be nil for a moment during startup.
	if not camera then -- Nothing to follow yet.
		return -- Try again next frame.
	end
	const now: number = os.clock() -- Monotonic time for gusts and strike timing.
	const position: Vector3 = camera.CFrame.Position -- Where the viewer is.
	skyPart.CFrame = CFrame.new(position + Vector3.yAxis * CONFIG.EmitterHeight) -- Keep the sky emitter above the viewer.
	mistPart.CFrame = CFrame.new(position - Vector3.yAxis * 4) -- Keep the mist emitter around eye level.
	lerpLook(current, target, 1 - math.exp(-CONFIG.BlendRate * math.min(dt, 0.1)), current) -- Frame-rate independent easing; dt clamp avoids jumps after lag.
	applyLook(current, now) -- Show the blended state.
	if PRESETS[selected].storm and current.rain > 1.5 and now >= nextStrike then -- Only in a developed storm.
		nextStrike = now + rng:NextNumber(CONFIG.StrikeMin, CONFIG.StrikeMax) / strikeBoost -- Overdrive means more frequent strikes.
		task.spawn(strike, position) -- Spawn a thread because strike yields on task.wait.
	end
end)
