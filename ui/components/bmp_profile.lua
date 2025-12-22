-- BMP Profile UI component - displays in upper left corner
-- Independent UI module that doesn't modify existing UI elements

MP.BMP_PROFILE_UI = nil
MP.BMP_PROFILE_REF = {
	username = "",
	ranked_mmr = "",
	ranked_rank = "",
	ranked_mmr_change = "",
	smallworld_mmr = "",
	smallworld_rank = "",
	smallworld_mmr_change = "",
	vanilla_mmr = "",
	vanilla_rank = "",
	vanilla_mmr_change = "",
	is_connected = false,
}

local MMR_FIELDS = { "ranked_mmr", "smallworld_mmr", "vanilla_mmr" }
local MMR_CONFIGS = {
	{ "k_ranked", "ranked_mmr", "ranked_rank", "ranked_mmr_change" },
	{ "k_smallworld", "smallworld_mmr", "smallworld_rank", "smallworld_mmr_change" },
	{ "k_vanilla", "vanilla_mmr", "vanilla_rank", "vanilla_mmr_change" },
}

local function create_text_node(config)
	return { n = G.UIT.T, config = config }
end
local function create_row_node(config, nodes)
	return { n = G.UIT.R, config = config, nodes = nodes }
end
local function create_col_node(config, nodes)
	return { n = G.UIT.C, config = config, nodes = nodes }
end

local function update_profile_ref()
	local is_connected = MP.DISCORD_AUTH.is_connected()
	local profile_data = MP.DISCORD_AUTH.get_profile_data()
	MP.BMP_PROFILE_REF.is_connected = is_connected
	local default_value = is_connected and localize("k_profile_not_available") or ""

	if is_connected and profile_data then
		MP.BMP_PROFILE_REF.username = profile_data.username or localize("k_profile_username")
		for _, field in ipairs(MMR_FIELDS) do
			MP.BMP_PROFILE_REF[field] = profile_data[field] and tostring(profile_data[field]) or default_value
		end
		-- Update rank fields
		for _, config in ipairs(MMR_CONFIGS) do
			local rank_key = config[3]
			local mmr_change_key = config[4]
			MP.BMP_PROFILE_REF[rank_key] = profile_data[rank_key] and ("#" .. tostring(profile_data[rank_key]))
				or default_value
			if profile_data[mmr_change_key] then
				local change = tonumber(profile_data[mmr_change_key])
				if change and change > 0 then
					MP.BMP_PROFILE_REF[mmr_change_key] = "+" .. tostring(math.floor(change))
				elseif change and change < 0 then
					MP.BMP_PROFILE_REF[mmr_change_key] = "-" .. tostring(math.floor(math.abs(change)))
				else
					MP.BMP_PROFILE_REF[mmr_change_key] = "—"
				end
			else
				MP.BMP_PROFILE_REF[mmr_change_key] = default_value
			end
		end
	else
		MP.BMP_PROFILE_REF.username = is_connected and localize("k_profile_username") or ""
		for _, field in ipairs(MMR_FIELDS) do
			MP.BMP_PROFILE_REF[field] = default_value
		end
		-- Clear rank and mmr_change fields
		for _, config in ipairs(MMR_CONFIGS) do
			MP.BMP_PROFILE_REF[config[3]] = default_value
			MP.BMP_PROFILE_REF[config[4]] = default_value
		end
	end
end

local function get_mmr_change_colour(profile_data, mmr_change_key)
	if not profile_data or not profile_data[mmr_change_key] then return G.C.UI.TEXT_LIGHT end
	local change = tonumber(profile_data[mmr_change_key])
	if not change then return G.C.UI.TEXT_LIGHT end
	if change > 0 then
		return G.C.GREEN
	elseif change < 0 then
		return G.C.RED
	else
		return G.C.UI.TEXT_LIGHT
	end
end

local function create_gain_loss_col(queue_mmr_change_key, profile_data)
	local bg_colour = get_mmr_change_colour(profile_data, queue_mmr_change_key)

	return create_col_node({
		align = "cm",
		padding = 0.1,
		minw = 0.5,
		r = 0.1,
		colour = bg_colour,
	}, {
		create_text_node({
			ref_table = MP.BMP_PROFILE_REF,
			ref_value = queue_mmr_change_key,
			scale = 0.35,
			colour = G.C.WHITE,
			shadow = true,
		}),
	})
end

local function create_rank_row(queue_rank_key)
	return create_row_node({
		align = "cm",
		padding = 0.15,
		minw = 1.45,
		r = 0.1,
		hover = true,
		colour = G.C.BLACK,
	}, {
		create_text_node({
			ref_table = MP.BMP_PROFILE_REF,
			ref_value = queue_rank_key,
			scale = 0.6,
			colour = G.C.UI.TEXT_LIGHT,
			shadow = true,
		}),
	})
end

local function create_mmr_value_row(queue_mmr_key, queue_mmr_change_key, profile_data)
	return create_row_node({
		align = "tm",
		padding = 0.15,
		minw = 1.45,
		r = 0.1,
		hover = true,
		colour = G.C.BLACK,
	}, {
		create_text_node({
			ref_table = MP.BMP_PROFILE_REF,
			ref_value = queue_mmr_key,
			scale = 0.6,
			colour = G.C.UI.TEXT_LIGHT,
			shadow = true,
		}),
		create_gain_loss_col(queue_mmr_change_key, profile_data),
	})
end

