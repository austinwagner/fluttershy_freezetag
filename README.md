# Fluttershy's Freeze Tag
_A Team Fortress 2 game mode for [SourceMod](http://www.sourcemod.net/)._

## Licensing
This project is licensed under the Simplified BSD License. Details can be found in _LICENSE.txt_.

## Dependencies
Fluttershy's Freeze Tag requires:

* [Metamod:Source 1.8 or higher](http://www.sourcemm.net/)
* [SourceMod 1.4.2 or higher](http://www.sourcemod.net/downloads.php)
* [SDKHooks 2.1 or higher](http://forums.alliedmods.net/showthread.php?t=106748)
* [TF2Items 1.5.2 or higher](https://forums.alliedmods.net/showthread.php?t=115100)
* [TF2Items Give Weapon 3.10 or higher](http://forums.alliedmods.net/showthread.php?t=141962)

## Installation
First configure all of the dependenices in the order listed above according the their respective documentation.

Copy all of the folders in this project into your server's `tf/` directory.

This will copy the map, sounds, default configurations, plugin, and plugin source to your server.

**If you are already using TF2 Items Give Weapon and have created custom weapons, you must manually merge the tf2items.givecustom.txt configuration file. Be careful not to overwrite your existing configuration!**

Your server should automatically load the plugin when it starts. If the server is already running, run `sm plugins load freezetag` in the server console.

## Configuration
### Basic Configuration
There are two configuration files for this mod.

`cfg/sourcemod/freezetag.cfg` contains all of the configurable paramters for Freeze Tag. Descriptions of what each cvar does is listed in the config file. This file will be automatically create when the plugin is first executed.

`cfg/sourcemod/freezetagsounds.cfg` lists the sounds that the game should play for different events. They are chosen randomly to play from the list. To add a sound to the list, enter its path relative to `tf/sounds/`. These sounds are loaded when the plugin is loaded. If you change this file, you must reload the plugin by entering `sm plugins reload freezetag` into the console.

### Custom Weapons
This plugin uses the TF2Items Give Weapon plugin to create custom weapons for balance purposes. The configuration file for Give Weapon is located in `addons\sourcemod\configs\tf2items.givecustom.txt`. For more information on how to use this configuration file see the documentation for [Give Weapon](ttp://forums.alliedmods.net/showthread.php?t=141962).

This plugin requires custom weapons to be at specific ids according to the formula: `freezetag_custom_weapon_start - CLASS - SLOT`.

CLASS and SLOT are defined as follows:

    #define SLOT_PRIMARY 0
    #define SLOT_SECONDARY 1
    #define SLOT_MELEE 2
    
    #define SCOUT 0
    #define DEMOMAN 3
    #define PYRO 6
    #define SNIPER 9
    #define SPY 12
    #define HEAVY 15
    #define SOLDIER 18
    #define ENGINEER 21
    #define MEDIC 24

`freezetag_custom_weapon_start` defaults to -1000 and thus requires the range of items from -1000 to -1026 to be unused by other plugins. This should not be changed to a positive number as there is a chance it could overlap with an existing item.

If a custom item is not defined for a slot, the player will be given the default weapon for that slot. Note that Spy and Engineer are disallowed classes so creating custom weapons for these two classes is unnecessary. Also note that Medic is reserved for BLU and will only be given a melee weapon.

## Running the Game
The game will automatically run on any map prefixed with `freezetag_`. To have the plugin auto-enabled on other maps, modify `freezetag_maps`. This console variable takes a Perl Compatible Regular Expression. If any matches are found in the map name, the game is enabled. The game can also be started manually with the admin command or `freezetag_enabled 1`. The game will remain active until the end of the map.

To administrate the game, there are admin commands which can be run by anyone with generic admin rights.

* `ft_flutts <#userid|name>` will cause a player to be moved to the Fluttershy team. If this player is the only player remaining on RED that was not frozen, the round will end.
* `ft_unflutts <#userid|name>` will move a player from the Fluttershy team to RED. If this action causes no Fluttershys to remain, the round will end.
* `ft_freeze <#userid|name>` will freeze a player in place as if they were hit by a Fluttershy. If this player was the last unfrozen player on RED, the round will end.
* `ft_unfreeze <#userid|name>` will remove the freeze effect from a player.
* `ft_forgive <#userid|name>` will allow players who disconnected or moved to spectate while stunned to rejoin the game instead of being stuck in spectate until the next round.
* `ft_enable` will enable the game mode.
* `ft_disable` will disable the game mode, scramble the teams, and restart the round.

## Development

The source for this plugin is located in `addons/sourcemod/scripting/freezetag.sp`. To compile the code, you must have all of the dependencies installed. The web compiler that SourceMod provides cannot link to these dependencies. You need to use the compiler executable included with SourceMod.

The source file in the master branch will always match the compiled plugin. Development versions of the source code can be found in the delvelopment branch. The compiled plugin in the development branch will be the last release version and thus will not match the source code.

Maps must be custom made to work with this plugin. The map should contain a team_control_point_master and a team_round_timer. There should be no additional objectives on the map. This causes the game to only show a round timer on the HUD. Additional considerations should be made when adapting maps to remove resupply cabinets and one-way doors such as the spawn room doors.