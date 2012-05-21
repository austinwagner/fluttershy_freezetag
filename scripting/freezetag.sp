#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"
#define CVAR_FLAGS FCVAR_PLUGIN | FCVAR_NOTIFY
#define CLEAR_FLUTTERSHY_MSG "The Guardians have rescinded %N's Flutterhood!"
#define MAX_CLIENT_IDS MAXPLAYERS + 1

public Plugin:myinfo =
{
	name = "Fluttershy Freeze Tag",
	author = "Ambit (idea by RogueDarkJedi)",
	description = "Chrysalis is back and has her minions disguised as Fluttershy. Discord added some chaos into the mix by giving them magic sticks that freeze anything they hit. Stop these fakes from freezing everypony before it's too late!",
	version = PLUGIN_VERSION,
	url = ""
};

new String:hit_sounds[3][PLATFORM_MAX_PATH] = { "flutts\\imsorry.mp3", "flutts\\dontbemad.mp3", "flutts\\mycheering.mp3" }
new String:unfreeze_sounds[2][PLATFORM_MAX_PATH] = { "flutts\\1milyrs.mp3", "flutts\\stretching.mp3" }
new String:loss_sound[PLATFORM_MAX_PATH] = { "flutts\\howdareyou.mp3" }
new String:win_sound[PLATFORM_MAX_PATH] = { "misc\\yay.mp3" }

new original_ff_val
new original_disable_respawn_times_val
new original_scramble_teams_val
new original_teams_unbalance_val
new original_autobalance_val
new original_respawnwavetime_val

new Handle:ff_cvar
new Handle:disable_respawn_times_cvar
new Handle:scramble_teams_cvar
new Handle:teams_unbalance_cvar
new Handle:autobalance_cvar
new Handle:respawnwavetime_cvar

new Handle:max_hp_cvar
new Handle:freeze_duration_cvar
new Handle:freeze_immunity_cvar
new Handle:round_restart_cvar
new Handle:enabled_cvar

new max_hp
new Float:freeze_duration
new Float:freeze_immunity_time
new round_restart_time
new bool:enabled

new bool:is_fluttershy[MAX_CLIENT_IDS]
new displayed_health[MAX_CLIENT_IDS]
new current_health[MAX_CLIENT_IDS]
new bool:bypass_immunity[MAX_CLIENT_IDS]
new bool:stun_immunity[MAX_CLIENT_IDS]
new String:dc_while_stunned[128][20]
new killer[4]
new num_killers
new num_fluttershys
new num_red
new num_stunned
new num_dc_while_stunned


public OnPluginStart()
{    
    max_hp_cvar = CreateConVar("freezetag_max_hp", "2000", "The amount of life Fluttershys start with.", CVAR_FLAGS)
    freeze_duration_cvar = CreateConVar("freezetag_freeze_time", "120.0", "The amount of time in seconds a player will remain frozen for before automatically unfreezing.", CVAR_FLAGS)
    freeze_immunity_cvar = CreateConVar("freezetag_immunity_time", "2.0", "The amount of time in seconds during which a player cannot be unfrozen or refrozen.", CVAR_FLAGS)
    round_restart_cvar = CreateConVar("freezetag_round_restart_time", "8", "The amount of time in seconds to wait until starting a new round.", CVAR_FLAGS)
    enabled_cvar = CreateConVar("freezetag_enabled", "0", "0 to disable, 1 to enable.", CVAR_FLAGS)
    CreateConVar("freezetag_version", PLUGIN_VERSION, "Fluttershy Freeze Tag version", CVAR_FLAGS | FCVAR_REPLICATED | FCVAR_DONTRECORD);
    
    HookConVarChange(max_hp_cvar, ConVarChanged)
    HookConVarChange(freeze_duration_cvar, ConVarChanged)
    HookConVarChange(freeze_immunity_cvar, ConVarChanged)
    HookConVarChange(round_restart_cvar, ConVarChanged)
    HookConVarChange(enabled_cvar, ConVarChanged)
    
    LoadConVars()
    
    ff_cvar = FindConVar("mp_friendlyfire")
    disable_respawn_times_cvar = FindConVar("mp_disable_respawn_times")
    scramble_teams_cvar = FindConVar("mp_scrambleteams_auto")
    teams_unbalance_cvar = FindConVar("mp_teams_unbalance_limit")
    autobalance_cvar = FindConVar("mp_autoteambalance")
    respawnwavetime_cvar = FindConVar("mp_respawnwavetime")
    
    // Admin commands (currently not admin only for debugging)
    RegConsoleCmd("unfreeze", UnfreezePlayerCommand)
    RegConsoleCmd("freeze", FreezePlayerCommand)
    RegConsoleCmd("flutts", MakeFluttershyCommand)
    RegConsoleCmd("unflutts", ClearFluttershyCommand)
    
    RegConsoleCmd("ts", TestCmd)
}

