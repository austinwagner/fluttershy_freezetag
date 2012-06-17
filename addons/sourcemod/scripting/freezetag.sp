#pragma semicolon 1
#pragma tabsize 0

#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>
#include <regex>
#undef REQUIRE_PLUGIN
#include <tf2items_giveweapon>

#define PLUGIN_VERSION "0.4.0"
#define CVAR_FLAGS FCVAR_PLUGIN | FCVAR_NOTIFY
#define MAX_CLIENT_IDS MAXPLAYERS + 1
#define MAX_DC_PROT 64

/****** Teams ******/
#define TEAM_RED 2
#define TEAM_BLU 3

/****** Sounds ******/
#define SND_FREEZE 0
#define SND_UNFREEZE 1
#define SND_WIN 2
#define SND_LOSS 3
#define SND_MINIGUN_RELOAD_FINISHED 4
#define SND_FLAMETHROWER_RELOAD_FINISHED 5
#define SND_AIRBLAST_COOLDOWN 6

#define SNDLEVEL_DEFAULT SNDLEVEL_RAIDSIREN

#define PREVENT_DEATH_HP 3000
#define SHAME_STUN_DURATION 5000.0
#define SLOT_PRIMARY 0
#define SLOT_SECONDARY 1
#define SLOT_MELEE 2
#define FREE_CLASS_CHANGE_TIME 10.0
#define DEFAULT_CLASS TFClass_Soldier

public Plugin:myinfo =
{
	name = "Fluttershy's Freeze Tag",
	author = "Ambit, RogueDarkJedi",
	description = "Defeat the Fluttershys before they freeze everyone.",
	version = PLUGIN_VERSION,
	url = ""
};

new Handle:sounds[7];

/****** Saving original values ******/
new original_ff_val;
new original_scramble_teams_val;
new original_teams_unbalance_val;

/****** Game settings ******/
new Handle:ff_cvar;
new Handle:scramble_teams_cvar;
new Handle:teams_unbalance_cvar;

/****** FSFT settings ******/
new Handle:max_hp_cvar;
new Handle:freeze_duration_cvar;
new Handle:freeze_immunity_cvar;
new Handle:enabled_cvar;
new Handle:flamethrower_reload_time_cvar;
new Handle:minigun_reload_time_cvar;
new Handle:minigun_ammo_cvar;
new Handle:flamethrower_ammo_cvar;
new Handle:airblast_cooldown_time_cvar;
new Handle:round_time_cvar;
new Handle:fluttershy_ratio_cvar;
new Handle:map_name_regex_cvar;
new Handle:class_change_time_limit_cvar;

/****** Local settings ******/
new max_hp;
new Float:freeze_duration;
new Float:freeze_immunity_time;
new bool:enabled;
new Float:minigun_reload_time;
new Float:flamethrower_reload_time;
new minigun_ammo;
new flamethrower_ammo;
new Float:airblast_cooldown_time;
new round_time;
new Float:fluttershy_ratio;
new Handle:map_name_regex;
new Float:class_change_time_limit;
new Float:round_start_time;

/****** Tracking player conditions ******/
new bool:is_fluttershy[MAX_CLIENT_IDS];
new displayed_health[MAX_CLIENT_IDS];
new current_health[MAX_CLIENT_IDS];
new bool:bypass_immunity[MAX_CLIENT_IDS];
new bool:stun_immunity[MAX_CLIENT_IDS];
new String:dc_while_stunned[MAX_DC_PROT][100];
new bool:airblast_cooldown[MAX_CLIENT_IDS];
new Handle:airblast_timer[MAX_CLIENT_IDS];
new Handle:reload_timer[MAX_CLIENT_IDS];
new Handle:beacon_timer[MAX_CLIENT_IDS];
new Float:beacon_radius[MAX_CLIENT_IDS];
new Handle:sound_busy_timer[MAX_CLIENT_IDS];
new Float:last_class_change[MAX_CLIENT_IDS];

/****** Misc ******/
new killer[16];
new num_killers;
new num_dc_while_stunned;
new ammo_offset;
new master_cp = -1;
new bool:win_conditions_checked;
new ring_model;
new halo_model;
new Float:tick_interval;



/**
 * The starting point of the plugin. Called when the plugin is first loaded.
 */
