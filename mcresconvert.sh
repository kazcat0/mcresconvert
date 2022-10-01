#!/bin/bash

# enable this to see which line cause warnings
# set -o xtrace

ZENITY="zenity --width 800 --title mcresconvert"

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
	echo "Usage: $(basename $0) [OPTIONS]"
	echo "   [OPTIONS] can be:"
	echo "   - <file>    - a zip filename to convert"
	echo "   - all       - attempts to convert all installed resource packs"
	echo "   - default   - attempts to convert the default resource pack"
	exit 1
fi

for required in unzip convert composite; do
	type $required > /dev/null
	if [ $? -ne 0 ]; then
		echo "Unable to find \"$required\" program, exiting"
		exit 1
	fi
done

type zenity > /dev/null
if [ $? -ne 0 ]; then
	echo "WARNING: Zenity not found, attempting to continue without gui support"
	NOGUI=yes
fi

convert_alphatex() {
	if [ -f _n/$2 ]; then
		g="_n/$2"
		if [ -f "$g.mcmeta" ]; then
			if grep -q "animation" "$g.mcmeta"; then
				# FIXME: need a list of not animated textures
				if echo "$5" | grep -q "grass"; then
					w=`file $g |sed 's/.*, \([0-9]*\) x \([0-9]*\).*/\1/'`
					convert "$g" -crop ${w}x${w}+0+0 -depth 8 _n/_g.png
					g="_n/_g.png"
				fi
			fi
		fi
		convert $1 -crop 1x1+$3 -depth 8 -resize ${4}x${4} _n/_c.png
		composite -compose Multiply _n/_c.png $g _n/_i.png
		composite -compose Dst_In $g _n/_i.png -alpha Set $5
		echo -e "." >> _n/_tot
		echo -e "." >> _n/_counter
	fi
}

copy_or_crop_from_anim() {
	IN=$1
	OUT=$2

	crop="0"
	if [ -f "$IN.mcmeta" ]; then
		if grep -q "animation" "$IN.mcmeta"; then
			# item are never animated in minetest
			if echo $IN | grep -q "/item/"; then
				crop="1"
			fi
			# in minetest block textures are called *_animated.png" if they are
			if ! echo $OUT | grep -q "_animated.png"; then
				crop="1"
			fi
		fi
	fi

	if [ "$crop" == "1" ]; then
		convert "$IN" -crop ${PXSIZE}x${PXSIZE}+0+0 -depth 8 "$OUT"
	else
		cp "$IN" "$OUT"
	fi
}

compose_door() {
	l=$1
	u=$2
	r=$3

	if [ -f $l -a -f $u ]; then
		# Cut out first frame if animated texture
		if [ -f $l.mcmeta ]; then
			w=`file $l |sed 's/.*, \([0-9]*\) x.*/\1/'`
			convert $l -background none -crop ${w}x${w}+0+0 _n/_cl.png
			l=_n/_cl.png
		fi
		if [ -f $u.mcmeta ]; then
			w=`file $u |sed 's/.*, \([0-9]*\) x.*/\1/'`
			convert $u -background none -crop ${w}x${w}+0+0 _n/_cu.png
			u=_n/_cu.png
		fi
		convert -background none $u -resize ${PXSIZE}x${PXSIZE} _n/_u.png
		convert -background none $l -resize ${PXSIZE}x${PXSIZE} _n/_l.png
		convert -background none _n/_u.png -flop _n/_fu.png
		convert -background none _n/_l.png -flop _n/_fl.png
		montage -background none _n/_fu.png _n/_u.png _n/_fl.png _n/_l.png -geometry +0+0 _n/_d.png
		convert _n/_d.png -background none -extent $(( (PXSIZE * 2) + (3 * (PXSIZE / 8) ) ))x$((PXSIZE * 2)) _n/_d2.png
		convert _n/_d2.png \
			\( -clone 0 -crop $((PXSIZE/8))x$((PXSIZE*2))+$((PXSIZE-1))+0 \) -gravity NorthWest -geometry +$((PXSIZE*2))+0 -composite \
			\( -clone 0 -crop $((PXSIZE/16))x$((PXSIZE*2))+0+0 \) -gravity NorthWest -geometry +$((PXSIZE*2+(PXSIZE/8)))+0 -composite \
			\( -clone 0 -crop $((PXSIZE/16))x$((PXSIZE*2))+$((PXSIZE*2-1))+0 \) -gravity NorthWest -geometry +$((PXSIZE*2+(3*(PXSIZE/16))))+0 -composite \
			\( -clone 0 -crop $((PXSIZE/16))x$((PXSIZE*2))+0+0 \) -gravity NorthWest -geometry +$((PXSIZE*2+(4*(PXSIZE/16))))+0 -composite \
			\( -clone 0 -crop $((PXSIZE/16))x$((PXSIZE*2))+$((PXSIZE*2-1))+0 \) -gravity NorthWest -geometry +$((PXSIZE*2+(5*(PXSIZE/16))))+0 -composite \
			$r
		return 0
	fi
	return 1
}