public Action:RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    num_killers = 0
    num_fluttershys = 0
    num_red = 0
    num_stunned = 0
    num_dc_while_stunned = 0
    
    for (new i = 0; i < 128; i++)
    {
        dc_while_stunned[i] = ""
    }
    
    for (new i = 1; i <= MaxClients; i++)
    {
        is_fluttershy[i] = false
        bypass_immunity[i] = false
        stun_immunity[i] = false
    }
    
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsClientObserver(i))
        {
            ChangeClientTeam(i, 2)
            TF2_RespawnPlayer(i)
            num_red++
        }
    }
    
    new fshy_goal = RoundToCeil(FloatMul(float(num_red), 0.11111))
    while (num_fluttershys < fshy_goal)
    {
        new client = GetRandomInt(1, MaxClients)
        if (IsClientInGame(client) && !IsClientObserver(client) && !is_fluttershy[client])
            MakeFluttershy(client)
    }
}

public ConVarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
    LoadConVars()
}

LoadConVars()
{
    max_hp = GetConVarInt(max_hp_cvar)
    freeze_duration = GetConVarFloat(freeze_duration_cvar)
    freeze_immunity_time = GetConVarFloat(freeze_immunity_cvar)
    round_restart_time = GetConVarInt(round_restart_cvar)
    
    if (enabled != GetConVarBool(enabled_cvar))
    {
        enabled = GetConVarBool(enabled_cvar)
        if (enabled)
            EnablePlugin()
        else
            DisablePlugin()
    }
}

EnablePlugin()
{
    original_ff_val = GetConVarInt(ff_cvar)
    original_disable_respawn_times_val = GetConVarInt(disable_respawn_times_cvar)
    original_scramble_teams_val = GetConVarInt(scramble_teams_cvar)
    original_teams_unbalance_val = GetConVarInt(teams_unbalance_cvar)
    original_autobalance_val = GetConVarInt(autobalance_cvar)
    original_respawnwavetime_val = GetConVarInt(respawnwavetime_cvar)
    
    SetConVarInt(ff_cvar, 1)
    SetConVarInt(disable_respawn_times_cvar, 1)
    SetConVarInt(scramble_teams_cvar, 0)
    SetConVarInt(teams_unbalance_cvar, 0)
    SetConVarInt(autobalance_cvar, 0)
    SetConVarInt(respawnwavetime_cvar, 0)
    
    // Initialize arrays
    for (new i = 1; i < MAX_CLIENT_IDS; i++)
    {
        is_fluttershy[i] = false
        bypass_immunity[i] = false
        stun_immunity[i] = false
    }
    
    num_killers = 0
    num_fluttershys = 0
    num_red = 0
    num_stunned = 0
    
    // Apply SDKHooks to all clients in the server when the plugin is loaded
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            OnClientPutInServer(i)
        }
    }
    
    // Block team swapping and suicides
    AddCommandListener(BlockCommandAll, "jointeam")
    AddCommandListener(JoinClassCommand, "joinclass")
    AddCommandListener(BlockCommandFluttershy, "kill")
    AddCommandListener(BlockCommandAll, "spectate")
    AddCommandListener(BlockCommandFluttershy, "explode")
    
    HookEvent("teamplay_round_start", RoundStart, EventHookMode_Pre)
    
    ServerCommand("mp_restartgame_immediate 1")
}