local function create_username_box()
	return create_col_node({ align = "cm", padding = 0.15, emboss = 0.1, r = 0.2, colour = G.C.L_BLACK, minw = 2.6 }, {
		create_text_node({
			ref_table = MP.BMP_PROFILE_REF,
			ref_value = "username",
			scale = 0.6,
			colour = G.C.UI.TEXT_LIGHT,
			shadow = true,
		}),
	})
end

local function create_mmr_box(queue_name_key, queue_mmr_key, queue_rank_key, queue_mmr_change_key)
	local profile_data = MP.DISCORD_AUTH.get_profile_data()

	return create_col_node({ align = "cm", padding = 0.1, emboss = 0.1, r = 0.2, colour = G.C.L_BLACK, minw = 2.6 }, {
		create_row_node({ align = "cm" }, {
			create_text_node({
				text = localize(queue_name_key),
				scale = 0.35,
				colour = G.C.UI.TEXT_LIGHT,
				shadow = true,
			}),
		}),
		create_mmr_value_row(queue_mmr_key, queue_mmr_change_key, profile_data),
		create_rank_row(queue_rank_key),
	})
end

local function create_settings_button()
	return create_col_node({
		align = "cm",
		minw = 0.6,
		minh = 0.6,
		r = 0.1,
		hover = true,
		colour = G.C.GREY,
		button = "bmp_open_settings",
		shadow = true,
		shadow_height = 0.5,
	}, {
		{ n = G.UIT.O, config = { object = Sprite(0, 0, 0.3, 0.3, G.ASSET_ATLAS["mod_tags"], { x = 2, y = 0 }) } },
	})
end

local function create_disconnect_button()
	return create_col_node({
		align = "cm",
		minw = 0.6,
		minh = 0.6,
		r = 0.1,
		hover = true,
		colour = G.C.RED,
		button = "disconnect_discord",
		shadow = true,
		shadow_height = 0.5,
		on_demand_tooltip = {
			text = { localize("b_disconnect_discord") },
		},
	}, {
		{ n = G.UIT.O, config = { object = Sprite(0, 0, 0.3, 0.3, G.ASSET_ATLAS["icons"], { x = 0, y = 0 }) } },
	})
end

local function create_connect_button_row()
	return create_row_node({ align = "cm", padding = 0.2 }, {
		UIBox_button({
			id = "bmp_discord_button",
			label = { localize("b_connect_discord") },
			colour = G.C.BLUE,
			button = "connect_discord",
		}),
	})
end

local function create_profile_box()
	local nodes = {}

	if MP.BMP_PROFILE_REF.is_connected then
		table.insert(
			nodes,
			create_row_node({ align = "cl" }, {
				create_username_box(),
				create_col_node({ align = "cm", minw = 3 }, {
					create_row_node({ align = "cr", padding = 0.1 }, {
						create_settings_button(),
						create_disconnect_button(),
					}),
				}),
			})
		)
	else
		table.insert(nodes, { n = G.UIT.B, config = { w = 0.1, h = 0.1 } })
		table.insert(nodes, create_connect_button_row())
		table.insert(
			nodes,
			create_row_node({ align = "cl", padding = 0.1 }, {
				create_username_box(),
			})
		)
	end

	for _, config in ipairs(MMR_CONFIGS) do
		table.insert(
			nodes,
			create_row_node({ align = "cl" }, {
				create_mmr_box(config[1], config[2], config[3], config[4]),
			})
		)
	end

	return UIBox({
		definition = {
			n = G.UIT.ROOT,
			config = { align = "cm", colour = G.C.CLEAR },
			nodes = {
				create_col_node({
					align = "cm",
					padding = 0.1,
					r = 0.1,
					colour = G.C.CLEAR,
					outline_colour = G.C.BLACK,
					minw = 1,
					minh = 1,
				}, nodes),
			},
		},
		config = { align = "tli", bond = "Weak", offset = { x = -0.5, y = -0.5 }, major = G.ROOM_ATTACH },
	})
end

function G.FUNCS.bmp_open_settings(e)
	G.SETTINGS.paused = true
	if G.FUNCS["openModUI_Multiplayer"] then G.FUNCS["openModUI_Multiplayer"]({ config = { page = "config" } }) end
end

function MP.UI.Create_BMP_Profile()
	if MP.BMP_PROFILE_UI then
		MP.BMP_PROFILE_UI:remove()
		MP.BMP_PROFILE_UI = nil
	end
	if not G.MAIN_MENU_UI or G.OVERLAY_MENU then return end

	update_profile_ref()
	MP.BMP_PROFILE_UI = create_profile_box()
end

function MP.UI.Update_BMP_Profile()
	if not G.MAIN_MENU_UI or G.OVERLAY_MENU then return end
	if not MP.BMP_PROFILE_UI then
		MP.UI.Create_BMP_Profile()
		return
	end

	local was_connected = MP.BMP_PROFILE_REF.is_connected
	local had_profile_data = MP.DISCORD_AUTH.get_profile_data() ~= nil
	update_profile_ref()
	local has_profile_data = MP.DISCORD_AUTH.get_profile_data() ~= nil

	-- Recreate UI if connection state changed or profile data was just loaded
	if was_connected ~= MP.BMP_PROFILE_REF.is_connected or (not had_profile_data and has_profile_data) then
		MP.UI.Create_BMP_Profile()
	elseif MP.BMP_PROFILE_UI and MP.BMP_PROFILE_UI.parent then
		MP.BMP_PROFILE_UI.parent.UIBox:recalculate()
	end
end
