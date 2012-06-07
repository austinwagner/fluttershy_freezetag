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

Your server should automatically load the plugin when it starts. If the server is already running, run `sm plugins load freezetag` in the server console.

## Configuration
There are three configuration files for this mod.

`cfg/freezetag_degrootkeep_v2.cfg` is the configuration file that is run when the map is loaded. By default, this configuration enables Freeze Tag when the map starts.

`cfg/sourcemod/freezetag.cfg` contains all of the configurable paramters for Freeze Tag. Descriptions of what each cvar does is listed in the config file.

`cfg/sourcemod/freezetagsounds.cfg` lists the sounds that the game should play for different events. They are chosen randomly to play from the list. To add a sound to the list, enter its path relative to `tf/sounds/`. These sounds are loaded when the plugin is loaded. If you change this file, you must reload the plugin by entering `sm plugins freezetag reload` into the console.

## Running the Game
If the game is not already running, run `freezetag_enabled 1` in the server console. This will cause the game mode to load and the round to restart. The game mode will remain active until something causes `freezetag_enabled` to become 0.

To administrate the game, there are four admin commands which can be run by anyone with generic admin rights.

* `ft_flutts <#userid|name>` will cause a player to be moved to the Fluttershy team. If this player is the only player remaining on RED that was not frozen, the round will end.
* `ft_unflutts <#userid|name>` will move a player from the Fluttershy team to RED. If this action causes no Fluttershys to remain, the round will end.
* `ft_freeze <#userid|name>` will freeze a player in place as if they were hit by a Fluttershy. If this player was the last unfrozen player on RED, the round will end.
* `ft_unfreeze <#userid|name>` will remove the freeze effect from a player.

## Development

The source for this plugin is located in `addons/sourcemod/scripting/freezetag.sp`. To compile the code, you must have SDKHooks installed. The web compiler that SourceMod provides cannot link to this dependency. You need to use the compiler executable included with SourceMod.

The source file in the master branch will always match the compiled plugin. Development versions of the source code can be found in the delvelopment branch. The compiled plugin in the development branch will be the last release version and thus will not match the source code.

Maps must be custom made to work with this plugin. The map should contain a team_control_point_master and a team_round_timer. There should be no additional objectives on the map. This causes the game to only show a round timer on the HUD. Additional considerations should be made when adapting maps to remove resupply cabinets and one-way doors such as the spawn room doors.