public OnPluginStart()
{    
    decl String:cvar_string[512];
    
    LoadTranslations("freezetag.phrases");
    
    // Create Console Variables
    max_hp_cvar = CreateConVar("freezetag_max_hp", "6750", "The amount of life Fluttershys start with.", CVAR_FLAGS);
    freeze_duration_cvar = CreateConVar("freezetag_freeze_time", "300.0", "The amount of time in seconds a player will remain frozen for before automatically unfreezing.", CVAR_FLAGS);
    freeze_immunity_cvar = CreateConVar("freezetag_immunity_time", "2.5", "The amount of time in seconds during which a player cannot be unfrozen or refrozen.", CVAR_FLAGS);
    enabled_cvar = CreateConVar("freezetag_enabled", "0", "0 to disable, 1 to enable.", CVAR_FLAGS | FCVAR_DONTRECORD);
    minigun_reload_time_cvar = CreateConVar("freezetag_minigun_reload", "5.0", "The amount of time in seconds it takes to reload a player's Minigun.", CVAR_FLAGS);
    flamethrower_reload_time_cvar = CreateConVar("freezetag_flamethrower_reload", "5.0", "The amount of time in seconds it takes to reload a player's Flamethrower.", CVAR_FLAGS);
    minigun_ammo_cvar = CreateConVar("freezetag_minigun_ammo", "75", "The maximum number of bullets a Minigun can hold.", CVAR_FLAGS);
    flamethrower_ammo_cvar = CreateConVar("freezetag_flamethrower_ammo", "100", "The maximum amount of ammo a Flamethrower can hold.", CVAR_FLAGS);
    airblast_cooldown_time_cvar = CreateConVar("freezetag_airblast_cooldown", "3.0", "The amount of time in seconds before a Pyro can airblast again.", CVAR_FLAGS);
    round_time_cvar = CreateConVar("freezetag_round_time", "300", "The amount of time in seconds that a round will last.", CVAR_FLAGS);
    fluttershy_ratio_cvar = CreateConVar("freezetag_player_ratio", "6", "1 out of this many players will be selected as a Fluttershy.", CVAR_FLAGS);
    map_name_regex_cvar = CreateConVar("freezetag_maps", "freezetag_", "The maps to automatically enable this plugin on, written as a PCRE. If any text in the map name matches the RegEx, the plugin will be enabled.", CVAR_FLAGS);
    class_change_time_limit_cvar = CreateConVar("freezetag_class_change_time_limit", "15.0", "How long in seconds a player must wait before changing classes again.", CVAR_FLAGS);
    CreateConVar("freezetag_version", PLUGIN_VERSION, "Fluttershy Freeze Tag version", CVAR_FLAGS | FCVAR_REPLICATED | FCVAR_DONTRECORD);
    
    HookConVarChange(max_hp_cvar, ConVarChanged);
    HookConVarChange(freeze_duration_cvar, ConVarChanged);
    HookConVarChange(freeze_immunity_cvar, ConVarChanged);
    HookConVarChange(enabled_cvar, ConVarChanged);
    HookConVarChange(minigun_reload_time_cvar, ConVarChanged);
    HookConVarChange(flamethrower_reload_time_cvar, ConVarChanged);
    HookConVarChange(minigun_ammo_cvar, ConVarChanged);
    HookConVarChange(flamethrower_ammo_cvar, ConVarChanged);
    HookConVarChange(airblast_cooldown_time_cvar, ConVarChanged);
    HookConVarChange(round_time_cvar, ConVarChanged);
    HookConVarChange(fluttershy_ratio_cvar, ConVarChanged);
    HookConVarChange(class_change_time_limit_cvar, ConVarChanged);
    
    // Get the current values for all of the console variables
    max_hp = GetConVarInt(max_hp_cvar);
    freeze_duration = GetConVarFloat(freeze_duration_cvar);
    freeze_immunity_time = GetConVarFloat(freeze_immunity_cvar);
    minigun_reload_time = GetConVarFloat(minigun_reload_time_cvar);
    flamethrower_reload_time = GetConVarFloat(flamethrower_reload_time_cvar);
    minigun_ammo = GetConVarInt(minigun_ammo_cvar);
    flamethrower_ammo = GetConVarInt(flamethrower_ammo_cvar);
    airblast_cooldown_time = GetConVarFloat(airblast_cooldown_time_cvar);
    round_time = GetConVarInt(round_time_cvar);
    fluttershy_ratio = FloatDiv(1.0, float(GetConVarInt(fluttershy_ratio_cvar)));
    GetConVarString(map_name_regex_cvar, cvar_string, sizeof(cvar_string)); 
    map_name_regex = CompileRegex(cvar_string);
    class_change_time_limit = GetConVarFloat(class_change_time_limit_cvar);
    enabled = false;
    
    // Get the default TF2 convars that will need to be changed
    ff_cvar = FindConVar("mp_friendlyfire");
    scramble_teams_cvar = FindConVar("mp_scrambleteams_auto");
    teams_unbalance_cvar = FindConVar("mp_teams_unbalance_limit");
    
    // Register admin commands for rearranging players and debugging
    RegAdminCmd("ft_unfreeze", UnfreezePlayerCommand, ADMFLAG_GENERIC);
    RegAdminCmd("ft_freeze", FreezePlayerCommand, ADMFLAG_GENERIC);
    RegAdminCmd("ft_flutts", MakeFluttershyCommand, ADMFLAG_GENERIC);
    RegAdminCmd("ft_unflutts", ClearFluttershyCommand, ADMFLAG_GENERIC);
    RegAdminCmd("ft_enable", EnableCommand, ADMFLAG_GENERIC);
    RegAdminCmd("ft_disable", DisableCommand, ADMFLAG_GENERIC);
	RegAdminCmd("ft_forgive", ForgiveCommand, ADMFLAG_GENERIC);
    
    ammo_offset = FindSendPropOffs("CTFPlayer", "m_iAmmo");
    tick_interval = GetTickInterval();
    
    AutoExecConfig(true, "freezetag");
    
    // Modified Minigun - Spread (106): 80%, Spinup Time (87): 50%, Deployed Movespeed (75): 209% (230 total)
    TF2Items_CreateWeapon(-1000, "tf_weapon_minigun", 15, SLOT_PRIMARY, 0, 0, "106 ; .8 ; 87 ; .5 ; 75 ; 2.09", 50, _, true);
    // Modified Bonesaw - +Health (26): 850 (1000 total), Health regen (57): -6 (0 total)
    TF2Items_CreateWeapon(-1001, "tf_weapon_bonesaw", 8, SLOT_MELEE, 0, 0, "26 ; 850 ; 57 ; -6", _, _, true);
    // Modified Grenade Launcher - Projectile Speed (103): 110%
    TF2Items_CreateWeapon(-1002, "tf_weapon_grenadelauncher", 19, SLOT_MELEE, 0, 0, "103 ; 1.1", 4, _, true);
    // Modified Sicky Launcher - +Arm Time (126): -.42 (.5 total), +Max Stickies Deployed (89): -5 (3 total), Self Pushback (59): 50%
    TF2Items_CreateWeapon(-1003, "tf_weapon_pipebomblauncher", 20, SLOT_SECONDARY, 0, 0, "126 ; -.42 ; 89 ; -5 ; 59 ; .5", 8, _, true);
    // Modified Scattergun - Movespeed (54): 80% (320 total), Bullets per Shot (45): 50% (5 total)
    TF2Items_CreateWeapon(-1004, "tf_weapon_scattergun", 13, SLOT_PRIMARY, 0, 0, "54 ; .8 ; 45 ; .5", 6, _, true);
    // Modified SMG - Fire Rate (6): 200%
    TF2Items_CreateWeapon(-1005, "tf_weapon_smg", 16, SLOT_SECONDARY, 0, 0, "6 ; .5", 6, _, true);
    // Modified Rifle - Charge Rate (41): 300%
    TF2Items_CreateWeapon(-1006, "tf_weapon_sniperrifle", 14, SLOT_PRIMARY, 0, 0, "41 ; 3", 6, _, true);
	// Modified Pistol - Damage (1): 70%
	TF2Items_CreateWeapon(-1007, "tf_weapon_pistol", 23, SLOT_SECONDARY, 0, 0, "1 ; .7", 12, _, true);
    
    LoadSoundConfig();
    
    if (GetConVarBool(enabled_cvar))
        EnablePlugin();
}

/**
 * Read the sound configuration file located in $GAME_ROOT/cfg/sourcemod/freezetagsounds.cfg.
 */
LoadSoundConfig()
{
    decl String:line[PLATFORM_MAX_PATH];
    decl String:type[120];
    decl String:full_path[PLATFORM_MAX_PATH];
    if(FileExists("cfg\\sourcemod\\freezetagsounds.cfg") == false)
    {
      LogError("%T", "SoundConfFail", LANG_SERVER);
      return;
    }   
    new Handle:kvTree = CreateKeyValues("FluttershyFreezeTag");
    FileToKeyValues(kvTree, "cfg\\sourcemod\\freezetagsounds.cfg");
    new section = -1;
    
    for (new i = 0; i < sizeof(sounds); i++)
        sounds[i] = CreateArray(PLATFORM_MAX_PATH, 0);
    
    KvGotoFirstSubKey(kvTree);
    do 
    {
        KvGetString(kvTree, "file", line, sizeof(line), "");
        KvGetString(kvTree, "type", type, sizeof(type), "");
        if (StrEqual(type, "FreezeSound", false))
            section = SND_FREEZE;
        else if (StrEqual(type, "UnfreezeSound", false))
            section = SND_UNFREEZE;
        else if (StrEqual(type, "WinSound", false))
            section = SND_WIN;
        else if (StrEqual(type, "LossSound", false))
            section = SND_LOSS;
        else if (StrEqual(type, "MinigunReloadFinishedSound", false))
            section = SND_MINIGUN_RELOAD_FINISHED;
        else if (StrEqual(type, "FlamethrowerReloadFinishedSound", false))
            section = SND_FLAMETHROWER_RELOAD_FINISHED;
        else if (StrEqual(type, "AirblastCooldownSound", false))
            section = SND_AIRBLAST_COOLDOWN;
        full_path = "sound\\";
        StrCat(full_path, sizeof(full_path), line);
        if (FileExists(full_path))
        PushArrayString(sounds[section], line);
        else
        LogError("%T", "FileNoExist", LANG_SERVER, full_path);
    } while (KvGotoNextKey(kvTree));
  
    CloseHandle(kvTree);
}

/**
 * Event handler for when the round timer expires.
 * 
 * @param event An handle to the event that triggered this callback.
 * @param name The name of the event that triggered this callback.
 * @param dontBroadcast True if the event broadcasts to clients, otherwise false.
 */
public Action:RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
    CheckWinCondition(true);
}

/**
 * Event handler for the start of a new round.
 * 
 * @param event An handle to the event that triggered this callback.
 * @param name The name of the event that triggered this callback.
 * @param dontBroadcast True if the event broadcasts to clients, otherwise false.
 */