DisablePlugin()
{
    SetConVarInt(ff_cvar, original_ff_val)
    SetConVarInt(disable_respawn_times_cvar, original_disable_respawn_times_val)
    SetConVarInt(scramble_teams_cvar, original_scramble_teams_val)
    SetConVarInt(teams_unbalance_cvar, original_teams_unbalance_val)
    SetConVarInt(autobalance_cvar, original_autobalance_val)
    SetConVarInt(respawnwavetime_cvar, original_respawnwavetime_val)
    
    RemoveCommandListener(BlockCommandAll, "jointeam")
    RemoveCommandListener(JoinClassCommand, "joinclass")
    RemoveCommandListener(BlockCommandFluttershy, "kill")
    RemoveCommandListener(BlockCommandAll, "spectate")
    RemoveCommandListener(BlockCommandFluttershy, "explode")
    
    UnhookEvent("teamplay_round_start", RoundStart, EventHookMode_Pre)
    
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKUnhook(i, SDKHook_OnTakeDamage, OnTakeDamage)
            SDKUnhook(i, SDKHook_OnTakeDamagePost, OnTakeDamagePost)
            SDKUnhook(i, SDKHook_WeaponCanSwitchTo, WeaponCanSwitchTo)
            SDKUnhook(i, SDKHook_WeaponCanUse, WeaponCanSwitchTo)
            SDKUnhook(i, SDKHook_Spawn, OnSpawn)
            SDKUnhook(i, SDKHook_PreThinkPost, PreThinkPost)
        }
    }   
    
    ServerCommand("mp_scrambleteams")
    ServerCommand("mp_restartgame_immediate 1")
}

public OnMapStart()
{
    for (new i = 0; i < sizeof(hit_sounds); i++)
    {
        LoadSound(hit_sounds[i])
    }
    
    for (new i = 0; i < sizeof(unfreeze_sounds); i++)
    {
        LoadSound(unfreeze_sounds[i])
    }
    
    LoadSound(loss_sound)
    LoadSound(win_sound)
}

LoadSound(String:sound[])
{
    decl String:path[PLATFORM_MAX_PATH]
    
    path = "sound\\"
    StrCat(path, sizeof(path), sound)
    AddFileToDownloadsTable(path);
    PrecacheSound(sound, true);
}

public PreThinkPost(client){   
    if (is_fluttershy[client] && GetPlayerWeaponSlot(client, 2) > 0)
        SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", GetPlayerWeaponSlot(client, 2))
    
    if(!is_fluttershy[client] && TF2_GetPlayerClass(client) == TFClass_Scout)
        SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", 300.0);
}

public OnPluginEnd()
{
    DisablePlugin()
}

public OnClientPutInServer(client)
{
    if (enabled)
    {
        SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage)
        SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost)
        SDKHook(client, SDKHook_WeaponCanSwitchTo, WeaponCanSwitchTo)
        SDKHook(client, SDKHook_WeaponCanUse, WeaponCanSwitchTo)
        SDKHook(client, SDKHook_Spawn, OnSpawn)
        SDKHook(client, SDKHook_PreThinkPost, PreThinkPost)
        ChangeClientTeam(client, 2)
        num_red++
    }
}

public OnClientDisconnect(client)
{
    decl String:steam_id[20]
    
    if (enabled)
    {
        if (is_fluttershy[client])
        {
            is_fluttershy[client] = false
            num_fluttershys--
        }
        else
        {
            num_red--
        }
            
        if (TF2_IsPlayerInCondition(client, TFCond_Dazed))
        {
            GetClientAuthString(client, steam_id, sizeof(steam_id))
            dc_while_stunned[num_dc_while_stunned] = steam_id
            num_dc_while_stunned++
            num_stunned--
        }
            
        is_fluttershy[client] = false
        bypass_immunity[client] = false
        stun_immunity[client] = false
        
        CheckWinCondition()
    }
}

