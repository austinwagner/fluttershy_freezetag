#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"
#define CVAR_FLAGS FCVAR_PLUGIN | FCVAR_NOTIFY
#define MAX_CLIENT_IDS MAXPLAYERS + 1
#define MAX_DC_PROT 64
#define TEAM_RED 2
#define TEAM_BLU 3
#define SND_FREEZE 0
#define SND_UNFREEZE 1
#define SND_WIN 2
#define SND_LOSS 3
#define PREVENT_DEATH_HP 3000
#define SHAME_STUN_DURATION 5000.0
#define SLOT_MELEE 2
#define SLOT_PRIMARY 0

public Plugin:myinfo =
{
	name = "Fluttershy Freeze Tag",
	author = "Ambit (idea by RogueDarkJedi)",
	description = "Defeat the Fluttershys before they freeze everyone.",
	version = PLUGIN_VERSION,
	url = ""
};

new Handle:sounds[4];

new original_ff_val;
new original_scramble_teams_val;
new original_teams_unbalance_val;
new original_autobalance_val;

new Handle:ff_cvar;
new Handle:scramble_teams_cvar;
new Handle:teams_unbalance_cvar;
new Handle:autobalance_cvar;

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

new bool:is_fluttershy[MAX_CLIENT_IDS];
new displayed_health[MAX_CLIENT_IDS];
new current_health[MAX_CLIENT_IDS];
new bool:bypass_immunity[MAX_CLIENT_IDS];
new bool:stun_immunity[MAX_CLIENT_IDS];
new String:dc_while_stunned[MAX_DC_PROT][20];
new bool:airblast_cooldown[MAX_CLIENT_IDS];
new Handle:airblast_timer[MAX_CLIENT_IDS];
new killer[4];
new num_killers;
new num_dc_while_stunned;
new ammo_offset;
new Handle:reload_timer[MAX_CLIENT_IDS];
new master_cp = -1;
new bool:win_conditions_checked;


public OnPluginStart()
{    
    LoadTranslations("freezetag.phrases");
    max_hp_cvar = CreateConVar("freezetag_max_hp", "2000", "The amount of life Fluttershys start with.", CVAR_FLAGS);
    freeze_duration_cvar = CreateConVar("freezetag_freeze_time", "120.0", "The amount of time in seconds a player will remain frozen for before automatically unfreezing.", CVAR_FLAGS);
    freeze_immunity_cvar = CreateConVar("freezetag_immunity_time", "2.0", "The amount of time in seconds during which a player cannot be unfrozen or refrozen.", CVAR_FLAGS);
    enabled_cvar = CreateConVar("freezetag_enabled", "0", "0 to disable, 1 to enable.", CVAR_FLAGS);
    minigun_reload_time_cvar = CreateConVar("freezetag_minigun_reload", "10.0", "The amount of time in seconds it takes to reload a player's Minigun.", CVAR_FLAGS);
    flamethrower_reload_time_cvar = CreateConVar("freezetag_flamethrower_reload", "10.0", "The amount of time in seconds it takes to reload a player's Flamethrower.", CVAR_FLAGS);
    minigun_ammo_cvar = CreateConVar("freezetag_minigun_ammo", "50", "The maximum number of bullets a Minigun can hold.", CVAR_FLAGS);
    flamethrower_ammo_cvar = CreateConVar("freezetag_flamethrower_ammo", "100", "The maximum amount of ammo a Flamethrower can hold.", CVAR_FLAGS);
    airblast_cooldown_time_cvar = CreateConVar("freezetag_airblast_cooldown", "5.0", "The amount of time in seconds before a Pyro can airblast again.", CVAR_FLAGS);
    round_time_cvar = CreateConVar("freezetag_round_time", "300", "The amount of time in seconds that a round will last.", CVAR_FLAGS);
    fluttershy_ratio_cvar = CreateConVar("freezetag_player_ratio", "9", "1 out of this many players will be selected as a Fluttershy.", CVAR_FLAGS);
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
    
    ff_cvar = FindConVar("mp_friendlyfire");
    scramble_teams_cvar = FindConVar("mp_scrambleteams_auto");
    teams_unbalance_cvar = FindConVar("mp_teams_unbalance_limit");
    autobalance_cvar = FindConVar("mp_autoteambalance");
    
    LoadConVars();
    
    RegAdminCmd("unfreeze", UnfreezePlayerCommand, ADMFLAG_GENERIC);
    RegAdminCmd("freeze", FreezePlayerCommand, ADMFLAG_GENERIC);
    RegAdminCmd("flutts", MakeFluttershyCommand, ADMFLAG_GENERIC);
    RegAdminCmd("unflutts", ClearFluttershyCommand, ADMFLAG_GENERIC);
    
    ammo_offset = FindSendPropOffs("CTFPlayer", "m_iAmmo");
    
    AutoExecConfig(true, "freezetag");
    
    LoadSoundConfig();
    
    if (enabled)
        EnablePlugin();
}