make_fence() {
	def=$1
	plank=$2
	out=$3
	if [ ! -f $def -a -f $plank ]; then
		w=`file $plank |sed 's/.*, \([0-9]*\) x.*/\1/'`
		if [ $w -eq $((PXSIZE/4)) ]; then
			convert $plank \( -clone 0 -rotate 90 -gravity center \) -composite $out
		else
			convert $plank \( -clone 0 -crop $((PXSIZE))x$((PXSIZE/4))+0+$(((PXSIZE/8)*3)) -rotate 90 -gravity center \) -composite $out
		fi
	elif [ -f $def ]; then
		cp $def $out
	fi
}

make_grass() {
	i=$1
	cmap=$2
	def=$3
	out=$4
	seg=$5
	if [ -f $i ]; then
		convert_alphatex $cmap $i 70+120 ${PXSIZE} $out
	else
		convert $def -page +0+$(((PXSIZE/8) * seg)) -background none -flatten $out
	fi
}

convert_file() {
	n=`basename "$@" .zip | tr -d ' \t."()[]' | tr -d "'"`
	echo "Found: $n"
	echo "   - File: `basename "$@"`"
	(
		texture_dir=~/.var/app/net.minetest.Minetest/.minetest/textures
		if [ ! -d $texture_dir ]; then
		  if [ -n "$NOGUI" ]; then
				echo "Creating texture directory under: \"$texture_dir\"."
			else
				$ZENITY --info --text="Creating texture directory under: \"$texture_dir\"." 2> /dev/null ;
			fi
			mkdir -p $texture_dir
		fi
		if ! mkdir $texture_dir/$n > /dev/null 2>&1 ; then
			if [ -n "$NOGUI" ]; then
				echo "A texture pack with name \"$n\" already exists, remove it before trying again."
				exit 1
			else
				if ! $ZENITY --question --text="A texture pack folder with name \"$n\" already exists, overwrite?" --default-cancel 2> /dev/null ; then
					exit 1
				fi
			fi
			rm -rf $texture_dir/$n
			mkdir $texture_dir/$n
		fi
		mkdir $texture_dir/$n/_z
		unzip -qq "$@" -d $texture_dir/$n/_z || exit 1
		cd $texture_dir/$n/_z
		# what a bunch of nonsense
		chmod -R +w *
		rm -rf __MACOSX
		assets_dir=`find * -name 'assets' -type 'd'`
		if [ -z "$assets_dir" ]; then
			echo "No 'assets' found in $@"
			exit 1
		fi
		if [ ! -d "$assets_dir"/minecraft/textures ]; then
			echo "No directory \"$assets_dir/minecraft/textures\" found in $@"
			exit 1
		fi
		# beware of zip files with a random extra toplevel folder.
		ln -sf _z/"$assets_dir"/minecraft/textures ../_n || exit 1
		cd ..

		# try and determine px size
		if [ -f "_n/block/cobblestone.png" ]; then
			PXSIZE=`file _n/block/cobblestone.png |sed 's/.*, \([0-9]*\) x.*/\1/'`
		fi

		( cat <<RENAMES
item/apple.png default_apple.png
item/writable_book.png default_book.png
item/written_book.png default_book_written.png
block/bookshelf.png default_bookshelf.png
item/bread.png farming_bread.png
item/bucket.png bucket.png
item/lava_bucket.png bucket_lava.png
item/water_bucket.png bucket_water.png
item/water_bucket.png bucket_river_water.png
item/brick.png default_clay_brick.png
block/bricks.png default_brick.png
item/clay_ball.png default_clay_lump.png
block/clay.png default_clay.png
item/coal.png default_coal_lump.png
block/coal_block.png default_coal_block.png
block/coal_ore.png default_mineral_coal.png
block/cobblestone.png default_cobble.png
block/mossy_cobblestone.png default_mossycobble.png
block/dead_bush.png default_dry_shrub.png
item/diamond.png default_diamond.png
item/diamond_axe.png default_tool_diamondaxe.png
block/diamond_block.png default_diamond_block.png
item/diamond_hoe.png farming_tool_diamondhoe.png
block/diamond_ore.png default_mineral_diamond.png
item/diamond_pickaxe.png default_tool_diamondpick.png
item/diamond_shovel.png default_tool_diamondshovel.png
item/diamond_sword.png default_tool_diamondsword.png
block/dirt.png default_dirt.png
item/oak_door.png doors_item_wood.png
item/iron_door.png doors_item_steel.png
item/black_dye.png dye_black.png
item/blue_dye.png dye_blue.png
item/brown_dye.png dye_brown.png
item/cyan_dye.png dye_cyan.png
item/green_dye.png dye_dark_green.png
item/lime_dye.png dye_green.png
item/gray_dye.png dye_dark_grey.png
item/magenta_dye.png dye_magenta.png
item/orange_dye.png dye_orange.png
item/pink_dye.png dye_pink.png
item/purple_dye.png dye_violet.png
item/red_dye.png dye_red.png
item/light_gray_dye.png dye_grey.png
item/white_dye.png dye_white.png
item/yellow_dye.png dye_yellow.png
block/farmland.png farming_soil.png
block/farmland_moist.png farming_soil_wet.png
block/fire_0.png fire_basic_flame_animated.png
item/flint.png default_flint.png
block/allium.png flowers_viola.png
block/blue_orchid.png flowers_geranium.png
block/dandelion.png flowers_dandelion_yellow.png
block/oxeye_daisy.png flowers_dandelion_white.png
block/red_tulip.png flowers_rose.png
block/orange_tulip.png flowers_tulip.png
block/furnace_front.png default_furnace_front.png
block/furnace_front_on.png default_furnace_front_active.png
block/furnace_side.png default_furnace_side.png
block/furnace_top.png default_furnace_bottom.png
block/furnace_top.png default_furnace_top.png
block/glass.png default_glass.png
block/gray_stained_glass.png default_obsidian_glass.png
block/gold_block.png default_gold_block.png
item/gold_ingot.png default_gold_ingot.png
item/gold_nugget.png default_gold_lump.png
block/gold_ore.png default_mineral_gold.png
block/grass_block_side.png default_grass_side.png
block/grass_block_snow.png default_snow_side.png
block/gravel.png default_gravel.png
block/hay_block_side.png farming_straw.png
block/ice.png default_ice.png
block/iron_bars.png xpanes_bar.png
item/iron_axe.png default_tool_steelaxe.png
item/iron_hoe.png farming_tool_steelhoe.png
item/iron_pickaxe.png default_tool_steelpick.png
item/iron_shovel.png default_tool_steelshovel.png
item/iron_sword.png default_tool_steelsword.png
block/iron_block.png default_steel_block.png
item/iron_ingot.png default_steel_ingot.png
block/iron_ore.png default_mineral_iron.png
block/iron_trapdoor.png doors_trapdoor_steel.png
block/iron_trapdoor.png doors_trapdoor_steel_side.png
block/ladder.png default_ladder_wood.png
block/lava_flow.png default_lava_flowing_animated.png
block/lava_still.png default_lava_source_animated.png
block/oak_log.png default_tree.png
block/oak_log_top.png default_tree_top.png
block/acacia_log.png default_acacia_tree.png
block/acacia_log_top.png default_acacia_tree_top.png
block/birch_log.png default_aspen_tree.png
block/birch_log_top.png default_aspen_tree_top.png
block/jungle_log.png default_jungletree.png
block/jungle_log_top.png default_jungletree_top.png
block/spruce_log.png default_pine_tree.png
block/spruce_log_top.png default_pine_tree_top.png
block/brown_mushroom.png flowers_mushroom_brown.png
block/red_mushroom.png flowers_mushroom_red.png
block/obsidian.png default_obsidian.png
item/paper.png default_paper.png
block/acacia_planks.png default_acacia_wood.png
block/birch_planks.png default_aspen_wood.png
block/jungle_planks.png default_junglewood.png
block/oak_planks.png default_wood.png
block/spruce_planks.png default_pine_wood.png
block/rail.png default_rail.png
block/rail_corner.png default_rail_curved.png
block/red_sand.png default_desert_sand.png
block/red_sandstone.png default_desert_stone.png
block/chiseled_red_sandstone.png default_desert_stone_brick.png
block/cut_red_sandstone.png default_desert_stone_block.png
block/sugar_cane.png default_papyrus.png
block/sand.png default_sand.png
block/sandstone.png default_sandstone.png
block/chiseled_sandstone.png default_sandstone_brick.png
block/cut_sandstone.png default_sandstone_block.png
block/birch_sapling.png default_aspen_sapling.png
block/jungle_sapling.png default_junglesapling.png
block/spruce_sapling.png default_pine_sapling.png
block/oak_sapling.png default_sapling.png
block/acacia_sapling.png default_acacia_sapling.png
item/wheat_seeds.png farming_wheat_seed.png
item/oak_sign.png default_sign_wood.png
item/oak_sign.png default_sign_wall_wood.png
item/snowball.png default_snowball.png
block/snow.png default_snow.png
item/stick.png default_stick.png
item/string.png farming_string.png
item/stone_axe.png default_tool_stoneaxe.png
item/stone_hoe.png farming_tool_stonehoe.png
item/stone_pickaxe.png default_tool_stonepick.png
item/stone_shovel.png default_tool_stoneshovel.png
item/stone_sword.png default_tool_stonesword.png
block/stone.png default_stone.png
block/stone_bricks.png default_stone_brick.png
block/smooth_stone.png default_stone_block.png
item/sugar.png farming_flour.png
block/tnt_bottom.png tnt_bottom.png
block/tnt_side.png tnt_side.png
block/tnt_top.png tnt_top.png
block/tnt_top.png tnt_top_burning.png
block/tnt_top.png tnt_top_burning_animated.png
block/torch.png default_torch_animated.png
block/torch.png default_torch_on_floor_animated.png
block/oak_trapdoor.png doors_trapdoor.png
block/oak_trapdoor.png doors_trapdoor_side.png
item/wheat.png farming_wheat.png
block/wheat_stage0.png farming_wheat_1.png
block/wheat_stage1.png farming_wheat_2.png
block/wheat_stage2.png farming_wheat_3.png
block/wheat_stage3.png farming_wheat_4.png
block/wheat_stage4.png farming_wheat_5.png
block/wheat_stage5.png farming_wheat_6.png
block/wheat_stage6.png farming_wheat_7.png
block/wheat_stage7.png farming_wheat_8.png
item/wooden_axe.png default_tool_woodaxe.png
item/wooden_hoe.png farming_tool_woodhoe.png
item/wooden_pickaxe.png default_tool_woodpick.png
item/wooden_shovel.png default_tool_woodshovel.png
item/wooden_sword.png default_tool_woodsword.png
block/black_wool.png wool_black.png
block/blue_wool.png wool_blue.png
block/brown_wool.png wool_brown.png
block/cyan_wool.png wool_cyan.png
block/gray_wool.png wool_dark_grey.png
block/green_wool.png wool_dark_green.png
block/lime_wool.png wool_green.png
block/magenta_wool.png wool_magenta.png
block/orange_wool.png wool_orange.png
block/pink_wool.png wool_pink.png
block/purple_wool.png wool_violet.png
block/red_wool.png wool_red.png
block/light_gray_wool.png wool_grey.png
block/white_wool.png wool_white.png
block/yellow_wool.png wool_yellow.png
block/redstone_lamp_on.png default_meselamp.png
item/spyglass.png binoculars_binoculars.png
item/raw_copper.png default_copper_lump.png
item/raw_gold.png default_gold_lump.png
item/raw_iron.png default_iron_lump.png
item/paper.png default_paper.png
block/kelp_plant.png default_kelp.png
item/gunpowder.png tnt_gunpowder_inventory.png
item/glass_bottle.png vessels_glass_bottle.png
block/brain_coral.png default_coral_pink.png
block/tube_coral.png default_coral_cyan.png
block/horn_coral.png default_coral_green.png
block/horn_coral_block.png default_coral_brown.png
block/fire_coral_block.png default_coral_orange.png
block/dead_brain_coral_block.png default_coral_skeleton.png
RENAMES
) |		while read IN OUT FLAG; do
			echo -e "." >> _n/_tot
			if [ -f "_n/$IN" ]; then
				echo -e "." >> _n/_counter
				copy_or_crop_from_anim "_n/$IN" "$OUT"
			elif [ -f "_z/$IN" ]; then
				echo -e "." >> _n/_counter
				copy_or_crop_from_anim "_z/$IN" "$OUT"
			# uncomment below 2 lines to see if any textures were not found.
			else
				echo "+$IN $OUT $FLAG: Not Found"
			fi
		done

		# attempt to colorize grasses by color cradient
		echo -e ".." >> _n/_tot
		if [ -f "_n/colormap/grass.png" ]; then
			convert _n/colormap/grass.png -crop 1x1+70+120 -depth 8 -resize ${PXSIZE}x${PXSIZE} _n/_c.png
			composite -compose Multiply _n/_c.png _n/block/grass_block_top.png default_grass.png
			echo -e "." >> _n/_counter

#			# default_dry_grass_side.png needs to match top coloring, maybe greyscale default_dry_grass_side.png and colorize.
#			convert _n/colormap/grass.png -crop 1x1+16+240 -depth 8 -resize ${PXSIZE}x${PXSIZE} _n/_c.png
#			composite -compose Multiply _n/_c.png _n/block/grass_block_top.png default_dry_grass.png
#			echo -e "." >> _n/_counter

#			# block/tallgrass.png no longer exists and is now tall_grass_top.png, tall_grass_bottom.png. maybe repurpose jungle grass.
#			convert_alphatex _n/colormap/grass.png block/tallgrass.png 70+120 ${PXSIZE} default_grass_5.png
#			make_grass block/tallgrass1.png _n/colormap/grass.png default_grass_5.png default_grass_4.png 1
#			make_grass block/tallgrass2.png _n/colormap/grass.png default_grass_5.png default_grass_3.png 2
#			make_grass block/tallgrass3.png _n/colormap/grass.png default_grass_5.png default_grass_2.png 3
#			make_grass block/tallgrass4.png _n/colormap/grass.png default_grass_5.png default_grass_1.png 4
#			#FIXME tile this
#			convert_alphatex _n/colormap/grass.png block/grass_side_overlay.png 70+120 ${PXSIZE} default_grass_side.png

#			convert_alphatex _n/colormap/grass.png block/tallgrass.png 16+240 ${PXSIZE} default_dry_grass_5.png
#			make_grass block/tallgrass1.png _n/colormap/grass.png default_dry_grass_5.png default_dry_grass_4.png 1
#			make_grass block/tallgrass2.png _n/colormap/grass.png default_dry_grass_5.png default_dry_grass_3.png 2
#			make_grass block/tallgrass3.png _n/colormap/grass.png default_dry_grass_5.png default_dry_grass_2.png 3
#			make_grass block/tallgrass4.png _n/colormap/grass.png default_dry_grass_5.png default_dry_grass_1.png 4
#			#FIXME tile this
#			convert_alphatex _n/colormap/grass.png block/grass_side_overlay.png 16+240 ${PXSIZE} default_dry_grass_side.png

#			# sizes are no longer correct.
#			# jungle grass - compose from tall grass 2 parts
#			if [ -f _n/colormap/grass.png -a -f _n/block/tall_grass_bottom.png -a -f _n/block/tall_grass_top.png ]; then
#				convert_alphatex _n/colormap/grass.png block/tall_grass_bottom.png 16+32 ${PXSIZE} _n/_jgb.png
#				convert_alphatex _n/colormap/grass.png block/tall_grass_top.png 16+32 ${PXSIZE} _n/_jgt.png
#				montage -tile 1x2 -geometry +0+0 -background none _n/_jgt.png _n/_jgb.png default_junglegrass.png
#				convert default_junglegrass.png -background none -gravity South -extent $((PXSIZE*2))x$((PXSIZE*2)) default_junglegrass.png
#			fi
		fi

		# crack
		echo -e "." >> _n/_tot
		if [ -f "_n/block/destroy_stage_0.png" ]; then
			c=( _n/block/destroy_stage_*.png )
			montage -tile 1x${#c[@]} -geometry +0+0 -background none ${c[@]} _n/c.png
			convert _n/c.png -alpha on -background none -channel A -evaluate Min 50% crack_anylength.png
			echo -e "." >> _n/_counter
		fi

		# same for leaf colors
		if [ -f "_n/colormap/foliag.png" ]; then
			FOLIAG=_n/colormap/foliag.png
		elif [ -f "_n/colormap/foliage.png" ]; then
			FOLIAG=_n/colormap/foliage.png
		fi
		echo -e "." >> _n/_tot
		if [ -n "$FOLIAG" ]; then
			convert_alphatex $FOLIAG block/oak_leaves.png 70+120 ${PXSIZE} default_leaves.png
			convert_alphatex $FOLIAG block/acacia_leaves.png 16+240 ${PXSIZE} default_acacia_leaves.png
			convert_alphatex $FOLIAG block/spruce_leaves.png 226+240 ${PXSIZE} default_pine_needles.png
			convert_alphatex $FOLIAG block/birch_leaves.png 70+120 ${PXSIZE} default_aspen_leaves.png
			convert_alphatex $FOLIAG block/jungle_leaves.png 16+32 ${PXSIZE} default_jungleleaves.png
			convert_alphatex $FOLIAG block/lily_pad.png 16+32 ${PXSIZE} flowers_waterlily.png
			convert_alphatex $FOLIAG block/lily_pad.png 16+32 ${PXSIZE} flowers_waterlily_bottom.png
			echo -e "." >> _n/_counter
		fi

		# compose doors texture maps
		# TODO: minetest also has doors_door_{glass,obsidian}.png
		# TODO: minecraft also has: acacia, birch, dark_oak, jungle, spruce
		echo -e "." >> _n/_tot
		if compose_door _n/block/oak_door_bottom.png _n/block/oak_door_top.png doors_door_wood.png; then
			echo -e "." >> _n/_counter
		fi

		echo -e "." >> _n/_tot
		if compose_door _n/block/iron_door_bottom.png _n/block/iron_door_top.png doors_door_steel.png; then
			echo -e "." >> _n/_counter
		fi

		# fences - make alternative from planks
		# TODO: minecraft has: big_oak
		make_fence _n/block/fence_oak.png _n/block/oak_planks.png default_fence_wood.png
		make_fence _n/block/fence_acacia.png _n/block/acacia_planks.png default_fence_acacia_wood.png
		make_fence _n/block/fence_spruce.png _n/block/spruce_planks.png default_fence_pine_wood.png
		make_fence _n/block/fence_jungle.png _n/block/jungle_planks.png default_fence_junglewood.png
		make_fence _n/block/fence_birch.png _n/block/birch_planks.png default_fence_aspen_wood.png

		# chest textures
		echo -e "..." >> _n/_tot
		if [ -f _n/entity/chest/normal.png ]; then
			CHPX=$((PXSIZE / 16 * 14)) # chests in MC are 2/16 smaller!
			convert _n/entity/chest/normal.png \
				\( -clone 0 -crop $((CHPX))x$((CHPX))+$((CHPX))+0 \) -geometry +0+0 -composite -extent $((CHPX))x$((CHPX)) default_chest_top.png
			convert _n/entity/chest/normal.png \
				\( -clone 0 -crop $((CHPX))x$(((PXSIZE/16)*5))+$((CHPX))+$((CHPX)) \) -geometry +0+0 -composite \
				\( -clone 0 -crop $((CHPX))x$(((PXSIZE/16)*10))+$((CHPX))+$(( (2*CHPX)+((PXSIZE/16)*5) )) \) -geometry +0+$(((PXSIZE/16)*5)) -composite \
				-extent $((CHPX))x$((CHPX)) default_chest_front.png
			cp default_chest_front.png default_chest_lock.png
			convert _n/entity/chest/normal.png \
				\( -clone 0 -crop $((CHPX))x$(((PXSIZE/16)*5))+$((2*CHPX))+$((CHPX)) \) -geometry +0+0 -composite \
				\( -clone 0 -crop $((CHPX))x$(((PXSIZE/16)*10))+$((2*CHPX))+$(( (2*CHPX)+((PXSIZE/16)*5) )) \) -geometry +0+$(((PXSIZE/16)*5)) -composite \
				-extent $((CHPX))x$((CHPX)) default_chest_side.png
			echo -e "..." >> _n/_counter
		fi

		echo -e "." >> _n/_tot
		if [ -f _n/environment/sun.png ]; then
			convert _n/environment/sun.png -colorspace HSB -separate _n/_mask.png
			convert _n/environment/sun.png -fill '#a1a1a1' -draw 'color 0,0 reset' _n/_lighten.png
			convert _n/_lighten.png _n/environment/sun.png -compose Lighten_Intensity -composite -alpha Off _n/_mask-2.png -compose CopyOpacity -composite PNG32:sun.png
			convert sun.png -bordercolor none -border 1x1 -fuzz 0% -trim sun.png
			rm _n/_mask*
			echo -e "." >> _n/_counter
		fi
		echo -e "." >> _n/_tot
		if [ -f _n/environment/moon_phases.png ]; then
			S=`identify -format "%[fx:w/4]" _n/environment/moon_phases.png`
			convert _n/environment/moon_phases.png -colorspace HSB -separate _n/_mask.png
			convert _n/environment/moon_phases.png -alpha Off _n/_mask-2.png -compose CopyOpacity -composite PNG32:moon.png
			convert -background none moon.png -gravity NorthWest -extent ${S}x${S} moon.png
			convert moon.png -bordercolor none -border 1x1 -fuzz 0% -trim moon.png
			echo -e "." >> _n/_counter
		fi

		# inventory torch
		echo -e "." >> _n/_tot
		if [ -f _n/block/torch.png ]; then
			convert _n/block/torch.png -background none -gravity North -extent ${PXSIZE}x${PXSIZE} default_torch_on_floor.png
			echo -e "." >> _n/_counter
		fi

		# hotbar
		echo -e "." >> _n/_tot
		if [ -f _n/gui/widgets.png ]; then
			convert _n/gui/widgets.png -resize 256x256 -background none -gravity NorthWest -crop 24x24+0+22 gui_hotbar_selected.png
			convert _n/gui/widgets.png -resize 256x256 -background none -gravity NorthWest -extent 140x22 _n/a.png
			convert _n/gui/widgets.png -resize 256x256 -background none -gravity NorthWest -crop 22x22+160+0 +repage -extent 22x22 _n/b.png
			montage _n/a.png _n/b.png -tile 2x1 -background none -geometry +0+0 PNG32:gui_hotbar.png
			echo -e "." >> _n/_counter
		fi

		# health & breath
		echo -e "." >> _n/_tot
		if [ -f _n/gui/icons.png ]; then
			convert _n/gui/icons.png -resize 256x256 -background none -gravity NorthWest -crop 9x9+52+0 heart.png
			convert _n/gui/icons.png -resize 256x256 -background none -gravity NorthWest -crop 9x9+16+18 bubble.png
			echo -e "." >> _n/_counter
		fi

		# steve? ha! This assumes 64x32 dimensions, won't work well with 1.8 skins.
		echo -e "." >> _n/_tot
		if [ -f _n/entity/steve.png ]; then
			S=`identify -format "%[fx:w]" _n/entity/steve.png`
			convert _n/entity/steve.png -background none -gravity NorthWest \
			-extent $((S))x$((S/2)) character.png
			echo -e "." >> _n/_counter
		fi

		# attempt to make desert cobblestone
		echo -e "." >> _n/_tot
		if [ -f _n/block/cobblestone.png -a -f _n/block/red_sand.png ]; then
			convert _n/block/red_sand.png -resize 1x1 -resize ${PXSIZE}x${PXSIZE} _n/_c.png
			convert _n/block/cobblestone.png _n/_c.png -compose Overlay -composite default_desert_cobble.png
			echo -e "." >> _n/_counter
		fi

		# make copper and bronze from colorizing steel
		echo -e "...." >> _n/_tot
		if [ -f _n/item/iron_ingot.png ]; then
			#ffa05b
			convert -size ${PXSIZE}x${PXSIZE} xc:\#CA8654 _n/_c.png

			composite -compose Screen _n/_c.png _n/item/iron_ingot.png _n/_i.png
			composite -compose Dst_In _n/item/iron_ingot.png _n/_i.png -alpha Set default_copper_ingot.png

			convert _n/block/iron_block.png _n/_c.png -compose Overlay -composite default_copper_block.png

			#ffb07c
			convert -size ${PXSIZE}x${PXSIZE} xc:\#6F4C35 _n/_c.png

			composite -compose Screen _n/_c.png _n/item/iron_ingot.png _n/_i.png
			composite -compose Dst_In _n/item/iron_ingot.png _n/_i.png -alpha Set default_bronze_ingot.png

			convert _n/block/iron_block.png _n/_c.png -compose Overlay -composite default_bronze_block.png
			echo -e "...." >> _n/_counter
		fi

		# de-animate flint and steel
		echo -e "." >> _n/_tot
		if [ -f _n/item/flint_and_steel.png ]; then
			convert -background none -gravity North -extent ${PXSIZE}x${PXSIZE} _n/item/flint_and_steel.png fire_flint_steel.png
			echo -e "." >> _n/_counter
		fi

		# cactus needs manual cropping
		echo -e ".." >> _n/_tot
		if [ -f _n/block/cactus_top.png ]; then
			convert _n/block/cactus_top.png -crop +$((PXSIZE/16))+$((PXSIZE/16))x$(((PXSIZE/16)*14))x$(((PXSIZE/16)*14)) +repage -extent $(((PXSIZE/16)*14))x$(((PXSIZE/16)*14)) default_cactus_top.png
			convert _n/block/cactus_side.png -crop +$((PXSIZE/16))+$((PXSIZE/16))x$(((PXSIZE/16)*14))x$(((PXSIZE/16)*14)) +repage -extent $(((PXSIZE/16)*14))x$(((PXSIZE/16)*14)) default_cactus_side.png
			echo -e ".." >> _n/_counter
		fi

		# steel ladder
		echo -e "." >> _n/_tot
		if [ -f _n/block/ladder.png ]; then
			convert _n/block/ladder.png -channel RGBA -matte -colorspace gray default_ladder_steel.png
			echo -e "." >> _n/_counter
		fi

		# steel sign
		echo -e ".." >> _n/_tot
		if [ -f _n/item/oak_sign.png ]; then
			convert _n/item/oak_sign.png -channel RGBA -matte -colorspace gray default_sign_steel.png
			convert _n/item/oak_sign.png -channel RGBA -matte -colorspace gray default_sign_wall_steel.png
			echo -e ".." >> _n/_counter
		fi

#		# emerald -> mese
#		if [ -f _n/block/emerald_ore.png ]; then
#			compare _n/block/stone.png _n/block/emerald_ore.png -metric AE -fuzz 5% -compose Src -highlight-color White -lowlight-color none _n/m.png 2> /dev/null
#			composite -compose Dst_In -gravity center _n/m.png _n/block/emerald_ore.png -alpha Set _n/o.png
#			convert _n/o.png -modulate 100,100,80 default_mineral_mese.png
#			convert _n/block/emerald_block.png -modulate 100,100,80 default_mese_block.png
#			convert _n/item/emerald.png -modulate 100,100,80 default_mese_crystal.png
#		fi

		# logo
		echo -e ".." >> _n/_tot
		if [ -n "`find _z -name pack.png -type f`" ]; then
			# fix aspect ratio
			#convert "`find _z -name pack.png -type f | head -n 1`" -gravity North -resize 128x128 -background none -extent 160x148 screenshot.png
			cp "`find _z -name pack.png -type f | head -n 1`" screenshot.png
			echo -e ".." >> _n/_counter
		elif [ -f _n/block/grass_side.png -a -f _n/dirt.png ]; then
			# make something up
			montage -geometry +0+0 _n/block/grass_block_side.png _n/block/grass_block_side.png _n/block/grass_block_side.png _n/block/grass_block_side.png \
				_n/block/dirt.png _n/block/dirt.png _n/block/dirt.png _n/block/dirt.png \
				_n/block/dirt.png _n/block/dirt.png _n/block/dirt.png _n/block/dirt.png screenshot.png
		fi

		count=`cat _n/_counter | wc -c`
		tot=`cat _n/_tot | wc -c`
		echo "$n ${PXSIZE}px [$((100 * count / tot))%]" > description.txt
		echo "(Converted from $n with Minetest Texture and Resource Pack Converter)" >> description.txt
		echo "   - Conversion quality: $count / $tot"
		if [ -n "$PXSIZE" ]; then
			echo "   - Pixel size: ${PXSIZE}px"
		fi
		if [ -f _z/pack.txt ]; then
			echo "Original Description:" >> description.txt
			cat _z/pack.txt >> description.txt
		fi
		rm -rf _z _n
	)
}

if [ -n "$NOGUI" ]; then
	choice=$1
	if [ -z "$choice" ]; then
		choice=all
	elif [ "$choice" != all ] && [ "$choice" != default ]; then
		convert_file "$@"
		exit $?
	fi
else
	choice=`$ZENITY --list --title "Choose resource packs to convert" --column="Convert" \
	--text "Do you want to convert installed resource packs, or convert a single zip file?" \
	--column="Description" --height 400 \
	"all" "Find Minecraft resource packs installed in your minecraft folders and convert those automatically" \
	"default" "(Unworking) Convert the default resource pack" \
	"other" "Choose a file to convert manually" 2> /dev/null`
fi

if [ "$choice" == "all" ]; then
	echo "Automatically converting resourcepacks and texturepacks found..."

	echo "Scanning for texture/resourcepacks..."
	(
		find ~/.minecraft/texturepacks/ -name '*.zip'
		find ~/.minecraft/resourcepacks -name '*.zip'
	) | while read f; do
		convert_file "$f"
	done
elif [ "$choice" == "other" ]; then
	# assume file name to zip is passed
	convert_file "`$ZENITY --file-selection --file-filter="*.zip" 2> /dev/null`"
elif [ "$choice" == "default" ]; then
	if ! cp ~/.minecraft/versions/1.9/1.9.jar /tmp/mc-default-1.9.zip ; then
		exit 1
	fi
	convert_file /tmp/mc-default-1.9.zip
	rm /tmp/mc-default-1.9.zip
fi