public Action:RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    decl players[MAX_CLIENT_IDS];
    num_killers = 0;
    num_dc_while_stunned = 0;
    win_conditions_checked = false;
    
    for (new i = 0; i < MAX_DC_PROT; i++)
    {
        dc_while_stunned[i] = "";
    }
    
    // Move everyone to RED and reset all of the arrays
    new num_players = 0;
    for (new i = 1; i <= MaxClients; i++)
    {
        is_fluttershy[i] = false;
        bypass_immunity[i] = false;
        stun_immunity[i] = false;
        last_class_change[i] = -1000.0;
        
        if (IsClientInGame(i) && !IsClientObserver(i))
        {
            ChangeClientTeam(i, TEAM_RED);
            players[num_players] = i;
            num_players++;
            SetEntProp(i, Prop_Send, "m_CollisionGroup", 2); // Only collide with world and triggers
        }
        StopBeacon(i);
    }
    
    // Select players to become Fluttershys
    new num_fluttershys = 0;
    new fshy_goal = RoundToCeil(FloatMul(float(num_players), fluttershy_ratio));
    new client;
    
    while (num_fluttershys < fshy_goal)
    {
        client = players[GetRandomInt(0, num_players - 1)];
        if (!is_fluttershy[client])
        {
            num_fluttershys++;
            MakeFluttershy(client);
            ShowVGUIPanel(client, "class_red", _, false);
        }
    }
    
    // Make sure all of the players are alive
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsClientObserver(i))
            TF2_RespawnPlayer(i);
    }
    
    // Round end events go to this entity
    master_cp = FindEntityByClassname(-1, "team_control_point_master");
    if (master_cp == -1)
    {
        master_cp = CreateEntityByName("team_control_point_master");
        DispatchSpawn(master_cp);
        AcceptEntityInput(master_cp, "Enable");
    }
    
    
    // Configure the round timer
    new team_round_timer = FindEntityByClassname(-1, "team_round_timer");
    if (team_round_timer == -1)
        DispatchSpawn(team_round_timer);    
    
    SetEntProp(team_round_timer, Prop_Send, "m_nSetupTimeLength", 0);
    SetEntProp(team_round_timer, Prop_Send, "m_bShowInHUD", 1);
    SetVariantInt(round_time);
    AcceptEntityInput(team_round_timer, "SetMaxTime");
    SetVariantInt(round_time);
    AcceptEntityInput(team_round_timer, "SetTime");
    
    round_start_time = GetGameTime();
}

/**
 * Callback for when a console variable is changed.
 * 
 * @param convar The handle of the console variable that was changed.
 * @param oldValue The value of the console variable before this event.
 * @param newValue The value of the console variable after this event.
 */
public ConVarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
    if (convar == max_hp_cvar)
        max_hp = GetConVarInt(convar);
    else if (convar == freeze_duration_cvar)
        freeze_duration = GetConVarFloat(convar);
    else if (convar == freeze_immunity_cvar)
        freeze_immunity_time = GetConVarFloat(convar);
    else if (convar == minigun_reload_time_cvar)
        minigun_reload_time = GetConVarFloat(convar);
    else if (convar == flamethrower_reload_time_cvar)
        flamethrower_reload_time = GetConVarFloat(convar);
    else if (convar == minigun_ammo_cvar)
        minigun_ammo = GetConVarInt(convar);
    else if (convar == flamethrower_ammo_cvar)
        flamethrower_ammo = GetConVarInt(convar);
    else if (convar == airblast_cooldown_time_cvar)
        airblast_cooldown_time = GetConVarFloat(convar);
    else if (convar == round_time_cvar)
        round_time = GetConVarInt(convar);
    else if (convar == fluttershy_ratio_cvar)
        fluttershy_ratio = FloatDiv(1.0, float(GetConVarInt(convar)));
    else if (convar == map_name_regex_cvar)
        map_name_regex = CompileRegex(newValue);
    else if (convar == class_change_time_limit_cvar)
        class_change_time_limit = GetConVarFloat(class_change_time_limit_cvar);
    else if (convar == enabled_cvar)
    {
        if (GetConVarBool(convar))
            EnablePlugin();
        else
            DisablePlugin();
    }
}

/**
 * Turns on the plugin. Hooks required functions and initializes variables.
 */
EnablePlugin()
{
    if (enabled)
        return;
    
    enabled = true;
    
    // Save convars to restore them to their original state when the plubun is unloaded
    original_ff_val = GetConVarInt(ff_cvar);
    original_scramble_teams_val = GetConVarInt(scramble_teams_cvar);
    original_teams_unbalance_val = GetConVarInt(teams_unbalance_cvar);
    
    // Set convars to make the unfreezing and stacked teams work
    SetConVarInt(ff_cvar, 1);
    SetConVarInt(scramble_teams_cvar, 0);
    SetConVarInt(teams_unbalance_cvar, 0);
    
    // Initialize arrays
    for (new i = 1; i < MAX_CLIENT_IDS; i++)
    {
        is_fluttershy[i] = false;
        bypass_immunity[i] = false;
        stun_immunity[i] = false;
        airblast_cooldown[i] = false;
    }
    
    // Apply SDKHooks to all clients in the server when the plugin is loaded
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SetupPlayer(i);
        }
    }
    
    // Block team swapping and suicides
    AddCommandListener(JoinTeamCommand, "jointeam");
    AddCommandListener(JoinClassCommand, "joinclass");
    AddCommandListener(BlockCommandFluttershy, "kill");
    AddCommandListener(SpectateCommand, "spectate");
    AddCommandListener(BlockCommandFluttershy, "explode");
    
    HookEvent("teamplay_round_start", RoundStart, EventHookMode_Pre);
    HookEvent("teamplay_round_win", RoundEnd);
    HookEvent("teamplay_round_stalemate", RoundEnd);
    HookEvent("post_inventory_application", PostInventoryApplication);
    
    ServerCommand("mp_restartgame_immediate 1");


}

/**
 * Turns of the plugin. Unhooks events and restores console variables.
 *
 * @param unloading Set to true only if this function is being called due to a full unload of the plugin.
 */
DisablePlugin(bool:unloading = false)
{
    if (!enabled)
        return;
    
    enabled = false;

    
    // Restore convars to original state
    SetConVarInt(ff_cvar, original_ff_val);
    SetConVarInt(scramble_teams_cvar, original_scramble_teams_val);
    SetConVarInt(teams_unbalance_cvar, original_teams_unbalance_val);
    
    // Unhook commands and events. If the plugin is ending, these have already been removed.
    if (!unloading)
    {
        RemoveCommandListener(JoinTeamCommand, "jointeam");
        RemoveCommandListener(JoinClassCommand, "joinclass");
        RemoveCommandListener(BlockCommandFluttershy, "kill");
        RemoveCommandListener(SpectateCommand, "spectate");
        RemoveCommandListener(BlockCommandFluttershy, "explode");
    
        UnhookEvent("teamplay_round_start", RoundStart, EventHookMode_Pre);
        UnhookEvent("teamplay_round_win", RoundEnd);
        UnhookEvent("teamplay_round_stalemate", RoundEnd);
        UnhookEvent("post_inventory_application", PostInventoryApplication);
    }
    
    // Remove SDKHooks player event hooks
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKUnhook(i, SDKHook_OnTakeDamage, OnTakeDamage);
            SDKUnhook(i, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
            SDKUnhook(i, SDKHook_WeaponCanSwitchTo, WeaponCanSwitchTo);
            SDKUnhook(i, SDKHook_WeaponCanUse, WeaponCanSwitchTo);
            SDKUnhook(i, SDKHook_Spawn, OnSpawn);
            SDKUnhook(i, SDKHook_PreThinkPost, PreThinkPost);
            
            if (!IsClientObserver(i))
                SetEntProp(i, Prop_Send, "m_CollisionGroup", 5); // Default collision for player
        }
        if (reload_timer[i] != INVALID_HANDLE)
        {
            KillTimer(reload_timer[i]);
            reload_timer[i] = INVALID_HANDLE;
        }  
        
        if (airblast_timer[i] != INVALID_HANDLE)
        {
            KillTimer(airblast_timer[i]);
            airblast_timer[i] = INVALID_HANDLE;
        }  
        
        StopBeacon(i);
        
    }   
     
    ServerCommand("mp_scrambleteams");
    ServerCommand("mp_restartgame_immediate 1");
}

/**
 * Called when the map is first loaded.
 */
public OnMapStart()
{
    decl String:path[PLATFORM_MAX_PATH];
    new size;
    
    for (new i = 0; i < sizeof(sounds); i++)
    {
        size = GetArraySize(sounds[i]);
        for (new j = 0; j < size; j++)
        {
            GetArrayString(sounds[i], j, path, sizeof(path));
            LoadSound(path);
        }
    }
    
    ring_model = PrecacheModel("materials/sprites/laser.vmt");
    halo_model = PrecacheModel("materials/sprites/halo01.vmt");
    
    GetCurrentMap(path, sizeof(path));
    if (MatchRegex(map_name_regex, path) > 0)
        SetConVarBool(enabled_cvar, true);
}

public OnMapEnd()
{
	SetConVarBool(enabled_cvar, false);
}