LoadSoundConfig()
{
    decl String:line[PLATFORM_MAX_PATH];
    decl String:full_path[PLATFORM_MAX_PATH];
    new Handle:file = OpenFile("cfg\\sourcemod\\freezetagsounds.cfg", "r");
    new section = -1;
    
    for (new i = 0; i < sizeof(sounds); i++)
    {
        sounds[i] = CreateArray(PLATFORM_MAX_PATH, 0);
    }
    
    if (file != INVALID_HANDLE)
    {
        while (ReadFileLine(file, line, sizeof(line)))
        {
            TrimString(line);
            if (StrEqual(line, "[FreezeSounds]", false))
                section = SND_FREEZE;
            else if (StrEqual(line, "[UnfreezeSounds]", false))
                section = SND_UNFREEZE;
            else if (StrEqual(line, "[WinSounds]", false))
                section = SND_WIN;
            else if (StrEqual(line, "[LossSounds]", false))
                section = SND_LOSS;
            else if (section >= 0 && line[0] != '\0')
            {
                full_path = "sound\\";
                StrCat(full_path, sizeof(full_path), line);
                if (FileExists(full_path))
                    PushArrayString(sounds[section], line);
                else
                    LogError("%T", "FileNoExist", LANG_SERVER, full_path);
            }
        }
    }
    else
    {
        LogError("%T", "SoundConfFail", LANG_SERVER);
    }
}

public Action:RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
    CheckWinCondition();
}

public Action:RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    num_killers = 0;
    num_dc_while_stunned = 0;
    win_conditions_checked = false;
    
    for (new i = 0; i < MAX_DC_PROT; i++)
    {
        dc_while_stunned[i] = "";
    }
    
    // Move everyone to RED and reset all of the arrays
    new num_red = 0;
    for (new i = 1; i <= MaxClients; i++)
    {
        is_fluttershy[i] = false;
        bypass_immunity[i] = false;
        stun_immunity[i] = false;
        
        if (IsClientInGame(i) && !IsClientObserver(i))
        {
            ChangeClientTeam(i, TEAM_RED);
            num_red++;
        }
    }
    
    // Select players to become Fluttershys
    new num_fluttershys = 0;
    new fshy_goal = RoundToCeil(FloatMul(float(num_red), fluttershy_ratio));
    while (num_fluttershys < fshy_goal)
    {
        new client = GetRandomInt(1, MaxClients);
        if (IsClientInGame(client) && !IsClientObserver(client) && !is_fluttershy[client])
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
}

public ConVarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
    LoadConVars2();
}

LoadConVars()
{
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
    enabled = GetConVarBool(enabled_cvar);
}

// Temp workaround
LoadConVars2()
{
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

    if (enabled != GetConVarBool(enabled_cvar))
    {
        enabled = GetConVarBool(enabled_cvar);
        if (enabled)
            EnablePlugin();
        else
            DisablePlugin();
    }
}

