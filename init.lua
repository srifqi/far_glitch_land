-- Far Glitch Land
-- MIT License
-- To change parameters, use the Settings menu.

----------------
-- Parameters --
----------------

local thickness = 80
local is_clean_gen = true
local height_min = -31000
local height_max = 31000

-------------------
-- Read settings --
-------------------

local thickness_setting = minetest.settings:get("fgl_thickness")
if thickness_setting ~= nil then
	thickness = tonumber(thickness_setting)
end

if thickness <= 0 then
	return -- Do nothing
end

is_clean_gen = minetest.settings:get_bool("fgl_clean_generation", false)

local height_min_setting = minetest.settings:get("fgl_min_height")
if height_min_setting ~= nil then
	height_min = tonumber(height_min_setting)
end

local height_max_setting = minetest.settings:get("fgl_max_height")
if height_max_setting ~= nil then
	height_max = tonumber(height_max_setting)
end

if height_max < height_min then
	return -- Do nothing
end

-----------------------
-- Initial variables --
-----------------------

local edge_min, edge_max = minetest.get_mapgen_edges()
local chunksize = tonumber(minetest.get_mapgen_setting("chunksize"))
local sidelen = chunksize * 16 -- 16*16*16 nodes per chunk
local sidelen_v = {x = sidelen, y = sidelen, z = sidelen}

local water_level = tonumber(minetest.get_mapgen_setting("water_level"))

-- Land generation limits

thickness = thickness - 1 -- Offset by 1
local e_xmin = edge_min.x + thickness
local e_xmax = edge_max.x - thickness
local e_zmin = edge_min.z + thickness
local e_zmax = edge_max.z - thickness

local g_ymin = math.max(edge_min.y, height_min)
local g_ymax = math.min(edge_max.y, height_max)

-- Main noise

local spread_base = 3
local spread_mult_y = 2
local spread_mult_side = 32

local np_shape = {
	offset = 0,
	scale = 1,
	spread = {x = spread_base, y = spread_base, z = spread_base},
	seed = 40,
	octaves = 1,
	persistence = 0.5,
	lacunarity = 2.0,
}

--------------------
-- Map generation --
--------------------