public Action:OnSpawn(client)
{
    if (!is_fluttershy[client] && GetClientTeam(client) != 2)
    {
        ChangeClientTeam(client, 2)
        TF2_RespawnPlayer(client)
    }
    else if (is_fluttershy[client] && GetClientTeam(client) != 3)
    {
        ChangeClientTeam(client, 3)
        TF2_RespawnPlayer(client)
    }
    else if (!is_fluttershy[client] && ShouldShame(client))
    {
        FreezePlayer(client, 0, true)
    }
    
    return Plugin_Continue
}

bool:ShouldShame(client)
{
    decl String:steam_id[20]
    
    GetClientAuthString(client, steam_id, sizeof(steam_id))
    
    for (new i = 0; i < num_dc_while_stunned; i++)
    {
        if (StrEqual(steam_id, dc_while_stunned[i]))
            return true
    }
    
    return false
}

public Action:WeaponCanSwitchTo(client, weapon)
{
    if (!is_fluttershy[client] || GetPlayerWeaponSlot(client, 2) < 0 || weapon == GetPlayerWeaponSlot(client, 2))
        return Plugin_Continue
    else
        return Plugin_Handled
}

public OnGameFrame()
{
    if (enabled)
    {
        // This reverses the health degeneration of the Fluttershys
        for (new i = 0; i < sizeof(is_fluttershy); i++)
        {
            if (is_fluttershy[i])
                SetEntityHealth(i, displayed_health[i])
        }
    }
}

public OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype, weapon, const Float:damageForce[3], const Float:damagePosition[3])
{
    // The player is supposed to die, do not modify damage
    if (bypass_immunity[victim])
    {
        bypass_immunity[victim] = false
    }
    else if (is_fluttershy[victim] && !IsWorldDeath(attacker))
    {
        current_health[victim] = current_health[victim] - RoundFloat(damage)
        
        if (current_health[victim] <= 0)
        {
            killer[num_killers] = GetClientUserId(attacker)
            num_killers++
            PrintToChatAll("%N has defeated %N!", attacker, victim)
            ClearFluttershy(victim, attacker)
        }
        else
        {
            displayed_health[victim] = displayed_health[victim] - RoundFloat(damage)
            
            // Refill the life bar and display to the user the multiple of 1000 that his life is now counting down from
            if (displayed_health[victim] <= 0)
            {
                PrintToChat(victim, "Current Health: %d", current_health[victim]);
                displayed_health[victim] = current_health[victim] - ((current_health[victim] / 1000) * 1000)
            }
            
        
            SetEntityHealth(victim, displayed_health[victim])
        }
    }
    else if (!is_fluttershy[victim])
    {
        // Set the health back to normal
        SetEntityHealth(victim, current_health[victim])
    }
}

public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{    
    // The player is supposed to die, don't modify damage but remove the gib effect that happens
    // due to using an explosive entity to kill the player
    if (bypass_immunity[victim])
    {
        damagetype = damagetype | _:DMG_NEVERGIB & _:(!DMG_ALWAYSGIB)
        return Plugin_Changed
    }
    
    // Respawn players that fall off the map instantly since they cannot die to the fall damage
    if (IsWorldDeath(attacker))
    {
        TF2_RespawnPlayer(victim)
        return Plugin_Handled
    }
        
    if (is_fluttershy[victim])
    {
        // Damage doesn't get modified by crits or distance until after OnTakeDamage has run
        // Since we need to wait for OnTakeDamage to complete, set the player's health 
        // very high to prevent them from dying during OnTakeDamage. We will force the player
        // to die later if necessary
        SetEntityHealth(victim, 3000)
        return Plugin_Continue
    }
        
    // If enemy is hit and not frozen, freeze him. Damage done by the environment can never freeze a player.
    if (attacker != 0 && GetClientTeam(victim) != GetClientTeam(attacker) && !TF2_IsPlayerInCondition(victim, TFCond_Dazed))
    {
        FreezePlayer(victim, attacker)
    }
    // If ally is hit and frozen, unfreeze him
    else if (attacker != 0 && GetClientTeam(victim) == GetClientTeam(attacker) && TF2_IsPlayerInCondition(victim, TFCond_Dazed) && weapon == GetPlayerWeaponSlot(attacker, 2))
    {
        UnfreezePlayer(victim, attacker)
    }
    
    if (victim != attacker && GetClientTeam(victim) == GetClientTeam(attacker))
    {
        damage = 0.0;
    }
    
    // Make sure that damage taken will not kill the player
    current_health[victim] = GetClientHealth(victim)
    SetEntityHealth(victim, 3000)
    return Plugin_Changed
}