EnablePlugin()
{
    original_ff_val = GetConVarInt(ff_cvar);
    original_scramble_teams_val = GetConVarInt(scramble_teams_cvar);
    original_teams_unbalance_val = GetConVarInt(teams_unbalance_cvar);
    original_autobalance_val = GetConVarInt(autobalance_cvar);
    
    SetConVarInt(ff_cvar, 1);
    SetConVarInt(scramble_teams_cvar, 0);
    SetConVarInt(teams_unbalance_cvar, 0);
    SetConVarInt(autobalance_cvar, 0);
    
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
            OnClientPutInServer(i);
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
    
    ServerCommand("mp_restartgame_immediate 1");
}

DisablePlugin()
{
    SetConVarInt(ff_cvar, original_ff_val);
    SetConVarInt(scramble_teams_cvar, original_scramble_teams_val);
    SetConVarInt(teams_unbalance_cvar, original_teams_unbalance_val);
    SetConVarInt(autobalance_cvar, original_autobalance_val);
    
    RemoveCommandListener(JoinTeamCommand, "jointeam");
    RemoveCommandListener(JoinClassCommand, "joinclass");
    RemoveCommandListener(BlockCommandFluttershy, "kill");
    RemoveCommandListener(SpectateCommand, "spectate");
    RemoveCommandListener(BlockCommandFluttershy, "explode");
    
    UnhookEvent("teamplay_round_start", RoundStart, EventHookMode_Pre);
    UnhookEvent("teamplay_round_win", RoundEnd);
    UnhookEvent("teamplay_round_stalemate", RoundEnd);
    
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
    }   
     
    ServerCommand("mp_scrambleteams");
    ServerCommand("mp_restartgame_immediate 1");
}

public OnMapStart()
{
    decl String:path[PLATFORM_MAX_PATH];
    new size;
    
    LoadTranslations("freezetag.phrases");
    
    for (new i = 0; i < sizeof(sounds); i++)
    {
        size = GetArraySize(sounds[i]);
        for (new j = 0; j < size; j++)
        {
            GetArrayString(sounds[i], j, path, sizeof(path));
            LoadSound(path);
        }
    }
}

LoadSound(String:sound[])
{
    decl String:path[PLATFORM_MAX_PATH];
    
    path = "sound\\";
    StrCat(path, sizeof(path), sound);
    AddFileToDownloadsTable(path);
    PrecacheSound(sound, true);
}

public PreThinkPost(client) 
{
    if (IsClientObserver(client))
        return;

    if (is_fluttershy[client] && GetPlayerWeaponSlot(client, SLOT_MELEE) > 0)
        SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", GetPlayerWeaponSlot(client, SLOT_MELEE));
    
    if (!is_fluttershy[client] && TF2_GetPlayerClass(client) == TFClass_Scout)
        SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", 300.0);
    
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
            PrintToChat(client, "%t", "MinigunReloading");
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
            PrintToChat(client, "%t", "FlamethrowerReloading");
            SetEntData(client, ammo_offset + 4, 0, 4);
            reload_timer[client] = CreateTimer(flamethrower_reload_time, ReloadFlamethrower, client);
        }
    }
    else
    {
        SetEntData(client, ammo_offset + 4, 99, 4);
    }
    
    SetEntData(client, ammo_offset + 8, 99, 4);
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
    if (enabled)
    {
        if (airblast_cooldown[client] && TF2_GetPlayerClass(client) == TFClass_Pyro)
        {
            buttons &= ~IN_ATTACK2;
        }
        else if (buttons & IN_ATTACK2 == IN_ATTACK2 && TF2_GetPlayerClass(client) == TFClass_Pyro)
        {
            airblast_cooldown[client] = true;
            airblast_timer[client] = CreateTimer(airblast_cooldown_time, ResetAirblast, client);
        }
        
        return Plugin_Changed;
    }
    
    return Plugin_Continue;
}