minetest.register_on_generated(function(minp, maxp, seed)
	if minp.y > g_ymax and maxp.y < g_ymin and
			minp.x > e_xmin and maxp.x < e_xmax and
			minp.z > e_zmin and maxp.z < e_zmax then
		return -- Do nothing
	end

	minetest.log("info", "far_glitch_land is generating | " ..
			"minp: (" .. minp.x .. ", " .. minp.y .. ", " .. minp.z .. ") | " ..
			"maxp: (" .. maxp.x .. ", " .. maxp.y .. ", " .. maxp.z .. ")")

	-- Initial variables

	local cid = minetest.get_content_id

	local air_block = cid("air")
	local stone_block = cid("mapgen_stone")
	local water_block = cid("mapgen_water_source")

	local pr = PseudoRandom(seed)

	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()

	-- Noises

	local p3d_shape_x = nil
	local p3d_shape_z = nil
	local p3d_shape_xz = nil
	if minp.x <= e_xmin or maxp.x >= e_xmax then
		np_shape.spread.x = spread_base * spread_mult_side
		np_shape.spread.y = spread_base * spread_mult_y
		np_shape.spread.z = spread_base
		local pm_shape_x = minetest.get_perlin_map(np_shape, sidelen_v)
		p3d_shape_x = pm_shape_x:get_3d_map_flat(minp)
	end
	if minp.z <= e_zmin or maxp.z >= e_zmax then
		np_shape.spread.x = spread_base
		np_shape.spread.y = spread_base * spread_mult_y
		np_shape.spread.z = spread_base * spread_mult_side
		local pm_shape_z = minetest.get_perlin_map(np_shape, sidelen_v)
		p3d_shape_z = pm_shape_z:get_3d_map_flat(minp)
	end
	if (minp.x <= e_xmin or maxp.x >= e_xmax) and
			(minp.z <= e_zmin or maxp.z >= e_zmax) then
		np_shape.spread.x = spread_base * spread_mult_side
		np_shape.spread.y = spread_base
		np_shape.spread.z = spread_base * spread_mult_side
		local pm_shape_xz = minetest.get_perlin_map(np_shape, sidelen_v)
		p3d_shape_xz = pm_shape_xz:get_3d_map_flat(minp)
	end

	-- Main generation

	local ni = 1
	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			ni = ni + sidelen * (sidelen - 1)
			if x <= e_xmin or x >= e_xmax or
					z <= e_zmin or z >= e_zmax then

				-- Read biome data

				local biome_id = minetest.get_biome_data(vector.new(x, maxp.y, z))["biome"]
				local biome_name = minetest.get_biome_name(biome_id)

				local biome_data = minetest.registered_biomes[biome_name]
				if biome_data == nil then
					biome_data = {}
				end

				local block_top = stone_block
				if biome_data["node_top"] ~= nil then
					block_top = cid(biome_data["node_top"])
				end
				local depth_top = 0
				if biome_data["depth_top"] ~= nil then
					depth_top = biome_data["depth_top"]
				end

				local block_filler = stone_block
				if biome_data["node_filler"] ~= nil then
					block_filler = cid(biome_data["node_filler"])
				end
				local depth_filler = 0
				if biome_data["depth_filler"] ~= nil then
					depth_filler = biome_data["depth_filler"]
					depth_filler = pr:next(0, depth_filler)
				end

				local block_riverbed = stone_block
				if biome_data["node_riverbed"] ~= nil then
					block_riverbed = cid(biome_data["node_riverbed"])
				end
				local depth_riverbed = 0
				if biome_data["depth_riverbed"] ~= nil then
					depth_riverbed = biome_data["depth_riverbed"]
				end

				local block_stone = stone_block
				if biome_data["node_stone"] ~= nil then
					block_stone = cid(biome_data["node_stone"])
				end

				-- Generation is run from top to bottom to make it easier when
				-- placing land cover (block_top), below it (block_filler),
				-- and stone (block_stone).

				local last_air_block = maxp.y + sidelen * sidelen
				local last_water_block = maxp.y + sidelen * sidelen

				for y = maxp.y, minp.y, -1 do
					local vi = area:index(x, y, z)
					if y >= g_ymin and y <= g_ymax then
						if is_clean_gen or
								data[vi] == air_block or
								data[vi] == stone_block or
								data[vi] == water_block then
							local value = 0
							if (x <= e_xmin or x >= e_xmax) and
									(z <= e_zmin or z >= e_zmax) then
								value = p3d_shape_xz[ni] + 0.25 -- More air
							elseif x <= e_xmin or x >= e_xmax then
								value = p3d_shape_x[ni]
							elseif z <= e_zmin or z >= e_zmax then
								value = p3d_shape_z[ni]
							end

							if value <= 0 then -- Is solid
								local dist_to_air = last_air_block - y
								local dist_to_water = last_water_block - y
								local depth_both = depth_filler + depth_top

								if dist_to_air > depth_top and dist_to_air <= depth_both or
										dist_to_water > depth_riverbed and dist_to_water <= depth_both then
									data[vi] = block_filler
								elseif dist_to_air > 0 and dist_to_air <= depth_top then
									data[vi] = block_top
								elseif dist_to_water > 0 and dist_to_water <= depth_riverbed then
									data[vi] = block_riverbed
								else
									data[vi] = block_stone
								end
							elseif is_clean_gen then
								if y > water_level then
									data[vi] = air_block
								else
									data[vi] = water_block
								end
							end
						end
					end

					if data[vi] == air_block then
						last_air_block = y
					elseif data[vi] == water_block then
						last_water_block = y
					end

					ni = ni - sidelen
				end -- For each y
			else
				ni = ni - sidelen * sidelen
			end
			ni = ni + sidelen + 1
		end -- For each x
		ni = ni + sidelen * (sidelen - 1)
	end -- For each z

	-- Decorations and ores

	vm:set_data(data)

	minetest.generate_decorations(vm)
	minetest.generate_ores(vm)

	vm:calc_lighting()
	vm:write_to_map()
	vm:update_liquids()
end)