/**
 * Prepare a sound for use later. Adds the sound to the download table
 * and precaches the sound.
 *
 * @param sound The path to the sound file relative to the $GAME_ROOT\sound\ directory.
 */
LoadSound(const String:sound[])
{
    decl String:path[PLATFORM_MAX_PATH];
    
    path = "sound\\";
    StrCat(path, sizeof(path), sound);
    AddFileToDownloadsTable(path);
    PrecacheSound(sound, true);
}

/**
 * Event handler for a post hook on PreThink.
 *
 * @param client Index of the client.
 */
public PreThinkPost(client) 
{   
    if (IsClientObserver(client))
        return;
    
    // Handle reloading weapons that normally don't have a reload
    if (TF2_GetPlayerClass(client) == TFClass_Heavy)
    {
        if (GetEntData(client, ammo_offset + 4, 4) > minigun_ammo)
        {
            SetEntData(client, ammo_offset + 4, minigun_ammo, 4);
        }
        else if (reload_timer[client] == INVALID_HANDLE && 
            ((GetClientButtons(client) & IN_RELOAD == IN_RELOAD && GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon") == GetPlayerWeaponSlot(client, SLOT_PRIMARY))
            || GetEntData(client, ammo_offset + 4, 4) == 0))
        {
            PrintToChat(client, "%t", "MinigunReloading", minigun_reload_time);
            SetEntData(client, ammo_offset + 4, 0, 4);
            reload_timer[client] = CreateTimer(minigun_reload_time, ReloadMinigun, client);
        }
    }
    else if (TF2_GetPlayerClass(client) == TFClass_Pyro)
    {
        if (GetEntData(client, ammo_offset + 4, 4) > flamethrower_ammo)
        {
            SetEntData(client, ammo_offset + 4, flamethrower_ammo, 4);
        }
        else if (reload_timer[client] == INVALID_HANDLE && 
            ((GetClientButtons(client) & IN_RELOAD == IN_RELOAD && GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon") == GetPlayerWeaponSlot(client, SLOT_PRIMARY)) 
            || GetEntData(client, ammo_offset + 4, 4) == 0))
        {
            PrintToChat(client, "%t", "FlamethrowerReloading", flamethrower_reload_time);
            SetEntData(client, ammo_offset + 4, 0, 4);
            reload_timer[client] = CreateTimer(flamethrower_reload_time, ReloadFlamethrower, client);
        }
    }
    else
    {
        // Give 99 primary weapon ammo
        SetEntData(client, ammo_offset + 4, 99, 4);
    }
    
    // Give 99 secondary weapon ammo
    SetEntData(client, ammo_offset + 8, 99, 4);
}

/**
 * Handler for when a client's movement buttons are processed.
 *
 * @param client Index of the client.
 * @param buttons Bitflags representing the buttons the player is pressing.
 * @param impulse The current impulse command.
 * @param vel Player's desired velocity.
 * @param angles Player's desired view angles.
 * @param weapon Entity index of the new weapon if the player switches weapons, otherwise 0.
 * @return Plugin_Handled, Plugin_Continue, or Plugin_Changed to indicate how the original event should be processed
 */
public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
    decl String:sound_path[PLATFORM_MAX_PATH];
    
    if (enabled)
    {
        if (buttons & IN_ATTACK2 == IN_ATTACK2 && airblast_cooldown[client] && TF2_GetPlayerClass(client) == TFClass_Pyro)
        {
            if (sound_busy_timer[client] == INVALID_HANDLE)
            {
                GetArrayString(sounds[SND_AIRBLAST_COOLDOWN], GetRandomInt(0, GetArraySize(sounds[SND_AIRBLAST_COOLDOWN]) - 1), sound_path, sizeof(sound_path));
                EmitSoundToClient(client, sound_path, _, _, SNDLEVEL_DEFAULT);
                sound_busy_timer[client] = CreateTimer(2.0, ResetSound, client);
            }
            buttons &= ~IN_ATTACK2;
        }
        else if (buttons & IN_ATTACK2 == IN_ATTACK2 && TF2_GetPlayerClass(client) == TFClass_Pyro)
        {
            airblast_cooldown[client] = true;
            airblast_timer[client] = CreateTimer(airblast_cooldown_time, ResetAirblast, client);
            sound_busy_timer[client] = CreateTimer(1.0, ResetSound, client);
        }
        
        return Plugin_Changed;
    }
    
    return Plugin_Continue;
}

/**
 * Timer callback to reenable a player's airblast.
 * 
 * @param timer A handle to the timer that triggered this callback.
 * @param client Index of the client.
 */
public Action:ResetAirblast(Handle:timer, any:client)
{
    if (IsClientInGame(client) && !IsClientObserver(client))
    {
        airblast_cooldown[client] = false;
    }
    airblast_timer[client] = INVALID_HANDLE;
}

/**
 * Timer to prevent a sound from playing too often.
 * 
 * @param timer A handle to the timer that triggered this callback.
 * @param client Index of the client.
 */
public Action:ResetSound(Handle:timer, any:client)
{
    sound_busy_timer[client] = INVALID_HANDLE;
}

/**
 * Timer callback to reload a player's minigun.
 * 
 * @param timer A handle to the timer that triggered this callback.
 * @param client Index of the client.
 */
public Action:ReloadMinigun(Handle:timer, any:client)
{
    decl String:sound_path[PLATFORM_MAX_PATH];
    
    if (IsClientInGame(client) && !IsClientObserver(client))
    {
        PrintToChat(client, "%t", "MinigunReloaded");
        GetArrayString(sounds[SND_MINIGUN_RELOAD_FINISHED], GetRandomInt(0, GetArraySize(sounds[SND_MINIGUN_RELOAD_FINISHED]) - 1), sound_path, sizeof(sound_path));
        EmitSoundToClient(client, sound_path, _, _, SNDLEVEL_DEFAULT);
        SetEntData(client, ammo_offset + 4, minigun_ammo, 4);  
    }
    reload_timer[client] = INVALID_HANDLE;
}

/**
 * Timer callback to reload a player's flamethrower.
 * 
 * @param timer A handle to the timer that triggered this callback.
 * @param client Index of the client.
 */
public Action:ReloadFlamethrower(Handle:timer, any:client)
{
    decl String:sound_path[PLATFORM_MAX_PATH];
    
    if (IsClientInGame(client) && !IsClientObserver(client))
    {
        PrintToChat(client, "%t", "FlamethrowerReloaded");
        GetArrayString(sounds[SND_FLAMETHROWER_RELOAD_FINISHED], GetRandomInt(0, GetArraySize(sounds[SND_FLAMETHROWER_RELOAD_FINISHED]) - 1), sound_path, sizeof(sound_path));
        EmitSoundToClient(client, sound_path, _, _, SNDLEVEL_DEFAULT);
        SetEntData(client, ammo_offset + 4, flamethrower_ammo, 4);    
    }
    reload_timer[client] = INVALID_HANDLE;
}

/**
 * Called when the plugin is being unloaded.
 */
public OnPluginEnd()
{
    DisablePlugin(true);
}

/**
 * Called when a new player joins the server.
 *
 * @param client Index of the client.
 */
public OnClientPutInServer(client)
{
    if (enabled)
        SetupPlayer(client);
}

/**
 * Hooks player events and moves player to RED.
 *
 * @param client Index of the client.
 */
SetupPlayer(client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
    SDKHook(client, SDKHook_WeaponCanSwitchTo, WeaponCanSwitchTo);
    SDKHook(client, SDKHook_WeaponCanUse, WeaponCanSwitchTo);
    SDKHook(client, SDKHook_Spawn, OnSpawn);
    SDKHook(client, SDKHook_PreThinkPost, PreThinkPost);
    ChangeClientTeam(client, TEAM_RED);
}

/**
 * Called when a player leaves the server.
 *
 * @param client Index of the client.
 */
public OnClientDisconnect(client)
{
    decl String:steam_id[100];
    
    if (enabled)
    {
        is_fluttershy[client] = false;
            
        // If a player disconnected while stunned, make a note of it
        if (TF2_IsPlayerInCondition(client, TFCond_Dazed))
        {
            TF2_RemoveCondition(client, TFCond_Dazed); // Try to prevent player's camera from bugging out
            GetClientAuthString(client, steam_id, sizeof(steam_id));
            dc_while_stunned[num_dc_while_stunned % MAX_DC_PROT] = steam_id;
            num_dc_while_stunned++;
        }
            
        is_fluttershy[client] = false;
        bypass_immunity[client] = false;
        stun_immunity[client] = false;
        
        if (reload_timer[client] != INVALID_HANDLE)
        {
            KillTimer(reload_timer[client]);
            reload_timer[client] = INVALID_HANDLE;
        }
        
        if (airblast_timer[client] != INVALID_HANDLE)
        {
            KillTimer(airblast_timer[client]);
            airblast_timer[client] = INVALID_HANDLE;
        }
        
        // It is possible that the disconnected player caused the win condition to be met
        CheckWinCondition();  
    }
}

/**
 * Handler for when a player spawns.
 *
 * @param client Index of the client.
 * @return Plugin_Handled, Plugin_Continue, or Plugin_Changed to indicate how the original event should be processed
 */
public Action:OnSpawn(client)
{
    SetEntProp(client, Prop_Send, "m_CollisionGroup", 2); // Only collide with world and triggers
    if (!is_fluttershy[client] && GetClientTeam(client) != TEAM_RED)
    {
        ChangeClientTeam(client, TEAM_RED);
        TF2_RespawnPlayer(client);
    }
    else if (is_fluttershy[client] && GetClientTeam(client) != TEAM_BLU)
    {
        ChangeClientTeam(client, TEAM_BLU);
        TF2_RespawnPlayer(client);
    }
    else if (GetClientTeam(client) == TEAM_RED && !IsRedClassAllowedByEnum(TF2_GetPlayerClass(client)))
    {       
        // If the player spawns as an invalid class, force them to change
        // Automatically sets them to soldier so they can't just cancel the forced
        // class change.
        TF2_SetPlayerClass(client, DEFAULT_CLASS);
        TF2_RespawnPlayer(client);
        ShowVGUIPanel(client, "class_red"); 
    }
    
    return Plugin_Continue;
}

/**
 * Checks if a player is on the list of players that disconnected or spectated
 * while they were stunned.
 *
 * @param client Index of the client.
 * @return True if the player was on the shame list, otherwise false.
 */
 bool:ShouldShame(client)
{
    decl String:steam_id[100];
    
    GetClientAuthString(client, steam_id, sizeof(steam_id));
    
    for (new i = 0; i < MAX_DC_PROT; i++)
    {
        if (StrEqual(steam_id, dc_while_stunned[i]))
            return true;
    }
    
    return false;
}

/**
 * Event handler for a player attempting to switch weapons.
 * 
 * @param client Index of the client.
 * @param weapon Entity index of the weapon that the player is switching to.
 * @return Plugin_Continue if the player is allowed to switch weapons, otherwise Plugin_Handled.
 */
public Action:WeaponCanSwitchTo(client, weapon)
{
    if (!is_fluttershy[client] || GetPlayerWeaponSlot(client, SLOT_MELEE) < 0 || weapon == GetPlayerWeaponSlot(client, SLOT_MELEE))
        return Plugin_Continue;
    else
        return Plugin_Handled;
}

/**
 * Post event handler for a player taking damage. Values in here cannot be modified,
 * but correctly represent the amount of damage the victim took.
 *
 * @param victim Index of the victim.
 * @param attacker Index of the attacker.
 * @param inflictor Entity index of the damage inflictor (usually the same as attacker).
 * @param damage The amount of damage that the victim took.
 * @param damagetype Bitflags for the type of damage that the victim took.
 * @param weapon Entity index of the weapon that the victim was injured with.
 * @param damageForce A vector representing the amount of force the weapon applied to the victim.
 * @param damagePosition A vector representing the location that the damage came from.
 */
public OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype, weapon, const Float:damageForce[3], const Float:damagePosition[3])
{
    decl String:victim_name[MAX_NAME_LENGTH];
    decl String:attacker_name[MAX_NAME_LENGTH];
    
    GetCustomClientName(victim, victim_name, sizeof(victim_name));
    GetCustomClientName(attacker, attacker_name, sizeof(attacker_name));
    
    // The player is supposed to die, do not modify damage
    if (bypass_immunity[victim])
    {
        bypass_immunity[victim] = false;
    }
    else if (is_fluttershy[victim] && !IsWorldDeath(attacker))
    {
        current_health[victim] = current_health[victim] - RoundFloat(damage);
        
        if (current_health[victim] <= 0)
        {
            killer[num_killers] = GetClientUserId(attacker);
            num_killers++;
            PrintToChatAll("%t", "PlayerDefeat",  attacker_name, victim_name);
            ClearFluttershy(victim, attacker);
        }
        else
        {
            displayed_health[victim] = displayed_health[victim] - RoundFloat(damage);
            
            // Refill the life bar and display to the user the multiple of 1000 that his life is now counting down from
            if (displayed_health[victim] <= 0)
            {
                PrintToChatAll("%t", "CurrentHealth", victim_name, current_health[victim]);
                displayed_health[victim] = current_health[victim] - ((current_health[victim] / 1000) * 1000);
            }
            
        
            SetEntityHealth(victim, displayed_health[victim]);
        }
    }
    else if (!is_fluttershy[victim])
    {
        // Set the health back to normal
        SetEntityHealth(victim, current_health[victim]);
    }
}