public Action:ResetAirblast(Handle:timer, any:client)
{
    if (IsClientInGame(client) && !IsClientObserver(client))
    {
        airblast_cooldown[client] = false;
    }
    airblast_timer[client] = INVALID_HANDLE;
}

public Action:ReloadMinigun(Handle:timer, any:client)
{
    if (IsClientInGame(client) && !IsClientObserver(client))
    {
        PrintToChat(client, "%t", "MinigunReloaded");
        SetEntData(client, ammo_offset + 4, minigun_ammo, 4);  
    }
    reload_timer[client] = INVALID_HANDLE;
}

public Action:ReloadFlamethrower(Handle:timer, any:client)
{
    if (IsClientInGame(client) && !IsClientObserver(client))
    {
        PrintToChat(client, "%t", "FlamethrowerReloaded");
        SetEntData(client, ammo_offset + 4, flamethrower_ammo, 4);    
    }
    reload_timer[client] = INVALID_HANDLE;
}

public OnPluginEnd()
{
    if (enabled)
        DisablePlugin();
}

public OnClientPutInServer(client)
{
    if (enabled)
    {
        SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
        SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
        SDKHook(client, SDKHook_WeaponCanSwitchTo, WeaponCanSwitchTo);
        SDKHook(client, SDKHook_WeaponCanUse, WeaponCanSwitchTo);
        SDKHook(client, SDKHook_Spawn, OnSpawn);
        SDKHook(client, SDKHook_PreThinkPost, PreThinkPost);
        ChangeClientTeam(client, TEAM_RED);
    }
}

public OnClientDisconnect(client)
{
    decl String:steam_id[20];
    
    if (enabled)
    {
        is_fluttershy[client] = false;
            
        if (TF2_IsPlayerInCondition(client, TFCond_Dazed))
        {
            GetClientAuthString(client, steam_id, sizeof(steam_id));
            dc_while_stunned[num_dc_while_stunned % MAX_DC_PROT] = steam_id;
            num_dc_while_stunned++;
        }
            
        is_fluttershy[client] = false;
        bypass_immunity[client] = false;
        stun_immunity[client] = false;
        
        CheckWinCondition();
        
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
    }
}

public Action:OnSpawn(client)
{
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
        TF2_SetPlayerClass(client, TFClass_Soldier);
        TF2_RespawnPlayer(client);
        ShowVGUIPanel(client, "class_red"); 
    }
    
    return Plugin_Continue;
}

bool:ShouldShame(client)
{
    decl String:steam_id[20];
    
    GetClientAuthString(client, steam_id, sizeof(steam_id));
    
    for (new i = 0; i < MAX_DC_PROT; i++)
    {
        if (StrEqual(steam_id, dc_while_stunned[i]))
            return true;
    }
    
    return false;
}

public Action:WeaponCanSwitchTo(client, weapon)
{
    if (!is_fluttershy[client] || GetPlayerWeaponSlot(client, SLOT_MELEE) < 0 || weapon == GetPlayerWeaponSlot(client, SLOT_MELEE))
        return Plugin_Continue;
    else
        return Plugin_Handled;
}

public OnGameFrame()
{
    if (enabled)
    {
        // This reverses the health degeneration of the Fluttershys
        for (new i = 0; i < sizeof(is_fluttershy); i++)
        {
            if (is_fluttershy[i])
                SetEntityHealth(i, displayed_health[i]);
        }
    }
}

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
                PrintToChat(victim, "%t", "CurrentHealth", current_health[victim]);
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
        // Damage doesn't get modified by crits or distance until after OnTakeDamage has run
        // Since we need to wait for OnTakeDamage to complete, set the player's health 
        // very high to prevent them from dying during OnTakeDamage. We will force the player
        // to die later if necessary
        SetEntityHealth(victim, PREVENT_DEATH_HP);
        
        return Plugin_Changed;
    }
        
    // If enemy is hit and not frozen, freeze him. Damage done by the environment can never freeze a player.
    if (attacker != 0 && GetClientTeam(victim) != GetClientTeam(attacker) && !TF2_IsPlayerInCondition(victim, TFCond_Dazed))
    {
        FreezePlayer(victim, attacker);
    }
    // If ally is hit and frozen, unfreeze him
    else if (attacker != 0 && GetClientTeam(victim) == GetClientTeam(attacker) && TF2_IsPlayerInCondition(victim, TFCond_Dazed) && weapon == GetPlayerWeaponSlot(attacker, 2))
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