// Check if the id that did damage belongs to the world insta-kill
// THIS IS NOT TESTED, but it works on koth_nucleus
bool:IsWorldDeath(attacker)
{
    return attacker == 107
}

FreezePlayer(victim, attacker, bool:is_shamed=false)
{
    decl String:victim_name[MAX_NAME_LENGTH]
    decl String:attacker_name[MAX_NAME_LENGTH]
    GetCustomClientName(victim, victim_name, sizeof(victim_name))
    GetCustomClientName(attacker, attacker_name, sizeof(attacker_name))
      
    if (!stun_immunity[victim] && !TF2_IsPlayerInCondition(victim, TFCond_Dazed))
    {   
        if (attacker > 0)
        {
            EmitSoundToAll(hit_sounds[GetRandomInt(0, sizeof(hit_sounds) - 1)], attacker)
        }
        num_stunned++
        if (is_shamed)
        {
            PrintToChatAll("Hey everybody, %s tried to cheat his way out of a freeze. Let's all point and laugh!", victim_name)
            PrintToChat(victim, "You are frozen until the round is over.")
            TF2_StunPlayer(victim, 5000.0, 0.0, TF_STUNFLAG_BONKSTUCK, attacker)
        }
        else
        {
            PrintToChatAll("%s frozen by %s.", victim_name, attacker_name)
            CreateTimer(freeze_immunity_time, RemoveFreezeImmunity, GetClientUserId(victim))
            TF2_StunPlayer(victim, freeze_duration, 0.0, TF_STUNFLAG_BONKSTUCK, attacker)
        }
          
        stun_immunity[victim] = true
        CheckWinCondition()
    }
}

UnfreezePlayer(victim, attacker)
{
    decl String:victim_name[MAX_NAME_LENGTH]
    decl String:attacker_name[MAX_NAME_LENGTH]
    GetCustomClientName(victim, victim_name, sizeof(victim_name))
    GetCustomClientName(attacker, attacker_name, sizeof(attacker_name))
    
    if (!stun_immunity[victim] && TF2_IsPlayerInCondition(victim, TFCond_Dazed))
    {
        num_stunned--
        EmitSoundToAll(unfreeze_sounds[GetRandomInt(0, sizeof(unfreeze_sounds) - 1)], victim)
        PrintToChatAll("%s has been unfrozen by %s!", victim_name, attacker_name)
        TF2_RemoveCondition(victim, TFCond_Dazed)
        stun_immunity[victim] = true
        CreateTimer(freeze_immunity_time, RemoveFreezeImmunity, GetClientUserId(victim))
    }
}

public Action:RemoveFreezeImmunity(Handle:timer, any:user_id)
{
    new client = GetClientOfUserId(user_id)
    if (client > 0 && IsClientInGame(client))
        stun_immunity[client] = false
}

GetCustomClientName(client, String:name[], length)
{
    if (client < 1)
        strcopy(name, length, "The Guardians")
    else
        GetClientName(client, name, length)
}

// Handle debug/admin unfreeze command
public Action:UnfreezePlayerCommand(client, args)
{
    decl String:name[MAX_NAME_LENGTH]
    
    name[0] = '\0'
    GetCmdArgString(name, sizeof(name))
     
    new target = SelectPlayer(client, UnfreezePlayerMenuHandler, name)
    if (target > 0)
        UnfreezePlayer(client, 0)
        
    return Plugin_Handled
}