/**
 * Event handler for a player taking damage. Values are base damage only,
 * they are not crit or distance modified.
 *
 * @param victim Index of the victim.
 * @param attacker Index of the attacker.
 * @param inflictor Entity index of the damage inflictor (usually the same as attacker).
 * @param damage The base damage that the victim will take.
 * @param damagetype Bitflags for the type of damage that the victim took.
 * @param weapon Entity index of the weapon that the victim was injured with.
 * @param damageForce A vector representing the amount of force the weapon applied to the victim.
 * @param damagePosition A vector representing the location that the damage came from.
 */
public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{    
    // The player is supposed to die, don't modify damage but remove the gib effect that happens
    // due to using an explosive entity to kill the player
    if (bypass_immunity[victim])
    {
        damagetype = damagetype | _:DMG_NEVERGIB & _:(!DMG_ALWAYSGIB);
        return Plugin_Changed;
    }
    
    // Respawn players that fall off the map instantly since they cannot die to the fall damage
    if (IsWorldDeath(attacker))
    {
        TF2_RespawnPlayer(victim);
        return Plugin_Handled;
    }

    if (is_fluttershy[victim])
    {
        damagetype |= _:DMG_PREVENT_PHYSICS_FORCE;
        if (GetClientTeam(victim) == GetClientTeam(attacker))
        {
            damage = 0.0;
        }
        else
        {
            // Damage doesn't get modified by crits or distance until after OnTakeDamage has run
            // Since we need to wait for OnTakeDamage to complete, set the player's health 
            // very high to prevent them from dying during OnTakeDamage. We will force the player
            // to die later if necessary
            SetEntityHealth(victim, PREVENT_DEATH_HP);
        }
        return Plugin_Changed;
    }
        
    // If enemy is hit and not frozen, freeze him. Damage done by the environment can never freeze a player.
    if (attacker != 0 && GetClientTeam(victim) != GetClientTeam(attacker) && !TF2_IsPlayerInCondition(victim, TFCond_Dazed))
    {
        FreezePlayer(victim, attacker);
    }
    // If ally is hit and frozen, unfreeze him
    else if (attacker != 0 && victim != attacker && GetClientTeam(victim) == GetClientTeam(attacker) && TF2_IsPlayerInCondition(victim, TFCond_Dazed) && weapon == GetPlayerWeaponSlot(attacker, 2))
    {
        UnfreezePlayer(victim, attacker);
    }
    
    if (attacker != 0 && victim != attacker)
    {
        damage = 0.0;
    }
    
    // Make sure that damage taken will not kill the player
    current_health[victim] = GetClientHealth(victim);
    SetEntityHealth(victim, PREVENT_DEATH_HP);
    return Plugin_Changed;
}

/**
 * Check if the entity that did damage belongs to the world insta-kill.
 *
 * @param attacker The entity index to check.
 * @return True if the attacker is the world, otherwise false.
 */