// Check if the id that did damage belongs to the world insta-kill
bool:IsWorldDeath(attacker)
{
    // Entity IDs 1 to MaxClients are reserved for players
    // Any damage done by a non player entity must be outside of this range
    return attacker > MaxClients;
}

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
        EmitSoundToAll(sound_path, attacker);
        PrintToChatAll("%t", "PlayerFrozen", victim_name, attacker_name);
        CreateTimer(freeze_immunity_time, RemoveFreezeImmunity, GetClientUserId(victim));
        TF2_RemoveCondition(victim, TFCond_Dazed); // Prevent bonk from blocking admin freeze
        TF2_StunPlayer(victim, freeze_duration, 0.0, TF_STUNFLAG_BONKSTUCK, attacker);
        stun_immunity[victim] = true;
        CheckWinCondition();
    }
}

UnfreezePlayer(victim, attacker)
{
    decl String:victim_name[MAX_NAME_LENGTH];
    decl String:attacker_name[MAX_NAME_LENGTH];
    decl String:sound_path[PLATFORM_MAX_PATH];
    
    GetCustomClientName(victim, victim_name, sizeof(victim_name));
    GetCustomClientName(attacker, attacker_name, sizeof(attacker_name));
    
    if (!stun_immunity[victim] && TF2_IsPlayerInCondition(victim, TFCond_Dazed))
    {
        GetArrayString(sounds[SND_UNFREEZE], GetRandomInt(0, GetArraySize(sounds[SND_UNFREEZE]) - 1), sound_path, sizeof(sound_path));
        EmitSoundToAll(sound_path, victim);
        PrintToChatAll("%t", "PlayerUnfrozen", victim_name, attacker_name);
        TF2_RemoveCondition(victim, TFCond_Dazed);
        stun_immunity[victim] = true;
        CreateTimer(freeze_immunity_time, RemoveFreezeImmunity, GetClientUserId(victim));
    }
}

public Action:RemoveFreezeImmunity(Handle:timer, any:user_id)
{
    new client = GetClientOfUserId(user_id);
    if (client > 0 && IsClientInGame(client))
        stun_immunity[client] = false;
}

GetCustomClientName(client, String:name[], length)
{
    if (client < 1)
        strcopy(name, length, "The Guardians");
    else
        GetClientName(client, name, length);
}

// Handle debug/admin unfreeze command
public Action:UnfreezePlayerCommand(client, args)
{
    decl String:name[MAX_NAME_LENGTH];
    
    name[0] = '\0';
    GetCmdArgString(name, sizeof(name));
     
    new target = SelectPlayer(client, UnfreezePlayerMenuHandler, name);
    if (target > 0)
        UnfreezePlayer(client, 0);
        
    return Plugin_Handled;
}

// Handle debug/admin freeze command
public Action:FreezePlayerCommand(client, args)
{
    decl String:name[MAX_NAME_LENGTH];
    
    name[0] = '\0';
    GetCmdArgString(name, sizeof(name));
     
    new target = SelectPlayer(client, FreezePlayerMenuHandler, name);
    if (target > 0)
        FreezePlayer(client, 0);
        
    return Plugin_Handled;
}