// Handle debug/admin freeze command
public Action:FreezePlayerCommand(client, args)
{
    decl String:name[MAX_NAME_LENGTH]
    
    name[0] = '\0'
    GetCmdArgString(name, sizeof(name))
     
    new target = SelectPlayer(client, FreezePlayerMenuHandler, name)
    if (target > 0)
        FreezePlayer(client, 0)
        
    return Plugin_Handled
}


// Handle debug/admin flutts command
public Action:MakeFluttershyCommand(client, args)
{
    decl String:name[MAX_NAME_LENGTH]
    
    name[0] = '\0'
    GetCmdArgString(name, sizeof(name))
     
    new target = SelectPlayer(client, MakeFluttershyMenuHandler, name)
    if (target > 0)
        MakeFluttershy(target)
        
    return Plugin_Handled
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
    decl String:user_id[16]
    decl String:name[MAX_NAME_LENGTH]
    
    if (search_name[0] == '\0')
    {
        new Handle:menu = CreateMenu(handler)
        SetMenuTitle(menu, "Select a player:")
        for (new i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                GetClientName(i, name, sizeof(name))
                IntToString(GetClientUserId(i), user_id, sizeof(user_id))
                AddMenuItem(menu, user_id, name)
            }
        }
        
        SetMenuExitButton(menu, true)
        DisplayMenu(menu, client, 20)
        
        return -1
    }
    else if (strcmp(search_name, "@me", false) == 0)
    {
        return client
    }
    else
    { 
        new target = -1
        new startidx = 0
        
        if (search_name[0] == '"')
        {
            startidx = 1
            new len = strlen(search_name);
            if (search_name[len-1] == '"')
            {
                search_name[len-1] = '\0'
            }
        }
        
        for (new i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                GetClientName(i, name, sizeof(name))
                if (StrContains(name, search_name[startidx], false) > -1)
                {
                    if (target != -1)
                    {
                        ReplyToCommand(client, "Ambiguous player name '%s'.", search_name[startidx])
                        return -1
                    }
                    else
                    {
                        target = i
                    }
                }
            }
        }
        if (target > 0)
        {
            return target
        }
        else
        {
            ReplyToCommand(client, "Could not find player '%s'.", search_name[startidx])
            return -1
        }
    }
}

// Handle debug/admin unflutts command
public Action:ClearFluttershyCommand(client, args)
{
    decl String:name[MAX_NAME_LENGTH]
    
    name[0] = '\0'
    GetCmdArgString(name, sizeof(name))
     
    new target = SelectPlayer(client, ClearFluttershyMenuHandler, name)
    if (target > 0)
    {
        PrintToChatAll(CLEAR_FLUTTERSHY_MSG, target)
        ClearFluttershy(target, 0)
    }
        
    return Plugin_Handled   
}

public ClearFluttershyMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
    decl String:info[32]

    if (action == MenuAction_Select)
    {
        GetMenuItem(menu, param2, info, sizeof(info))
        new target = GetClientOfUserId(StringToInt(info))
        if (IsClientInGame(target))
        {
            PrintToChatAll(CLEAR_FLUTTERSHY_MSG, target)
            ClearFluttershy(target, 0)
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu)
    }
}

public MakeFluttershyMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
    decl String:info[32]

    if (action == MenuAction_Select)
    {
        GetMenuItem(menu, param2, info, sizeof(info))
        new target = GetClientOfUserId(StringToInt(info))
        if (IsClientInGame(target))
            MakeFluttershy(target)
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu)
    }
}

public UnfreezePlayerMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
    decl String:info[32]

    if (action == MenuAction_Select)
    {
        GetMenuItem(menu, param2, info, sizeof(info))
        new target = GetClientOfUserId(StringToInt(info))
        if (IsClientInGame(target))
            UnfreezePlayer(target, 0)
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu)
    }
}

public FreezePlayerMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
    decl String:info[32]

    if (action == MenuAction_Select)
    {
        GetMenuItem(menu, param2, info, sizeof(info))
        new target = GetClientOfUserId(StringToInt(info))
        if (IsClientInGame(target))
            FreezePlayer(target, 0)
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu)
    }
}