bool:IsWorldDeath(attacker)
{
    // Entity IDs 1 to MaxClients are reserved for players
    // Any damage done by a non player entity must be outside of this range
    return attacker > MaxClients;
}

/**
 * Freeze a player in place.
 *
 * @param victim Index of the player to freeze.
 * @param attacker Index of the player that caused the freeze.
 * 0 represents an unknown source (e.g. forced freeze by admins).
 */
FreezePlayer(victim, attacker)
{
    decl String:victim_name[MAX_NAME_LENGTH];
    decl String:attacker_name[MAX_NAME_LENGTH];
    decl String:sound_path[PLATFORM_MAX_PATH];
    
    GetCustomClientName(victim, victim_name, sizeof(victim_name));
    GetCustomClientName(attacker, attacker_name, sizeof(attacker_name));
              
    if (!stun_immunity[victim] && ((attacker > 0 && !TF2_IsPlayerInCondition(victim, TFCond_Dazed)) || attacker <= 0))
    {
        GetArrayString(sounds[SND_FREEZE], GetRandomInt(0, GetArraySize(sounds[SND_FREEZE]) - 1), sound_path, sizeof(sound_path));
        EmitSoundToAll(sound_path, attacker, _, SNDLEVEL_DEFAULT);
        TF2_AddCondition(victim, TFCond_Ubercharged, freeze_immunity_time);
        CreateTimer(freeze_immunity_time, RemoveFreezeImmunity, GetClientUserId(victim));
        TF2_RemoveCondition(victim, TFCond_Dazed); // Prevent bonk from blocking admin freeze
        TF2_StunPlayer(victim, freeze_duration, 0.0, TF_STUNFLAG_BONKSTUCK, attacker);
        stun_immunity[victim] = true;
        StartBeacon(victim);
        CheckWinCondition();
    }
}

/**
 * Remove the freeze effect from a player.
 *
 * @param victim Index of the player to unfreeze.
 * @param attacker Index of the player that caused the unfreeze.
 * 0 represents an unknown source (e.g. forced freeze by admins).
 */
UnfreezePlayer(victim, attacker)
{
    decl String:victim_name[MAX_NAME_LENGTH];
    decl String:attacker_name[MAX_NAME_LENGTH];
    decl String:sound_path[PLATFORM_MAX_PATH];
    
    GetCustomClientName(victim, victim_name, sizeof(victim_name));
    GetCustomClientName(attacker, attacker_name, sizeof(attacker_name));
    
    if (!stun_immunity[victim] && !stun_immunity[attacker] && TF2_IsPlayerInCondition(victim, TFCond_Dazed))
    {
        GetArrayString(sounds[SND_UNFREEZE], GetRandomInt(0, GetArraySize(sounds[SND_UNFREEZE]) - 1), sound_path, sizeof(sound_path));
        EmitSoundToAll(sound_path, victim, _, SNDLEVEL_DEFAULT);
        TF2_RemoveCondition(victim, TFCond_Dazed);
        stun_immunity[victim] = true;
        TF2_AddCondition(victim, TFCond_Ubercharged, freeze_immunity_time);
        CreateTimer(freeze_immunity_time, RemoveFreezeImmunity, GetClientUserId(victim));
        StopBeacon(victim);
    }
}

/**
 * Timer handler for removing freeze immunity.
 *
 * @param timer A handle to the timer that triggered this callback.
 * @param user_id User ID of the client.
 */
public Action:RemoveFreezeImmunity(Handle:timer, any:user_id)
{
    new client = GetClientOfUserId(user_id);
    if (client > 0 && IsClientInGame(client))
        stun_immunity[client] = false;
}

/**
 * Wrapper around GetClientName to make any ID lower than 0 return as "The Guardians".
 * 
 * @param client Index of the client.
 * @param name Buffer to store the client's name.
 * @param length Maximum size of the string buffer (including NULL terminator).
 */
GetCustomClientName(client, String:name[], length)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        strcopy(name, length, "The Guardians");
    else
        GetClientName(client, name, length);
}

/**
 * Command handler for enabling this plugin.
 *
 * @param client Index of the client that sent the command.
 * @param args The number of arguments.
 */
public Action:EnableCommand(client, args)
{
    ServerCommand("freezetag_enabled 1");
}

/**
 * Command handler for disabling this plugin.
 *
 * @param client Index of the client that sent the command.
 * @param args The number of arguments.
 */
public Action:DisableCommand(client, args)
{
    ServerCommand("freezetag_enabled 0");
}

/**
 * Command handler for unfreezing a player.
 *
 * @param client Index of the client that sent the command.
 * @param args The number of arguments.
 */
public Action:UnfreezePlayerCommand(client, args)
{
    decl String:arg[MAX_NAME_LENGTH];
    decl String:name[MAX_NAME_LENGTH];
    decl targets[MAX_CLIENT_IDS];
    new bool:tn_is_ml;
       
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: ft_unfreeze <#userid|name>");
		return Plugin_Handled;
	}
    
	GetCmdArg(1, arg, sizeof(arg));
    new num_targets = ProcessTargetString(arg, client, targets, sizeof(targets), 0, name, sizeof(name), tn_is_ml);
                                
    if (num_targets <= 0)
    {
        ReplyToTargetError(client, num_targets);
    }
    else
    {
        for (new i = 0; i < num_targets; i++)
        {
            UnfreezePlayer(targets[i], 0);
        }
    }
 
	return Plugin_Handled;
}

/**
 * Command handler for freezing a player.
 *
 * @param client Index of the client that sent the command.
 * @param args The number of arguments.
 */
public Action:FreezePlayerCommand(client, args)
{
    decl String:arg[MAX_NAME_LENGTH];
    decl String:name[MAX_NAME_LENGTH];
    decl targets[MAX_CLIENT_IDS];
    new bool:tn_is_ml;
       
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: ft_freeze <#userid|name>");
		return Plugin_Handled;
	}
    
	GetCmdArg(1, arg, sizeof(arg));
    new num_targets = ProcessTargetString(arg, client, targets, sizeof(targets), 0, name, sizeof(name), tn_is_ml);
                                
    if (num_targets <= 0)
    {
        ReplyToTargetError(client, num_targets);
    }
    else
    {
        for (new i = 0; i < num_targets; i++)
        {
            FreezePlayer(targets[i], 0);
        }
    }
 
	return Plugin_Handled;
}

/**
 * Command handler for turning a player into a Fluttershy.
 *
 * @param client Index of the client that sent the command.
 * @param args The number of arguments.
 */
public Action:MakeFluttershyCommand(client, args)
{
    decl String:arg[MAX_NAME_LENGTH];
    decl String:name[MAX_NAME_LENGTH];
    decl targets[MAX_CLIENT_IDS];
    new bool:tn_is_ml;
       
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: ft_flutts <#userid|name>");
		return Plugin_Handled;
	}
    
	GetCmdArg(1, arg, sizeof(arg));
    new num_targets = ProcessTargetString(arg, client, targets, sizeof(targets), 0, name, sizeof(name), tn_is_ml);
                                
    if (num_targets <= 0)
    {
        ReplyToTargetError(client, num_targets);
    }
    else
    {
        for (new i = 0; i < num_targets; i++)
        {
            MakeFluttershy(targets[i]);
        }
    }
 
	return Plugin_Handled;
}

/**
 * Command handler for moving a player to RED.
 *
 * @param client Index of the client that sent the command.
 * @param args The number of arguments.
 */
public Action:ClearFluttershyCommand(client, args)
{
    decl String:arg[MAX_NAME_LENGTH];
    decl String:name[MAX_NAME_LENGTH];
    decl targets[MAX_CLIENT_IDS];
    new bool:tn_is_ml;
       
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: ft_unflutts <#userid|name>");
		return Plugin_Handled;
	}
    
	GetCmdArg(1, arg, sizeof(arg));
    new num_targets = ProcessTargetString(arg, client, targets, sizeof(targets), 0, name, sizeof(name), tn_is_ml);
                                
    if (num_targets <= 0)
    {
        ReplyToTargetError(client, num_targets);
    }
    else
    {
        for (new i = 0; i < num_targets; i++)
        {
            GetCustomClientName(targets[i], name, sizeof(name));
            PrintToChatAll("%t", "ClearFluttershy", name);
            ClearFluttershy(targets[i], 0);
        }
    }
 
	return Plugin_Handled;
}