// Handle debug/admin flutts command
public Action:MakeFluttershyCommand(client, args)
{
    decl String:name[MAX_NAME_LENGTH];
    
    name[0] = '\0';
    GetCmdArgString(name, sizeof(name));
     
    new target = SelectPlayer(client, MakeFluttershyMenuHandler, name);
    if (target > 0)
        MakeFluttershy(target);
        
    return Plugin_Handled;
}

// Selects a player by name, defaulting to a menu if no name is specified.
// Prints a message to the client if the player name is not found or if more
// than one player matches the search string. The name "@me" will return the
// id of the client making the request.
//
// @param client The client who is performing the action
// @param handler A fallback menu handler if the client selects the name using the menu
// @param search_name The player name to search for
// @return The client ID of the player if found, otherwise -1
SelectPlayer(client, MenuHandler:handler, String:search_name[])
{
    decl String:user_id[16];
    decl String:name[MAX_NAME_LENGTH];
    
    if (search_name[0] == '\0')
    {
        new Handle:menu = CreateMenu(handler);
        SetMenuTitle(menu, "Select a player:");
        for (new i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                GetClientName(i, name, sizeof(name));
                IntToString(GetClientUserId(i), user_id, sizeof(user_id));
                AddMenuItem(menu, user_id, name);
            }
        }
        
        SetMenuExitButton(menu, true);
        DisplayMenu(menu, client, 20);
        
        return -1;
    }
    else if (StrEqual(search_name, "@me", false))
    {
        return client;
    }
    else
    { 
        new target = -1;
        new startidx = 0;
        
        if (search_name[0] == '"')
        {
            startidx = 1;
            new len = strlen(search_name);
            if (search_name[len-1] == '"')
            {
                search_name[len-1] = '\0';
            }
        }
        
        for (new i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                GetClientName(i, name, sizeof(name));
                if (StrContains(name, search_name[startidx], false) > -1)
                {
                    if (target != -1)
                    {
                        ReplyToCommand(client, "%t", "AmbiguousPlayer", search_name[startidx]);
                        return -1;
                    }
                    else
                    {
                        target = i;
                    }
                }
            }
        }
        if (target > 0)
        {
            return target;
        }
        else
        {
            ReplyToCommand(client, "%t", "PlayerNotFound", search_name[startidx]);
            return -1;
        }
    }
}

// Handle debug/admin unflutts command
public Action:ClearFluttershyCommand(client, args)
{
    decl String:name[MAX_NAME_LENGTH];
    
    name[0] = '\0';
    GetCmdArgString(name, sizeof(name));
     
    new target = SelectPlayer(client, ClearFluttershyMenuHandler, name);
    if (target > 0)
    {     
        GetCustomClientName(target, name, sizeof(name));
        PrintToChatAll("%t", "ClearFluttershy", name);
        ClearFluttershy(target, 0);
    }
        
    return Plugin_Handled;
}

public ClearFluttershyMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
    decl String:info[32];
    decl String:name[MAX_NAME_LENGTH];

    if (action == MenuAction_Select)
    {
        GetMenuItem(menu, param2, info, sizeof(info));
        new target = GetClientOfUserId(StringToInt(info));
        if (IsClientInGame(target))
        {
            GetCustomClientName(target, name, sizeof(name));
            PrintToChatAll("%t", "ClearFluttershy", name);
            ClearFluttershy(target, 0);
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
}

public MakeFluttershyMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
    decl String:info[32];

    if (action == MenuAction_Select)
    {
        GetMenuItem(menu, param2, info, sizeof(info));
        new target = GetClientOfUserId(StringToInt(info));
        if (IsClientInGame(target))
            MakeFluttershy(target);
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
}

public UnfreezePlayerMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
    decl String:info[32];

    if (action == MenuAction_Select)
    {
        GetMenuItem(menu, param2, info, sizeof(info));
        new target = GetClientOfUserId(StringToInt(info));
        if (IsClientInGame(target))
            UnfreezePlayer(target, 0);
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
}

public FreezePlayerMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
    decl String:info[32];

    if (action == MenuAction_Select)
    {
        GetMenuItem(menu, param2, info, sizeof(info));
        new target = GetClientOfUserId(StringToInt(info));
        if (IsClientInGame(target))
            FreezePlayer(target, 0);
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
}

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
        TF2_RegeneratePlayer(client);
        displayed_health[client] = max_hp < 1000 ? max_hp : 1000;
        current_health[client] = max_hp;
        SetEntityHealth(client, displayed_health[client]);
    }
}