MakeFluttershy(client)
{
    if (!is_fluttershy[client])
    {
        if (TF2_IsPlayerInCondition(client, TFCond_Dazed))
            num_stunned--
            
        PrintToChatAll("%N is now a Fluttershy.", client)
        is_fluttershy[client] = true
        ChangeClientTeam(client, 3)
        TF2_RespawnPlayer(client)
        TF2_SetPlayerClass(client, TFClass_Medic)
        TF2_RegeneratePlayer(client)
        displayed_health[client] = max_hp < 1000 ? max_hp : 1000
        current_health[client] = max_hp
        SetEntityHealth(client, displayed_health[client])
        num_fluttershys++
        num_red--
    }
}

ClearFluttershy(client, attacker)
{
    if (is_fluttershy[client])
    {
        is_fluttershy[client] = false
        bypass_immunity[client] = true
        KillPlayer(client, attacker)
        ChangeClientTeam(client, 2)
        TF2_RespawnPlayer(client)
        TF2_SetPlayerClass(client, TFClass_Soldier)
        TF2_RegeneratePlayer(client)
        num_fluttershys--
        num_red++
        CheckWinCondition()
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

public Action:BlockCommandAll(client, const String:command[], argc)
{
    return Plugin_Handled
}

public Action:BlockCommandFluttershy(client, const String:command[], argc)
{
    if (is_fluttershy[client])
        return Plugin_Handled
    else
        return Plugin_Continue
}

public Action:JoinClassCommand(client, const String:command[], argc)
{
    decl String:class[10]
    
    GetCmdArg(1, class, sizeof(class))
    
    if (is_fluttershy[client])
    {
        PrintToChat(client, "Fluttershys cannot change class!")
        return Plugin_Handled
    }
    else if (TF2_IsPlayerInCondition(client, TFCond_Dazed))
    {
        PrintToChat(client, "You cannot change class while frozen!")
        return Plugin_Handled
    }
    else if (!IsRedClassAllowed(class))
    {
        ShowVGUIPanel(client, "class_red")
        return Plugin_Handled
    }
    else
    {
        TF2_RespawnPlayer(client)
        return Plugin_Continue
    }
}

public Action:TestCmd(client, args)
{
    EmitSoundToAll(hit_sounds[GetRandomInt(0, sizeof(hit_sounds) - 1)], client)
}

bool:IsRedClassAllowed(const String:class[])
{
    return !(StrEqual(class, "medic", false) || StrEqual(class, "engineer", false) || StrEqual(class, "spy", false))
}

CheckWinCondition()
{
    new clientid
     
    // There are no Fluttershys remaining, print the winners
    if (num_fluttershys == 0)
    {
        EmitSoundToAll(loss_sound)
        PrintToChatAll("The Fluttershys have been defeated!")
        PrintToChatAll("Winners:")
        for (new i = 1; i <= num_killers; i++)
        {
            clientid = GetClientOfUserId(killer[i]) 
            if (clientid > 0 && IsClientInGame(clientid))
                PrintToChatAll(" %N", clientid)
        }
        ServerCommand("mp_restartround %d", round_restart_time)
        return
    }
    
    // Did the Fluttershys win
    // TODO: Check if time has run out
    if (num_stunned == num_red)
    {
        EmitSoundToAll(win_sound)
        PrintToChatAll("The Fluttershys have won!")
        PrintToChatAll("Winners:")
        for (new i = 1; i <= MaxClients; i++)
        {
            if (is_fluttershy[i])
                PrintToChatAll(" %N", i)
        }
        for (new i = 1; i <= num_killers; i++)
        {
            clientid = GetClientOfUserId(killer[i]) 
            PrintToChatAll("%d %d", clientid, killer[i])
            if (clientid > 0 && IsClientInGame(clientid))
                PrintToChatAll(" %N", clientid)
        }      
        ServerCommand("mp_restartround %d", round_restart_time)
    }
}