/**
 * Command handler for letting a player who disconencted while stunned rejoin the game.
 *
 * @param client Index of the client that sent the command.
 * @param args The number of arguments.
 */
public Action:ForgiveCommand(client, args)
{
    decl String:arg[MAX_NAME_LENGTH];
    decl String:name[MAX_NAME_LENGTH];
    decl targets[MAX_CLIENT_IDS];
	decl String:steam_id[100];
    new bool:tn_is_ml;
       
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: ft_forgive <#userid|name>");
		return Plugin_Handled;
	}
    
	GetCmdArg(1, arg, sizeof(arg));
    new num_targets = ProcessTargetString(arg, client, targets, sizeof(targets), 0, name, sizeof(name), tn_is_ml);
                                
    if (num_targets <= 0)
    {
        ReplyToTargetError(client, num_targets);
    }
    else
    {
        for (new i = 0; i < num_targets; i++)
        {
			GetClientAuthString(targets[i], steam_id, sizeof(steam_id));
			for (new j = 0; j < num_dc_while_stunned; j++)
			{
				if (StrEqual(steam_id, dc_while_stunned[j]))
				{
					GetCustomClientName(client, name, sizeof(name));
					PrintToChatAll("%t", "PlayerForgiven", name);
					dc_while_stunned[j] = "";
					break;
				}
			}
        }
    }
 
	return Plugin_Handled;
}

/**
 * Turns a player into a Fluttershy.
 *
 * @param client Index of the player to turn into a Fluttershy.
 */
MakeFluttershy(client)
{
    decl String:name[MAX_NAME_LENGTH];
    
    if (!is_fluttershy[client])
    {          
        GetCustomClientName(client, name, sizeof(name));
        PrintToChatAll("%t", "MadeFluttershy", name);
        is_fluttershy[client] = true;
        ChangeClientTeam(client, TEAM_BLU);
        TF2_SetPlayerClass(client, TFClass_Medic);
        TF2_RespawnPlayer(client);
        RegenVanilla(client);
        displayed_health[client] = max_hp - ((max_hp / 1000) * 1000);
        if (displayed_health[client] <= 0) displayed_health[client] = 1000;
        current_health[client] = max_hp;
        SetEntityHealth(client, displayed_health[client]);
        PrintToChatAll("%t", "CurrentHealth", name, current_health[client]);
        StartBeacon(client);
    }
}

/**
 * Removes Fluttershy status from a player.
 *
 * @param client The index of the player to remove Fluttershy status from.
 * @param attacker The index of the player who caused the Fluttershy status to be removed.
 *                 0 represents an unknown source (e.g. clearing through the admin command).
 */
ClearFluttershy(client, attacker)
{
    if (is_fluttershy[client])
    {
        is_fluttershy[client] = false;
        bypass_immunity[client] = true;
        KillPlayer(client, attacker);
        ChangeClientTeam(client, TEAM_BLU);
        TF2_SetPlayerClass(client, DEFAULT_CLASS);
        TF2_RespawnPlayer(client);
        RegenVanilla(client);
        StopBeacon(client);
        CheckWinCondition();
    }
}

// From pheadxdll's Roll the Dice mod (http://forums.alliedmods.net/showthread.php?t=75561)
// Modified by Dr. McKay (http://forums.alliedmods.net/showthread.php?p=1710929)
/**
 * Kills a player while correctly identifying the killer and weapon in the killboard.
 *
 * @param client The index of the player to kill.
 * @param attacker The index of the player to credit the kill with.
 */
KillPlayer(client, attacker) 
{ 
    new ent = CreateEntityByName("env_explosion"); 
     
    if (IsValidEntity(ent)) 
    { 
        DispatchKeyValue(ent, "iMagnitude", "5000"); 
        DispatchKeyValue(ent, "iRadiusOverride", "2"); 
        SetEntPropEnt(ent, Prop_Data, "m_hInflictor", attacker); 
        SetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity", attacker); 
        DispatchKeyValue(ent, "spawnflags", "3964"); 
        DispatchSpawn(ent); 
         
        new Float:pos[3]; 
        GetClientAbsOrigin(client, pos); 
        TeleportEntity(ent, pos, NULL_VECTOR, NULL_VECTOR); 
        AcceptEntityInput(ent, "explode", client, client); 
        CreateTimer(0.2, RemoveExplosion, ent); 
    } 
} 

// From pheadxdll's Roll the Dice mod (http://forums.alliedmods.net/showthread.php?t=75561)
// Modified by Dr. McKay (http://forums.alliedmods.net/showthread.php?p=1710929)
/**
 * Timer handled for removing the explosion used to kill a player.
 *
 * @param timer The handle to the timer that triggered this handler.
 * @param ent The explosition entity to remove.
 */
public Action:RemoveExplosion(Handle:timer, any:ent) 
{ 
    if (IsValidEntity(ent)) 
    { 
        decl String:edictname[128]; 
        GetEdictClassname(ent, edictname, 128); 
        if(StrEqual(edictname, "env_explosion")) 
        { 
            RemoveEdict(ent); 
        } 
    } 
}  

/**
 * Handler for the player attempting to join a team.
 *
 * @param client Index of the player.
 * @param command The name of the command.
 * @param argc The number of arguments.
 * @return Plugin_Handled to block the command, otherwise Plugin_Changed.
 */
public Action:JoinTeamCommand(client, const String:command[], argc)
{
    decl String:team[10];
    decl String:name[MAX_NAME_LENGTH];
    
    GetCmdArg(1, team, sizeof(team));
    if (IsClientObserver(client) && !ShouldShame(client))
    {
        return Plugin_Continue;
    }
    else if (StrEqual(team, "spectate"))
    {
        SpectateCommand(client, "spectate", 0);
        return Plugin_Continue;
    }
    else if (ShouldShame(client))
    {
        GetCustomClientName(client, name, sizeof(name));
        PrintToChatAll("%t", "ShameAll", name);
        PrintToChat(client, "%t", "ShamePlayer");
        return Plugin_Handled;
    }
    else
    {
        return Plugin_Handled;
    }
}

/**
 * Handler for commands that a Fluttershy or stunned player should not be allowed to run.
 *
 * @param client Index of the player.
 * @param command The name of the command.
 * @param argc The number of arguments.
 * @return Plugin_Handled to block the command, otherwise Plugin_Changed.
 */
public Action:BlockCommandFluttershy(client, const String:command[], argc)
{
    if (is_fluttershy[client] || TF2_IsPlayerInCondition(client, TFCond_Dazed))
        return Plugin_Handled;
    else if (StrEqual(command, "kill", false) || StrEqual(command, "explode", false))
    {
        ForcePlayerSuicide(client);
        TF2_RespawnPlayer(client);
        return Plugin_Handled;
    }
    else
        return Plugin_Continue;
}

/**
 * Handler for the spectate command.
 *
 * @param client Index of the player.
 * @param command The name of the command.
 * @param argc The number of arguments.
 * @return Plugin_Handled to block the command, otherwise Plugin_Changed.
 */
public Action:SpectateCommand(client, const String:command[], argc)
{
    if (!IsClientObserver(client))
        OnClientDisconnect(client);
    return Plugin_Continue;
}

/**
 * Handler for a player trying to change class.
 *
 * @param client Index of the player.
 * @param command The name of the command.
 * @param argc The number of arguments.
 * @return Plugin_Handled to block the command, otherwise Plugin_Changed.
 */