ClearFluttershy(client, attacker)
{
    if (is_fluttershy[client])
    {
        is_fluttershy[client] = false;
        bypass_immunity[client] = true;
        KillPlayer(client, attacker);
        ChangeClientTeam(client, TEAM_BLU);
        TF2_SetPlayerClass(client, TFClass_Soldier);
        TF2_RespawnPlayer(client);
        TF2_RegeneratePlayer(client);
        CheckWinCondition();
    }
}

// From pheadxdll's Roll the Dice mod (http://forums.alliedmods.net/showthread.php?t=75561)
// Modified by Dr. McKay (http://forums.alliedmods.net/showthread.php?p=1710929)
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

public Action:BlockCommandFluttershy(client, const String:command[], argc)
{
    if (is_fluttershy[client] || TF2_IsPlayerInCondition(client, TFCond_Dazed))
        return Plugin_Handled;
    else
        return Plugin_Continue;
}

public Action:SpectateCommand(client, const String:command[], argc)
{
    if (!IsClientObserver(client))
        OnClientDisconnect(client);
    return Plugin_Continue;
}

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
    else if (!IsRedClassAllowed(class))
    {
        ShowVGUIPanel(client, "class_red");
        return Plugin_Handled;
    }
    else
    {
        // Handle class change manually
        new TFClassType:class_enum;
        if (ClassNameToEnum(class, class_enum))
        { 
            if (reload_timer[client] != INVALID_HANDLE)
            {
                KillTimer(reload_timer[client]);
                reload_timer[client] = INVALID_HANDLE;
            }
            TF2_SetPlayerClass(client, class_enum);
            TF2_RespawnPlayer(client);
            TF2_RegeneratePlayer(client);
        }
        return Plugin_Handled;
    }
}
bool:IsRedClassAllowed(const String:class[])
{
    new TFClassType:class_enum;
    if (ClassNameToEnum(class, class_enum))
        return IsRedClassAllowedByEnum(class_enum);
    else
        return false;
}

bool:IsRedClassAllowedByEnum(TFClassType:class)
{
    return !(class == TFClass_Medic || class == TFClass_Engineer || class == TFClass_Spy);
}

bool:ClassNameToEnum(const String:class[], &TFClassType:class_enum)
{
    if (StrEqual(class, "scout", false))
        class_enum = TFClass_Scout;
    else if (StrEqual(class, "medic", false))
        class_enum = TFClass_Medic;
    else if (StrEqual(class, "sniper", false))
        class_enum = TFClass_Sniper;
    else if (StrEqual(class, "heavyweap", false))
        class_enum = TFClass_Heavy;
    else if (StrEqual(class, "demoman", false))
        class_enum = TFClass_DemoMan;
    else if (StrEqual(class, "spy", false))
        class_enum = TFClass_Spy;
    else if (StrEqual(class, "engineer", false))
        class_enum = TFClass_Engineer;
    else if (StrEqual(class, "soldier", false))
        class_enum = TFClass_Soldier;
    else if (StrEqual(class, "pyro", false))
        class_enum = TFClass_Pyro;
    else
        return false;
    
    return true;
}

CheckWinCondition()
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
        EmitSoundToAll(sound_path);
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
    else if (all_players_stunned)
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
        SetVariantInt(TEAM_BLU);
        AcceptEntityInput(master_cp, "SetWinner");
    }
}