public Action:JoinClassCommand(client, const String:command[], argc)
{
    decl String:class[10];
    
    GetCmdArg(1, class, sizeof(class));
	
    if (is_fluttershy[client])
    {
        PrintToChat(client, "%t", "FluttershyClassError");
        return Plugin_Handled;
    }
    else if (TF2_IsPlayerInCondition(client, TFCond_Dazed))
    {
        PrintToChat(client, "%t", "FrozenClassError");
        return Plugin_Handled;
    }
    else if (GetGameTime() - round_start_time > FREE_CLASS_CHANGE_TIME && last_class_change[client] + class_change_time_limit > GetGameTime())
    {
        PrintToChat(client, "%t", "TooSoonClassError", RoundToNearest(last_class_change[client] + class_change_time_limit - GetGameTime()));
        return Plugin_Handled;
    }
    else if (!IsRedClassAllowed(class))
    {
        ShowVGUIPanel(client, "class_red");
        return Plugin_Handled;
    }
    else
    {
        // Handle class change manually
        new TFClassType:class_enum = ClassNameToEnum(class);
        if (class_enum != TFClass_Unknown)
        { 
            if (reload_timer[client] != INVALID_HANDLE)
            {
                KillTimer(reload_timer[client]);
                reload_timer[client] = INVALID_HANDLE;
            }
            TF2_SetPlayerClass(client, class_enum);
            RegenVanilla(client);
			if (!IsPlayerAlive(client))
				RespawnPlayer(client);
            last_class_change[client] = GetGameTime();
        }
        return Plugin_Handled;
    }
}

/**
 * Finds the TFClassType enum matching the class name.
 * 
 * @param class The name of the class (from the joinclass command).
 * @return The class if the name is valid, otherwise TFClass_Unknown.
 */
TFClassType:ClassNameToEnum(const String:class[])
{
    if (StrEqual(class, "heavyweap", false))
        return TFClass_Heavy;
    else
        return TF2_GetClass(class);
}

/**
 * Check if a class allowed for RED players.
 *
 * @param class The name of the class that the player is attempting to join (from the joinclass command).
 * @return True if the class is allowed, otherwise false.
 */
bool:IsRedClassAllowed(const String:class[])
{
    new TFClassType:class_enum = TF2_GetClass(class);
    return IsRedClassAllowedByEnum(class_enum);
}

/** 
 * Check if a class is allowed for RED players.
 *
 * @param class The class that the player is attempting to join.
 * @return True if the class is allowed, otherwise false.
 */
bool:IsRedClassAllowedByEnum(TFClassType:class)
{
    return !(class == TFClass_Medic || class == TFClass_Engineer || class == TFClass_Spy || class == TFClass_Unknown);
}

/**
 * Check if the game has been won and list the winners if it has.
 */
CheckWinCondition(bool:round_end = false)
{
    decl String:sound_path[PLATFORM_MAX_PATH];
    new bool:fluttershy_exists = false;
    new bool:all_players_stunned = true;
    new clientid;
    
    if (win_conditions_checked)
        return;
    
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsClientObserver(i))
        {
            if (is_fluttershy[i])
            {
                fluttershy_exists = true;
            }
            else if (!TF2_IsPlayerInCondition(i, TFCond_Dazed))
            {
                all_players_stunned = false;
            }
        }
    }
    
    if (!fluttershy_exists)
    {
        GetArrayString(sounds[SND_LOSS], GetRandomInt(0, GetArraySize(sounds[SND_LOSS]) - 1), sound_path, sizeof(sound_path));
        EmitSoundToAll(sound_path, _, _, SNDLEVEL_DEFAULT);
        PrintToChatAll("%t", "FluttershyLose");
        PrintToChatAll("%t", "Winners");
        for (new i = 0; i < num_killers; i++)
        {
            clientid = GetClientOfUserId(killer[i]) ;
            if (clientid > 0 && IsClientInGame(clientid))
                PrintToChatAll("- %N", clientid);
        }
        
        win_conditions_checked = true;
        SetVariantInt(TEAM_RED);
        AcceptEntityInput(master_cp, "SetWinner");
    }
    else if (all_players_stunned || round_end)
    {
        GetArrayString(sounds[SND_WIN], GetRandomInt(0, GetArraySize(sounds[SND_WIN]) - 1), sound_path, sizeof(sound_path));
        EmitSoundToAll(sound_path);
        PrintToChatAll("%t", "FluttershyWin");
        PrintToChatAll("%t", "Winners");
        for (new i = 1; i <= MaxClients; i++)
        {
            if (is_fluttershy[i])
                PrintToChatAll("- %N", i);
        }
        for (new i = 0; i < num_killers; i++)
        {
            clientid = GetClientOfUserId(killer[i]) ;
            if (clientid > 0 && IsClientInGame(clientid))
                PrintToChatAll("- %N", clientid);
        }     
      
        win_conditions_checked = true;
        
        if (!round_end)
        {
            SetVariantInt(TEAM_BLU);
            AcceptEntityInput(master_cp, "SetWinner");
        }
    }
}

StartBeacon(client)
{
    if (beacon_timer[client] == INVALID_HANDLE)
    {
        if (is_fluttershy[client])
        {
            beacon_radius[client] = 275.0;
            beacon_timer[client] = CreateTimer(1.0, SpawnBeacon, client, TIMER_REPEAT);
        }
        else
        {
            beacon_radius[client] = 0.0;
            beacon_timer[client] = CreateTimer(1.8, SpawnBeacon, client, TIMER_REPEAT);
        }
    }
}

StopBeacon(client)
{
    if (beacon_timer[client] != INVALID_HANDLE)
    {
        KillTimer(beacon_timer[client]);
        beacon_timer[client] = INVALID_HANDLE;
    }
}

/**
 * Timer handler for making a beacon.
 *
 * @param timer A handle to the timer that triggered this callback.
 * @param client Index of the client.
 */
public Action:SpawnBeacon(Handle:timer, any:client)
{
    decl Float:position[3];
    decl color[4];
    
    if (client > 0 && IsClientInGame(client) && !IsClientObserver(client))
    {
        GetClientAbsOrigin(client, position);
        position[2] += 20;
        
        
        
        if (is_fluttershy[client])
        {
            color = {0, 0, 255, 255};
        }
        else
        {
            color = {255, 0, 0, 255};
            if (beacon_radius[client] < 800)
                beacon_radius[client] += 40.0;
        }
            
        TE_SetupBeamRingPoint(position, 40.0, beacon_radius[client], ring_model, halo_model, 0, 15, 0.5, 30.0, 0.0, color, 10, 0);
        TE_SendToAll();
    } else {
        StopBeacon(client);
    }
}

public PostInventoryApplication(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
    SetVanillaWeapons(client);
}

RegenVanilla(client)
{
    TF2_RegeneratePlayer(client);
    SetVanillaWeapons(client);
}

SetVanillaWeapons(client)
{
    TF2_RemoveWeaponSlot(client, 0);
    TF2_RemoveWeaponSlot(client, 1);
    TF2_RemoveWeaponSlot(client, 2);
    
    switch (TF2_GetPlayerClass(client))
    {
    case TFClass_Scout:
    {
        TF2Items_GiveWeapon(client, -1004);
        TF2Items_GiveWeapon(client, -1007);
        TF2Items_GiveWeapon(client, 0);
    }
    case TFClass_DemoMan:
    {
        TF2Items_GiveWeapon(client, -1002);
        TF2Items_GiveWeapon(client, -1003);
        TF2Items_GiveWeapon(client, 1);
    }
    case TFClass_Pyro:
    {
        TF2Items_GiveWeapon(client, 21);
        TF2Items_GiveWeapon(client, 12);
        TF2Items_GiveWeapon(client, 2);
    }
    case TFClass_Sniper:
    {
        TF2Items_GiveWeapon(client, -1006);
        TF2Items_GiveWeapon(client, -1005);
        TF2Items_GiveWeapon(client, 3);
    }
    case TFClass_Spy:
    {
        TF2Items_GiveWeapon(client, 24);
        // Can't give sapper?
        TF2Items_GiveWeapon(client, 4);
    }
    case TFClass_Heavy:
    {
        TF2Items_GiveWeapon(client, -1000);
        TF2Items_GiveWeapon(client, 11);
        TF2Items_GiveWeapon(client, 5);
    }
    case TFClass_Soldier:
    {
        TF2Items_GiveWeapon(client, 18);
        TF2Items_GiveWeapon(client, 10);
        TF2Items_GiveWeapon(client, 6);
    }
    case TFClass_Engineer:
    {
        TF2Items_GiveWeapon(client, 9);
        TF2Items_GiveWeapon(client, 22);
        TF2Items_GiveWeapon(client, 7);
    }
    case TFClass_Medic:
    {
        TF2Items_GiveWeapon(client, -1001);
    }
    }
}